# Evaluation Plan — proving "better, faster, smaller"

Date: 2026-09-20. Companion to `2026-09-20-landscape-and-recommendation.md`.
Revised 2026-09-28 to add T4b, T11, a calibration rule and the typed-decision
baselines — see `2026-09-28-system-one-models-and-tiny-on-device-models.md`.

Principle: the benchmark is built in Phase 0, before any model is trained,
and never changes after a model has seen it. Every phase gate in the roadmap
is a number from this suite.

## 0. Goal restatement (2026-09-28)

**The target is general English competence, not GRE coverage.** GRE-level words are a
*proficiency probe* — a way to test whether the system holds up in the hard tail — not
the scope of the product. Two consequences for this plan:

1. **Report every subtask stratified by Zipf frequency band**, never as a single
   average. "Good at English" means competent from *said* (Zipf 4.9) to *perspicacious*
   (Zipf 1.7); an average conceals precisely the failure that matters. Measured
   2026-09-28: SWORDS median Zipf 4.86, ProLex 4.67, our GRE inventory 2.76 — existing
   benchmarks live at the common end, so stratified reporting is mandatory rather than
   optional.
2. **Two capabilities are missing from the battery below** and should be added:
   **collocation acceptability** ("strong tea" vs "powerful tea") and **idiom
   handling** (figurative vs literal). MAGPIE covers the second for free — 1,756
   English idioms, 56,622 crowd-annotated BNC instances, idiomatic/literal/other.

Competence at common words is **table stakes, not a lesser test**. A model that
mis-ranks substitutes for *good* is not good at English regardless of its rare-word
score. The 2026-09-28 fine-tune failed at the common end (AUC 0.618 vs a 0.600
zero-training baseline), which is a stronger negative than it first appeared.

Benchmark to prioritise: **LongTail-Swap (LT-Swap)** — correct-vs-incorrect word use in
context, natively stratified from 512+ occurrences down to once-or-never. Plus **T3
below (950 GRE closest-opposite items), which is already in this plan and has never
been run.**

## 1. Subtasks, datasets, metrics

