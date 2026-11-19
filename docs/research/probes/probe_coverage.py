import json, statistics
from nltk.corpus import wordnet as wn, sentiwordnet as swn, cmudict
from wordfreq import zipf_frequency

words = json.load(open("data/gre_words.json"))
cmu = cmudict.dict()

have = {k:0 for k in ["definition","pos","ipa","frequency","synonyms>=3","antonyms>=1","examples>=2","connotation"]}
misses = {k:[] for k in have}

for w in words:
    ss = wn.synsets(w)
    def hit(k, cond):
        if cond: have[k]+=1
        elif len(misses[k])<8: misses[k].append(w)
    hit("definition", bool(ss))
    hit("pos", bool(ss))
    hit("ipa", w in cmu)
    hit("frequency", zipf_frequency(w,"en") > 0)
    lemmas = {l.name().replace('_',' ').lower() for s in ss for l in s.lemmas()} - {w}
    hit("synonyms>=3", len(lemmas) >= 3)
    ants = {a.name() for s in ss for l in s.lemmas() for a in l.antonyms()}
    hit("antonyms>=1", len(ants) >= 1)
    ex = [e for s in ss for e in s.examples()]
    hit("examples>=2", len(ex) >= 2)
    con = False
    for s in ss:
        try:
            t = swn.senti_synset(s.name())
            if t.pos_score() or t.neg_score(): con = True; break
        except Exception: pass
    hit("connotation", con)

n=len(words)
print(f"=== T9 coverage over {n} GRE words, from free local data only ===\n")
print(f"{'field':16s} {'coverage':>9s}   {'target':>7s}  examples of misses")
targets={"definition":"99%","pos":"99%","ipa":"99%","frequency":"99%","synonyms>=3":"—","antonyms>=1":"—","examples>=2":"90%","connotation":"—"}
for k,v in have.items():
    print(f"{k:16s} {v/n:8.1%}   {targets[k]:>7s}  {', '.join(misses[k][:5])}")
