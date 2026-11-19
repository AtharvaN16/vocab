"""Build (sentence, candidate) -> acceptable/not pairs.
Positives: human-annotated substitutes. Negatives: WordNet near-synonyms of the
target that are NOT in the positive list -- plausible but wrong, matching the
distribution of ProLex's own unacceptable substitutes."""
import csv, ast, json, random, hashlib, re, math
from nltk.corpus import wordnet as wn
from model2vec import StaticModel
random.seed(7)
_POT = StaticModel.from_pretrained("minishlab/potion-base-32M")
_CACHE = {}
def _vec(w):
    if w not in _CACHE: _CACHE[w] = _POT.encode([w])[0]
    return _CACHE[w]
def _sim(a, b):
    va, vb = _vec(a), _vec(b)
    d = float(sum(x*y for x, y in zip(va, vb)))
    na = math.sqrt(float(sum(x*x for x in va))); nb = math.sqrt(float(sum(y*y for y in vb)))
    return d / (na*nb + 1e-12)

WNPOS = {"NOUN": wn.NOUN, "VERB": wn.VERB, "ADJ": wn.ADJ, "ADV": wn.ADV,
         "noun": wn.NOUN, "verb": wn.VERB, "adjective": wn.ADJ, "adverb": wn.ADV}

def lit(s):
    try: return ast.literal_eval(s) if s and s.strip() else []
    except Exception: return []

def hard_negatives(target, pos, positives, k):
    """Close-but-wrong: co-hyponyms and similar_to lemmas, excluding gold."""
    wnp = WNPOS.get(pos)
    cands = set()
    same_synset = set()   # true synonyms -- NEVER use as negatives
    for syn in wn.synsets(target, pos=wnp) or wn.synsets(target):
        same_synset |= {l.name().replace('_',' ').lower() for l in syn.lemmas()}
        for s in syn.similar_tos():
            cands |= {l.name().replace('_',' ').lower() for l in s.lemmas()}
        for hyper in syn.hypernyms():
            for sib in hyper.hyponyms():
                cands |= {l.name().replace('_',' ').lower() for l in sib.lemmas()}
    # a co-hyponym that is ALSO a same-synset lemma is a synonym; drop it
    cands -= same_synset
    bad = {target.lower()} | {p.lower() for p in positives}
    cands = {c for c in cands if c not in bad and re.fullmatch(r"[a-z][a-z '\-]*", c) and len(c) > 2}
    # HARD negatives: keep the ones most similar to the target, i.e. plausible but wrong.
    # This matches ProLex's own negatives (charming -> enticing) rather than absurd ones.
    ranked = sorted(cands, key=lambda c: _sim(target, c), reverse=True)
    return ranked[:k]

def build(path, name):
    out, no_neg = [], 0
    for r in csv.DictReader(open(path, encoding="utf-8")):
        sent = (r.get("tagged_sentences") or "").strip()
        tgt  = (r.get("target_words") or "").strip()
        pos  = (r.get("query_pos") or "").strip()
        subs = [s for s in lit(r.get("substitutes")) if s and s.strip()]
        if not sent or "**" not in sent or not tgt or not subs:
            continue
        sent = re.sub(r"\s+", " ", sent)
        negs = hard_negatives(tgt, pos, subs, k=len(subs))
        if not negs: no_neg += 1
        for s in subs:  out.append({"sent": sent, "target": tgt, "cand": s, "label": 1})
        for s in negs:  out.append({"sent": sent, "target": tgt, "cand": s, "label": 0})
    random.shuffle(out)
    p = sum(1 for x in out if x["label"] == 1)
    print(f"{name:16s} pairs={len(out):6d}  pos={p:5d} neg={len(out)-p:5d}  "
          f"(items with no WordNet negatives: {no_neg})")
    return out

human = build("data/prolex/swords_filtered.csv", "human-only")
synth = build("data/prolex/synthetic_gpt4.csv", "synthetic-gpt4")
combined = human + synth
random.shuffle(combined)
print(f"{'combined':16s} pairs={len(combined):6d}")

# --- test set: binary acceptability from official ProLex test
test = []
for r in csv.DictReader(open("data/prolex/ProLex_v1.0_test.csv", encoding="utf-8")):
    sent = re.sub(r"\s+", " ", (r["Sentence"] or "").strip()); tgt = (r["target word"] or "").strip()
    if "**" not in sent: continue
    for s in lit(r["acc_subs"]):   test.append({"sent": sent, "target": tgt, "cand": s, "label": 1})
    for s in lit(r["unacc_subs"]): test.append({"sent": sent, "target": tgt, "cand": s, "label": 0})
tp = sum(1 for x in test if x["label"] == 1)
print(f"\n{'TEST (official)':16s} pairs={len(test):6d}  pos={tp} neg={len(test)-tp}  "
      f"majority-class={max(tp,len(test)-tp)/len(test):.1%}")

for obj, fn in ((human,"train_human.json"), (combined,"train_combined.json"), (test,"test_prolex.json")):
    json.dump(obj, open(f"data/{fn}","w"))
    h = hashlib.sha256(open(f"data/{fn}","rb").read()).hexdigest()[:16]
    print(f"  {fn:22s} sha256={h}  (frozen)")
print("\nsample train pair:", human[0])
