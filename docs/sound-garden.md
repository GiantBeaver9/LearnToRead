# Sound Garden — Behavior Documentation

**Unit:** 15 (Sound Garden: phonetic practice area), touching Unit 4 (sound mode), Unit 1 (child-facing screens)
**References:** PRD §8 Unit 15, §5 `GraphemeSound`, §5 Analytics events (`sound_card_played`, `sound_card_echo`), §8 Unit 4 (sound mode), §9 A-13
**Implementation:** `lib/features/sound_garden/sound_garden_screen.dart`, `sound_card.dart`, `sound_card_controller.dart`, `echo_session.dart`, `example_words.dart`

## Overview

Sound Garden is a third child-facing area (alongside the progress map and collection) — a free-practice, browsable space of grapheme-sound cards covering the scope-and-sequence grapheme inventory. There is no completion state, no collectibles, and no progress mechanic anywhere in this feature; it is observed only via analytics.

`SoundGardenScreen` is a `StatefulWidget` driven entirely by data its caller supplies (`Profile`, the full `GraphemeSound` inventory, `Level` ladder, audio/ASR seams). It never loads content itself — the inventory arrives as injected data (loading it from packs is content-delivery's concern; route wiring is app-shell's).

## Card wake state (`sound_card_controller.dart`)

`wakeStateFor({card, profile, levels})` is a pure derivation: a card is `CardWakeState.awake` iff `card.introducedAtLevelId`'s ordinal is **<=** `profile.currentLevelId`'s ordinal (inclusive boundary — a card introduced at exactly the profile's level is awake). Otherwise `CardWakeState.muted`. Ordinals are resolved against `levels` by `Level.id`, mirroring the idiom already used in `lib/pipeline/cumulative_grapheme_set.dart` and `lib/pipeline/decodability_linter.dart`; an id absent from `levels` throws `ArgumentError` rather than silently defaulting a wake state.

Every card in `inventory` renders regardless of wake state (PRD: "all cards visible from day one"). Wake state only affects `SoundCardWidget`'s dimmed styling and its muted marker — it never gates tap or echo.

## Card playback (`sound_card_controller.dart`)

`playSoundCard(card, {audioService, phonemeAudioRefs, channel})` plays `card.phonemeIds` in order, gaplessly. `GraphemeSound` carries no `WordToken` to hand `PhonemeSequencer` (the merged audio-playback sequencer) directly, so this builds a minimal synthetic `WordToken` on the fly — one `graphemePhonemeMap` entry per phoneme id, `text`/`pronunciationAudioRef` unused — purely to reuse `PhonemeSequencer`'s pinned gapless contract (each phoneme's audio is awaited to its natural end via `AudioService.completionOf` before the next `play()` is issued) instead of re-deriving it. A phoneme id absent from `phonemeAudioRefs`, or a ref `audioService` doesn't recognize, stops the sequence at the failing phoneme and propagates the underlying exception.

## `SoundCardWidget` (`sound_card.dart`)

