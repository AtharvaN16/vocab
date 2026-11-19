# Measured results — 2026-09-28 session

Hardware: Apple M2, 16 GB, macOS 27.0, Python 3.14.6. Scripts preserved in
`docs/research/probes/`; the 2.3 GB environment was deleted afterwards.

## Session summary

**Established (measured, reusable):**

| Finding | Number |
|---|---|
| Lexical coverage of 1,707 GRE words: definitions / POS / frequency | **99.5 / 99.5 / 99.0 %** |
| Connotation from SentiWordNet tables | **78.3%** — beats every model tested |
| `potion-base-32M` as the retrieval/similarity pick | **1.9 MB**, 0.03 ms/word, healthy geometry |
| Zero-training bar any judgment model must clear (ProLex acceptability, AUC) | **0.600** |
| Best fine-tuned model achieved | **0.618** — fails the agreed 0.75 bar |
| Needle 3 | **rejected** — tool-calling model; judgment at majority-class |
| Register from free sources | **not achievable** — three routes ruled out |

**The decisive question is still open.** Two fine-tunes: one invalidated by synthetic
labels, one that beat a free zero-training baseline by 1.8 AUC points. Neither tested
the frequency range that matters.

**Three claims asserted and later withdrawn** (all from concluding before measuring):
1. Needle 3 is "8–29 MB" — vendor figure; measured 33.7 MB + 0.78 MB engine.
2. "The NaN is an Apple MPS bug" — CPU failed identically; it is an AdamW/DeBERTa defect.
3. "No English datasets exist for this" — false. English is the best-resourced language;
   MAGPIE, PPDB, LT-Swap, Card-660 and Stanford RW all exist. Only one narrow
   intersection is genuinely missing (see Step 4).

**Goal clarified mid-session:** the target is *general English competence*, not GRE
coverage — GRE words are a proficiency probe for the hard tail. Every metric must
therefore be reported stratified by word frequency, never averaged. Competence on
common words is table stakes, which makes the 0.618 result a **stronger** negative
than it first appeared, since it failed at the common end.

**Next steps, in order:**
1. **LT-Swap rare strata** — natively frequency-stratified correct-vs-incorrect usage
   judgment. First measurement that would speak to the actual goal.
2. **T3 — 950 GRE closest-opposite items**, already in `evaluation-plan.md`, never run.
   Original host (umiacs) is 404; author's site is live.
3. Add **collocation** and **idiom** (MAGPIE, 56,622 annotated instances) to the battery.
4. Phase 1 knowledge-base ETL — proven valuable independently of all of the above,
   and can proceed in parallel.
5. Deferred: Kaggle + DeBERTa retry. Demoted because it would optimise a benchmark now
   known to be the wrong *shape* (single capability, common-word skewed, unstratified).

**Still owed by you:** the Pavlick formality lexicon licence decision (register is
blocked on it), and rotating the Kaggle token pasted in chat.

---

# Measured probe — Needle 3 and potion-base-32M

Date: 2026-09-28. Hardware: Apple M2, 16 GB, macOS 27.0, Python 3.14.6.
Harness: throwaway, `spike/` (see `spike/FINDINGS.md`). **Every number here was
measured locally.** Vendor figures are shown only for contrast.

Status: **decisive for Needle 3, indicative for potion.** 12 judgment items and a
15-word retrieval probe are far too few to *rank* models; they are enough to reject
a model that ties the majority-class baseline while inverting `vitriol`, and an
embedding space whose nearest neighbour for *arduous* is `carburettor`.

## 1. Needle 3 (cactus-needle 3.0.5) — REJECTED

### Measured vs claimed

