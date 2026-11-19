import json, re, time, urllib.request, urllib.parse, collections

WORDS = json.load(open("data/gre_words.json"))
SAMPLE = WORDS[::14][:120]   # spread across the alphabet

LABELS = ("formal","informal","colloquial","slang","archaic","dated","obsolete",
          "literary","poetic","humorous","derogatory","offensive","vulgar",
          "technical","rare","euphemistic","chiefly US","chiefly UK","now rare")

def wikitext(word):
    url = ("https://en.wiktionary.org/w/api.php?action=query&prop=revisions&rvprop=content"
           "&rvslots=main&format=json&formatversion=2&titles=" + urllib.parse.quote(word))
    req = urllib.request.Request(url, headers={"User-Agent":"VocabModelSpike/0.1 (research probe)"})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.load(r)
    pg = d["query"]["pages"][0]
    if "revisions" not in pg: return None
    return pg["revisions"][0]["slots"]["main"]["content"]

found, tagged, tagcount = 0, 0, collections.Counter()
examples = []
t0=time.time()
for i,w in enumerate(SAMPLE):
    try: txt = wikitext(w)
    except Exception: txt = None
    if not txt: continue
    found += 1
    # English section only
    m = re.search(r"==\s*English\s*==(.*?)(?=\n==[^=]|\Z)", txt, re.S)
    en = m.group(1) if m else txt
    labs = set()
    for tpl in re.findall(r"\{\{(?:lb|label|lbl|tlb)\|en\|([^}]*)\}\}", en):
        for part in tpl.split("|"):
            part = part.strip().lower()
            if part in [l.lower() for l in LABELS]: labs.add(part)
    if labs:
        tagged += 1; tagcount.update(labs)
        if len(examples) < 12: examples.append((w, sorted(labs)))
    if i and i % 40 == 0: time.sleep(0.4)

n=len(SAMPLE)
print(f"=== Wiktionary register/usage labels, sample of {n} GRE words ({time.time()-t0:.0f}s) ===")
print(f"page exists         : {found}/{n} = {found/n:.0%}")
print(f"has a usage label   : {tagged}/{n} = {tagged/n:.0%}   (of pages found: {tagged/max(found,1):.0%})")
print(f"\nmost common labels: {tagcount.most_common(12)}")
print("\nexamples:")
for w,l in examples: print(f"  {w:16s} {l}")