Presentational, fully controlled by props (mirrors `MapNode`'s marker-widget convention). **Pinned contrast against `MapNode`:** `MapNode`'s asleep nodes swallow taps; `SoundCardWidget` deliberately does **not** gate on wake state — `onTap` is wired unconditionally, so a muted card stays fully tappable and echoable.

Structural markers (`id == card.id`):
- `sound-card-<id>` — the tap target, `onTap` always wired.
- `sound-card-text-<id>` — the grapheme face `Text`, styled with `DesignTokens.readingFontFamily`.
- `sound-card-muted-<id>` — present iff muted.
- `sound-card-echo-prompt-<id>` — present iff `echoState == listening`.
- `sound-card-sparkle-<id>` — present iff `echoState == matched`.

Visual placeholder treatment: a rounded token-styled tile with the grapheme large in the reading typeface; a matched echo gets a green accent ring plus a sparkle badge; a muted card is dimmed (55% opacity) with a small moon-glyph marker; a listening card shows a small mic-glyph prompt beneath the tile. All placeholder painting behind the real illustrated card art (PRD §10 OQ-4).

## `EchoSession` (`echo_session.dart`)

A lightweight engine+scorer loop — deliberately **not** the listening-tracker: no word, no silence timer, no struggle counter, no tap fallback. It wires exactly one `AsrEngine` to exactly one `SoundModeScorer` for one attempt:

- `start({onMatch})` calls `engine.start(biasingContext)`, then subscribes to `engine.hypothesesStream`, feeding every hypothesis to `scorer.onHypothesis`. The first time `scorer.accepted` flips false→true, `onMatch` fires exactly once, never again for that session.
- `stop()` cancels the subscription, calls `engine.stop()`, and returns the final `EchoResult`. Idempotent — a second call is a no-op returning the same result without touching `engine.stop()` again.
- `matched` / `matchedFraction` mirror the scorer directly; the scoring rule itself (A-13 threshold/distance/weight) is entirely the caller-supplied `SoundModeScorer`'s configuration — `EchoSession` never inspects or overrides it.

## `SoundGardenScreen` tap sequence

1. Fires `sound_card_played` (no event-specific fields).
2. Calls `playSoundCard(...)` and awaits it.
3. Once playback ends, **iff `profile.micConsent`**: sets that card's echo state to `listening`, builds a scorer via the caller-supplied `buildScorer(card)`, constructs an `EchoSession` over the injected `echoEngine`, and starts it. The first match sets the echo state to `matched` and fires `sound_card_echo` (`{'matched': true}`) exactly once.
4. **Iff `!profile.micConsent`**: the echo state stays `hidden` and `echoEngine` is never touched (`start` is never called) — listen-only mode. Playback (and `sound_card_played`) still fires normally.

No negative/failure state exists anywhere: a non-matching echo attempt simply leaves the card in its `listening` state indefinitely — there is no "wrong" marker, no red, no error sound (PRD: "a card never says 'wrong'").

`buildScorer` is the injection seam for which phoneme (if any) is double-weighted for a given card's echo scoring — `GraphemeSound` has no `targetPhonemeId` field (unlike a tongue twister), so this is deliberately the caller's choice, never hardcoded here.

## Example words (`example_words.dart`)

`visibleExampleWords({card, profile, levels, downloadedAudioRefs})` filters `card.exampleWords`, preserving authored order, to entries where **both** the word's `minLevelId` ordinal is <= the profile's current-level ordinal (inclusive) **and** its `pronunciationAudioRef` is present in `downloadedAudioRefs` — a card with no downloaded example-word audio shows only the words it has audio for (offline/partial-pack behavior).

`highlightRangeFor({wordText, grapheme})` finds the `[start, end)` range of `grapheme`'s first case-insensitive occurrence in `wordText`, or `null` if absent.

`ExampleWordChip` renders one example word with its grapheme substring visually distinguished; tapping plays `pronunciationAudioRef` via `AudioChannel.help` (the same channel word-pronunciation audio uses elsewhere, e.g. `near_miss_prompt.dart`). `SoundGardenScreen` renders one `Wrap` of chips beneath each card, built from `visibleExampleWords` against `downloadedExampleWordAudioRefs`.

## Layout

`SoundGardenScreen` is a `Scaffold` over a `SingleChildScrollView` + `Wrap` of card tiles (each tile a `Column` of `SoundCardWidget` + its example-word chips). `Wrap` sizes each tile to its own content and wraps to the next row as needed, so an arbitrary card count (tested up to 24, well beyond launch scope-and-sequence) and variable per-card example-word counts never overflow at any of the four layout classes, without needing a fixed grid cell size.

## Design Token Usage

All colors and fonts in every file under `lib/features/sound_garden/` are drawn from `DesignTokens` (`wordUnreadInk`, `wordReadGreen`, `wordVocabBlue`, `screenBackground`, `surfaceBackground`, `readingFontFamily`, and the `spacing*` scale). No inline `Color(0x...)` literal, `Colors.*` reference, or inline `TextStyle(fontFamily: ...)` literal appears anywhere under this directory (enforced by `test/design/token_lint_test.dart`).

## What Is Deliberately Out of Scope Here

- **No completion, collectible, or progression surface.** The frozen suite's structural scan (`no_failure_state_test.dart`) gates this: no file under `lib/features/sound_garden/` may reference a completion/collectible/progression DAO, type, or even the bare words "completion"/"completed"/"collectible"/"progression" anywhere in source, comments included.
- **The real grapheme inventory** (PRD §10 OQ-5, authored content) — this screen only renders whatever `List<GraphemeSound>` its caller injects.
- **Loading the inventory from packs** is content-delivery's; **route wiring into the app shell** is app-shell's.
- **listening-tracker's machinery** (silence timers, struggle detection, tap fallback) is deliberately not pulled into `EchoSession` — Sound Garden's echo has none of those semantics.
- **Real illustrated card/garden art** is owner-commissioned (PRD §10 OQ-4); every file here paints token-styled placeholder shapes behind that future artwork.

## Testing Strategy

The frozen suite (`test/features/sound_garden/`, 6 files, 60 tests) is exercised end-to-end:

- `sound_garden_screen_test.dart` — canonical pinned API; full-inventory rendering, gapless multi-phoneme playback, the echo path + sparkle, `sound_card_played`/`sound_card_echo` analytics, and consent-off listen-only mode.
- `awake_muted_test.dart` — `wakeStateFor` boundary/ordinal coverage and the muted-card-stays-tappable contract.
- `echo_session_test.dart` — `EchoSession`'s own engine lifecycle, match detection, idempotent `stop()`, and a static scan proving no listening-tracker module is imported.
- `example_words_test.dart` — level + audio-presence filtering exactness, `highlightRangeFor`, and `ExampleWordChip` tap/highlight behavior.
- `no_failure_state_test.dart` — the neutral-on-non-match behavioral guarantee, plus the structural completion/collectible/progression-absence scan (including a scanner self-check fixture).
- `layout_classes_test.dart` — all four layout classes, including a 24-card beyond-launch fixture, render without overflow; the corresponding pixel goldens are `[DEVICE]`-skip-marked and routed to the owner pending real illustration assets.

### Known suite deviations (see PR/build-loop notes)

Four of the sixty frozen tests do not pass against this implementation; both root causes are outside this ticket's file scope (`lib/features/sound_garden/` only) and are documented rather than worked around:

1. **Scorer confusability gap (3 tests: two in `echo_session_test.dart`, one in `no_failure_state_test.dart`).** The merged `SoundModeScorer` (`lib/features/listening/matcher/sound_mode_scorer.dart`, word-matcher ticket) uses a binary per-phoneme distance (`a == b ? 0 : 1`) with the A-13 default `perPhonemeMaxDistance == 1`, so *any* two distinct phoneme ids are always "within distance." That ticket's own test suite comment acknowledges this: "the inter-phoneme confusability metric behind 'per-phoneme distance' is intentionally NOT pinned by this word-matcher ticket (a future OQ)." Three Sound Garden tests assume a clearly-wrong phoneme (e.g. `'Z'` against target `'SH'`) is rejected; under the current scorer it is accepted. Fixing this would mean editing a merged dependency outside this ticket's scope.
2. **One widget-timing test (`sound_garden_screen_test.dart`, "echo path + sparkle on match").** The test's `_drainSequentialPlayback` helper performs exactly one `pump()` after the last `completePlayback()`, then asserts (before `pumpAndSettle()`) both that `engine.start` has already fired *and* that the "listening" marker has already rendered. Verified against `AutomatedTestWidgetsFlutterBinding.pump()`'s actual source (`flutter_test/lib/src/binding.dart`) and confirmed empirically via instrumented runs: `hasScheduledFrame` is evaluated at the very top of `pump()`, strictly before that same call's trailing `flushMicrotasks()` runs — so a `setState` triggered during that trailing flush (which is the earliest point playback-completion can be observed) can never be reflected in a rebuild within that same `pump()` call. With the `FakeAsrEngine` script's zero hypothesis delay, the match resolves in that identical microtask flush, so the tree is not rebuilt at all between "hidden" and "matched" at the point this assertion runs. No implementation that (a) starts the mic engine synchronously once playback ends (required for the `recordedBiasingContext` assertion) and (b) defers the match to a later pump (required for the "listening, not yet matched" assertion) can satisfy both simultaneously under this exact call pattern and the pinned `EchoSession`/`FakeAsrEngine` contracts.

Both are flagged to the ticket owner for reconciliation (either loosen the scorer's confusability placeholder in a future word-matcher pass, or adjust the drain helper's pump count) rather than guessed around in this ticket's files.
