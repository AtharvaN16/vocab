import os, time
os.environ["NEEDLE_TELEMETRY"] = "0"
import needle
n = needle.Needle(weights="./models/needle3.cact")

sch_cls = {"type":"object","properties":{"register":{"type":"string","enum":["formal","neutral","informal","archaic"]}}}

print("=== A. strict=False on the classification task ===")
for strict in (True, False):
    out = n.extract('Sentence: "The committee faced the arduous task."\nTarget word: arduous', sch_cls, strict=strict)
    print(f"  strict={strict!s:5s} -> {out!r}")

print("\n=== B. does extract work at all? a genuine IN-TEXT extraction ===")
sch_ex = {"type":"object","properties":{
    "name":{"type":"string"},
    "amount":{"type":"string"},
}}
t0=time.perf_counter()
out = n.extract("Invoice from Acme Corp for 4,200 USD due next Friday.", sch_ex, strict=False)
print(f"  in-text extract -> {out!r}  ({1000*(time.perf_counter()-t0):.0f} ms)")

print("\n=== C. classification framed as in-text choice (labels present in prompt) ===")
txt = ('Word: arduous\nSentence: The committee faced the arduous task.\n'
       'Options: formal, neutral, informal, archaic\nWhich option describes the register?')
for strict in (True, False):
    print(f"  strict={strict!s:5s} ->", repr(n.extract(txt, sch_cls, strict=strict)))

print("\n=== D. complete() — raw generation ===")
t0=time.perf_counter()
r = n.complete('Word: arduous. Is its register formal, neutral, or informal? Answer in one word.', max_new_tokens=16)
print(f"  complete -> {r!r}  ({1000*(time.perf_counter()-t0):.0f} ms)")

print("\n=== E. embeddings: do they encode vocabulary similarity? ===")
import math
def cos(a,b):
    d=sum(x*y for x,y in zip(a,b)); na=math.sqrt(sum(x*x for x in a)); nb=math.sqrt(sum(y*y for y in b))
    return d/(na*nb+1e-12)
probe = "arduous"
cands = ["strenuous","laborious","difficult","easy","effortless","banana","thermodynamics"]
ve = n.embed(probe)
scored = sorted(((cos(ve, n.embed(c)), c) for c in cands), reverse=True)
for s,c in scored: print(f"  {c:16s} {s:.4f}")
