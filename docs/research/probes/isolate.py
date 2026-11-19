import json, random, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
rows=json.load(open("data/train_human.json"))

def trial(label, name="microsoft/deberta-v3-small", lr=2e-5, optim="adamw", wd=0.01, steps=4, clip=1.0):
    torch.manual_seed(0); random.seed(0)
    tok=AutoTokenizer.from_pretrained(name)
    m=AutoModelForSequenceClassification.from_pretrained(name,num_labels=2)
    opt=(torch.optim.AdamW(m.parameters(),lr=lr,weight_decay=wd) if optim=="adamw"
         else torch.optim.SGD(m.parameters(),lr=lr))
    m.train(); msg=[]
    for i in range(steps):
        b=rows[i*8:(i+1)*8]
        e=tok([x['sent'] for x in b],[x['cand'] for x in b],truncation=True,max_length=128,padding=True,return_tensors='pt')
        y=torch.tensor([x['label'] for x in b])
        out=m(**e,labels=y); loss=out.loss
        loss.backward()
        gn=torch.nn.utils.clip_grad_norm_(m.parameters(),clip).item()
        wfin=all(torch.isfinite(p).all().item() for p in m.parameters())
        msg.append(f"s{i}: loss={loss.item():.4f} gnorm={gn:.3f} weights_finite={wfin}")
        opt.step(); opt.zero_grad()
    print(f"\n{label}\n   " + "\n   ".join(msg), flush=True)

trial("A) deberta-v3-small, AdamW lr=2e-5  (the failing config)")
trial("B) deberta-v3-small, AdamW lr=0", lr=0.0)
trial("C) deberta-v3-small, SGD lr=1e-4", optim="sgd", lr=1e-4)
trial("D) distilbert-base-uncased, AdamW lr=2e-5", name="distilbert-base-uncased")
