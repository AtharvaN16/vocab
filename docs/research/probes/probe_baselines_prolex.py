"""Baselines on the SAME frozen ProLex acceptability test set, so the
fine-tuned cross-encoder has something honest to be compared against."""
import json, math, time, statistics as st
te = json.load(open("data/test_prolex.json"))
ys = [x["label"] for x in te]
pos, neg = sum(ys), len(ys)-sum(ys)

def report(name, scores, size, lat):
    # threshold at the median so the decision rate matches the data, not luck
    thr = st.median(scores)
    pred = [1 if s >= thr else 0 for s in scores]
    tp=sum(1 for p,y in zip(pred,ys) if p==1 and y==1); fp=sum(1 for p,y in zip(pred,ys) if p==1 and y==0)
    fn=sum(1 for p,y in zip(pred,ys) if p==0 and y==1); tn=sum(1 for p,y in zip(pred,ys) if p==0 and y==0)
    acc=(tp+tn)/len(ys); prec=tp/max(tp+fp,1); rec=tp/max(tp+fn,1)
    f1=2*prec*rec/max(prec+rec,1e-9); bal=0.5*(rec+tn/max(tn+fp,1))
    pairs=sorted(zip(scores,ys)); rank=sum(i for i,(s,y) in enumerate(pairs,1) if y==1)
    auc=(rank-pos*(pos+1)/2)/max(pos*neg,1)
    print(f"  {name:34s} acc={acc:.3f} F1={f1:.3f} balAcc={bal:.3f} AUC={auc:.3f}  {size:>9s} {lat:>10s}")

print(f"frozen ProLex acceptability test: {len(te)} pairs ({pos} acceptable / {neg} not)")
print(f"  {'majority-class (always acceptable)':34s} acc={pos/len(te):.3f} F1={2*pos/(2*pos+neg):.3f} balAcc=0.500 AUC=0.500  {'0':>9s} {'0 ms':>10s}")

# potion static-embedding similarity between sentence context and candidate
from model2vec import StaticModel
pot = StaticModel.from_pretrained("minishlab/potion-base-32M")
def cos(a,b):
    d=float(sum(x*y for x,y in zip(a,b))); na=math.sqrt(float(sum(x*x for x in a))); nb=math.sqrt(float(sum(y*y for y in b)))
    return d/(na*nb+1e-12)
t0=time.time(); sc=[]
for x in te:
    ctx = pot.encode([x["sent"].replace("**","")])[0]
    sc.append(cos(ctx, pot.encode([x["cand"]])[0]))
lat=f"{1000*(time.time()-t0)/len(te):.2f} ms"
report("potion-base-32M cos(ctx,cand)", sc, "1.9 MB", lat)

# potion: similarity to the TARGET word rather than the sentence
t0=time.time(); sc=[]
for x in te: sc.append(cos(pot.encode([x["target"]])[0], pot.encode([x["cand"]])[0]))
lat=f"{1000*(time.time()-t0)/len(te):.2f} ms"
report("potion-base-32M cos(target,cand)", sc, "1.9 MB", lat)

# word frequency: is the candidate common? (today's anti-signal check)
from wordfreq import zipf_frequency
t0=time.time()
sc=[zipf_frequency(x["cand"].split()[0], "en") for x in te]
lat=f"{1000*(time.time()-t0)/len(te):.3f} ms"
report("candidate frequency (Zipf)", sc, "0", lat)
