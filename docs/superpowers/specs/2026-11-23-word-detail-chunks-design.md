# Word detail, one page at a time — design

Date: 2026-11-23 · Size: medium (rewrites `WordDetailView`'s layout; data loading stays)

## Intent
The word detail page used to show everything at once. Now it shows one page at a time, in the
simplified card's format, and moves on with a big labelled button. Chosen from the explorations in
`docs/explorations/word-detail-reveal.html` (option C · Next), then revised on device the same day.

## What the user asked for
- Pages of information shown one by one, never the whole entry at once.
- Minimal and in the simplified card's format: extremely simple, big, easy to read.
- No long drags. A long drag down closes the page (the zoom transition's dismiss) and must keep working.
- Visible signifiers for how to reach more.
- A full page, with no cards inside it.
- Revision 1:
  - The close ✕ goes top left, with more space between it and the word.
  - The speaker is a filled glyph with no filled frame (same touch area).
  - All definitions go on one page.
  - No headings on the pages.
  - Synonyms and antonyms are big pills, 4 each.
  - Their pages are always there so you can add your own.
  - The pages are named "Mnemonic" and "Etymology".

## The layout
- **Full-page card surface** (`CardSurface`).
- **The ✕** (36 pt, `Theme.control` circle) sits top left with 28 pt below it.
- **The word is pinned** in `Theme.cardWordFont` (52 pt), followed by a bare `speaker.wave.2.fill`
  in `.ink3` with a 44 pt touch area.
- **One page under the word, with no heading.** The text is `Theme.cardDefinitionFont`
  (32 pt bold) and steps down to 60% before it would overflow.
- **The bottom bar:**
  - Progress segments (4 pt, one per page).
  - A 56 pt back circle, shown after the first page.
  - A 56 pt next capsule named after the next page. On the last page it reads "Back to the deck"
    and closes.

## Pages, in order
1. **Definitions** (always): the primary definition, as on the card, then up to 2 more of
   `ranked.shown`, all in secondary ink.
2. **In a sentence** (if the primary sense has an example).
3. **Synonyms** (always): up to 4, saved words first, as 60 pt pills in the card's type.
   - Saved words are filled pills and open their page.
   - Unsaved words are outlined pills with a plus. Holding one adds it (`HoldToAdd`, `GenerateStage`).
   - The list ends with an outlined "+ Add" pill. It turns into a field, and return puts the typed
     word at the front of `details.synonyms`, saved on the word.
4. **Antonyms** (always): the same, with `details.antonyms`.
5. **Etymology** (always): its first two sentences, or "Nothing found yet." in `.ink4`.
6. **Usage** (if there is one): its first two sentences.
7. **Mnemonic** (always): the mnemonic, or a "Write one with AI" button.
8. **Linked words** (if any): pills, without the Add pill.

Pages are tracked by id, so details that load later never move the page on screen.

## Motion and gestures
- **Changing pages:** a blur replace. The old page rises 18 pt, fades out and blurs to 8 pt, while
  the new one rises into focus. Going back mirrors it. The spring is
  `.spring(duration: 0.3, bounce: 0)`. With `reduceMotion`, pages crossfade instead.
- **Taps:** on next and back.
- **Sideways swipe:** a short one also moves (past 40 pt, or a flick). It is a UIKit pan
  (`SidewaysSwipe`) that only begins on a horizontal move, so vertical drags reach the zoom
  transition's drag-down-to-close. The first build used a SwiftUI `DragGesture`, which blocked it.
- **Haptics:** `.selection` on each page change. The hold-to-add haptics are unchanged.
