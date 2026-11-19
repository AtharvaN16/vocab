# Resources Catalog

Date verified: 2026-09-20; rows marked **(09-28)** verified 2026-09-28.
"Verified" means I read the page that day. Licenses marked *check* were not
stated on the page I read. Performance figures attributed to a vendor are
vendor-reported and have not been replicated by us.

## A. Lexical data (ships inside the app's knowledge base)

| Resource | What it gives | License | Link |
|---|---|---|---|
| Open English WordNet 2025 / 2025+ | synsets, glosses, examples, hypernym/hyponym/antonym/similar relations; JSON, LMF, RDF, WNDB | CC-BY 4.0 | https://github.com/globalwordnet/english-wordnet · https://en-word.net/ |
| English Wiktionary via kaikki.org (wiktextract) | glosses with tags (formal, informal, archaic, dated, slang, literary…), examples and quotations, IPA + audio, etymology, inflected forms, synonyms/antonyms/hypernyms/derived/related; JSONL, updated ~weekly; 1.39M distinct words, 967k noun senses | CC BY-SA 4.0 + GFDL (Wiktionary content) | https://kaikki.org/dictionary/English/index.html · https://github.com/tatuylonen/wiktextract |
| CMUdict | ARPAbet pronunciations, ~134k words | BSD-style | https://github.com/cmusphinx/cmudict |
| ipa-dict | IPA for en_US / en_UK | MIT | https://github.com/open-dict-data/ipa-dict |
| wordfreq | Zipf frequency for ~0.5M English words | Apache 2.0 (code); data from CC-BY-SA sources and SUBTLEX (permission granted for any purpose) | https://github.com/rspeer/wordfreq |
| Google Books Ngrams (v3) | n-gram counts for collocations and trends | CC BY 3.0 | https://registry.opendata.aws/google-ngrams/ · https://github.com/orgtre/google-books-ngram-frequency |
| OANC | 15M words American English, POS/lemma annotated | CC0 | https://anc.org/data/oanc/ |
| Leipzig Corpora Collection | up to 1M English sentences + co-occurrence stats | CC-BY | https://wortschatz.uni-leipzig.de/en/download |
| OpenSubtitles (OPUS) | spoken-register text for spoken-vs-written ratios | open (OPUS) | https://opus.nlpl.eu/OpenSubtitles |
| Moby Thesaurus II | 30,260 root words, 2.5M synonym links | public domain | https://github.com/words/moby · Project Gutenberg #3202 |
| Tatoeba | example sentences | CC BY 2.0 FR (some CC0) | https://tatoeba.org/en/downloads |
| CEFR-J Open Language Profiles | word → CEFR level, grammar profile | free for research and commercial use with citation | https://github.com/openlanguageprofiles/olp-en-cefrj |
| Words-CEFR-Dataset | word/lemma/stem → CEFR level, POS, Google-1gram frequency | MIT | https://github.com/Maximax67/Words-CEFR-Dataset |
| Oxford 3000 / 5000 by CEFR | reference lists (PDF) | © Oxford University Press — reference only, do not redistribute | https://www.oxfordlearnersdictionaries.com/wordlists/ |
| gre-words-collection | ~9,566 GRE words merged from 13 prep sources (CSV) | none stated; word lists are facts, definitions are not ours to copy | https://github.com/Xatta-Trone/gre-words-collection |
| Brysbaert et al. 2014 concreteness (40k) | concreteness ratings | supplementary material; free for research, *check* commercial | https://link.springer.com/article/10.3758/s13428-013-0403-5 |
| Kuperman et al. 2012 age of acquisition (30k) | AoA ratings | same | Behavior Research Methods 2012 |
| Warriner et al. 2013 VAD (14k) | valence/arousal/dominance | same | Behavior Research Methods 2013 |
| NRC VAD Lexicon v2 (55k terms) | valence/arousal/dominance | free for research; commercial via nominal-fee NRC license | https://saifmohammad.com/WebPages/nrc-vad.html |
| Pavlick & Nenkova style lexicon | human formality (7,794) and complexity (5,699) scores for words/phrases | *check* (academic page, no license text) | https://cs.brown.edu/people/epavlick/data.html |
| Feng et al. 2013 connotation lexicon | 93,873 entries: word, POS, positive/negative/neutral connotation | *check* (contact authors) | https://www3.cs.stonybrook.edu/~ychoi/connotation/ |
| SemCor / LLM-relabeled SemCor | sense-tagged corpus for WSD training | WordNet license / Apache-2.0 | https://github.com/GliteTech/llm-relabeled-semcor |

