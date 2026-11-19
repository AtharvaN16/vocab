# On-Device Vocabulary Intelligence — Landscape, Process, and Recommendation

Date: 2026-09-20
Status: research complete, awaiting decisions (see §10)
Author: research pass by Claude for Atharva's Vocab_Model project

> **Revised 2026-09-28.** Layer 2 of the recommended architecture now has
> better candidates than this document knew about: three "System One"
> typed-decision models shipped 15–18 September 2026, five days before this
> pass. See `2026-09-28-system-one-models-and-tiny-on-device-models.md` for
> the evaluation, a corrected four-job framing of the project's choices, and
> the new benchmark items. Affects §4.2, §4.3, §8 Layer 2, §10.3 and §10.4.
> Layers 1 and 3, the process in §2, and the roadmap in §9 are unchanged.

This document answers the questions in the project brief:

1. Is what we want in the same realm as Desert Ant Labs? (§1)
2. How do people actually make small specialised models? Is there a process? (§2)
3. What can realistically run on an iPhone today? (§3)
4. Which existing models and datasets can we reuse? (§4, §5)
5. Can we do it for free? (§6)
6. What does "better, faster, smaller than anything out there" mean, and how do we prove it? (§7)
7. What architecture should we build? (§8)
8. What is the path from here to a working prototype? (§9)

Sources are linked inline. Every number below came from a source I read today;
where I could not verify something, I say so.

---

## 1. Desert Ant Labs, and how our problem differs