| Property | Measured | Vendor claim |
|---|---|---|
| Weights (`needle3.cact`) | **33.7 MB** | "8–29 MB" |
| Engine (`libneedle.dylib`) | 0.78 MB | "<1 MB" — confirmed |
| Peak RAM | **99.0 MB** | 28.5 MB (their Pi 5 example) |
| Prefill | 3,135 tok/s | 1–10k tok/s — confirmed |
| `embed` latency / dim | 5.1 ms / 3072 | not published |
| `extract` latency | 89–120 ms median | not published |
| Confidence head in base archive | **present** | not documented |
| Local free LoRA (`needle finetune`) | **exists**, distinct from paid `needle platform` | **V3 resolved: free path is real** |
| Telemetry | **ON by default**; `NEEDLE_TELEMETRY=0` disables | not documented |

### Accuracy — at or below baseline

| Task | Needle 3 | Majority-class baseline |
|---|---|---|
| Register (4-way) | **0/12** | 50% |
| Connotation (3-way) | **6/12 = 50%** | **50%** |

Errors are inversions on precisely the target vocabulary: `vitriol`→positive,
`magnanimity`→neutral, `lit`→negative, `knave`→positive.

### Embeddings — unusable for lexical semantics

| Metric | Needle 3 | Healthy value |
|---|---|---|
| Mean pairwise cosine | **0.9262** | ≈ 0 (isotropic) |
| Spread (max−min) | 0.0894 | large |
| After mean-centering | −0.0654, spread 0.8477 | geometry fixed, ranking not |
| Nearest neighbour of *arduous* | **`carburettor`** (raw and centered) | `strenuous` |
| Rank of `difficult` | 12 / 15 | top 3 |

### Root cause
Needle 3 is a **tool-calling model**. `complete()` returns
`{'type':'call','function_calls':[],'reasoning':'no tools declared, returning the
empty call','decode_tps':0.0}` — no free-text generation. Its capacity is spent on
tool selection and argument filling, not lexical knowledge. Its published benchmarks
(mobile tool calls, DroidCall) do not transfer to lexical semantics, and we should
not have assumed they would.

### API trap worth recording
`extract()` requires a **Pydantic model**. Passed a raw JSON-Schema dict it returns
`None` silently — no exception, no warning. It is also field-name sensitive: field
`register` produced a value; renaming it `style` produced `None` on all 12 items.
An initial reading of "extract is broken" was wrong for this reason.

## 2. potion-base-32M (Model2Vec, MIT) — PROVISIONALLY ADOPTED

| | potion-base-32M | Needle 3 |
|---|---|---|
| On disk | **1.9 MB** | 33.7 MB |
| Dimension | 512 | 3072 |
| Embed latency | **0.03 ms** | 5.1 ms |
| Mean pairwise cosine | **0.0933** (healthy) | 0.9262 (degenerate) |
| Unrelated words ranked below related | **9 / 10** | not at all |
| Precision@5 for true synonyms | 2/5 | 1/5 raw, 3/5 centered |

potion's failure mode is the **expected** one: antonyms sit beside synonyms
(`effortless` +0.3992 vs `strenuous` +0.3994) because they share contexts. This is
what SimLex-999 measures. Needle's failure mode is pathological — unrelated nouns
outrank synonyms.

**Note on the metric.** Precision@5 conflates two different abilities and made
Needle look competitive. Report them separately in T4b:
(a) related vs unrelated separation, and (b) synonym vs antonym discrimination.
Only (a) is a property we should ask an embedding for.

## 3. Design rule earned here

**Never ask an embedding to decide synonym vs antonym — WordNet already encodes it.**
Use KB relations to select the candidate *type*, and the embedding only to rank
within a type. This converts potion's single weakness into a non-issue at 1.9 MB
and 0.03 ms, and it generalises: any capability available as a table should be read
from the table, never inferred.

## 4. What the KB got right that the model got wrong

Free lexical data answered, correctly and first try, every question the model failed:
WordNet glosses and relations, SentiWordNet polarity (`vitriol` correctly negative),
CMUdict pronunciation. This is direct evidence for the grounded-hybrid thesis:
**knowledge belongs in data, judgment in models, and most of what a vocabulary app
is asked for is knowledge.**

