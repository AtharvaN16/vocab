# System One Models and Tiny On-Device Models — Revision to the Judgment Layer

Date: 2026-09-28
Status: **SUPERSEDED IN PART — Needle 3 was measured and rejected the same day.**
Revises: §4.2, §4.3 and §8 of `2026-09-20-landscape-and-recommendation.md`

> **Correction, 2026-09-28 (later the same day).** This document recommended
> Needle 3 as the lead Layer 2 candidate on the strength of vendor documentation.
> It was then measured on an M2 and **rejected for both the judgment and the
> embedding slot**: connotation accuracy tied the majority-class baseline (6/12
> vs 50%), register returned `None` on all 12 items, and the nearest neighbour of
> *arduous* in its embedding space is `carburettor`. Measured numbers, root cause
> and consequences: `results/2026-09-28-needle3-potion-probe.md`.
> `potion-base-32M` (1.9 MB, MIT) replaces it in the embedding slot. The <100M
> judgment slot is open again. Sections 0, 4 and 7 below are wrong where they
> favour Needle 3; the §9 verification ledger is what held up.

Between 15 and 18 September 2026 — five days before the original landscape
pass — three models shipped that land directly on **Layer 2** of our
architecture, the layer that had the weakest answer in the Sept 20 report.
This document evaluates them, corrects a framing error, and adds the
benchmark items needed to decide whether to adopt any of them.

Everything below is **vendor-reported unless marked otherwise**. The sources
are two weeks old, the benchmarks are self-published, and none of the three
has an independent replication. §9 is the ledger of what we have to measure
ourselves before any of this becomes a decision.

---

## 0. Summary

| Model | Verdict for us |
|---|---|
| **Jev** (TypeSafe AI) | **Reject.** Closed, waitlist-only, API-only. Fails offline, free and privacy simultaneously. Keep only as a published latency number to cite. |
| **Laya** (Convai Innovations) | **Adopt the method, not the model.** 421M is too heavy for the phone and has no Core ML path, but its calibration recipe is exactly what Layer 2 needs, and it makes a good Mac-side teacher/oracle. |
| **Needle 3** (Cactus Compute) | **REJECTED on measurement (2026-09-28).** Tested the same day: judgment ties the majority-class baseline, embeddings rank `carburettor` nearest to *arduous*, real size is 33.7 MB not 8–29 MB. It is a tool-calling model. See `results/2026-09-28-needle3-potion-probe.md`. |

The framing correction: "use an existing LLM vs. train our own vs. use a
System One model" is not a three-way choice. See §6.

---

## 1. What a "System One model" is

TypeSafe AI coined the category on 2026-09-15. A System One model is
**non-autoregressive**: it takes program state plus a schema and returns a
*typed decision with a calibrated probability* in a single parallel forward
pass. No token-by-token generation, no parsing, no retries. The name is from
Kahneman's fast/intuitive System 1, against System 2 deliberation.

Three primitives recur across implementations:

- `choice` — categorical, with per-option probabilities
- `score` — ordinal against a stated rubric
- `bool` — yes/no with a calibrated probability

The category claim is that a large share of production "LLM calls" are
actually decisions with a known answer set, and paying autoregressive
generation costs for them is waste. That claim is *correct for us*: most of
Layer 2 in our architecture is precisely this shape.

**Important distinction.** Needle 3 is often grouped with these but is **not**
in the class — it is a tiny autoregressive model with grammar-constrained
decoding. It fills the same architectural slot by different means.

---

## 2. Jev — TypeSafe AI

Launched 2026-09-15. Closed weights, waitlist-only, served as an API.
Vendor-reported 70–500 ms end-to-end, framed against the 3–329 s a
reasoning model spends on the same decision.

**Rejected.** An API breaks the three constraints the project is built on:
offline operation, zero cash, and on-device privacy. Its only residual use is
as a citable reference point in §7 of the landscape doc. Note that Laya's
measurement of Jev (236–276 ms) includes network round-trip, so it is not a
like-for-like comparison with local inference — do not repeat that framing.

Source: [Introducing System One Models & Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev)

---

## 3. Laya — Convai Innovations

Open-sourced 2026-09-18 by Nandakishor M (Convai Innovations). **Apache 2.0
weights** on Hugging Face, `pip install laya`, runs on local GPU or CPU.

### 3.1 Checkpoints

