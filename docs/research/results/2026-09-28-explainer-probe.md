# Measured probe — Qwen3.5-0.8B-4bit as the Layer 3 explainer

Date: 2026-09-28 (same day as the Needle 3 / potion probe, later session).
Hardware: Apple M2, 16 GB, macOS 27.0. Runtime: LM Studio local server
(OpenAI-compatible, `http://localhost:1234/v1`), model id `qwen3.5-0.8b-mlx`.
Weights: `lmstudio-community/Qwen3.5-0.8B-MLX-4bit`, **625,229,523 bytes measured**
(0.625 GB). Decoding: temperature 0, repeat penalty **off**, thinking **off**,
no conversation history. Script: `spike/probe_explainer.py`.

Status: **decisive on the architecture's central assumption, indicative on quality.**
Six prompts, one word pair and one rare word. Enough to confirm that grounding
steers this model and to characterise its failure modes. Nowhere near enough to
accept or reject it as the shipped explainer.

---

## 0. Summary

| Question | Answer |
|---|---|
| Does supplying KB facts actually control the output? | **Yes — confirmed by falsified-fact test** |
| Is the model usable *ungrounded*? | **No — confident semantic inversions on rare words** |
| Is the base model usable *grounded*, as-is? | **No — ~17% of atomic claims unsupported vs a <2% target** |
| Does the 0.8B beat the templated-explanation baseline today? | **No** |
| Is fine-tuning optional? | **No — it moves from polish to prerequisite** |

The result that would have killed the grounded-hybrid thesis did not occur. The
result that kills *shipping the base model* did.

---

## 1. Setup

The prompt under test is the **product prompt**, not a research prompt — a system
message stating the grounding contract, and a user message containing a `FACTS`
block (standing in for Layer 1 output) plus a `TASK`.

```
You are a vocabulary tutor. You write short explanations for English learners.

Rules:
- Use only the information in the FACTS block. Do not add outside knowledge.
- Write 3 to 5 sentences of plain prose. No lists, no headings, no questions.
- Never ask the user anything. Always write the explanation immediately.
```

Two words were used throughout: **sanctimonious / self-righteous** (a register and
rarity contrast) and **hebetude** (Zipf ≈ 1.2, chosen because the model should have
almost no reliable knowledge of it).

---

## 2. The decisive test — T2, falsified facts

The architecture assumes the KB is the source of truth and the model is a renderer.
That assumption fails silently if the model overrides supplied facts with its own
memory. Two fields were deliberately falsified (`register: informal`,
`connotation: positive` — both wrong):

> *"This word means making a show of being morally superior to others. It is rare
> and informal, but it can be used positively to describe someone who acts with
> great moral superiority."*

**It obeyed.** Four atomic claims, all traceable to the supplied facts, including
both falsified ones. No attempt to correct from memory.

This is the single most important number in the probe. **Grounding demonstrably
steers a 0.8B model**, which is the premise the entire Layer 1 → Layer 3 design
rests on. Had it "corrected" the poisoned facts, every explanation about a rare
word would have been at the mercy of the model's unreliable memory, and Option A
would have needed rethinking.

Minor defect: asked for 3–5 sentences, produced 2.

---

## 3. The receipt for Layer 1 — T3 vs T4, same word, same model

**T3, grounded** (KB facts supplied):

> *"The word hebetude describes a state of being mentally dull or lethargic, which
> is a very rare and formal term that carries a negative connotation."*

**T4, ungrounded** (identical word, no facts):

> *"The word 'hebetude' describes a state of extreme restlessness or agitation,
> often characterized by a sudden, intense urge to move or act. It is a serious
> condition that requires immediate attention to prevent harm. … lethargy refers
> to a state of lethargy, which is a dull, slow, and uncoordinated state …
> hebetude is about sudden movement, whereas lethargy is about a lack of movement."*

The ungrounded answer is the **exact semantic inverse** of the truth, with an
invented clinical framing ("requires immediate attention to prevent harm") and a
circular definition of *lethargy*. Delivered with no hedging.

The only variable between the two is whether the dictionary file was in the prompt.
This is direct, local, measured evidence for the grounded-hybrid thesis, and it is
the strongest argument in the project so far for spending Phase 1 on ETL.

---

## 4. Where the grounded output still fails

| Test | Constraints met | Faithfulness |
|---|---|---|
| A — compare two words | prose ✓, no lists ✓, no questions ✓, 4 sentences ✓ | 2 of 8 claims unsupported |
| T2 — falsified facts | 2 sentences (asked 3–5) ✗ | **0 of 4 unsupported** |
| T3 — rare word, grounded | prose ✓ | 1 of 8 unsupported; **task not completed** |
| T6 — constraint stack | 2 sentences ✓, 32 words ✓, no semicolons ✓, **used the banned word "moral"** ✗ | 1 of 3 unsupported |

**Claim audit across the four grounded outputs: 4 of 23 atomic claims unsupported or
distorted ≈ 17%.** The T8 target in `evaluation-plan.md` is **< 2%**. Three of four
outputs contained at least one error.

Representative failures:

- **Relation garbling (T3).** Facts said `related: lethargy` and
  `opposite: alertness, acuity`. Output: *"lethargy is a synonym for the opposite
  condition"* — incoherent, and not entailed by anything supplied.
- **Instruction leakage (T3).** *"To explain this word to a learner, you must define
  it as…"* — it narrated the task instead of performing it, and never answered the
  actual question (how *hebetude* differs from *lethargy*).
- **Invented gloss (T6).** *"means the speaker is very strict about their behavior"*
  — absent from the facts and wrong.

Caveat: the claim audit is a single hand-rater (me) over 23 claims. It is a
characterisation, not a metric. The automatic NLI check specified in T8 is what
should produce the shippable number.