Caveat recorded: WordNet 3.0 via NLTK was used for speed; its glosses contain
artefacts (`arduous.s.02` = "taxing to the utmost; testing powers of endurance; ; ;
- F.D.Roosevelt"). Open English WordNet 2025 is cleaner and is what Phase 1 should use.

## 5. Consequences

- Needle 3 removed as a Layer 2 candidate (both judgment and embedding slots).
- potion-base-32M is the embedding/retrieval candidate, pending full T4b.
- The **<100M judgment slot is open**; the plan's original masked-LM-scoring baseline
  and fine-tuned small cross-encoder return as the lead.
- T4b must split its metric as described in §2.

---

# Step 1 — Layer 1 coverage probe (same day)

Question: which judgments can be read from free tables, at zero parameters?
Inventory: **1,707 unique GRE words** merged from 4 published prep lists
(GregMat960, Magoosh-1000, Barron's-333, PrepScholar-357 — words only; their
definitions were not taken). Sources: WordNet 3.0 via NLTK, SentiWordNet,
CMUdict, wordfreq, Wiktionary API.

## T9 coverage, free local data only

| Field | Coverage | Target | Verdict |
|---|---|---|---|
| Definition | **99.5%** | 99% | **met** |
| POS | **99.5%** | 99% | **met** |
| Frequency (Zipf) | **99.0%** | 99% | **met** |
| IPA (CMUdict) | 90.2% | 99% | **gap** — misses exactly the rare words (`abjure`, `abstemious`, `anodyne`) |
| Connotation (SentiWordNet) | 78.3% | — | usable; beats Needle 3's 50% (= baseline) decisively |
| Examples ≥2 | 64.0% | 90% | **gap** — WordNet examples are sparse |
| Synonyms ≥3 | 61.6% | — | **gap** — WordNet alone is thin; Moby would raise recall |
| Antonyms ≥1 | **20.4%** | — | **large gap**, and it refines the design rule below |

## Register is the weak link — three approaches tested, all inadequate

**1. Wiktionary usage labels: wrong tool.** 285 GRE words sampled (batched API;
one-at-a-time gets 429-rate-limited). 82% had pages; 34% of those carried a
usage label. Distribution:

`obsolete` 43 · `archaic` 21 · `rare` 18 · `dated` 14 · `us` 8 · `slang` 5 ·
`informal` 4 · `poetic` 3 · … · **`formal` 0**

**`formal` is never marked.** Lexicography tags only *deviations* from the
unmarked default, so the majority class for a GRE app is precisely the one
Wiktionary will not tell us. Worse, the labels are **per-sense**: flattening to
word level gave `compound`→dated/obsolete and `dogged`→dated/slang from obscure
senses, which is wrong for the common sense. Wiktionary labels are still
valuable — for flagging archaic/obsolete/slang/rare, which is a *different and
genuinely useful field*. They are not a register signal.

**2. Frequency: measures rarity, not formality.** With rarity held constant the
signal collapses — formal-vs-informal gap is only −0.58 Zipf among rare words
and −0.73 among common ones, with heavily overlapping ranges. `however`
(formal, 5.58) is more frequent than every informal word tested; `persnickety`
(informal, 1.68) is rarer than `circumlocution` (formal, 1.62). An initial test
showing clean separation was an artefact of comparing rare-formal against
common-informal.

**3. Word length: the best free proxy, still imperfect.** Separates consistently
at both rarity levels (formal 12.2 vs informal 6.6 among rare; 8.4 vs 4.0 among
common) and cleanly for common words, but overlaps for rare ones (`obfuscate` 9
vs `gobsmacked` 10, `persnickety` 11).

**Conclusion:** register needs the **Pavlick & Nenkova formality lexicon**
(7,794 human-rated words, license *check* in the catalogue) plus a regressor for
out-of-lexicon words. Promote it from "nice to have" to a Phase 1 blocker. Note
this is a **data** gap, not a model gap — it does not revive Needle 3, it makes
Layer 1 harder. Also note the 12-item register gold used earlier was my own
judgement, not a validated source; T11 needs real labels before it can grade
anything.

## The design rule, corrected

Earlier draft: *"use WordNet relations to separate synonyms from antonyms."*
With antonyms present for only **20.4%** of GRE words, that cannot work as
stated. The correct form is directional:

> **Retrieve by relation, then rank by embedding.** Never retrieve by embedding
> and filter by relation.

Because we generate candidates *from* WordNet relations, we never accidentally
offer an antonym as a synonym — so potion-base-32M's inability to tell
`effortless` from `strenuous` never gets exercised. Sparse antonym coverage stops
mattering. The reverse pipeline would have been sunk by it.

## Net effect on the architecture

- **Context-free attributes at 0 params: confirmed for connotation (78.3%),
  refuted for register.** The attribute half of Layer 2 shrinks but does not vanish.
- **Phase 1 ETL is bigger than the plan implies.** WordNet alone hits the targets
  for definitions/POS/frequency and misses badly on examples, synonyms, antonyms
  and IPA. Wiktionary, Moby and Tatoeba are not optional enrichment — they are
  required to hit the §7 coverage targets.
- **The one slot still needing a model is unchanged:** context-dependent
  synonym-fit and word-sense disambiguation.

---

# Step 1b — the one slot that still needs a model: synonym-fit

Benchmark auto-built from WordNet: **300 items**, gold = the word the author
actually used, distractors = co-hyponyms and `similar_to` lemmas (close and
genuinely confusable, not random). Mean 4.9 options.
Example: *"an ___ enemy"* → unmitigable / unappeasable / inexorable /
**implacable** / grim.

| Approach | Size | Accuracy@1 | MRR | Latency |
|---|---|---|---|---|
| `distilbert-base-uncased` masked-LM scoring | 67.0M params | **37.7%** | 0.609 | 113 ms/item |
| `potion-base-32M` static embeddings | **1.9 MB** | **33.3%** | 0.564 | **0.9 ms/item** |
| Random choice | 0 | 20.6% | — | — |
| Always-pick-most-frequent | 0 | **14.3%** | — | — |

## What this says

**1. There is real signal — and it is not enough to ship.** 37.7% against a 20.6%
random baseline is 1.8× chance, but our T1b target is ≥50. Zero-training masked-LM
scoring is well short, exactly as §9 Phase 2 predicted; the plan's answer
(fine-tuned cross-encoder on SWORDS + ProLex) remains necessary. This probe
establishes the floor it has to beat.

**2. potion-base-32M lands within 4.4 points of a 67M contextual model, at 1/125th
the latency and 1/35th the size.** For a <100M budget that is a remarkable
efficiency result and makes potion the default baseline for this slot, not just
for retrieval.

*Caveat that cuts against it:* WordNet example sentences are extremely short
("an ___ enemy", "___ wisdom"), so there is almost no context for a contextual
model to exploit. This flatters the static model. Re-run on SWORDS/ProLex, whose
contexts are full sentences, before trusting the 4.4-point gap.

**3. Frequency is an *anti*-signal here — 14.3%, below random.** The right answer
is systematically the *rarer* option, because GRE words are rarer than their
everyday near-synonyms. Never use frequency as a tiebreaker in this task; doing so
is worse than guessing.

**4. distilbert's 113 ms/item misses the <50 ms gate** even before Core ML
conversion, because pseudo-log-likelihood needs one forward pass per subword token
per candidate. Either the scorer becomes a single-pass cross-encoder, or this
approach is too slow regardless of accuracy.

## Limitation of this benchmark

Gold is the single word the author used, but several distractors are often
*also* acceptable (`implacable` / `inexorable` / `unappeasable` above). True
accuracy is therefore understated and the achievable ceiling is unknown — which is
precisely why SWORDS and ProLex pay for human appropriateness judgements. Treat
these three numbers as **relative** rankings on a fixed set, not as absolute
quality.

---

# Step 2 — cross-encoder fine-tune: FAILED EXPERIMENT (method error)

**Conclusion: this run does not answer whether a small cross-encoder can judge
word fit. The training data was invalid.** Recorded because the failure mode is
reusable knowledge and the baselines are sound.

## Setup

Task: given (sentence with target marked, candidate substitute) → acceptable or not.
This is *not* ProLex's published metric (which asks a model to generate substitutes
and scores soft F1@10, GPT-4 = 54.7). Not comparable to published numbers.