| Checkpoint | Encoder | Params | Context |
|---|---|---|---|
| `laya` | ModernBERT-large | 421M | 512 |
| `laya-multilingual` | mmBERT-base | 322M | 1024 (to 8,192) |
| `laya-typed-decisions` | ModernBERT-large | 421M | 1024 |

The English checkpoint fully fine-tunes ModernBERT-large (395M) and adds a
head trained from scratch: **two transformer layers, a scorer that reads one
`[MASK]` token per option, and an act-or-escalate output** — 421M total.

### 3.2 What is genuinely valuable here

1. **The schema is supplied at inference time.** One encoder serves every
   decision task, so our register / connotation / sense / difficulty /
   collocation judgments do not each need their own model. This is a better
   deal than the "several tiny heads" plan in §8 Layer 2.
2. **Explicit calibration.** The training loop is RLCD — the policy emits a
   distribution, exploration adds zero-mean Gaussian noise to the logits, the
   reward is a *strictly proper scoring rule*, GRPO-style policy gradient —
   followed by fitting per-task temperature. Calibrated confidence is not a
   nicety for us: the spaced-repetition scheduler and the escalate-to-explainer
   gate both consume it.
3. **The act-or-escalate head** is the Layer 2 → Layer 3 routing decision,
   learned rather than thresholded by hand.
4. **The recipe fits our budget.** Their Kaggle notebook does dataset build →
   RLCD → calibration → eval → Hub push in **4–5 h on free 2×T4**, 4 epochs
   over ~30k questions. That is inside Kaggle's 30 GPU-h/week.

### 3.3 Why we should not ship it

- **Size.** 421M is heavy for a judgment layer. The MLX port is **843 MB at
  FP16**; per-channel INT8 ≈ 420 MB. Our whole on-disk target is ≤1 GB with
  ~500 MB already committed to the explainer. Open decision §10.3 (download
  budget) decides whether this is even admissible; on current targets it is not.
- **No Core ML path.** Upstream ships ONNX export with per-channel INT8
  (`scripts/export_onnx.py --quantize`) and community MLX; Core ML / Core AI is
  not supported. ModernBERT's unpadded attention, alternating local/global
  attention and RoPE are the usual conversion friction, and `coremltools`
  dropped ONNX ingestion years ago, so the route would be PyTorch → Core AI.
  Unquantified risk.
- **It knows no vocabulary.** Base checkpoints score **0.362 / 0.352** on the
  author's own typed-decisions benchmark, rising to **0.766** only after
  fine-tuning. Fine-tuning is mandatory, so our bottleneck is labelled
  GRE-level judgment data — not the model. That is the same conclusion §2
  Step 3 of the landscape doc already reached.
- **Multilingual is wasted capacity.** `laya-multilingual` buys 100+ languages
  we do not need for an English GRE app.

### 3.4 The Mac-side role it *should* play

Two jobs where 843 MB does not matter:

- **Accuracy oracle.** Fine-tune `laya` on our judgment data on Kaggle, run it
  on the Mac, and treat its score as the ceiling that a phone-sized model is
  allowed to lose a few points against. Cheaper and more legally comfortable
  than a frontier API teacher (Apache 2.0, see the teacher caveat in §6 of the
  landscape doc).
- **Label generator** for the Layer 2 training set, judge-filtered as usual.

The MLX port (`aac6fef/laya-mlx`, FP16, 843 MB, macOS 14+) reports FP16
agreeing with upstream PyTorch MPS FP32 on the **argmax of 63/63 decision
distributions**, max probability delta 0.0054, on an M3 Max — so the Mac path
is credible without a PyTorch dependency.

