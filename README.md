# Vocab Model — On-Device Vocabulary Intelligence

Research and (eventually) code for a small, fast, offline vocabulary-intelligence
engine that powers an iOS vocabulary-learning app: definitions, nuance between
synonyms, contextual word choice, register/connotation, pronunciation, and a
tutor that can explain *why* one word fits better than another, running
entirely on an iPhone.

## Status (2026-11-19)

The iOS app lives in [`app/`](app/README.md): SwiftUI, SwiftData, Wiktionary lookups,
FSRS study mode, and a swappable AI explainer. Research below.

## Research status (2026-09-28)

Research phase, **first measurements taken**. Read, in order:

1. `docs/research/2026-09-20-landscape-and-recommendation.md` — what exists,
   how small specialised models are actually made, what runs on an iPhone in
   2026, the recommended hybrid architecture, and a phased plan that costs
   nothing but time.
2. `docs/research/evaluation-plan.md` — the benchmark suite we build *first*
   so that "better, faster, smaller" is a measured claim, not a slogan.
3. `docs/research/resources-catalog.md` — every dataset, model, runtime and
   tool considered, with license and link.
4. `docs/research/2026-09-28-system-one-models-and-tiny-on-device-models.md` —
   revision to the judgment layer, plus the correction from "three options" to
   four jobs, only one of which has a live decision. **Read its correction
   banner:** its lead recommendation (Needle 3) was measured and rejected the
   same day.
5. **`docs/research/results/2026-09-28-needle3-potion-probe.md` — start here for
   what is actually measured.** Needle 3 rejected; `potion-base-32M` (1.9 MB, MIT)
   adopted for retrieval; lexical coverage 99.5%; the judgment model failed its bar
   (AUC 0.618 vs a 0.600 zero-training baseline). Includes the claims that were
   withdrawn and why.
6. **`docs/research/results/2026-09-28-explainer-probe.md` — the Layer 3 explainer,
   measured.** Qwen3.5-0.8B-4bit (625 MB) tested as the grounded explainer.
   Grounding **works** (it obeys deliberately falsified facts), and ungrounded it
   inverts the meaning of rare words outright — the clearest evidence yet for the
   knowledge base. But at ~17% unsupported claims against a <2% target it loses to
   the templated baseline, so fine-tuning moves from polish to **prerequisite**.
7. `docs/research/probes/` — the probe scripts, with a guide to rebuilding the
   environment and the frozen split hashes.

## The one-paragraph recommendation

Do not try to make one small generative model "contain" English. Build a
three-layer hybrid: (1) a deterministic lexical knowledge base compiled from
open data (Open English WordNet, Wiktionary, CMUdict, frequency and
psycholinguistic norms, CEFR/GRE lists); (2) tiny discriminative models in the
Desert Ant style (20–300M parameters, Core ML / Neural Engine) that rank
candidate words in context, disambiguate senses and score register,
connotation and difficulty; (3) a 0.8B–2B instruction model, fine-tuned on
judge-filtered synthetic tutor data and always *grounded* on the outputs of
layers 1 and 2, that produces the explanations. Measure everything against a
purpose-built evaluation suite from day one.

**Revised 2026-09-28.** The plan to collapse layer (2) into a single
schema-driven typed-decision model was tested with Needle 3 and **failed on
measurement** — it ties the majority-class baseline on connotation and its
embeddings are unusable for lexical similarity. Standing now: retrieval →
`potion-base-32M` (**1.9 MB measured**, MIT); context-free attributes such as
register and connotation → **tables, 0 MB**; context-dependent judgment →
open, masked-LM scoring baseline first. The probe also earned the rule that
governs this architecture: **never ask a model for what a table already
encodes.** Details in `docs/research/results/`.
