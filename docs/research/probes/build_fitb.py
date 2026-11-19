"""Auto-build a near-synonym fill-in-the-blank set from WordNet.
Gold = the word the author actually used. Distractors = co-hyponyms / similar_to
(semantically close, so genuinely confusable) - NOT random words."""
import json, random, re
from nltk.corpus import wordnet as wn
random.seed(11)

gre = set(json.load(open("data/gre_words.json")))

def near_synonyms(syn, target, k=6):
    """Close-but-distinct candidates: adjective similar_to, else co-hyponyms."""
    out = set()
    for s in syn.similar_tos():
        out |= {l.name().lower() for l in s.lemmas()}
    for hyper in syn.hypernyms():
        for sib in hyper.hyponyms():
            if sib != syn:
                out |= {l.name().lower() for l in sib.lemmas()}
    # same-synset lemmas are true synonyms -> ambiguous gold, exclude them
    same = {l.name().lower() for l in syn.lemmas()}
    out -= same
    out = {w for w in out if "_" not in w and w.isalpha() and len(w) > 2}
    return random.sample(sorted(out), min(k, len(out)))

items = []
for w in sorted(gre):
    for syn in wn.synsets(w):
        for ex in syn.examples():
            # the example must contain the exact surface form
            if not re.search(rf"\b{re.escape(w)}\b", ex, re.I):
                continue
            cands = near_synonyms(syn, w, k=4)
            if len(cands) < 3:
                continue
            sent = re.sub(rf"\b{re.escape(w)}\b", "___", ex, count=1, flags=re.I)
            opts = cands + [w]
            random.shuffle(opts)
            items.append({"sentence": sent, "gold": w, "options": opts,
                          "gloss": syn.definition(), "pos": syn.pos()})
            break
        if len(items) and items[-1]["gold"] == w:
            break

random.shuffle(items)
items = items[:300]
json.dump(items, open("data/fitb.json","w"), indent=1)
ks = [len(i["options"]) for i in items]
print(f"built {len(items)} items | options per item: min {min(ks)} max {max(ks)} mean {sum(ks)/len(ks):.1f}")
print(f"random-choice baseline accuracy = {sum(1/len(i['options']) for i in items)/len(items):.1%}")
print("\nexamples:")
for i in items[:4]:
    print(f"  {i['sentence']}")
    print(f"     options={i['options']}  gold={i['gold']}")