## B. Evaluation datasets (never shipped; see evaluation-plan.md)

| Resource | Task | License |
|---|---|---|
| SWORDS (+ CoInCo, SemEval-2007 LexSub, TWSI) | lexical substitution in context | CC-BY-3.0-US — https://github.com/p-lambda/swords |
| ProLex | proficiency-oriented lexical substitution | see repo LICENSE — https://github.com/BillyZhang24kobe/LS_Proficiency |
| Near-synonym FITB (Edmonds 1997; Inkpen & Hirst 2006; Wang & Hirst 2010) | near-synonym choice | academic — https://aclanthology.org/J06-2003.pdf |
| CLOTH | teacher-written cloze | research — https://arxiv.org/pdf/1711.03225 |
| SC-Ques | 289k ESL sentence-completion questions | research — https://github.com/ai4ed/SC-Ques |
| MSR Sentence Completion Challenge | 1,040 sentences, 5 options | MSR license |
| lexEN + SenseBench | corrected WSD benchmark and leaderboard | Apache-2.0 (code) — https://github.com/GliteTech/lexen · https://github.com/GliteTech/sensebench |
| WiC | word-in-context | CC BY-NC 4.0 — https://pilehvar.github.io/wic/ |
| Raganato et al. 2017 WSD framework | ALL / SemEval WSD | research |
| TOEFL 80 synonym questions | synonym MCQ | on request — https://aclweb.org/aclwiki/TOEFL_Synonym_Questions_(State_of_the_art) |
| Mohammad et al. 2008 GRE closest-opposite | antonym MCQ, 162 dev / 950 test | research — http://www.umiacs.umd.edu/~saif/WebDocs/LC-data/ |
| SimLex-999, WordSim-353, SimVerb-3500 | similarity | open |
| BEA 2026 Shared Task 1 (KVL) | vocabulary difficulty | task terms — https://arxiv.org/abs/2605.14257 |
| ChiKhaPo | lexical comprehension/generation | CC-BY 4.0 — https://arxiv.org/abs/2510.16928 |

## C. Models