Sources: [GitHub](https://github.com/NandhaKishorM/laya),
[convaiinnovations/laya](https://huggingface.co/convaiinnovations/laya),
[laya-mlx](https://huggingface.co/aac6fef/laya-mlx)

---

## 4. Needle 3 — Cactus Compute

Shipped 2026-09-17/18. **Apache 2.0 weights** per the Hugging Face card.
Note we already know this vendor: Cactus appears in §3.2 of the landscape doc
as a *runtime* (50 tok/s, 632 MB on Gemma 4 E2B, iPhone 17 Pro), and its
license was already flagged in open decision §10.4. Needle 3 is Cactus's own
model for that runtime.

### 4.1 What it is

- **8–29 MB as a single `.cact` file**, 29–121M params at CQ2-bit, with a
  platform engine under 1 MB and in-place memory mapping.
- **Laddered Simple Attention Network**: 20 layers trained so that *every*
  prefix from 2 to 20 layers is itself a deployable model. Monarch Hadamard
  MLP in place of a dense FFN; grouped-query attention with causal convolution
  taps. Most parameters sit in what Cactus calls "engram memory".
- **1024-token window**, with global attention at layers 4, 9, 14 and 19.
  (One secondary source claims 8k context; treat as unverified — the vendor
  page says 1024.)
- **Three jobs only**, general chat deliberately traded away:
  1. tool calling — select functions and fill every argument, returning an
     empty list rather than guessing when no tool applies
  2. typed structured extraction — Pydantic schemas, byte-level grammar so
     output is guaranteed parseable
  3. text embeddings — for local search, matching and routing
- **Platforms include iOS, tvOS and watchOS**, plus macOS, Linux, Windows,
  Android, WASM. `pip install cactus-needle`; `needle build` slices and
  exports a depth; `needle finetune` does LoRA on a frozen base.
- Raspberry Pi 5: prefill 1–10k tok/s, decode 400–4k tok/s, **28.5 MB peak
  memory** in their example.

### 4.2 Why this is the most interesting of the three for us

| Our need (landscape doc) | Needle 3 capability |
|---|---|
| §8 Layer 2 attribute + sense judgments | typed extraction with byte-level grammar → `{register, connotation, sense_id}` guaranteed parseable |
| §4.3 embeddings for related words / offline similarity | built-in embeddings, same file |
| Layer 1→2→3 routing, escalate-or-answer | tool calling |
| §7 "better, faster, smaller — and proven" | the ladder lets us **ship the shallowest depth that passes the gate**, which turns the slogan into an accuracy-vs-MB curve |
| §10.3 download budget | 8–29 MB against ~420 MB for Laya or 308M for EmbeddingGemma |

The ladder deserves emphasis: it converts "how small can this be?" from a
guess made before training into a measurement made after. That is exactly the
posture `evaluation-plan.md` is built around.

### 4.3 The honest objections

- **It is not a knowledge model.** 29–121M params, most of them in engram
  memory. It will not know what *obdurate* means and cannot replace Layer 1 or
  Layer 3. It is plumbing: route, extract, embed. Anyone reading the size and
  imagining it replaces the explainer has misread it.
- **No calibrated probabilities advertised** — Laya's main differentiator.
  Whether Needle exposes usable logits is a **blocking question** for the SRS
  scheduler and the escalation gate. Must be checked before adoption.
- **No published embedding numbers.** No MTEB, no dimension stated. The
  embedding claim is the load-bearing one for us and it is entirely
  unverified. Their published metrics are tool-call exact-match and extraction
  field micro-F1.
- **The right incumbent to beat is `potion-base-32M`, not EmbeddingGemma.**
  §4.3 of the landscape doc already lists Model2Vec's potion models: 8–32 MB,
  **MIT**, static, no new runtime, 92% of MiniLM's MTEB at 32M. Needle's
  embeddings have to beat that to justify adding an inference stack — a much
  higher bar than beating a 308M model.
- **Benchmarks are narrow and self-run.** "Beats models 10× its size" is on
  mobile tool calls; the 62.5 score and the claim of exceeding DeepSeek V4
  Flash is a 4-layer/29M variant tuned on DroidCall, one Android-command
  benchmark. Nothing there transfers to lexical judgment.
- **Possible cost leak.** Cactus Platform advertises fine-tuning at **$19 for
  3 runs**, while the Python package documents `needle finetune` / `needle
  build`. Whether the fully-local LoRA path is free and complete is a
  **go/no-go for the zero-cash constraint**.
- **Engine license ≠ weight license.** Weights are Apache 2.0; the `.cact`
  engine is a separate question, and Cactus is "source-available" per §3.2.
  This is open decision §10.4, now load-bearing.

Sources: [Cactus — Needle 3](https://cactuscompute.com/needle),
[Cactus-Compute/needle3](https://huggingface.co/Cactus-Compute/needle3),
[Designing tools for Needle](https://cactuscompute.com/blog/designing-tools-for-needle)

---

## 5. Layer 2 / Layer 3 candidates, side by side

| Option | Size on disk | License | iOS path | Calibrated? | Knows vocab? |
|---|---|---|---|---|---|
| `NLContextualEmbedding` | 0 (built in) | Apple | native | no | no |
| `potion-base-32M` (Model2Vec) | 8–32 MB | MIT | trivial (static) | n/a | no |
| ~~Needle 3~~ **REJECTED** | 33.7 MB measured | Apache 2.0 (weights) | vendor engine | head present, but accuracy at baseline | no |
| all-MiniLM-L6-v2 | ~22M params | Apache 2.0 | Core ML, well-trodden | no | no |
| Glite LENS (WSD bi-encoder) | 298M | Apache 2.0 code; weights TBC | Core ML likely | no | senses |
| EmbeddingGemma-300M | 308M | Gemma Terms | Core ML, 99.8% ANE | n/a | no |
| **Laya** | 420 MB int8 / 843 MB fp16 | Apache 2.0 | **none today** | **yes** | no |
| Jev | n/a (API) | closed | none | yes | no |

No option in this table knows vocabulary. That is the point of the
architecture: Layer 1 carries the knowledge, and every model here is a
judgment or retrieval device over facts it is handed.

---

## 6. Framing correction: it was never three options

A natural way to state the project's choice is "use an existing LLM, train our
own small model, or use a System One model." All three parts of that are
misleading:

1. **System One models are not an alternative to an LLM.** They replace part
   of Layer 2. They cannot define a word or explain nuance.
2. **"Train our own" is not available at zero cash.** §2 Step 0 of the
   landscape doc settled this: SmolLM3 (3B) took ~437,760 GPU-hours to
   pretrain. The real option is *fine-tune an existing base*, which is what
   the plan already says.
3. **It omits the option doing most of the work** — the lexical knowledge
   base, which is not a model at all.

The app has four distinguishable jobs, and each has its own best answer:

| Job | Examples | Right tool | Size |
|---|---|---|---|
| **Facts / lookup** | definitions, senses, POS, etymology, IPA, examples, synonym lists | **lexical KB — no model** | tables (~150–300 MB) |
| **Judgment** | which synonym fits, register, connotation, difficulty, collocation acceptability, WSD, grading a learner's sentence | typed-decision model / small classifier | 8 MB – 300M |
| **Semantics / retrieval** | semantic search, distractor generation, nearest-neighbour synonyms, tip-of-the-tongue queries | embeddings | 8–32 MB |
| **Open-ended explanation** | "why is *arduous* better than *strenuous* here", arbitrary follow-ups, tutor prose | instruction-tuned decoder | 0.8B–2B |

Most of what a vocabulary app is asked for is **retrieval, not inference** —
exact, tiny, offline, free. That is also what makes the generative layer cheap:
it never has to *know* anything, only explain facts handed to it.

**A genuine either/or survives in exactly one row**, the explainer:

- **(a) Off-the-shelf on-device** — AFM 3 Core via Foundation Models. Free,
  zero download, but no iOS 27 adapter toolkit, so its behaviour is fixed.
- **(b) Fine-tune a small open base** — 0.8B–2B, LoRA on Kaggle's free tier.
  Controllable tone and format; costs ~500 MB of download.
- **(c) Skip generation** — templated explanations driven by KB fields plus
  Layer 2 outputs. Underrated: fastest to a shippable, benchmarkable v1, and
  it gives the fine-tune a real baseline to beat. **Worth adding to Phase 0.**
- **(d) API** — ruled out; breaks offline, privacy and free at once.

This is the same conclusion as Options A/B/C in §8, stated as layers rather
than as alternatives. Nothing about the recommendation changes; the *choice*
was narrower than it looked.

---

## 7. What this changes in the architecture

Layer 1 and Layer 3 are unchanged. Layer 2 gains a cheaper first candidate and
absorbs the embedding slot:

```
 Layer 1  Lexical KB (SQLite, ~150–300 MB)            [unchanged]
             │ facts
 Layer 2  Judgment + retrieval                        [REVISED]
             │   was: several Core ML heads, 20–300M each
             │   tried: one Needle 3 depth for typed judgment
             │        + embeddings + routing -> REJECTED on
             │        measurement 2026-09-28
             │   now: potion-base-32M (1.9 MB) for retrieval,
             │        tables for context-free attributes,
             │        judgment slot OPEN (masked-LM first)
             │ scores + calibrated confidence + route
 Layer 3  Explainer (0.8B–2B, 4-bit, ~500 MB)         [unchanged]
             │   plus a new (c) templated baseline
             ▼
        streamed answer + structured card
```

Budget consequence, if Needle 3 passes: Layer 2 drops from a few hundred MB to
tens of MB, which puts the ≤1 GB total (goal ~700 MB) target in §7 comfortably
within reach and makes option (b) for the explainer affordable on more devices.

---

## 8. What this does *not* change

- **Phase 0 still comes first.** None of this is adoptable before the
  benchmark exists. Building the eval suite remains the next action.
- **Phase 1 is still the priority build.** The KB delivers most of the user
  value alone, grounds everything above it, and *generates the labelled data
  Layer 2 needs*. Neither Needle nor Laya can be fine-tuned or evaluated
  until it exists.
- **The data bottleneck is untouched.** Both models start near chance on
  domain judgment (Laya: 0.362 → 0.766 with fine-tuning). Labelled GRE-level
  judgment items are the scarce input, not parameters.
- **Targets and gates in `evaluation-plan.md` §4 stand.** These are new
  candidates for existing gates, not new gates.

---

## 9. Claims we must verify ourselves

Ordered by how much they would change the plan. Every row is currently
vendor-reported or unknown.

| # | Claim / question | Why it matters | Cost to check |
|---|---|---|---|
| V1 | Needle 3 embedding quality on **vocabulary** retrieval vs `potion-base-32M` | decides the whole Layer 2 consolidation | ~1 day, Mac, free |
| V2 | Does Needle 3 expose usable per-option probabilities / logits? | SRS scheduler + escalation gate depend on it | hours |
| V3 | Is a **fully local, free** `needle finetune` path complete, or is Cactus Platform ($19/3 runs) required? | zero-cash constraint | hours |
| V4 | `.cact` **engine** license terms for a commercial app | open decision §10.4 | hours, reading |
| V5 | Needle 3 typed-extraction accuracy on our GRE judgment probe, per ladder depth | gives the accuracy-vs-MB curve | ~2 days |
| V6 | Real on-device size, latency, memory on an actual iPhone (not a Pi 5) | §7 targets are phone targets | Phase 4 |
| V7 | Context window: 1024 (vendor) vs 8k (secondary source) | irrelevant if 1024 — our inputs are a word plus a sentence | minutes |
| V8 | Laya ModernBERT-large → Core AI conversion feasibility | only matters if we ever want Laya on-device | ~2 days, skip for now |

V1–V4 are cheap and gate everything else. Do them together before any
Needle-based design work.

---

## 10. Additions to the evaluation plan

Folded into `evaluation-plan.md` as part of this revision:

- **T4b — vocabulary retrieval with embeddings.** Gloss → headword (MRR@10)
  and word → rank true synonyms above near-misses and antonyms, over the GRE
  inventory and OEWN. Baselines: `potion-base-32M`, `NLContextualEmbedding`,
  EmbeddingGemma-300M. (Needle 3 was run 2026-09-28 and rejected.) V1 is
  answered for Needle; still open for the rest.
- **T11 — typed-decision judgment probe.** ~100 hand-written GRE-level items
  across synonym-fit, register, connotation and sense-ID, expressed as a
  typed schema. Metrics: accuracy **and expected calibration error**. This is
  V2 and V5, and it is the smallest artifact that can kill or confirm this
  whole direction.
- **T10 extension.** Record on-disk size *including the runtime engine*, and
  report an accuracy-vs-MB curve across ladder depths rather than one number.
- **New Phase 0 baselines.** Needle 3 (several depths); Laya via `laya-mlx` on
  the Mac as the judgment oracle; and the **templated-explanation baseline**
  from §6(c) for T8.
- **New calibration rule.** Any model whose confidence feeds the SRS scheduler
  or the escalation gate must report ECE on T11, not accuracy alone.

---

## 11. Effect on the open decisions

The two open decisions in §10 of the landscape doc that this makes urgent:

- **§10.3 Download budget.** Now genuinely consequential: 8–29 MB (Needle) vs
  ~420 MB (Laya int8) for the same architectural slot. A ~300 MB total budget
  is only reachable on the Needle branch.
- **§10.4 License comfort.** Was a general question about Cactus as a runtime;
  is now specific — Apache 2.0 weights running on a source-available engine,
  in a commercial app. V4 answers it.

Unchanged and still needed: Mac specs (§10.1), minimum iPhone (§10.2),
teacher policy (§10.5), existing app location and stack (§10.6).
