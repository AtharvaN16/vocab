# Probe scripts — 2026-09-28 session

Throwaway scripts kept for reproducibility; the environment they ran in was deleted
to reclaim 2.3 GB. Nothing here is production code.

## Rebuild the environment

```bash
python3.14 -m venv .venv
.venv/bin/pip install wordfreq nltk model2vec pydantic sentencepiece protobuf
.venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv/bin/pip install transformers
.venv/bin/python -c "import nltk; [nltk.download(p) for p in ['wordnet','omw-1.4','sentiwordnet','cmudict']]"
```

## Scripts, in the order they were run

| Script | What it measures | Key result |
|---|---|---|
| `probe_needle*.py` | Needle 3 size, API, judgment accuracy, embedding quality | rejected: 33.7 MB (not 8–29), judgment at majority-class, `carburettor` nearest to *arduous* |
| `probe_potion.py` | potion-base-32M on the same embedding probe | 1.9 MB, healthy geometry, 170× faster |
| `probe_coverage.py` | T9 lexical coverage over 1,707 GRE words | definitions 99.5%, connotation 78.3%, antonyms 20.4% |
| `probe_register*.py` | Wiktionary usage labels as a register signal | **`formal` appears 0 times** — wrong tool |
| `build_fitb.py` / `probe_fitb.py` | auto-built near-synonym choice, 300 items | distilbert 37.7%, potion 33.3%, random 20.6% |
| `build_train.py` | **INVALID** — synthetic negatives. Kept as a cautionary example | taught the model to spot its own mining script |
| `build_real.py` | real SWORDS human labels, stratified negatives | 8,124 balanced pairs, contamination-clean |
| `train_ce.py` | cross-encoder fine-tune + eval | **AUC 0.618** vs 0.600 free baseline — fails the 0.75 bar |
| `probe_baselines_prolex.py` | zero-training baselines on the frozen test | potion 0.600, frequency 0.594, majority 0.500 |
| `isolate*.py` | the AdamW/DeBERTa NaN defect | NaN at step 1 even with lr=0; SGD and distilbert unaffected |

## Data sources (all re-downloadable, none redistributed here)

- GRE inventory: `Xatta-Trone/gre-words-collection` — 4 lists merged, words only
- SWORDS: `p-lambda/swords` → `assets/parsed/swords-v1.1_{dev,test}.json.gz` (CC-BY-3.0-US)
- ProLex: `BillyZhang24kobe/LS_Proficiency` → `data/{train,dev,test}/`
- Needle 3: `needle download needle3` (pip `cactus-needle`)

## Frozen split hashes (recorded so results stay checkable)

| File | sha256 (first 16) |
|---|---|
| `test_prolex.json` (the held-out test) | `29f497612239ee26` |
| `train_real.json` (real human labels) | `c87c4290b415b5fc` |
| `train_human.json` (INVALID, synthetic negs) | `0897fe383159c73e` |
