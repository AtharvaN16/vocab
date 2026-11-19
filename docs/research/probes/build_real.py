"""Training pairs with REAL human labels from SWORDS (CC-BY-3.0-US).
Held-out test stays the official ProLex test set (TOEFL-11 essays) - a different
corpus from SWORDS (CoInCo/MASC), so no contamination. This is the same
train/test arrangement the ProLex authors used."""
import gzip, json, random, hashlib, collections, re
random.seed(13)

def load(name):
    return json.load(gzip.open(f"data/swords/{name}.json.gz","rt",encoding="utf-8"))

pairs=[]
frac_hist=collections.Counter()
for split in ["swords-v1.1_dev","swords-v1.1_test"]:
    d=load(split)
    ctx, tgt, sub, lab = d["contexts"], d["targets"], d["substitutes"], d["substitute_labels"]
    for sid, s in sub.items():
        labels=[l for l in lab.get(sid,[]) if l in ("TRUE","FALSE")]
        if not labels: continue
        t=tgt[s["target_id"]]
        c=ctx[t["context_id"]]
        sent=re.sub(r"\s+"," ", c["context"]).strip()
        off, tw = t["offset"], t["target"]
        # mark the target in place, exactly as ProLex does with **
        marked = sent if tw.lower() not in sent.lower() else re.sub(
            rf"\b{re.escape(tw)}\b", f"**{tw}**", sent, count=1)
        frac = sum(1 for l in labels if l=="TRUE")/len(labels)
        frac_hist[round(frac,1)]+=1
        pairs.append({"sent": marked, "target": tw, "cand": s["substitute"],
                      "label": 1 if frac>0.5 else 0, "frac": round(frac,3),
                      "n_annot": len(labels)})

pos=[p for p in pairs if p["label"]==1]; neg=[p for p in pairs if p["label"]==0]
print(f"SWORDS human-labelled triples: {len(pairs)}  (majority TRUE={len(pos)}, FALSE={len(neg)})")
print(f"annotators per candidate: mean {sum(p['n_annot'] for p in pairs)/len(pairs):.1f}")
print(f"TRUE-vote fraction histogram: {dict(sorted(frac_hist.items()))}")

# Drop frac==0.5 exactly: annotators split evenly, so there is no label to learn.
pos = [p for p in pos if p["frac"] > 0.5]
neg = [p for p in neg if p["frac"] < 0.5]
# Balance 1:1, but STRATIFIED across difficulty so the model sees both
# unanimous rejections and contested ones, in their natural proportions.
bins = collections.defaultdict(list)
for p in neg: bins[round(p["frac"], 1)].append(p)
total_neg = sum(len(v) for v in bins.values())
neg_keep = []
for b, v in sorted(bins.items()):
    random.shuffle(v)
    take = max(1, round(len(pos) * len(v) / total_neg))
    neg_keep += v[:take]
random.shuffle(neg_keep); neg_keep = neg_keep[:len(pos)]
print(f"  negative difficulty mix: "
      f"{dict(sorted(collections.Counter(round(p['frac'],1) for p in neg_keep).items()))}")
train = pos + neg_keep
random.shuffle(train)
print(f"\nbalanced train set: {len(train)} pairs ({len(pos)} pos / {len(neg_keep)} neg)")
print(f"  (frac==0.5 coin-flips dropped entirely)")

# contamination check against the frozen ProLex test
te=json.load(open("data/test_prolex.json"))
te_sents={re.sub(r'[^a-z ]','',x['sent'].replace('**','').lower())[:90] for x in te}
overlap=sum(1 for p in train if re.sub(r'[^a-z ]','',p['sent'].replace('**','').lower())[:90] in te_sents)
print(f"\ncontamination check vs frozen ProLex test: {overlap} overlapping sentences  "
      f"({'CLEAN' if overlap==0 else 'PROBLEM'})")

json.dump(train, open("data/train_real.json","w"))
h=hashlib.sha256(open("data/train_real.json","rb").read()).hexdigest()[:16]
print(f"saved data/train_real.json  sha256={h}")
print("\nsample REAL negatives (human-rejected, stratified):")
for p in neg_keep[:6]:
    print(f"  {p['target']:12s} -> {p['cand']:18s} TRUE-votes={p['frac']:.2f} (n={p['n_annot']})")
print("sample REAL positives:")
for p in pos[:4]:
    print(f"  {p['target']:12s} -> {p['cand']:18s} TRUE-votes={p['frac']:.2f}")
