# Collections sheet: All words tile and collection colours

Date: 2026-11-23 · Size: small change

## Why
You can only study a collection; there is no way to test every word. The
Collections page (menu → Collections) also gives built-in and user collections
the same look, and user collections have no identity of their own.

## What changes
1. **Collections page** (MenuView only, not Save to): two squarish tiles side by
   side on top — *Favorites* (`heart.fill`) and *All words* (`rectangle.stack`),
   each with its count. A slightly larger gap, then user collections in today's
   row style, with their colour dot in the icon slot.
2. **All words opens like a collection.** Deck title "All words", back chevron on
   the left, Study button bottom right. Study draws from every word (due first,
   "Study everything anyway" when nothing is due) — same as a collection.
3. **Colour dots** for user collections: two concentric circles — a soft pastel
   ring with a stronger pastel dot inside. Shown in the Collections page rows,
   the Save to rows, and inline on each row in Edit collections.
4. **Recolouring in Edit collections:** tap a row's dot → the bottom *New
   collection* pill is replaced (blur/fade) by a horizontally scrolling swatch
   row; tapping a swatch recolours that collection immediately. The tapped dot
   is marked as the one being recoloured. Tapping the same dot again, another
   row's name, or Done closes the swatches and brings New collection back.

## Approaches
- **Deck scope enum (chosen).** Replace the deck's `collection: WordCollection?`
  with `home | all | collection(c)`. Home stays the + screen; `all` and
  `collection` share title, back chevron and Study. StudySession takes a title
  and a word list instead of a collection.
- *A hidden "All words" WordCollection in SwiftData* — rejected: fake persisted
  data that every collection list would have to filter out.
- *A separate `showingAll` flag beside `collection`* — rejected: two values that
  can contradict each other.

## Decisions (my calls — correct any)
- Colour stored on `WordCollection` as a string key (`colorKey`, default
  assigned on creation by cycling the palette), so reordering the palette never
  changes saved colours. Existing collections get colours assigned on first
  launch in their current order.
- Palette ~8 poppy pastels (e.g. peach, butter, lime, mint, sky, periwinkle,
  lavender, lilac), tuned for light and dark. No strong reds, so nothing reads
  as destructive.
- Favorites keeps its heart and gets no colour.
- Motion: swatch bar and New collection swap with the existing blur/fade,
  ~0.3 s; selection haptic on pick.

## Not doing
- No colour on the deck itself or study cards.
- No change to the Save to grid's layout beyond the dot.
