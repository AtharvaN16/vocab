import math, statistics, itertools, time
from model2vec import StaticModel
t0=time.perf_counter()
m = StaticModel.from_pretrained("minishlab/potion-base-32M")
print(f"load {time.perf_counter()-t0:.1f}s  dim={m.dim}")

words = ["arduous","strenuous","laborious","difficult","toilsome","gruelling",
         "easy","effortless","simple","trivial","facile",
         "banana","thermodynamics","xylophone","carburettor","Tuesday"]
V = {w: m.encode([w])[0] for w in words}
def cos(a,b):
    d=float(sum(x*y for x,y in zip(a,b))); na=math.sqrt(float(sum(x*x for x in a))); nb=math.sqrt(float(sum(y*y for y in b)))
    return d/(na*nb+1e-12)
pairs=[cos(V[a],V[b]) for a,b in itertools.combinations(words,2)]
print(f"mean pairwise cosine = {statistics.fmean(pairs):.4f}   spread = {max(pairs)-min(pairs):.4f}")

syn={"strenuous","laborious","toilsome","gruelling","difficult"}
ant={"easy","effortless","simple","trivial","facile"}
ranked = sorted(((cos(V["arduous"],V[w]), w) for w in words if w!="arduous"), reverse=True)
hits = sum(1 for _,w in ranked[:5] if w in syn)
print(f"\npotion-base-32M: precision@5 for true synonyms = {hits}/5   (Needle 3 raw: 1/5, centered: 3/5)")
for s,w in ranked:
    tag = "SYN" if w in syn else ("ANT" if w in ant else "UNREL")
    print(f"  {w:16s} {s:+.4f}  {tag}")

t0=time.perf_counter()
for _ in range(50): m.encode(["arduous"])
print(f"\nlatency: {1000*(time.perf_counter()-t0)/50:.2f} ms/word  (Needle 3 embed: 5.1 ms)")