- Test: **official ProLex test**, 3,385 pairs, 1,955 acceptable / 1,430 not.
  `sha256=29f497612239ee26`, frozen before training.
- Train: 6,307 pairs from 915 human SWORDS items — **positives human-annotated,
  negatives mined by me from WordNet and ranked by potion similarity.**
- Model: `distilbert-base-uncased` (67.0M), 3 epochs, AdamW lr 2e-5, MPS, 718 s.

## Zero-training baselines (sound; reuse these)

| Approach | Accuracy | balAcc | **AUC** | Size | Latency |
|---|---|---|---|---|---|
| Always "acceptable" | 0.578 | 0.500 | 0.500 | 0 | 0 |
| **potion-base-32M cos(ctx, cand)** | 0.570 | 0.572 | **0.600** | 1.9 MB | 0.22 ms |
| potion-base-32M cos(target, cand) | 0.555 | 0.556 | 0.577 | 1.9 MB | 0.19 ms |
| Candidate frequency (Zipf) | 0.567 | 0.568 | 0.594 | 0 | 0.02 ms |

**AUC 0.600 is the bar any judgment model must clear.** Every zero-training method
sits barely above chance — the task is hard.

**Do not report F1 on this data.** Always answering "acceptable" scores F1 **0.732**,
higher than any real method, because it never misses a positive. Use balanced
accuracy and AUC.

