# Vocab (iOS app)

A minimal SwiftUI app for bringing precise, literary words into your active vocabulary.
Started 2026-11-19 from a proof of concept; still early.

## Run
1. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`.
2. Open `Vocab.xcodeproj`, choose your iPhone or a simulator (iOS 26+), press ⌘R.

The `.xcodeproj` is generated from `project.yml` with XcodeGen and committed. `Vocab/` is a
synced folder, so new files added in Xcode need no regeneration. Edit `project.yml` and run
`xcodegen generate` only for project-level settings.

Debug launch arguments: `-seedDemo` fetches six literary words into a "Literary" collection
on first launch; `-demo search|ask|study|collections` opens that screen.
`-hitchLog` prints main-thread CPU per frame (worst frame of each card throw, and of every
2 s window) to stdout; run with `xcrun simctl launch --console-pty` to compare motion changes.
`-layerDump` prints, every 0.3 s, how many Core Animation layers carry a blur filter, a mask
or group opacity (the effects that cost offscreen render passes).

## Gestures
Deck: ← → move between cards · ↓ search · ↑ ask AI about this word
Study (per collection; front shows the meaning, tap to reveal the word):
→ knew it (Good) · ← didn't (Again, returns this session) · ↓ sort of (Hard) · ↑ ask AI

## Stack
- SwiftUI, iOS 26+, Swift 6 (main-actor by default)
- SwiftData: your words, collections and FSRS scheduling state
- Wiktionary REST for live lookups (CC BY-SA 4.0). The optional offline dictionary
  download in Settings is not built yet.
- FSRS-4.5 scheduler (`FSRS.swift`)
- AI mode: one `Explainer` interface with three engines: Apple Foundation Models
  (on-device), Groq free tier (debug builds only, key entered in Settings), and templates.

## Branches
Work happens on `dev`; merge to `main` when it is ready.
