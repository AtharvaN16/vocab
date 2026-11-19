"""Throwaway probe: can Qwen3.5-0.8B-4bit act as the GROUNDED explainer?
Server: LM Studio, temp 0, no repeat penalty, no history. Measured, not vendor."""
import json, urllib.request, uuid

URL="http://localhost:1234/v1/chat/completions"
SYS=("You are a vocabulary tutor. You write short explanations for English learners.\n\n"
     "Rules:\n"
     "- Use only the information in the FACTS block. Do not add outside knowledge.\n"
     "- Write 3 to 5 sentences of plain prose. No lists, no headings, no questions.\n"
     "- Never ask the user anything. Always write the explanation immediately.")

def gen(user, sys=SYS, maxtok=350):
    msgs=([{"role":"system","content":sys}] if sys else [])+[{"role":"user","content":user}]
    body=json.dumps({"model":"qwen3.5-0.8b-mlx","messages":msgs,"temperature":0,
                     "max_tokens":maxtok,"stream":False}).encode()
    r=urllib.request.Request(URL,data=body,headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(r,timeout=300))["choices"][0]["message"]["content"].strip()

def show(t,o): print("="*72);print(t);print("-"*72);print(o);print()

# --- cache-leak diagnostic -------------------------------------------------
show("D1. different word pair, bare (does the 'what was said' tic recur?)", gen(
"""FACTS
laconic (adjective): using very few words.
  rarity: rare. register: formal. connotation: neutral.
terse (adjective): brief and to the point, sometimes rudely so.
  rarity: uncommon. register: neutral. connotation: negative.

TASK
Explain how these two words differ, and when to choose each.""", sys=None))

show("D2. original pair + nonce prefix (busts any prefix cache)", gen(
f"[session {uuid.uuid4()}]\n"+"""FACTS
sanctimonious (adjective): making a show of being morally superior to others.
  rarity: rare. register: formal. connotation: negative.
self-righteous (adjective): convinced of one's own righteousness, especially
  in contrast to others.
  rarity: uncommon. register: neutral. connotation: negative.

TASK
Explain how these two words differ, and when to choose each.""", sys=None))

# --- Test 2: does it obey FALSIFIED facts, or override from memory? --------
show("T2. POISONED FACTS (register=INFORMAL, connotation=POSITIVE)", gen(
"""FACTS
sanctimonious (adjective): making a show of being morally superior to others.
  rarity: rare. register: informal. connotation: positive.

TASK
Explain this word to a learner, including when it would be appropriate to use."""))

# --- Test 3: rare word, grounded ------------------------------------------
show("T3. rare word, GROUNDED", gen(
"""FACTS
hebetude (noun): the state of being mentally dull or lethargic.
  rarity: very rare. register: formal, literary. connotation: negative.
  related: lethargy, torpor, sluggishness. opposite: alertness, acuity.
  origin: Latin hebes "blunt, dull".

TASK
Explain this word to a learner and say how it differs from "lethargy"."""))

# --- Test 4: same rare word, UNGROUNDED control ---------------------------
show("T4. same rare word, UNGROUNDED control", gen(
'Explain the word "hebetude" to a learner, and say how it differs from "lethargy".', sys=None))

# --- Test 5: what it must never be asked -----------------------------------
show("T5. cold synonyms/antonyms (expect invention)", gen(
'List 5 synonyms and 3 antonyms for "hebetude".', sys=None))

# --- Test 6: four simultaneous constraints ---------------------------------
show("T6. constraint stack: exactly 2 sentences, <40 words, no 'moral', no semicolons", gen(
"""FACTS
sanctimonious (adjective): making a show of being morally superior to others.
  rarity: rare. register: formal. connotation: negative.

TASK
Explain this word in exactly 2 sentences, under 40 words total, without using
the word "moral" and without any semicolons."""))