**Frequency changes sign with task framing.** Anti-signal on the FITB task above
(14.3%, below random, because gold is the rarer GRE word); mild positive signal here
(AUC 0.594, because acceptable substitutes are the more natural words). Never hard-code
a frequency heuristic without re-checking its direction for the exact question asked.

## Result

| | Dev (held out from my train set) | **Official ProLex test** |
|---|---|---|
| Epoch 1 | AUC 0.774 | 0.546 |
| Epoch 2 | AUC 0.827 | 0.550 |
| Epoch 3 | **AUC 0.833** | **0.548** |

Final: acc 0.561 (**below** the 0.578 majority baseline), balAcc 0.521, AUC 0.550 —
**worse than potion's zero-training 0.600.** Fine-tuning actively hurt.

## Root cause: synthetic negatives

Dev AUC 0.833 vs test AUC 0.548 is distribution mismatch. The model learned to
recognise *"was this candidate produced by my WordNet mining script?"* — a strong
signal in training, absent from the test set, whose negatives are candidates humans
judged inappropriate.

Two earlier bug-fixes to the mining (excluding same-synset lemmas; ranking negatives
by plausibility) were both correct and both irrelevant. **Plausible fake negatives
are still fake.**

## The fix

Use **real human negatives**, which exist and were skipped:
- The **full SWORDS dataset** carries graded human appropriateness scores for every
  candidate, including rejected ones. `swords_filtered.csv` contains positives only
  because ProLex had pre-filtered it that way.
- ProLex **dev** adds 68 items with real `unacc_subs`.

Until a model is trained on human-labelled negatives, the feasibility question is open.

## Process lessons worth keeping

1. **Check dev *and* test every epoch.** The gap was visible at epoch 1; three epochs
   were unnecessary to learn the run had failed.
2. **Assert the loss is finite inside the training loop.** An earlier 20-minute run
   returned "42% accuracy" while silently producing NaN from step 1. Now aborts in seconds.
3. **Never synthesise the label you are trying to predict.** Synthesising *inputs* is
   often fine; synthesising the decision boundary teaches the model your script.

## Tooling defect recorded