| Model | Params / size | License | Role | Link |
|---|---|---|---|---|
| Qwen3.5-0.8B (and 2B, 4B, 9B) | 0.8B; 262k ctx; vision encoder included | Apache 2.0 | explainer (lead); 9B as local teacher | https://huggingface.co/Qwen/Qwen3.5-0.8B |
| Gemma 4 E2B / E4B / 26B-A4B | 2.3B eff. / 4.5B eff. | Apache 2.0 | explainer alt; teacher | https://huggingface.co/google/gemma-4-E2B-it |
| Gemma 3 270M / 1B (+ QAT) | 0.27B / 1B | Gemma Terms of Use | narrow generators | https://developers.googleblog.com/en/introducing-gemma-3-270m/ |
| LFM2.5 230M / 350M / 1.2B / 2.6B | — | LFM Open License (<$10M revenue) | CPU-fast explainer alt | https://www.liquid.ai/blog/introducing-lfm2-5-the-next-generation-of-on-device-ai |
| Granite 4.0-H 350M / 1B | — | Apache 2.0 | alt | IBM on Hugging Face |
| SmolLM3-3B | 3B | Apache 2.0 | reference | https://huggingface.co/HuggingFaceTB |
| Apple AFM 3 Core | 3B | platform | baseline / fallback explainer | https://developer.apple.com/documentation/foundationmodels |
| Glite LENS | 298M bi-encoder, 83.6 Raganato ALL | Apache-2.0 code; weights *check* | sense disambiguation | https://github.com/GliteTech/research-semcor-relabeling |
| ltg/flan-t5-definition-en (base/large/xl) | 250M–3B | see card (research-intended) | definition generation for data/eval | https://huggingface.co/ltg/flan-t5-definition-en-base |
| ProLex fine-tuned Llama-2/Vicuna 7B/13B | 7–13B | Llama 2 license | reference / teacher for T1 | linked from ProLex repo |
| EmbeddingGemma-300M | 308M, 768-d | Gemma Terms | embeddings (Core ML / LiteRT conversions exist) | https://huggingface.co/google/embeddinggemma-300m |
| **potion-base-32M (Model2Vec) — MEASURED 2026-09-28** | **1.9 MB on disk**, 512-d, **0.03 ms/word** on M2 | MIT | **Provisional pick for retrieval/similarity.** Mean pairwise cosine 0.0933 (healthy); separates related from unrelated 9/10; does *not* separate synonyms from antonyms — read that from WordNet instead | https://github.com/MinishLab/model2vec |
| all-MiniLM-L6-v2 | 22M | Apache 2.0 | embeddings | sentence-transformers |
| DeBERTa-v3-small / ModernBERT-base | 44M–150M | MIT / Apache 2.0 | masked-LM ranker, cross-encoder | Hugging Face |
| **(09-28, MEASURED)** ~~Needle 3 (Cactus)~~ | **33.7 MB** weights + 0.78 MB engine, 99 MB peak RAM (measured on M2, not the claimed 8–29 MB / 28.5 MB) | Apache 2.0 (weights) | **REJECTED.** Tool-calling model. Connotation 6/12 = majority-class baseline; register 0/12; nearest neighbour of *arduous* is `carburettor`. `extract()` needs a Pydantic model and returns `None` silently for a dict schema. Telemetry on by default. See `results/2026-09-28-needle3-potion-probe.md` | https://huggingface.co/Cactus-Compute/needle3 |
| **(09-28)** Laya (Convai Innovations) | ModernBERT-large 395M + scratch head (2 transformer layers, one `[MASK]` scorer per option, act-or-escalate) = 421M; 512 ctx. Also `laya-multilingual` (mmBERT-base, 322M, 1024 ctx) and `laya-typed-decisions` (421M, 1024 ctx) | Apache 2.0 | **not shipped** — too large, no Core ML path. Mac-side judgment oracle and label generator; source of the RLCD + temperature calibration recipe | https://github.com/NandhaKishorM/laya · https://huggingface.co/convaiinnovations/laya |
| **(09-28)** laya-mlx | FP16, 843 MB; M3 Max: argmax matches PyTorch MPS FP32 on 63/63 decision distributions, max prob delta 0.0054 | Apache 2.0 | run the oracle on the Mac without PyTorch (macOS 14+) | https://huggingface.co/aac6fef/laya-mlx |
| **(09-28)** Jev (TypeSafe AI) | undisclosed; closed weights, waitlist API; vendor 70–500 ms end-to-end | proprietary | **rejected** — breaks offline, free and on-device privacy. Citable reference number only | https://typesafe.ai/blog/introducing-system-one-models-and-jev |

## D. Runtimes and tooling