---

## 5. T5 — the second receipt for "never ask a model what a table encodes"

Asked cold for 5 synonyms and 3 antonyms of *hebetude*:

> *"…refers to a state of deep or intense thought…"*
> Synonyms: **Concentration · Deep thought · Mental fixation**
> Antonyms: **Dissipation · Dispassionate · Dissipated**

Wrong definition (inverted again), 3 synonyms when 5 were requested, every synonym
wrong, and *Dissipation* and *Dissipated* offered as two distinct antonyms.

The Needle 3 probe earned this rule at 33.7 MB. It now holds at **625 MB and ~20×
the parameters**. Treat it as settled: WordNet answers this instantly and correctly.

---

## 6. NEW design rule — the template attractor

The model applies one comparison frame to every word pair, regardless of whether it
fits. For *sanctimonious / self-righteous* it produced:

> *"Choose self-righteous for what was said, and sanctimonious for how it came across."*

Fluent, parallel, confident — and **semantically wrong**, because neither word is
about speech. The same frame reappeared verbatim for *laconic / terse* (where it
happens to fit) and survived nonce-prefixed, cache-busted, isolated requests.

> **Rule: fact-level verification is necessary but not sufficient for this model.**
> Every individual claim in that sentence traces back to a supplied fact — rarity
> and register — so an NLI entailment check passes it. The error is in the *frame*,
> not the facts. T8's fact-consistency metric cannot catch this class, and the
> blind-preference half of T8 is therefore load-bearing, not decorative.

---

## 7. Methodology findings (and two claims withdrawn)

**7.1 The GUI result was an artefact, not a model failure.** In LM Studio's chat UI
the model twice refused the task and returned an assistant-style menu ("What would
you like me to do?"). Re-run through the API with zero history, the same prompt
produced a normal explanation. **Cause: prior assistant turns in the conversation.**
A small model copies its own previous turn in preference to following the system
prompt, and the effect is strengthened by disabling repeat penalty (which is
correct for measurement). *Withdrawn: the initial reading that the system prompt
was being ignored.*

> **Process rule: evaluate through the API with explicit message lists. Never
> measure a model in a chat UI** — conversation state is an uncontrolled variable,
> and LM Studio's system prompt is per-conversation, so editing it does not apply
> to a thread already in progress.

**7.2 Few-shot examples are actively harmful here.** A one-shot example
(*brusque/curt*) intended to fix the format instead caused the model to copy the
example's **content**: it described *sanctimonious* as *"speech that is too short
to be polite"* and echoed the `FACTS/TASK/RESPONSE` scaffold back verbatim.
Instruction-only prompting produced strictly better output than one-shot prompting.
*Withdrawn: the recommendation to add a worked example to the product prompt.*

**7.3 Cross-request contamination ruled out.** Distinctive phrasing from the
discarded example recurred in later prompts, suggesting leakage. Two tests
disproved it: a code word given in one request was not recalled in the next, and a
request with no system message reported having received none. The recurring
phrasing is the model's own attractor (§6), not server state. *Withdrawn: the
hypothesis that LM Studio was leaking context or injecting a default system prompt.*

**7.4 Thinking is off by default for this build.** `chat_template.jinja` emits an
empty, pre-closed `<think>\n\n</think>` block unless `enable_thinking` is defined
and true. Nothing needs disabling. LM Studio's "Reasoning Section Parsing" toggle
only affects display. Qwen3's `/no_think` string is **not** implemented in this
template and would sit in the prompt as literal text.

**7.5 Repeat penalty must be off for evaluation.** Top-K and Top-P are ignored at
temperature 0; repeat penalty is not — it rewrites logits every step and varies
with what has already been generated. With it off, runs are byte-identical across
fresh processes (verified twice).

---

## 8. Consequences

- **Layer 1 (KB) is vindicated by §3** and should proceed exactly as planned. The
  grounded/ungrounded pair on *hebetude* is the clearest evidence yet produced.
- **Qwen3.5-0.8B-4bit is not shippable as a base model.** At ~17% unsupported
  claims it loses to the **templated-explanation baseline** (item 9 in the Phase 0
  baseline list), which is 100% faithful by construction, costs 0 MB, and does not
  fail constraints.
- **Fine-tuning is reclassified from polish to prerequisite.** The landscape doc's
  Step 4 (SFT on judge-filtered synthetic tutor data) is now on the critical path
  for the explainer to exist at all, not merely to sound better.
- **T7 should be reconsidered.** Under the app design settled this session the
  product never *generates* definitions, it retrieves them. Definition-modelling
  against held-out glosses measures a capability no surface uses. What survives is
  "simplify a supplied gloss to a requested reading level without adding facts",
  which is a T8 sub-case.
- **T8 needs the preference half, not just the NLI half** — see §6.
- **The templated baseline should be built and measured next**, before any
  fine-tuning spend. It is currently winning on the only metric measured, and it
  sets the bar the 625 MB has to clear.

---

## 9. What this probe did not test

1. **One word pair and one rare word.** No frequency stratification, which the
   2026-09-28 goal clarification makes mandatory for any claim about competence.
2. **No comparison against the templated baseline** — asserted above from
   first principles (templates are faithful by construction), not measured.
3. **No on-device numbers.** Everything here is Mac-side. T10 (TTFT, decode tok/s,
   peak RSS, energy) is untouched.
4. **No fine-tuned variant.** The whole point of §8's reclassification is that the
   base model is the floor, not the candidate.
5. **Vendor figure for contrast only:** Qwen3.5-0.8B non-thinking IFEval **52.1**
   (model card, *vendor-reported*). The constraint failures in §4 are consistent
   with it but are our own measurement and are not comparable to it.