`AdamW` on `microsoft/deberta-v3-small` produces non-finite weights at the **first
optimiser step** under torch 2.14.0 / transformers 5.17.0 / Python 3.14 — on **both MPS
and CPU** (an initial attribution to MPS was wrong). Not caused by tied, zero-element
or non-float parameters; gradients are finite (norm 2.400). `eps=1e-6` prevents the NaN
but the loss then diverges (0.67 → 9.3 → 12.2 → 16.1). SGD is stable. `distilbert-base-uncased`
with AdamW is unaffected. **DeBERTa-v3 is unusable with AdamW on this stack** — which
matters, because it was the lead candidate for the judgment slot at 43.5M backbone.

---

# Step 3 — CRITICAL: every public benchmark is about the wrong words

Surfaced by asking whether Kaggle's GRE word lists could be training data. They
cannot (a word list has no sentences and no labelled decisions), but auditing the
benchmarks against the GRE inventory produced the most consequential finding of
the day.

| Dataset | Median Zipf | Overlap with our 1,707 GRE words | Commonest targets |
|---|---|---|---|
| **SWORDS** (train) | 4.86 | **7 / 762 = 0.9%** | said, good, take, get, say, know |
| **ProLex test** | 4.67 | **5 / 637 = 0.8%** | people, second, country, ideas |
| **Our GRE inventory** | **2.76** | — | perspicacious, obdurate, magnanimity |

Zipf is logarithmic: 4.86 vs 2.76 is ~**100× difference in word frequency**. The
careful, human-labelled, contamination-checked benchmark built in Step 2 measures
*judging substitutes for the word "said"*.

## Consequence for the feasibility test

The ProLex experiment is **necessary but not sufficient**:

- Score ≤ 0.61 → conclusive failure. A model that cannot judge substitutes for
  *good* will not manage *perspicacious*.
- Score ≥ 0.75 → **does not validate the product.** It demonstrates the capability
  on frequent words only. Rare words are strictly harder: sparser pretraining
  signal, finer distinctions, and precisely where small models were measured
  failing earlier today (`vitriol` → positive, `magnanimity` → neutral).

The agreed 0.75 threshold therefore settles half the question. It is a floor, not
a verdict.

## The uncosted scope item

**No public benchmark covers judging GRE-level vocabulary in context.** SWORDS,
ProLex, CoInCo, SemEval-2007 and TWSI are all built from news, fiction and learner
essays — everyday vocabulary. Kaggle has none either (searched: formality lexicon,
lexical substitution, synonym nuance, connotation — all empty; see §Kaggle below).

So a GRE-level judgment set must be **created**: teacher model generates candidate
substitutions for GRE words in context → judge-filter → hand-audit a sample. This
is the §2 Step 3 recipe in the landscape doc, but the plan positioned it as
*training* data for the explainer. It is now also on the critical path for
**evaluation**, which nothing in the plan accounted for.

This partly explains why no one has shipped this product: the data to train and
measure it does not exist.

## Process lesson

**Audit a benchmark's vocabulary distribution before training on it.** One
`zipf_frequency` histogram, thirty seconds, would have reframed the whole
experiment before six hours went into it. Coverage of the *task* was checked (T9);
coverage of the *evaluation* was not.

## Kaggle assessed

CLI works (`kaggle` pip package; token at `~/.kaggle/access_token`, mode 600).
Useful for **GPU access only**. Dataset search found nothing for our gaps:
formality lexicon (0), pavlick (0), lexical substitution (0), connotation lexicon
(0), synonym nuance (0); concreteness returned only Finnish and Italian sets; VAD
only TMDB movie scores. One CEFR list (`nezahatkk/10-000-english-words-cerf-labelled`)
is inferior to CEFR-J and the MIT Words-CEFR-Dataset already catalogued.
Academic lexicons live on university pages, not community upload sites — so the
register blocker is unchanged.

---

# Step 4 — the decisive fine-tune on REAL human labels: FAILS the agreed bar

Same task, same frozen test (`sha256=29f497612239ee26`). Training data rebuilt from
**real SWORDS human annotations** (CC-BY-3.0-US): 8,124 balanced pairs, mean 5.4
annotators per candidate, negatives stratified across difficulty, `frac==0.5`
coin-flips dropped, contamination-checked clean. `sha256=c87c4290b415b5fc`.
Model `distilbert-base-uncased` (67.0M), 3 epochs, 878 s on M2.