[Desert Ant Labs](https://desertant.com/) ships 18 small on-device models
(12 stable, 6 beta) behind one SDK for Swift, Kotlin and JavaScript. Their
thesis, verbatim: *"Small models that each do one job very well, with one
native SDK that drops them into any product in a few lines of code."* Models
are tiny — Tongue (language ID) is 2 MB, Clear (speech enhancement) 9 MB,
Redact (PII masking) 12 MB, Clips (video highlights) 284 MB — and run on Core
ML / the Neural Engine on iPhone and WebAssembly in browsers. They benchmark
against generalists: Redact reaches *"88.8% personal data detection from a
12MB model"* vs GLiNER-PII's 91.1% at 2.3 GB; Voz transcribes *"10 minutes of
audio in 2s on an iPhone"*, 4.7x faster than Whisper. Free up to 100k monthly
active devices per platform.
([intro post](https://desertant.com/blog/introducing-desert-ant-labs/),
[models](https://desertant.com/models/))

**What this tells us.** Every Desert Ant model is *discriminative*: classify,
detect, extract, align, transcribe. Those tasks compress into a few megabytes
because the output space is small. None of their models is a dictionary or
explains word nuance; there is no direct competitor there.

**How our problem differs.** The brief asks for two different kinds of
capability, and they belong to different model families:

| Capability | Kind | Right tool | Realistic size |
|---|---|---|---|
| "Which of these six words fits this blank best?" | ranking / classification | small encoder scoring candidates | 20–150M params |
| "Which sense of *arduous* is meant here?" | classification against a sense inventory | bi-encoder + precomputed gloss embeddings | 100–300M |
| "Is this word formal / negative / rare / GRE-level?" | regression / lookup | lexicon tables + tiny heads | ~0 (tables) |
| "Explain the difference between *arduous* and *strenuous* like I'm 12" | open-ended generation | instruction-tuned decoder | 0.8B–3B |

So we are *partly* in Desert Ant's realm (the judgment layer, which can and
should be tiny), and partly in the small-LLM realm (the explanation layer,
which cannot be 12 MB). The design in §8 keeps the generative part as small as
possible by never asking it to *know* facts — only to *explain* facts and
scores that the deterministic and discriminative layers hand it.

---

## 2. How small specialised models actually get made

There is a fairly standard process. It is documented in Hugging Face's
[Smol Training Playbook](https://huggingfacetb-smol-training-playbook.hf.space/)
(the full write-up of how SmolLM3 was built), in Google's
[Gemma 3 270M on-device recipe](https://developers.googleblog.com/en/own-your-ai-fine-tune-gemma-3-270m-for-on-device/),
in Apple's [adapter training guide](https://developer.apple.com/apple-intelligence/foundation-models-adapter),
and in the 2026 synthetic-data literature. The steps:

### Step 0 — Decide whether to train at all

The playbook's rule, paraphrased from its "why train" section: try
**prompting** a current model first (they name Qwen3 and Gemma 3); if that
fails, **fine-tune** — "even if the post-training budget needed to meet your
requirements is immense, it might still be cheaper than starting from
scratch"; **train from scratch** only for a research hypothesis, a hard
production constraint, or a strategic open-source gap. SmolLM3 (3B params, 11T
tokens) cost about 437,760 GPU-hours. Pretraining is therefore out of scope
for a zero-budget project; we will fine-tune.

### Step 1 — Build the evaluation before the model

Desert Ant leads with benchmark numbers against generalists; ProLex and
SWORDS (§5) exist precisely because "is this synonym appropriate here?" needs
human-judged gold data. We cannot claim "better" without a fixed test set. The
suite is specified in `evaluation-plan.md`.

### Step 2 — Pick a base model by deployment constraints, not leaderboard

License, size at 4-bit, runtime support on iOS, and whether a text-only
variant exists matter more than MMLU. Candidates are in §4.

### Step 3 — Assemble data: real seeds + synthetic distillation + a judge

The 2026 recipe is consistent across sources: *"small real seed, frontier
teacher, structured generation, judge filter, JSONL output into TRL or
Unsloth. The single most important step is the judge filter; an unfiltered
synthetic dataset is worse than a smaller filtered one."*
([Future AGI, 2026](https://futureagi.com/blog/synthetic-data-fine-tuning-llms/)).
ProLex is a worked example in our exact domain: its authors fine-tuned
Llama-2-13B on 1,383 GPT-4-synthesised pairs plus 1,132 filtered SWORDS pairs
and reached soft F1 54.2 / proficiency F1 48.4 against GPT-4's 54.7 / 48.8 with
32-shot prompting — a specialised small model matching the frontier model on
the task ([ProLex, ACL 2024](https://arxiv.org/html/2401.11356v3)).

Apple's guidance on quantity for the 3B adapter: *"100 to 1,000 samples to
teach the model basic tasks"*, *"5,000+ samples to teach the model complex
tasks"*. Google fine-tunes Gemma 3 270M with QLoRA on a free Colab T4 "in
minutes".

### Step 4 — Supervised fine-tuning (LoRA or full)

- Mac: `mlx-lm` LoRA needs roughly 2 GB of unified memory per 1B parameters
  (QLoRA ~0.5 GB/1B). A 0.8B model fine-tunes comfortably on a 16 GB Mac.
- Free cloud: Unsloth publishes free Colab notebooks for Qwen3.5 0.8B/2B/4B
  and Gemma 4 E2B ([Unsloth notebooks](https://github.com/unslothai/notebooks)).
- Kaggle gives 30 GPU-hours/week with sessions up to 9 h (§6).

### Step 5 — Optional preference tuning (DPO) for tone and format

Only after SFT works; needs pairwise data. Defer.

### Step 6 — Quantise and convert for the target runtime

4-bit or 8-bit weights; formats are MLX safetensors, GGUF (llama.cpp),
`.litertlm` (LiteRT-LM) or `.aiasset` (Apple Core AI). Gemma ships
quantisation-aware-trained (QAT) checkpoints so int4 loses very little.

### Step 7 — Measure on the phone

Quality on the eval suite, plus time-to-first-token, tokens/s, peak memory,
energy. Iterate on data, not architecture.

That is the whole "framework". Nothing in it requires money; it requires a
good test set and patience with data quality.

---

## 3. What runs on an iPhone in September 2026

### 3.1 Apple's stack after WWDC 2026 (iOS 27)

Apple reorganised on-device AI into three layers
([overview](https://andrew.ooo/answers/apple-core-ai-vs-foundation-models-vs-mlx-ios-27-framework-june-2026/)):

- **Foundation Models framework** — runs Apple's own system model. iOS 27
  ships *AFM 3 Core*, "the next generation of our 3-billion-parameter dense
  model" ([Apple ML Research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)).
  Context window is 8,192 tokens (queryable via `model.contextSize` since
  iOS 26.4). Image input and improved tool calling arrived in 27; Apple says
  guardrail false positives were reduced in 26.4 and again in 27
  ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)).
  Free, no download, but limited to Apple Intelligence devices (iPhone 15 Pro
  and later).
- **Core AI** — new in iOS 27; the successor to Core ML for running *your
  own* models. Load an `.aiasset`, specialise once per device, get an
  `InferenceFunction`, run with `NDArray` inputs; explicit CPU/GPU/Neural
  Engine targeting; 4- and 8-bit quantisation; MLX has an export path to
  `.aiasset` ([Apple docs](https://developer.apple.com/documentation/coreai),
  [WWDC26 "Meet Core AI"](https://developer.apple.com/videos/play/wwdc2026/324/)).
  One secondary source reports it is limited to Apple Intelligence-eligible
  devices — treat as unverified until checked against Apple's docs.
- **MLX** — research/training framework; MLX Swift also runs LLMs in apps.

**Custom adapters for Apple's model: not a safe foundation right now.** The
adapter toolkit trains rank-32 LoRA adapters (~160 MB each), needs a Mac with
32 GB or a Linux GPU, needs an Apple entitlement to ship, and *"each adapter
is compatible with a single specific system model version"*. Apple's page
states: *"Version 26.0.0 is the last release of this toolkit and is not
compatible with macOS, iOS, iPadOS, or visionOS 27 and later."* I found no
27-series toolkit today (checked Apple's page, community wrappers, and
third-party trainers). Apple's own advice is to exhaust prompting and tool
calling first. Conclusion: use Foundation Models as a *baseline and possible
fallback explainer*, not as the thing we fine-tune.

### 3.2 Third-party runtimes, with measured iPhone numbers

The most careful public comparison is
[apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
(iPhone 17 Pro, Gemma 4 E2B, warm runs, 2026-07-28):

| Runtime | Decode tok/s | Peak memory | Time to first token |
|---|---|---|---|
| LiteRT-LM (Google) | 61.1 | 497 MB | 16.3 ms |
| Cactus | 50.0 | 632 MB | — |
| MLX-Swift | 49.1 | 3,010 MB | 20.5 ms |
| Core AI | 47.1 | 755 MB | — |
| llama.cpp | 38.8 | 191 MB resident (weights mmap'd) | 24.4 ms |

On an M4 Max Mac Studio, Qwen3.5-0.8B decodes at 421 tok/s in MLX and 201
tok/s in llama.cpp; Qwen3.5-2B at 292 / 150.
[Cactus](https://huggingface.co/blog/rshemet/cactus-on-device-inference)
reports Qwen3-0.6B-int8 at "70+ tok/sec" on iPhone 17 and 16–20 tok/s on an
iPhone 11. Apple's 2025 figures for its own 3B model were 30 tok/s on iPhone
15 Pro.

Takeaways:

- A **0.8B model at 4-bit is comfortably fast** (50–100+ tok/s on recent
  iPhones) and fits in ~500–700 MB.
- **LiteRT-LM** has the best speed/memory but its Swift API is marked "Early
  Preview" ([repo](https://github.com/google-ai-edge/LiteRT-LM), Apache 2.0).
- **MLX Swift** is the simplest from Swift and fastest on Qwen-family models,
  at the cost of memory (weights fully resident). Ollama moved to MLX on Apple
  silicon in March 2026.
- **llama.cpp** is the portable, lowest-footprint option.
- **Cactus** is source-available, "free for hobbyists, students, non-profits
  as well as small businesses" — check the exact license before depending on it.
- For **encoders** (our ranking/sense/attribute models), Core ML on the
  Neural Engine remains the right choice; EmbeddingGemma conversions report
  99.8% of ops on the ANE.

### 3.3 Built-in free primitives

- `NLContextualEmbedding` (NaturalLanguage framework, iOS 17+): on-device
  BERT-style contextual embeddings, 512-d on iOS, 27 languages, zero download.
  Useful as a baseline for context-fit scoring.
- `AVSpeechSynthesizer`: offline TTS for pronunciation playback.
- `UIReferenceLibraryViewController`: Apple's dictionary UI (no programmatic
  access to definitions, so not a data source).

---

## 4. Candidate models to reuse

### 4.1 Generators (the explainer)

| Model | Params | License | Notes |
|---|---|---|---|
| [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B) | 0.8B | Apache 2.0 | Released 2026-03-02. Hybrid Gated-DeltaNet + sparse MoE; ships with a vision encoder (text-only mode available). 262k context. 274 community quantisations. **Lead candidate.** |
| Qwen3.5-2B / 4B | 2B / 4B | Apache 2.0 | Same family, higher quality; 2B still phone-feasible. |
| [Gemma 4 E2B](https://huggingface.co/google/gemma-4-E2B-it) | 2.3B effective (5.1B incl. embeddings) | Apache 2.0 | Multimodal (audio+vision). Best LiteRT-LM support. Heavier than needed for text-only. |
| Gemma 3 270M / 1B | 0.27B / 1B | Gemma Terms of Use | 270M is built for task specialisation; QAT int4 checkpoints; under 300 MB. Too small to write good explanations alone; fine for narrow generation (e.g. example sentences). |
| [LFM2.5](https://www.liquid.ai/blog/introducing-lfm2-5-the-next-generation-of-on-device-ai) 350M / 1.2B | 0.35B / 1.2B | LFM Open License (free under $10M revenue) | CPU-first design, ~2x faster decode than Qwen3 on CPU per Liquid. |
| Granite 4.0-H 350M / 1B | 0.35B / 1B | Apache 2.0 | Hybrid Mamba-2; in the iPhone benchmark suite. |
| SmolLM3-3B | 3B | Apache 2.0 | Fully documented training; probably too large for our budget. |
| AFM 3 Core (via Foundation Models) | 3B | Apple platform | Zero download; 8k context; guardrails; Apple Intelligence devices only. **Baseline and fallback.** |

### 4.2 Judgment models (rankers, sense, attributes)

- **Context-fit ranker**: any small masked language model (DeBERTa-v3-small,
  ModernBERT-base class, or even the built-in `NLContextualEmbedding`) scoring
  candidates in the blank is the classic lexical-substitution baseline
  (BERT-M / BERT-K in the SWORDS paper). Fine-tuning a cross-encoder on
  SWORDS + ProLex + cloze data is the upgrade path.
- **Word-sense disambiguation**: the September 2026 paper
  [English WSD in 2026: When the Labels Become the Bottleneck](https://arxiv.org/abs/2609.17554)
  evaluated 57 frontier LLMs — the top ones cluster at ~95% on the corrected
  lexEN benchmark — and released *Glite LENS*, a 298M bi-encoder scoring 83.6
  on Raganato ALL. Code is Apache-2.0 at
  [GliteTech/research-semcor-relabeling](https://github.com/GliteTech); weight
  availability needs checking. Their finding that coarsening the sense
  inventory raises both human agreement and model accuracy is directly useful:
  learners do not need WordNet-fine senses.
- **Attribute heads** (formality, connotation, intensity, difficulty): mostly
  table lookups from the lexicons in §5; a small regressor over static
  embeddings fills gaps for words outside the lexicons.
- **Typed-decision models** (added 2026-09-28): a single schema-driven model
  could in principle serve *all* of the above instead of one head per attribute.
  ~~[Needle 3](https://cactuscompute.com/needle)~~ **was measured and rejected
  on 2026-09-28** — it ties the majority-class baseline on connotation, returns
  nothing on register, and its embeddings put `carburettor` nearest to *arduous*;
  it is a tool-calling model, not a lexical one
  (`results/2026-09-28-needle3-potion-probe.md`). The idea remains worth testing
  with a better-suited model; the lead for this layer is once again the
  masked-LM scoring baseline and a fine-tuned small cross-encoder, below. [Laya](https://github.com/NandhaKishorM/laya) (Convai,
  Apache 2.0, 421M) is too heavy for the phone and has no Core ML path, but its
  RLCD + temperature calibration recipe and its act-or-escalate head are
  directly applicable, and it makes a good Mac-side oracle. Jev (TypeSafe) is
  closed and API-only: rejected. Full evaluation and the claims still to verify
  are in `2026-09-28-system-one-models-and-tiny-on-device-models.md`.

### 4.3 Embeddings

| Model | Size | License | Notes |
|---|---|---|---|
| [EmbeddingGemma-300M](https://huggingface.co/google/embeddinggemma-300m) | 308M | Gemma Terms | 768-d; Core ML and LiteRT conversions exist; 99.8% ANE. |
| [potion-base-8M / 32M](https://github.com/MinishLab/model2vec) (Model2Vec) | 8–32 MB | MIT | Static embeddings, hundreds of times faster than MiniLM; 32M keeps 92% of MiniLM's MTEB score. Ideal for "related words" and offline similarity. |
| all-MiniLM-L6-v2 | 22M | Apache 2.0 | Well-trodden Core ML path. |
| `NLContextualEmbedding` | built in | Apple | Free baseline. |
| ~~Needle 3~~ | measured 33.7 MB + 0.78 MB engine | Apache 2.0 | **REJECTED 2026-09-28 on measurement.** Embeddings severely anisotropic (mean pairwise cosine 0.9262); nearest neighbour of *arduous* is `carburettor`; `difficult` ranks 12/15. It did not clear `potion-base-32M`, which is 1.9 MB and 170× faster. |
| **potion-base-32M — measured** | **1.9 MB**, 512-d, 0.03 ms/word | MIT | Mean pairwise cosine 0.0933 (healthy); separates related from unrelated 9/10. Cannot distinguish synonym from antonym — by design, do not ask it to; read that from WordNet. **Provisional pick for this slot.** |

### 4.4 Definition generation (for data bootstrapping and evaluation, not shipping)

[ltg/flan-t5-definition-en](https://huggingface.co/ltg/flan-t5-definition-en-base)
(base/large/xl) generates a definition of a word *in context* (ACL 2023,
Giulianelli et al.). Research-intended per the card; useful for producing
sense-specific glosses for synthetic data, and as a sanity baseline.

---

## 5. Data: what is free, and what it gives us

Full table with links and licenses in `resources-catalog.md`. The important
ones:

| Need | Source | License | Why it matters |
|---|---|---|---|
| Senses, definitions, synsets, hypernyms, antonyms, examples | [Open English WordNet 2025](https://github.com/globalwordnet/english-wordnet) (JSON/LMF) | CC-BY 4.0 | Clean, permissive backbone. Proper nouns moved out in 2025. |
| Everything else: IPA, audio, etymology, inflections, usage tags (formal, informal, archaic, dated, slang, literary), quotations, synonyms | English Wiktionary via [kaikki.org / wiktextract](https://kaikki.org/dictionary/English/index.html) (JSONL, 1.39M distinct words incl. forms, 967k noun senses) | CC BY-SA 4.0 + GFDL | Richest free lexicon in existence. Share-alike applies to the *data* we ship; plan attribution. |
| Pronunciation (ARPAbet) | CMUdict; ipa-dict | BSD-style; MIT | Deterministic, ~134k words. |
| Frequency (Zipf) | [wordfreq](https://github.com/rspeer/wordfreq) | Apache 2.0 code; data from CC-BY-SA sources and SUBTLEX with permission | "How common is this word?" |
| Collocations | Google Books Ngrams (CC BY 3.0); OANC (CC0, 15M words); Leipzig corpora (CC-BY); OpenSubtitles via OPUS | open | Compute "words used with X" and spoken-vs-written ratios ourselves. |
| Huge synonym net | Moby Thesaurus II (30,260 roots, 2.5M links) | public domain | Recall booster; noisy. |
| Example sentences | Tatoeba (CC BY 2.0 FR; some CC0) | open | Learner-friendly sentences. |
| Difficulty level | [CEFR-J profiles](https://github.com/openlanguageprofiles/olp-en-cefrj) (free incl. commercial with citation); [Words-CEFR-Dataset](https://github.com/Maximax67/Words-CEFR-Dataset) (MIT) | open | A1–C2 tags per word/POS. Oxford 3000/5000 CEFR PDFs are © OUP — reference only. |
| GRE inventory | [gre-words-collection](https://github.com/Xatta-Trone/gre-words-collection): ~9,566 words merged from 13 prep sources | no license stated (word lists are facts; do not copy their definitions) | The "GRE+" target set we must cover. |
| Concreteness, age of acquisition, valence/arousal/dominance | Brysbaert 2014 (40k), Kuperman 2012 (30k), Warriner 2013 (14k) | free for research, distributed with papers; confirm commercial terms | Difficulty and "feel" of a word. |
| VAD, 55k terms | [NRC VAD v2](https://arxiv.org/html/2503.23547v1) | free for research; commercial needs a nominal-fee license from NRC | Same. |
| Formality and complexity, human-rated | Pavlick & Nenkova style lexicon (7,794 words/phrases formality; 5,699 complexity) | no license stated (academic) | "Which synonym sounds more formal?" |
| Connotation (pos/neg/neutral), 93,873 entries | [Feng et al. 2013](https://www3.cs.stonybrook.edu/~ychoi/connotation/) | no license stated; contact authors | "Is this word negative?" |
| Sense-tagged text for WSD training | SemCor (WordNet license); [LLM-relabeled SemCor](https://github.com/GliteTech/llm-relabeled-semcor) | permissive / Apache-2.0 | Train the sense bi-encoder. |
| Vocabulary difficulty (2026) | BEA 2026 Shared Task 1 (British Council KVL) | check task page | Fine-tuned models reach r > 0.91 on difficulty. |

Two license notes you should decide on early: Wiktionary's CC BY-SA means the
*compiled lexicon* we ship is a derivative that must stay share-alike with
attribution (the app code is unaffected); and the psycholinguistic norms and
NRC lexicons are research-free but may need a (cheap) commercial license if
the app is commercial. WordNet, CMUdict, Moby, Tatoeba, Ngrams, CEFR-J and
wordfreq are commercially clean.

---

## 6. Can we do it for free?

Yes, for everything except (possibly) two nominal data licenses. Budget:

| Resource | Free tier (verified 2026-09) | Enough for us? |
|---|---|---|
| Your Apple-silicon Mac | LoRA ≈ 2 GB per 1B params; full fine-tune of ≤0.8B fine on 16–32 GB | Yes for training 0.3–2B models |
| Kaggle | 30 GPU-hours/week (T4x2 or P100), sessions up to 9 h | Yes |
| Google Colab free | T4, dynamic (~15–30 h/week reported), sessions ≤12 h | Yes, with Unsloth notebooks |
| Apple adapter toolkit | needs Mac with ≥32 GB | Optional path only |
| Teacher via local open weights | Qwen3.5-9B, Gemma 4 E4B/26B-A4B on a 32–64 GB Mac through MLX | Best legal position (Apache 2.0) |
| Teacher via free APIs | Gemini Flash-class: hundreds to ~1,000 requests/day (Pro removed from free tier April 2026); Groq: 14,400 req/day, 6k tokens/min, all models | Enough for tens of thousands of samples over a few weeks |

**Terms-of-service caveat on teachers.** Anthropic's and Google's API terms
prohibit using outputs to develop *competing* models
([Claude help](https://support.claude.com/en/articles/12326764-can-i-use-my-outputs-to-train-an-ai-model),
[Gemini API terms](https://ai.google.dev/gemini-api/terms)). A vocabulary
tutor is arguably not a competitor, but the cleanest route is to generate
synthetic data with open-weight teachers (Qwen 3.5 and Gemma 4 are Apache
2.0) run locally on the Mac or through Groq. This also applies to me: data I
generate in a Claude Code session falls under the same terms — use me for
*judging* and *spot-checking*, and open models for bulk generation, unless you
confirm otherwise.

Your Mac's RAM is the single biggest unknown in this table (see §10).

---

## 7. What "better, faster, smaller than anything out there" has to mean

Nobody has published an on-device vocabulary-nuance engine, so "better" must
be defined against three reference points:

1. **Dictionary APIs** (your current baseline) — coverage, completeness,
   consistency. Measurable: % of the ~9.5k GRE inventory with definition, IPA,
   examples, synonyms, register and frequency; latency; offline.
2. **Frontier LLMs** (the quality ceiling) — on the contextual-choice task,
   GPT-4 with 32-shot prompting scores soft F1 54.7 / proficiency F1 48.8 on
   ProLex; on word-sense disambiguation, frontier models sit at ~95% on lexEN.
   A specialised 13B matched GPT-4 on ProLex; our target is to get within a
   few points at ≤1B on the phone, and to beat every model of comparable size.
3. **Human-curated learning products** — Membean's "word constellation" and
   nuance write-ups, Vocabulary.com's learner-friendly definitions. These are
   hand-written and cloud-only. Our bar for explanations: a blind rater
   prefers or ties our explanation ≥50% of the time against a frontier model's
   grounded explanation, and ≥70% against a raw dictionary entry.

"Faster" and "smaller" are straightforward: TTFT under 100 ms for ranking
answers, ≥30 tok/s streaming explanations on iPhone 15 Pro and newer,
whole engine ≤1 GB on disk (target ~700 MB), no network. The full metric
definitions and the datasets behind them are in `evaluation-plan.md`.

---

## 8. Recommended architecture — and two alternatives

### Option A (recommended): grounded hybrid engine

```
                 ┌──────────────────────────────────────────────┐
 user question   │ 1. Lexical Knowledge Base (SQLite, ~150–300MB)│
 + optional      │    senses · glosses · IPA · forms · tags ·    │
 context ───────►│    frequency · CEFR/GRE · norms · collocations │
                 └───────────────┬──────────────────────────────┘
                                 │ facts
                 ┌───────────────▼──────────────────────────────┐
                 │ 2. Judgment models (Core ML / ANE, 20–300M)   │
                 │    context-fit ranker · sense disambiguator · │
                 │    formality/connotation/intensity/difficulty │
                 └───────────────┬──────────────────────────────┘
                                 │ scores + rationale features
                 ┌───────────────▼──────────────────────────────┐
                 │ 3. Explainer (0.8B–2B, 4-bit, ~500MB)         │
                 │    fine-tuned tutor; prompt always contains   │
                 │    the retrieved facts and the scores         │
                 └───────────────┬──────────────────────────────┘
                                 ▼
                       streamed answer + structured card
```

- **Layer 1** answers "what does it mean / how is it pronounced / how common /
  what level / what register" deterministically, offline, and consistently —
  the exact gaps in your dictionary APIs. Built once by an ETL script from
  the §5 sources; validated for coverage on the GRE inventory.
- **Layer 2** answers "which word fits here", "which is more formal", "which
  sense is this", with tiny models that are fast and *measurable* on SWORDS,
  ProLex, cloze sets and WiC. Start with zero-training baselines (masked-LM
  scoring, `NLContextualEmbedding` similarity), then fine-tune.
  *Revised 2026-09-28, then corrected the same day:* the plan to replace these
  heads with **one schema-driven typed-decision model** was tested with Needle 3
  and failed — it ties the majority-class baseline on connotation and its
  embeddings are unusable for lexical similarity
  (`results/2026-09-28-needle3-potion-probe.md`). The consolidation idea is not
  disproven, only that candidate. Current standing: **retrieval → potion-base-32M
  (1.9 MB, measured); context-free attributes → tables, 0 MB; context-dependent
  judgment → open, masked-LM scoring baseline first.** The probe also earned a
  design rule: never ask a model for something a table already encodes.
- **Layer 3** turns facts and scores into teaching: explanations,
  ELI12, mnemonics, comparisons. Because it is grounded, a 0.8B model is
  enough and hallucination is controllable (we can automatically check that
  every claim it makes matches the facts it was given). Trained by SFT on
  judge-filtered synthetic tutor dialogues generated from real KB entries.
- **Every question type in the brief maps to one of the three layers**, and
  the most important one — contextual selection with explanation — uses
  layer 2 for the choice and layer 3 for the "why".

Trade-offs: three components to build and test; an ETL pipeline to maintain;
but each piece is small, replaceable, independently benchmarkable, and the
generator can be swapped (Qwen → Gemma → Apple's model) without touching the
knowledge or the rankers.

### Option B: Apple-native minimum

Layers 1 and 2 as above, and Apple's AFM 3 Core via the Foundation Models
framework as the explainer with grounded prompts and guided generation.
Fastest to prototype (no model files, no fine-tuning), but: Apple Intelligence
devices only, 8k context, guardrail refusals on innocuous-but-dark vocabulary
(*slaughter*, *vitriol*) are a known risk, the model changes under you with
each OS release, and there is currently no adapter toolkit for iOS 27. Worth
running as the **baseline** in the bake-off; could be the shipped fallback on
capable devices.

### Option C: one generative model that "knows everything"

Fine-tune a 2–4B model to answer every question from its weights. Simplest
architecture, but the heaviest download, the slowest, the least measurable,
and the most hallucination-prone on exactly the rare GRE+ words that matter.
Both the Smol playbook's advice and Desert Ant's results argue against it.
Not recommended.

---

## 9. Path to a working prototype (all free)

Each phase ends with a go/no-go number from the evaluation suite.

**Phase 0 — Evaluation suite and baselines (1–2 weeks).**
Assemble the datasets in `evaluation-plan.md`, write the harness (Python,
runs on the Mac), and score: Apple's AFM 3 (on a Mac running macOS 27),
Qwen3.5-0.8B / 2B, Gemma 4 E2B, LFM2.5-1.2B — all with plain prompting —
plus one frontier model as the ceiling if its terms allow evaluation use.
Output: a table showing how far small models are from the ceiling on each
subtask. *Gate:* we know which subtasks need fine-tuning and which are fine
with prompting.

**Phase 1 — Lexical knowledge base (2–3 weeks).**
ETL from OEWN 2025, Wiktionary (kaikki), CMUdict, wordfreq, Ngram
collocations, norms, CEFR-J, GRE inventory → one SQLite file with FTS; a
Swift package exposing typed queries. *Gate:* ≥99% of the GRE inventory has
definition + IPA + POS + frequency; ≥90% has ≥2 examples and register tags.

**Phase 2 — Judgment models (2–4 weeks).**
Context-fit ranker: masked-LM baseline → fine-tuned cross-encoder on
SWORDS + ProLex + CLOTH + SC-Ques + synthetic near-synonym blanks → Core ML.
Sense bi-encoder with precomputed gloss embeddings (coarse senses). Attribute
scoring from lexicons with regression fallback. *Gate:* beats the masked-LM
baseline on held-out SWORDS/ProLex and near-synonym FITB; <50 ms per query on
iPhone.

**Phase 3 — Grounded explainer (3–5 weeks).**
Generate 20–50k synthetic tutor samples from real KB entries and ranker
outputs with an open-weight teacher; judge-filter for factual agreement with
the KB, learner-appropriateness, and format; SFT Qwen3.5-0.8B (and 2B for
comparison) with Unsloth or mlx-lm; 4-bit quantise; run via MLX Swift (or
LiteRT-LM if its Swift API matures). *Gate:* hallucination rate vs KB facts
<2%; blind preference ≥50% vs frontier grounded explanations; ≥30 tok/s on
iPhone 15 Pro.

**Phase 4 — Integration and on-device benchmarking (2 weeks).**
Wire the three layers into the iOS app behind one Swift API; measure TTFT,
tok/s, memory, energy with Instruments; compare against the current
dictionary-API flow on coverage and latency; publish the benchmark table.

**Later.** DPO from in-app feedback; distil the ranker into static
embeddings; Apple adapter if a 27-series toolkit ships; shrink the KB with
sense pruning.

Total: roughly 10–16 weeks of part-time work, zero cash, with the possible
exception of two nominal data licenses at commercialisation.

---

## 10. Decisions and information needed from you

None of these block Phase 0; they shape the spec.

1. **Mac specs** (chip and RAM). Determines whether we run a 9B–27B
   open-weight teacher locally or lean on Groq/Gemini free tiers.
2. **Minimum iPhone to support.** iPhone 15 Pro and newer unlocks Apple's
   model and (reportedly) Core AI; older devices need MLX Swift or llama.cpp.
3. **Download budget.** ~300 MB (KB + rankers, explainer via Apple's model
   only) vs ~700 MB–1 GB (own 0.8B–2B explainer, works on every device).
   *Sharpened 2026-09-28, then eased:* with Needle 3 rejected and retrieval
   served by potion-base-32M at **1.9 MB measured**, Layer 2 is far cheaper than
   either branch assumed. The binding constraint is now the explainer, not the
   judgment layer.
4. **License comfort.** Shipping CC BY-SA lexicon data with attribution;
   paying nominal fees for NRC/norms at commercial launch; source-available
   runtimes (Cactus) vs Apache-2.0 ones.
   *Resolved and then moot (2026-09-28):* V3 was answered — `needle finetune`
   is a real local LoRA command, free and separate from the paid
   `needle platform`. V4 no longer matters because Needle 3 was rejected on
   accuracy. potion-base-32M is **MIT and needs no third-party runtime**, which
   removes this question from the critical path. One new privacy note: the
   `cactus-needle` package enables anonymous telemetry by default
   (`NEEDLE_TELEMETRY=0` disables it) — worth screening any future on-device
   dependency for the same.
5. **Teacher policy.** Open-weight only (safest), or also proprietary APIs
   under their terms.
6. **Where the existing iOS app lives** and its stack (SwiftUI? minimum iOS?)
   for Phase 4 integration.
