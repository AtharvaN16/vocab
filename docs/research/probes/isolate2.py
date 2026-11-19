import json, random, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
rows=json.load(open("data/train_human.json"))
NAME="microsoft/deberta-v3-small"
tok=AutoTokenizer.from_pretrained(NAME)

# is any parameter shared / duplicated / oddly shaped?
m0=AutoModelForSequenceClassification.from_pretrained(NAME,num_labels=2)
ids={}
for n,p in m0.named_parameters(): ids.setdefault(id(p),[]).append(n)
dupes={k:v for k,v in ids.items() if len(v)>1}
print("duplicated/tied parameter tensors:", dupes if dupes else "none")
print("zero-element params:", [n for n,p in m0.named_parameters() if p.numel()==0] or "none")
print("non-float params:", [(n,p.dtype) for n,p in m0.named_parameters() if not p.dtype.is_floating_point] or "none")

def trial(label, make_opt, steps=4):
    torch.manual_seed(0); random.seed(0)
    m=AutoModelForSequenceClassification.from_pretrained(NAME,num_labels=2)
    opt=make_opt(m); m.train(); msg=[]
    for i in range(steps):
        b=rows[i*8:(i+1)*8]
        e=tok([x['sent'] for x in b],[x['cand'] for x in b],truncation=True,max_length=128,padding=True,return_tensors='pt')
        y=torch.tensor([x['label'] for x in b])
        out=m(**e,labels=y); out.loss.backward()
        torch.nn.utils.clip_grad_norm_(m.parameters(),1.0)
        opt.step(); opt.zero_grad()
        ok=all(torch.isfinite(p).all().item() for p in m.parameters())
        msg.append(f"s{i}: loss={out.loss.item():.4f} finite={ok}")
    print(f"{label:46s} " + " | ".join(msg), flush=True)

trial("AdamW foreach=False", lambda m: torch.optim.AdamW(m.parameters(),lr=2e-5,weight_decay=0.01,foreach=False))
trial("AdamW eps=1e-6", lambda m: torch.optim.AdamW(m.parameters(),lr=2e-5,weight_decay=0.01,eps=1e-6))
trial("Adam (no decoupled decay)", lambda m: torch.optim.Adam(m.parameters(),lr=2e-5))
trial("AdamW capturable=False,foreach=False,wd=0", lambda m: torch.optim.AdamW(m.parameters(),lr=2e-5,weight_decay=0.0,foreach=False))