| Tool | Purpose | License / status | Link |
|---|---|---|---|
| Foundation Models framework (iOS 26/27) | Apple system LLM, guided generation, tools | platform; Apple Intelligence devices | https://developer.apple.com/documentation/foundationmodels |
| Foundation Models Adapter Training Toolkit 26.0.0 | LoRA adapters for the iOS 26 model | Apple; "last release of this toolkit… not compatible with 27" | https://developer.apple.com/apple-intelligence/foundation-models-adapter |
| Core AI (iOS 27) | run custom `.aiasset` models on CPU/GPU/ANE | platform | https://developer.apple.com/documentation/coreai |
| Core ML + coremltools | encoders on the Neural Engine | Apple / BSD | https://github.com/apple/coremltools |
| MLX / mlx-lm / MLX Swift | training (LoRA, full), inference on Mac and iPhone | MIT | https://github.com/ml-explore/mlx-lm · https://github.com/ml-explore/mlx-swift-examples |
| llama.cpp | GGUF inference, lowest footprint | MIT | https://github.com/ggml-org/llama.cpp |
| LiteRT-LM | Google's edge LLM runtime; best speed/memory on iPhone; Swift API "Early Preview" | Apache 2.0 | https://github.com/google-ai-edge/LiteRT-LM |
| Cactus | cross-platform NPU runtime | source-available; free for small businesses — *check terms* | https://github.com/cactus-compute/cactus |
| **(09-28, MEASURED)** `cactus-needle` 3.0.5 (pip) | Module is `needle`, not `cactus_needle`. CLI: run/finetune/build/download/fetch/playground. **`needle finetune` is a genuine free local LoRA** (V3 resolved), distinct from paid `needle platform`. Engine 0.78 MB confirmed. **Telemetry ON by default** — `NEEDLE_TELEMETRY=0`. Model rejected for this project; tooling notes kept for reference | Apache-2.0 | https://cactuscompute.com/needle |
| **(09-28)** `laya` (pip) | typed decisions via JSON schema (`choice` / `score` / `bool`) on local GPU or CPU; `scripts/export_onnx.py --quantize` gives per-channel INT8 ONNX; **no Core ML export** | Apache 2.0 | https://github.com/NandhaKishorM/laya |
| **(09-28)** Laya RLCD fine-tune notebook | dataset build → RLCD (proper-scoring-rule reward, GRPO-style policy gradient, Gaussian logit noise) → temperature calibration → eval → Hub push; ~4–5 h for 4 epochs over ~30k questions on **Kaggle's free 2×T4** | Apache 2.0 | linked from the Laya repo |
| Unsloth notebooks | free-Colab fine-tuning for Qwen3.5 / Gemma 4 / Gemma 3 | Apache 2.0 | https://github.com/unslothai/notebooks |
| TRL / PEFT | SFT, DPO | Apache 2.0 | Hugging Face |
| lighteval / lm-evaluation-harness | standard task evaluation | MIT | Hugging Face / EleutherAI |
| apple-silicon-llm-bench | reproducible iPhone/Mac LLM benchmarks | open | https://github.com/john-rocky/apple-silicon-llm-bench |
| Smol Training Playbook | how small models are trained end-to-end | — | https://huggingfacetb-smol-training-playbook.hf.space/ |

## E. Free compute and teacher access (verified 2026-09)

| Provider | Free allowance | Notes |
|---|---|---|
| Your Mac | unlimited | LoRA ≈ 2 GB/1B params; local teacher needs 32 GB+ for 9B-class at 4-bit |
| Kaggle | 30 GPU-h/week (T4x2 / P100), ≤9 h sessions | most reliable free GPU |
| Google Colab | T4, dynamic ~15–30 h/week, ≤12 h sessions | Unsloth notebooks target this |
| Groq API | 30 req/min, 6k tokens/min, 14,400 req/day, all hosted open models | good bulk-generation teacher |
| Gemini API | Flash-class only; hundreds to ~1,000 req/day; Pro removed from free tier April 2026 | terms restrict outputs for competing models |
| Anthropic (Claude) | via your subscription | terms restrict outputs for competing models; use for judging/spot-checks |
| **(09-28)** NVIDIA Build / NIM (`build.nvidia.com`) | 1,000 credits on developer-program signup, extendable to ~5,000 on request | **Inference only — not a training GPU.** Serves open-weight models (Llama, Mistral, DeepSeek), which makes it a **licence-clean teacher** for synthetic data: the served weights carry no competing-model restriction, unlike Gemini/Anthropic outputs. Check NVIDIA's own API terms. Relevant to open decision §10.5 |
| **(09-28)** NVIDIA Inception | up to $100k DGX Cloud + up to $100k AWS credits | Startup program with eligibility review, **not a free tier**. Only relevant if this commercialises |
| **(09-28)** Your M2 / 16 GB — **measured** | DeBERTa-v3-small cross-encoder fine-tune on 6.3k pairs runs locally on MPS | **No GPU rental needed at current model sizes.** Free cloud GPU only matters if the <100M cap is abandoned |

## F. Competitive reference points

| Product | Relevance |
|---|---|
| Desert Ant Labs | proof that 2–300 MB task models beat generalists on narrow tasks; no dictionary model |
| Membean | human-written nuance ("word constellations"), cloud, subscription — the explanation quality bar |
| Vocabulary.com | learner-friendly definitions, cloud |
| WordUp, Vocabia, "AI Dictionary" apps | cloud LLM wrappers |
| "Vocabulary" app (Apple newsroom, 2025) | uses Foundation Models on-device only to categorise saved words |
| Apple Dictionary | static, no API |
| **(09-28)** TypeSafe AI / "System One models" category | names the shape of our Layer 2 — non-autoregressive typed decisions with calibrated probabilities instead of generated text. Useful vocabulary and a latency reference; the products themselves are closed (Jev) or too large (Laya) |
