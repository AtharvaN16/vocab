import os, math, time
os.environ["NEEDLE_TELEMETRY"] = "0"
import needle
n = needle.Needle(weights="./models/needle3.cact")

print("=== F. extract with a pydantic-style schema (needle.Field / build_schema) ===")
try:
    from pydantic import BaseModel
    from typing import Literal
    class Judgment(BaseModel):
        register: Literal["formal","neutral","informal","archaic"]
    out = n.extract('The committee faced the arduous task.', Judgment, strict=False)
    print("  pydantic ->", repr(out))
except ImportError:
    print("  pydantic not installed; trying needle.build_schema")
except Exception as e:
    print(f"  pydantic -> ERROR {type(e).__name__}: {e}")

try:
    sch = needle.build_schema({"register": needle.Field(str, description="formal/neutral/informal")})
    print("  build_schema ->", repr(n.extract('The committee faced the arduous task.', sch, strict=False)))
except Exception as e:
    print(f"  build_schema -> ERROR {type(e).__name__}: {e}")

print("\n=== G. embeddings: anisotropy check + mean-centering rescue ===")
words = ["arduous","strenuous","laborious","difficult","toilsome","gruelling",
         "easy","effortless","simple","trivial","facile",
         "banana","thermodynamics","xylophone","carburettor","Tuesday"]
E = {w: n.embed(w) for w in words}
import statistics
D = len(E["arduous"])
mean = [statistics.fmean(E[w][i] for w in words) for i in range(D)]

def cos(a,b):
    d=sum(x*y for x,y in zip(a,b)); na=math.sqrt(sum(x*x for x in a)); nb=math.sqrt(sum(y*y for y in b))
    return d/(na*nb+1e-12)
def center(v): return [x-m for x,m in zip(v,mean)]

# mean cosine between ALL pairs = anisotropy indicator (isotropic ~0)
import itertools
raw_pairs = [cos(E[a],E[b]) for a,b in itertools.combinations(words,2)]
cen_pairs = [cos(center(E[a]),center(E[b])) for a,b in itertools.combinations(words,2)]
print(f"  mean pairwise cosine  RAW      = {statistics.fmean(raw_pairs):.4f}  (isotropic ~0.0)")
print(f"  mean pairwise cosine  CENTERED = {statistics.fmean(cen_pairs):.4f}")
print(f"  spread (max-min)      RAW      = {max(raw_pairs)-min(raw_pairs):.4f}")
print(f"  spread (max-min)      CENTERED = {max(cen_pairs)-min(cen_pairs):.4f}")

syn = ["strenuous","laborious","toilsome","gruelling","difficult"]
ant = ["easy","effortless","simple","trivial","facile"]
unrel = ["banana","thermodynamics","xylophone","carburettor","Tuesday"]
for label, fn in (("RAW", lambda v: v), ("CENTERED", center)):
    q = fn(E["arduous"])
    ranked = sorted(((cos(q, fn(E[w])), w) for w in syn+ant+unrel), reverse=True)
    top5 = [w for _,w in ranked[:5]]
    hits = sum(1 for w in top5 if w in syn)
    print(f"\n  {label}: precision@5 for true synonyms = {hits}/5")
    for s,w in ranked:
        tag = "SYN" if w in syn else ("ANT" if w in ant else "UNREL")
        print(f"    {w:16s} {s:+.4f}  {tag}")
