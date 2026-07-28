# vocab-cards (PRD §8 Unit 7)

The playful vocabulary popover: a blue word tapped on the reading screen
opens a card with the word large in the reading typeface, the authored
kid-friendly definition beneath, and an optional illustration slot.

## Behavior (pinned by test/features/vocab/)
- The definition audio auto-plays on open (recorded narrator ref, word
  channel); a replay button repeats it; tapping the word plays just the
  word's `pronunciationAudioRef`.
- Dismissal: tap-outside (barrier) or the explicit close button; either
  path fires `onClosed` exactly once. The reading screen owns cursor
  restore (Unit 5 contract).
- `vocab_card_opened` is emitted once per open with a schema-valid
  payload (storyId optional per §5), dispatched fire-and-forget via
  `Zone.root` like the reading controller's analytics.
- An unresolvable `vocabCardId` is a content-integrity no-op: `open()`
  completes immediately, shows nothing, logs nothing.
- DesignTokens-only styling; safe-area rendering in all four layout
  classes ([DEVICE] goldens skip-marked pending owner art).

## Files
- `lib/features/vocab/vocab_card.dart` — the popover widget.
- `lib/features/vocab/vocab_card_opener.dart` — `VocabCardHost` /
  `VocabCardHostState.open`, the seam the reading screen's
  `vocabCardOpener` callback plugs into (wired in app-shell).

## Provenance note
The implementer agent completed the code but stalled before committing;
the orchestrator verified the suite green, wrote this doc, and committed
with that provenance recorded.
