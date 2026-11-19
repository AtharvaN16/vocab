# Spike findings — 2026-09-28 (throwaway probe, ~1h)

Hardware: M2, 16 GB, macOS 27.0, Python 3.14.6. All numbers measured here, not vendor-reported.

## Needle 3 (cactus-needle 3.0.5)

| Measured | Value | Vendor claim |
|---|---|---|
| weights `needle3.cact` | **33.7 MB** (reported 35.34 MB by downloader) | "8–29 MB" |
| engine `libneedle.dylib` | **0.78 MB** | "<1 MB" OK |
| peak RAM (from `complete`) | **99.0 MB** | 28.5 MB (Pi 5 example) |
| prefill | 3135 tok/s | 1–10k tok/s OK |
| embed latency | 5.1 ms, dim 3072 | — |
| extract latency | 89–120 ms median | — |
| confidence head in base archive | **present** | undocumented |
| local free LoRA (`needle finetune`) | **exists**, separate from paid `needle platform` | V3 resolved |
| telemetry | **ON by default** (`NEEDLE_TELEMETRY=0` to disable) | undocumented |

### API trap
`extract()` requires a **Pydantic model**. Given a raw JSON-Schema dict it returns
`None` silently — no error, no warning. It is also sensitive to field names:
field `register` returned a value; renaming it to `style` returned `None` on all 12 items.

### It is a tool-calling model, not a classifier
`complete()` returns `{'type':'call','function_calls':[],'reasoning':'no tools declared,
returning the empty call','decode_tps':0.0}`. No free text generation.

### Accuracy on GRE-level judgment (12 hand-built items — tiny, but see below)
| Task | Needle 3 | Majority-class baseline |
|---|---|---|
| Register (4-way) | **0/12** (all `None`, field-name fragility) | 50% |
| Connotation (3-way) | **6/12 = 50%** | **50%** |

Zero signal above baseline, and the errors are inversions on exactly the words that matter:
`vitriol`→positive, `magnanimity`→neutral, `lit`→negative, `knave`→positive.

### Embeddings are unusable for vocabulary
Anisotropy: mean pairwise cosine **0.9262** (isotropic ≈ 0), spread 0.0894.
Mean-centering rescues the geometry (mean → -0.065, spread → 0.848) but not the ranking.
Nearest neighbour of *arduous*, raw and centered: **`carburettor`**. `difficult` ranks 12/15.

## potion-base-32M (Model2Vec, MIT) — same size class

| | potion-base-32M | Needle 3 |
|---|---|---|
| on disk | **1.9 MB** | 33.7 MB |
| dim | 512 | 3072 |
| embed latency | **0.03 ms** | 5.1 ms |
| mean pairwise cosine | **0.0933** (healthy) | 0.9262 (degenerate) |
| unrelated words ranked below related | **9/10 clean** | not at all |
| precision@5 synonyms | 2/5 | 1/5 raw, 3/5 centered |

potion's failure mode is the *expected* one: antonyms sit near synonyms (`effortless` +0.3992
vs `strenuous` +0.3994) because they share contexts. That is what SimLex-999 exists to measure.
Needle's failure mode is pathological: unrelated nouns outrank synonyms.

## Design rule this earns
**Never ask an embedding to decide synonym vs antonym — WordNet already knows.**
Use KB relations to pick the candidate *type*, and the embedding only to rank within type.
That converts potion's one weakness into a non-issue, at 1.9 MB and 0.03 ms.

## Verdict
- Needle 3: **out** for this app, both slots. It is an on-device tool-calling model.
- potion-base-32M: **in** for the embedding/retrieval slot, pending the full T4b probe.
- The <100M judgment slot is now **open** — needs a real candidate (masked-LM scoring or a
  fine-tuned small cross-encoder), which the plan already named as the baseline.

Caveat: 12 items is far too few to rank models. It is enough to reject one that ties
majority-class while inverting `vitriol` and `magnanimity`, and to reject an embedding
space that puts a carburettor closest to *arduous*.
