# Study mode in the deck — design

Date: 2026-11-22 · Size: small change (short design)

## Intent
Studying a collection should feel like the deck you already use, not a separate
screen with its own gestures. It keeps the FSRS spaced-repetition schedule that
already exists (`FSRS.swift`, FSRS-4.5, 90% target retention).

## What the user asked for
- Entering study mode: the bottom **+** button is gone.
- The **☰** menu button becomes **✕**, which ends the session.
- The **collection name** sits at the top, centred.
- The **card count** moves to the top right.
- A **progress bar** goes somewhere on screen.
- The card front shows **only the word, centred**. **Tapping flips** the card to the answer on the back.
- **Swipes work as in the deck**: left and right move between cards.
- The **bottom** has **3 spaced-repetition buttons**.

## Claude's calls (accepted 2026-11-22 with "Ok")
- **Progress bar:** a thin full-width line under the top bar that fills as cards are graded.
- **The buttons:** Again, Hard, Good (FSRS's Easy grade is dropped). They are neutral tinted grey
  (ink 0.16 background, ink text), following the "colour only for destructive" rule.
- **The count:** cards still to grade in this session, starting from cards due now.
- **Grading:** a button grades the card on screen and moves on to the next one.
  A card you swipe past without grading stays in the session until you grade it.
  Again puts the card back at the end of the session (as today).
- **End of session:** when every card is graded, show a "Done for now" card with
  "Study everything anyway" (as today). ✕ ends the session at any time and keeps the grades given so far.

## Approaches
1. **A study mode inside `DeckView` (chosen).** It reuses the deck's card stack, throw/rise
   motion and top/bottom bars. Only the chrome, the card face and the tap behaviour change.
2. **Restyle `StudyView` to look like the deck.** This means rebuilding the deck's card motion
   a second time, and the two would drift apart.
3. **A new shared card-stack component used by both.** This is the cleanest result, but it means
   refactoring a 1,000-line view just to add a mode.

## The design
- `DeckView` gets a study session state (collection, queue of words, graded count). The
  "Study" button in `CollectionsView` starts it instead of opening the `StudyView` cover.
- In study mode the deck draws its words from the session queue, not from all words or the
  collection filter.
- **Top bar:** ✕ (same frame and position as ☰) · collection name centred · remaining count on the right.
  The progress line sits under the top bar.
- **Card:** the front is the word centred. The back is the existing `CardFace`. A tap flips the card
  (Y-axis rotation on a ~0.3 s snappy spring; `reduceMotion` → crossfade). Moving to another card
  always shows its front.
- **Gestures in study mode:** left/right move between cards, and ↑ Ask AI and ↓ Save to work as in
  the deck. Long-press delete and tap-to-open-details are off.
- **Bottom bar:** the three grade buttons replace the counter and the + button.
- `StudyView.swift` is deleted once the deck mode replaces it.

## Left to the builder
The flip's exact curve, the progress-line thickness and colour (an ink tint), the button
heights and spacing (match `CircleButton` and the existing 56 pt controls), and how the
chrome animates in and out when a session starts and ends (blur/opacity, ~0.3 s).
