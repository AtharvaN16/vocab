import json, time, math, statistics as st
import torch
from transformers import AutoTokenizer, AutoModelForMaskedLM

items = json.load(open("data/fitb.json"))
dev = "mps" if torch.backends.mps.is_available() else "cpu"

NAME = "distilbert-base-uncased"
tok = AutoTokenizer.from_pretrained(NAME)
mdl = AutoModelForMaskedLM.from_pretrained(NAME).to(dev).eval()
nparam = sum(p.numel() for p in mdl.parameters())
print(f"{NAME}: {nparam/1e6:.1f}M params, device={dev}")

@torch.no_grad()
def pll(sentence, candidate):
    """Pseudo-log-likelihood of candidate's tokens in the blank, length-normalised."""
    filled = sentence.replace("___", candidate)
    enc = tok(filled, return_tensors="pt")
    ids = enc["input_ids"][0]
    cand_ids = tok(candidate, add_special_tokens=False)["input_ids"]
    # locate the candidate span
    span = None
    for s in range(1, len(ids) - len(cand_ids) + 1):
        if ids[s:s+len(cand_ids)].tolist() == cand_ids:
            span = list(range(s, s+len(cand_ids))); break
    if span is None: return -1e9
    total = 0.0
    for pos in span:
        masked = ids.clone(); masked[pos] = tok.mask_token_id
        out = mdl(input_ids=masked.unsqueeze(0).to(dev)).logits[0, pos]
        total += torch.log_softmax(out, -1)[ids[pos]].item()
    return total / len(span)

# --- 1. masked-LM scoring
t0 = time.time(); correct = 0; rr = []
for it in items:
    scores = {c: pll(it["sentence"], c) for c in it["options"]}
    ranked = sorted(scores, key=scores.get, reverse=True)
    correct += (ranked[0] == it["gold"])
    rr.append(1.0 / (ranked.index(it["gold"]) + 1))
mlm_t = time.time() - t0
print(f"\nmasked-LM ({NAME}, {nparam/1e6:.0f}M)")
print(f"  accuracy@1 = {correct}/{len(items)} = {correct/len(items):.1%}   MRR = {st.fmean(rr):.3f}")
print(f"  {1000*mlm_t/len(items):.0f} ms/item ({len(items)} items in {mlm_t:.0f}s)")

# --- 2. potion static embeddings: cosine(context, candidate)
from model2vec import StaticModel
pot = StaticModel.from_pretrained("minishlab/potion-base-32M")
def cos(a,b):
    d=float(sum(x*y for x,y in zip(a,b))); na=math.sqrt(float(sum(x*x for x in a))); nb=math.sqrt(float(sum(y*y for y in b)))
    return d/(na*nb+1e-12)
t0=time.time(); pc=0; prr=[]
for it in items:
    ctx = pot.encode([it["sentence"].replace("___"," ")])[0]
    sc = {c: cos(ctx, pot.encode([c])[0]) for c in it["options"]}
    ranked = sorted(sc, key=sc.get, reverse=True)
    pc += (ranked[0]==it["gold"]); prr.append(1.0/(ranked.index(it["gold"])+1))
pt = time.time()-t0
print(f"\npotion-base-32M (1.9 MB, static — no context modelling)")
print(f"  accuracy@1 = {pc}/{len(items)} = {pc/len(items):.1%}   MRR = {st.fmean(prr):.3f}")
print(f"  {1000*pt/len(items):.1f} ms/item")

# --- 3. baselines
rand = st.fmean(1/len(i["options"]) for i in items)
print(f"\nbaselines")
print(f"  random choice        = {rand:.1%}")
print(f"  always-most-frequent = ", end="")
from wordfreq import zipf_frequency
fc = sum(1 for i in items if max(i["options"], key=lambda c: zipf_frequency(c,'en')) == i["gold"])
print(f"{fc/len(items):.1%}  (pick the commonest option — a real trap for this task)")
