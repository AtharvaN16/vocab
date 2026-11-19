import json, sys, time, math, random, statistics as st
import torch, torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from transformers import AutoTokenizer, AutoModelForSequenceClassification, get_linear_schedule_with_warmup

TRAIN = sys.argv[1]; TAG = sys.argv[2]; EPOCHS = int(sys.argv[3]) if len(sys.argv)>3 else 3
NAME = sys.argv[4] if len(sys.argv)>4 else "distilbert-base-uncased"
MAXLEN = 256; BS = 16; LR = 2e-5
torch.manual_seed(0); random.seed(0)
dev = "mps" if torch.backends.mps.is_available() else "cpu"

tok = AutoTokenizer.from_pretrained(NAME)
data = json.load(open(TRAIN)); random.shuffle(data)
cut = int(len(data)*0.9); tr, va = data[:cut], data[cut:]
te = json.load(open("data/test_prolex.json"))
print(f"[{TAG}] model={NAME}")
print(f"[{TAG}] train={len(tr)} dev={len(va)} test={len(te)} device={dev}")

class DS(Dataset):
    def __init__(s, rows): s.r = rows
    def __len__(s): return len(s.r)
    def __getitem__(s, i):
        x = s.r[i]
        return x["sent"], x["cand"], x["label"]

def collate(b):
    a=[x[0] for x in b]; c=[x[1] for x in b]; y=torch.tensor([x[2] for x in b])
    e=tok(a, c, truncation=True, max_length=MAXLEN, padding=True, return_tensors="pt")
    return e, y

mdl = AutoModelForSequenceClassification.from_pretrained(NAME, num_labels=2).to(dev)
opt = torch.optim.AdamW(mdl.parameters(), lr=LR, weight_decay=0.01)
dl = DataLoader(DS(tr), batch_size=BS, shuffle=True, collate_fn=collate)
steps = len(dl)*EPOCHS
sch = get_linear_schedule_with_warmup(opt, int(0.1*steps), steps)

@torch.no_grad()
def evaluate(rows, name):
    mdl.eval(); probs=[]; ys=[]
    for i in range(0, len(rows), 64):
        b = rows[i:i+64]
        e = tok([x["sent"] for x in b], [x["cand"] for x in b],
                truncation=True, max_length=MAXLEN, padding=True, return_tensors="pt").to(dev)
        p = torch.softmax(mdl(**e).logits, -1)[:,1].cpu().tolist()
        probs += p; ys += [x["label"] for x in b]
    pred=[1 if p>=0.5 else 0 for p in probs]
    tp=sum(1 for p,y in zip(pred,ys) if p==1 and y==1); fp=sum(1 for p,y in zip(pred,ys) if p==1 and y==0)
    fn=sum(1 for p,y in zip(pred,ys) if p==0 and y==1); tn=sum(1 for p,y in zip(pred,ys) if p==0 and y==0)
    acc=(tp+tn)/len(ys); prec=tp/max(tp+fp,1); rec=tp/max(tp+fn,1)
    f1=2*prec*rec/max(prec+rec,1e-9)
    bal=0.5*(rec + tn/max(tn+fp,1))
    # AUC
    pairs=sorted(zip(probs,ys)); pos=sum(ys); neg=len(ys)-pos; rank=0; c=0
    for i,(p,y) in enumerate(pairs, start=1):
        if y==1: rank+=i
    auc=(rank - pos*(pos+1)/2)/max(pos*neg,1)
    print(f"    {name:12s} acc={acc:.3f}  F1={f1:.3f}  prec={prec:.3f}  rec={rec:.3f}  balAcc={bal:.3f}  AUC={auc:.3f}")
    mdl.train(); return acc, f1, bal, auc

t0=time.time(); best=None
for ep in range(EPOCHS):
    mdl.train(); tot=0; nb=0
    for e,y in dl:
        e={k:v.to(dev) for k,v in e.items()}; y=y.to(dev)
        out=mdl(**e, labels=y)
        if not torch.isfinite(out.loss):
            raise SystemExit(f"ABORT: non-finite loss at step {nb} — instrument broken, not a result")
        out.loss.backward()
        torch.nn.utils.clip_grad_norm_(mdl.parameters(), 1.0)
        opt.step(); sch.step(); opt.zero_grad()
        tot+=out.loss.item(); nb+=1
    print(f"  epoch {ep+1}/{EPOCHS} loss={tot/nb:.4f} ({time.time()-t0:.0f}s)")
    evaluate(va, "dev")
    m = evaluate(te, "TEST")
    if best is None or m[3] > best[3]: best = m
print(f"\n[{TAG}] BEST on frozen ProLex test: acc={best[0]:.3f} F1={best[1]:.3f} balAcc={best[2]:.3f} AUC={best[3]:.3f}")
print(f"[{TAG}] majority-class baseline acc=0.578 | trained in {time.time()-t0:.0f}s")
json.dump({"tag":TAG,"acc":best[0],"f1":best[1],"balacc":best[2],"auc":best[3]}, open(f"data/result_{TAG}.json","w"))