| # | Subtask (maps to a brief capability) | Dataset(s) | Size | License / use | Metric |
|---|---|---|---|---|---|
| T1 | **Contextual word choice** — pick the best word for a blank among near-synonyms, the brief's "most important capability" | [SWORDS](https://github.com/p-lambda/swords) (human-judged appropriateness of thesaurus candidates in context; bundles CoInCo, SemEval-2007 LexSub, TWSI in one format) | thousands of contexts | CC-BY-3.0-US | Ranking: GAP / precision@k against human labels; classification: F1 on "appropriate" |
| T1b | Same, learner-proficiency flavour | [ProLex](https://github.com/BillyZhang24kobe/LS_Proficiency) (target word, TOEFL-11 sentence, acceptable substitutes, proficiency-oriented substitutes) | 680 test pairs (avg 2.9 acceptable, 2.3 proficiency substitutes) | ACL 2024 repo; check LICENSE file | Soft/hard F1@10 for acceptable (F) and proficiency (Fp). Reference: GPT-4 32-shot 54.7 / 48.8 |
| T1c | Same, classic near-synonym sets | Edmonds / Inkpen & Hirst near-synonym FITB (7 sets, WSJ sentences with the near-synonym gapped) | ~2k sentences | academic; rebuild from WSJ-free text if needed | Accuracy |
| T1d | Exam-style cloze with distractors | [CLOTH](https://arxiv.org/pdf/1711.03225) (99,433 questions from Chinese middle/high-school English exams); [SC-Ques](https://github.com/ai4ed/SC-Ques) (289,148 ESL sentence-completion questions) | large | research use; eval and training splits kept separate | Accuracy; report the "vocabulary" subset separately from grammar items |
| T1e | Sentence completion, literary register | MSR Sentence Completion Challenge (1,040 Sherlock Holmes sentences, 5 options) | 1,040 | Microsoft Research license (eval only) | Accuracy |
| T2 | **Word sense in context** ("which meaning is meant here?") | [lexEN](https://github.com/GliteTech/lexen) (corrected ALL_NEW), Raganato ALL; [WiC](https://pilehvar.github.io/wic/) (same sense or not, binary) | ALL ≈ 7k instances; WiC 1.4k test | WiC is CC BY-NC 4.0 (eval only) | Accuracy, fine and coarse-grained. References: frontier LLMs ≈ 95% on lexEN; Glite LENS 298M = 83.6 on ALL |
| T3 | **Synonym / antonym knowledge at GRE level** | TOEFL 80 synonym questions (available on request; ACL wiki tracks SOTA); ESL 50; [Mohammad et al. 2008 GRE closest-opposite questions](http://www.umiacs.umd.edu/~saif/WebDocs/LC-data/) (162 dev / 950 test, 5 choices each) | ~1,100 | research | Accuracy. GRE antonyms are the direct "GRE+ level" test |
| T4 | **Similarity vs relatedness sanity** (embeddings) | SimLex-999, WordSim-353, SimVerb-3500 | ~5k pairs | open | Spearman ρ |
| T4b | **Vocabulary retrieval** (added 2026-09-28) — does an embedding model actually help *our* data? Two probes: (a) gloss → headword; (b) given a word, rank true synonyms above near-misses, co-hyponyms and antonyms | GRE inventory (~9,566) + Open English WordNet senses and relations; distractors drawn from Moby and WordNet siblings | ~10k queries | CC-BY / public domain | (a) MRR@10 and recall@1; (b) ranking accuracy and GAP. Run per candidate: `potion-base-32M`, `NLContextualEmbedding`, EmbeddingGemma-300M. (Needle 3 was run on 2026-09-28 and rejected — see `results/`.) **Report (a) and (b) as separate numbers:** a single precision@k conflates them and made a bad model look competitive. Only (a) is a capability we should ask an embedding for; (b) comes from WordNet relations. |
| T5 | **Register / formality / connotation** ("which sounds more formal?", "is it negative?") | Pavlick & Nenkova formality scores (pairwise comparisons derived from human ratings); Feng et al. connotation labels; Wiktionary usage tags (formal/informal/slang/archaic) as silver labels | 7.8k + 94k + large | academic / CC BY-SA | Pairwise accuracy (formality), macro-F1 (connotation), tag F1 |
| T6 | **Difficulty / level** ("is this a GRE word?", CEFR level) | CEFR-J word profiles; Words-CEFR-Dataset; BEA 2026 Shared Task 1 (British Council KVL) | tens of thousands | open / task terms | Spearman ρ with gold; exact-level accuracy ±1 |
| T7 | **Definition quality** ("what does it mean / explain simply / ELI12") | Held-out Open English WordNet and Wiktionary glosses (never used for training); CODWOE-style definition modelling | 2k held-out senses | CC-BY / CC BY-SA | BERTScore vs gold gloss; readability (Flesch-Kincaid grade) must hit the requested level; LLM-judge rubric |
| T8 | **Grounded explanation quality** ("how do these synonyms differ, and why does X fit best?") | Our own 300-item test set: (context, candidates, KB facts, ranker scores) → free-text explanation; gold written once by a frontier model with human editing | 300 | ours | (a) **Fact consistency**: every atomic claim in the explanation is entailed by the supplied KB facts — automatic NLI check + spot audit; target hallucination rate < 2%. (b) **Blind pairwise preference** vs a frontier model's grounded explanation and vs a raw dictionary entry. (c) Length and reading level compliance |
| T9 | **Coverage** (the dictionary-API pain point) | GRE inventory (~9,566 words from 13 prep sources) + Oxford 5000 headwords | ~12k | facts | % with definition, IPA, POS, frequency, ≥2 examples, register tag, ≥3 synonyms, ≥1 antonym |
| T10 | **Efficiency on device** | Fixed prompt set of 200 queries per layer | — | — | TTFT (ms), decode tok/s, peak RSS (MB), energy per 100 queries (Instruments/MetricKit), on-disk size (MB), cold-start (ms). Devices: oldest supported iPhone, iPhone 15 Pro, newest. *Added 2026-09-28:* on-disk size must include the **runtime engine**, not just weights; and for any laddered model report an **accuracy-vs-MB curve across depths** rather than a single number |
| T11 | **Typed-decision judgment probe** (added 2026-09-28) — the smallest artifact that can kill or confirm the typed-decision direction. ~100 hand-written GRE-level items expressed as one JSON schema: synonym-fit in context, register, connotation, sense-ID | Ours, hand-written; distractors from the GRE inventory and OEWN; cross-checked against T1/T5/T6 gold where they overlap | 100 items (grow to 500 if the direction survives) | ours | Accuracy **and expected calibration error (ECE, 10 bins)**, plus % of outputs that parse. Run zero-shot first, then after fine-tuning. **Verification items V2 and V5** |

## 2. Baselines to run in Phase 0 (prompting only, no training)

1. Apple AFM 3 Core via Foundation Models (macOS 27 / iOS 27 device).
2. Qwen3.5-0.8B, Qwen3.5-2B, Gemma 4 E2B, LFM2.5-1.2B, Gemma 3 1B via MLX on the Mac.
3. Masked-LM candidate scoring (DeBERTa-v3-small or similar) for T1 — the zero-training ranker baseline.
4. `NLContextualEmbedding` cosine similarity for T1/T2 — the zero-download baseline.
5. One frontier model as the quality ceiling, if its terms permit evaluation use.
6. The current dictionary-API pipeline for T9 (coverage) only.
7. ~~*(added 2026-09-28)* **Needle 3** at ladder depths 2/4/8/20~~ — **run and
   rejected 2026-09-28**, see `results/2026-09-28-needle3-potion-probe.md`.
   Replaced by: **potion-base-32M** (measured 1.9 MB, the retrieval pick) and a
   **masked-LM candidate-scoring baseline** for the open judgment slot.
8. *(added 2026-09-28)* **Laya** via `laya-mlx` on the Mac, for T11 and T1/T5 —
   not a shipping candidate, but the judgment oracle and label generator that a
   phone-sized model is measured against.
9. *(added 2026-09-28)* **Templated-explanation baseline** for T8: explanations
   assembled from KB fields and Layer 2 scores with no generative model at all.
   The explainer fine-tune has to beat this to justify its ~500 MB.
10. *(added 2026-09-28)* **`potion-base-32M`** for T4b — the embedding
    incumbent, MIT and requiring no new runtime. Any new embedding dependency
    must beat it, not merely beat EmbeddingGemma.

Every result goes into `docs/research/results/phase0.md` as a single table.

## 3. Rules

- Splits: any dataset used for training (CLOTH, SC-Ques, SWORDS train, SemCor, synthetic) has its test portion frozen and hashed before training starts.
- Synthetic training data must not be generated from the test items' contexts.
- LLM-as-judge is used only for T7/T8, always with a fixed rubric and a fixed judge model version, and 10% of judgments are audited by hand.
- On-device numbers are measured warm and cold, three runs, median reported, with quantisation and runtime version recorded (the practice the Apple-silicon benchmark repo follows).
- *(added 2026-09-28)* **Calibration rule.** Any model whose confidence feeds the spaced-repetition scheduler or the escalate-to-explainer gate must report ECE on T11, not accuracy alone. A well-ranked but badly calibrated model is unusable for routing, so a model that cannot emit per-option probabilities is disqualified from those two roles regardless of its accuracy.
- *(added 2026-09-28)* **Vendor numbers are not results.** Figures taken from a model card or vendor blog are recorded in a separate column marked *vendor-reported* and never mixed into our own measured tables. Nothing quoted from a vendor may satisfy a phase gate.

## 4. Targets for the shipped v1

| Metric | Target | Reference |
|---|---|---|
| T1b ProLex soft F1 / Fp (own ≤1B stack) | ≥ 50 / ≥ 45 | GPT-4 32-shot: 54.7 / 48.8; Llama-2-13B fine-tuned: 54.2 / 48.4 |
| T2 lexEN coarse accuracy (298M-class bi-encoder) | ≥ 85 | Glite LENS 83.6 (fine, ALL); frontier ≈ 95 |
| T3 GRE antonym accuracy | ≥ 85 | (to be set after Phase 0 baselines) |
| T8 hallucination rate vs KB | < 2% | — |
| T8 blind preference vs frontier grounded explanation | ≥ 50% win-or-tie | — |
| T9 GRE inventory coverage (definition+IPA+POS+freq) | ≥ 99% | dictionary APIs: measure in Phase 0 |
| T10 ranker latency (iPhone 15 Pro) | < 50 ms | — |
| T10 explainer decode (iPhone 15 Pro) | ≥ 30 tok/s | Apple 3B (2025): 30 tok/s; Qwen3-0.6B via Cactus on iPhone 17: 70+ |
| T10 total on-disk size | ≤ 1 GB (goal ~700 MB), engine included | — |
| T4b gloss → headword MRR@10 (shipped embedding model) | ≥ `potion-base-32M` at ≤ its size | potion-base-32M: measure in Phase 0 |
| T11 accuracy, ≤30 MB judgment model | ≥ 80% of the fine-tuned Laya oracle's accuracy, **and strictly above majority-class** | Laya after fine-tune: 0.766 (vendor). Needle 3 measured **at** majority-class (6/12 vs 50%) — this is why the baseline column is mandatory |
| T11 expected calibration error | ≤ 0.05 | — |
| T11 output parse rate | 100% (byte-level grammar should make this free) | — |
| T10 Layer 2 on-disk size | ≤ 50 MB | potion-base-32M: **1.9 MB measured**; Needle 3 was 33.7 MB measured and rejected |

## 5. Harness

Plain Python on the Mac (`uv` project), one module per subtask, JSONL in/out,
a single `make eval MODEL=...` entry point; MLX for local models, Foundation
Models via a tiny Swift CLI on macOS 27; results committed as Markdown tables.
Standard tasks (WiC, SimLex) can also run through `lighteval` or
`lm-evaluation-harness`, but the custom tasks are the ones that matter, so we
keep the harness small and ours.
