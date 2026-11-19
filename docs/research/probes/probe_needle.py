import os, time, json
os.environ["NEEDLE_TELEMETRY"] = "0"
import needle

W = "./models/needle3.cact"
n = needle.Needle(weights=W)

print("=== 1. embed: dimension + latency ===")
t0 = time.perf_counter(); v = n.embed("arduous"); t1 = time.perf_counter()
print(f"dim={len(v)}  latency={1000*(t1-t0):.1f} ms  first5={[round(x,4) for x in v[:5]]}")

print("\n=== 2. extract: a real vocab judgment ===")
schema = {
    "type": "object",
    "properties": {
        "register":    {"type": "string", "enum": ["formal", "neutral", "informal", "archaic"]},
        "connotation": {"type": "string", "enum": ["positive", "neutral", "negative"]},
    },
}
cases = [
    ("The committee faced the arduous task of reconciling every dissenting report.", "arduous"),
    ("That hike was super gnarly and kicked my butt.", "gnarly"),
    ("His speech was full of vitriol against his former allies.", "vitriol"),
]
for sent, word in cases:
    text = f'Sentence: "{sent}"\nTarget word: {word}\nJudge the target word as used here.'
    t0 = time.perf_counter()
    try:
        out = n.extract(text, schema)
        dt = 1000*(time.perf_counter()-t0)
        print(f"  {word:10s} -> {out!r}   ({dt:.0f} ms)  type={type(out).__name__}")
    except Exception as e:
        print(f"  {word:10s} -> ERROR {type(e).__name__}: {e}")

print("\n=== 3. does the returned object carry probabilities/confidence? ===")
out = n.extract('Sentence: "The task was arduous."\nTarget word: arduous', schema)
print("repr:", repr(out))
print("type:", type(out), "dir:", [a for a in dir(out) if not a.startswith('_')][:25])
if isinstance(out, dict):
    print("keys:", list(out.keys()))
