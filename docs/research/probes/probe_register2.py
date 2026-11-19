import json, re, time, urllib.request, urllib.parse, collections

WORDS = json.load(open("data/gre_words.json"))
SAMPLE = WORDS[::6][:300]

LABELS = {"formal","informal","colloquial","slang","archaic","dated","obsolete","literary",
          "poetic","humorous","derogatory","offensive","vulgar","technical","rare",
          "euphemistic","now rare","chiefly us","chiefly uk","british","us"}
UA = {"User-Agent": "VocabModelSpike/0.1 (on-device vocab research; single-run probe)"}

def fetch_batch(titles, tries=4):
    q = ("https://en.wiktionary.org/w/api.php?action=query&prop=revisions&rvprop=content"
         "&rvslots=main&format=json&formatversion=2&titles=" + urllib.parse.quote("|".join(titles), safe="|"))
    for a in range(tries):
        try:
            req = urllib.request.Request(q, headers=UA)
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)["query"]["pages"]
        except Exception as e:
            code = getattr(e, "code", None)
            wait = 2 * (a + 1) if code == 429 else 1.5 * (a + 1)
            print(f"    retry {a+1} ({type(e).__name__}{' '+str(code) if code else ''}) waiting {wait:.1f}s")
            time.sleep(wait)
    return []

pages = {}
B = 50
for i in range(0, len(SAMPLE), B):
    batch = SAMPLE[i:i+B]
    print(f"  batch {i//B+1}/{(len(SAMPLE)+B-1)//B} ({len(batch)} titles)")
    for pg in fetch_batch(batch):
        if "revisions" in pg:
            pages[pg["title"].lower()] = pg["revisions"][0]["slots"]["main"]["content"]
    time.sleep(1.2)

found = tagged = 0
tc = collections.Counter(); ex = []
for w in SAMPLE:
    txt = pages.get(w.lower())
    if not txt: continue
    found += 1
    m = re.search(r"==\s*English\s*==(.*?)(?=\n==[^=]|\Z)", txt, re.S)
    en = m.group(1) if m else txt
    labs = set()
    for tpl in re.findall(r"\{\{(?:lb|label|lbl|tlb)\|en\|([^}]*)\}\}", en):
        for part in tpl.split("|"):
            p = part.strip().lower()
            if p in LABELS: labs.add(p)
    if labs:
        tagged += 1; tc.update(labs)
        if len(ex) < 14: ex.append((w, sorted(labs)))

n = len(SAMPLE)
print(f"\n=== Wiktionary usage labels, {n} GRE words ===")
print(f"page exists       : {found}/{n} = {found/n:.0%}")
print(f"has a usage label : {tagged}/{n} = {tagged/n:.0%}  (of pages found: {tagged/max(found,1):.0%})")
print(f"\nlabel distribution: {tc.most_common(14)}")
print("\nexamples:")
for w,l in ex: print(f"  {w:16s} {l}")
json.dump({w: sorted({p.strip().lower() for tpl in re.findall(r'\{\{(?:lb|label|lbl|tlb)\|en\|([^}]*)\}\}', pages.get(w.lower(),'')) for p in tpl.split('|') if p.strip().lower() in LABELS}) for w in SAMPLE if pages.get(w.lower())}, open("data/register_tags.json","w"))
print("\nsaved -> data/register_tags.json")
