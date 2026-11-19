import os, time, statistics
os.environ["NEEDLE_TELEMETRY"]="0"
import needle
from pydantic import BaseModel, Field
from typing import Literal

n = needle.Needle(weights="./models/needle3.cact")

class Reg(BaseModel):
    style: Literal["formal","neutral","informal","archaic"]
class Con(BaseModel):
    tone: Literal["positive","neutral","negative"]

# gold: (sentence, word, gold_register, gold_connotation)
ITEMS = [
 ("The committee faced the arduous task of reconciling every dissenting report.","arduous","formal","negative"),
 ("His speech was full of vitriol against his former allies.","vitriol","formal","negative"),
 ("She showed remarkable magnanimity toward her rivals.","magnanimity","formal","positive"),
 ("That party was totally lit, no cap.","lit","informal","positive"),
 ("The wretch was cast out from the village.","wretch","archaic","negative"),
 ("He gave a perspicacious analysis of the treaty.","perspicacious","formal","positive"),
 ("Quit being such a whiner about the weather.","whiner","informal","negative"),
 ("Her prose has an ineffable luminosity.","ineffable","formal","positive"),
 ("The deal fell through because of his mendacity.","mendacity","formal","negative"),
 ("I grabbed a quick bite before the meeting.","bite","informal","neutral"),
 ("Thou art a most pernicious knave.","knave","archaic","negative"),
 ("The table was set for dinner.","table","neutral","neutral"),
]

for name, model, field, gold_idx in [("REGISTER",Reg,"style",2), ("CONNOTATION",Con,"tone",3)]:
    correct, lats, preds = 0, [], []
    for sent, word, gr, gc in ITEMS:
        gold = (gr, gc)[gold_idx-2]
        txt = f'Sentence: "{sent}"\nTarget word: {word}'
        t0=time.perf_counter()
        try:
            out = n.extract(txt, model)
            pred = getattr(out, field) if out is not None else None
        except Exception as e:
            pred = f"ERR:{type(e).__name__}"
        lats.append(1000*(time.perf_counter()-t0))
        ok = (pred == gold); correct += ok
        preds.append((word, pred, gold, ok))
    # majority-class baseline
    golds = [ (i[gold_idx]) for i in ITEMS ]
    maj = max(set(golds), key=golds.count)
    maj_acc = golds.count(maj)/len(golds)
    print(f"\n=== {name}: Needle 3 accuracy {correct}/{len(ITEMS)} = {correct/len(ITEMS):.0%}"
          f"   | majority-class ('{maj}') = {maj_acc:.0%}"
          f"   | median latency {statistics.median(lats):.0f} ms ===")
    for w,p,g,ok in preds:
        print(f"   {'OK ' if ok else 'XX '} {w:14s} pred={str(p):10s} gold={g}")