| | Dev | **Frozen ProLex test** |
|---|---|---|
| Epoch 1 | AUC 0.794 | 0.610 |
| Epoch 2 | AUC 0.827 | 0.614 |
| Epoch 3 | AUC 0.836 | **0.618** |

Best: acc **0.607**, balAcc 0.566, **AUC 0.618**.

## Verdict against pre-declared thresholds

| Reference | Value |
|---|---|
| Agreed "convincing" threshold | **0.75** |
| potion-base-32M, **zero training, 1.9 MB** | **0.600** |
| This model, 67M params, 8,124 human labels | **0.618** |
| Majority-class accuracy | 0.578 (model: 0.607) |

**Fine-tuning bought 1.8 AUC points over a static embedding with no training.**
Thresholds were set before the run: ≤0.61 fails, 0.62–0.74 ambiguous. 0.618 sits on
the failure boundary and is not rounded upward.

Real labels *did* help — test AUC rose from 0.550 (synthetic negatives) to 0.618 —
confirming the Step 2 diagnosis. They did not help enough.

Dev/test gap persists (0.836 vs 0.618): SWORDS is CoInCo/MASC news and fiction,
ProLex is TOEFL learner essays. Domain shift remains even with correct labels.

## Caveats before treating this as final

1. `distilbert` (67M) not `deberta-v3-small` (43.5M backbone, stronger per param) —
   blocked by the AdamW defect recorded above. Kaggle's older CUDA stack would run it.
2. Only 8,124 training pairs.
3. Binary acceptability framing, not ProLex's published generation metric.
4. **Tests the wrong vocabulary entirely** (Step 3): median Zipf 4.7–4.9 vs our 2.76.

## Corrected claim about missing evaluation data

Two claims made earlier today were **overstated and are withdrawn**:

- *"Kaggle has no English datasets / English is under-resourced"* — false. English is
  the best-resourced language in NLP. Kaggle specifically lacks lexical-semantic
  resources because they live in academic distributions and on Hugging Face.
  English idiom data does exist: **MAGPIE** (1,756 idioms, **56,622** crowd-annotated
  instances from the BNC, idiomatic/literal/other) and **PPDB** (~220M paraphrase pairs).
- *"No evaluation set exists for rare words in context"* — **false.**

Rare-word benchmarks that exist:

| Benchmark | What it measures | Relevance |
|---|---|---|
| **LongTail-Swap (LT-Swap)** | discriminates correct vs **incorrect word use in context**, stratified from 512+ occurrences down to once/never; `WordSwap` subtask | **very close to our task, and frequency-stratified — evaluate on the rare strata** |
| Card-660 (Cambridge Rare Word) | word–word similarity, 660 uncommon pairs | rare-word representation quality |
| Stanford Rare Word (RW) | word–word similarity, 2,034 pairs | same |
| F-Eval | word choice with advanced vocabulary, idioms, proverbs | partial |
| Mohammad et al. 2008 GRE antonyms | 950 GRE closest-opposite MCQ | **already in our plan as T3, never run**; original umiacs URL now 404 |

**The genuinely narrow gap:** human-judged *appropriateness ranking among near-synonyms*
for *GRE-level* words. That specific intersection was not found. Everything adjacent exists.

## Process lesson (third of the day, same shape)

"No dataset exists" claims need the same evidence standard as accuracy claims.
Twice today absence was asserted from a shallow search and withdrawn on a deeper one.
**Search before concluding; record the queries used.** The correct method is to
enumerate the task's dimensions (vocabulary tier × task form × label source) and
search each, rather than searching one phrase and generalising.

## Immediate consequences

- **Run T3 (GRE antonyms, 950 items) — it is GRE-level and already planned.** Locate
  the data; the original host is dead.
- **Evaluate on LT-Swap's rare strata** before commissioning any new annotation.
- Only then decide whether a bespoke GRE judgment set is needed.
