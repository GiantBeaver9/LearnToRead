# Stuck-word scaffold — tiered help (Unit 6)

The ratified tiered-help ladder: when a child stalls on a word, the app
sounds it out, then models it, then accepts the word and moves on. The child
is **never hard-blocked**, is never told they were wrong, and never sees a
marker saying a word was helped — the help fact is a database row, not UI.

Source: `lib/features/help/{stuck_word_controller,sound_out_sequence,near_miss_prompt,help_recorder}.dart`.
PRD refs: §8 Unit 6 (pinned design + acceptance), §5 `WordHelpRecord`, §4.3
(learning signal), §8 Unit 4 (near-miss acceptance), §7 R7 (tunable timings).
Ticket: `docs/tickets/stuck-word-scaffold.json`. Pinned by
`test/features/help/*.dart` (5 files, 59 tests — each file's header comment
states its exact pinned API surface).

Merged dependencies, reused verbatim, never forked: `lib/domain/tuning.dart`
(T1/T2), `lib/features/listening/contracts/` (`TrackerEvent` family,
`HelpState`), `lib/features/audio/` (`AudioService`, `PhonemeSequencer`,
`DuckingPolicy`, `FakeAudioService`), `lib/data/db/daos/word_help_dao.dart`.

## The ladder

```text
watchWord(index, word)
   │
   ├── WordAccepted ─────────────────────────▶ resolve: tier none  (encounter only)
   ├── WordAcceptedNearMiss ─────────────────▶ warm model + resolve: tier none
   │
   └── T1 silence  OR  struggleDetected  OR  Silence(duration >= T1)
          │
          ▼
       TIER 1 — sound it out
       phonemes via PhonemeSequencer, one HelpState per grapheme cluster
          │  (sound-out stream closes = all phonemes played)
          ├── WordAccepted ─────────────────▶ resolve: helped(soundOut)
          ▼
       wait T2
          ├── WordAccepted ─────────────────▶ resolve: helped(soundOut)
          ▼
       TIER 2 — model it
       word pronunciation, then the recorded "your turn" line
          │
          ├── WordAccepted ─────────────────▶ resolve: helped(modeled)   (repeat)
          ▼
       wait T2
          └── nothing arrives ──────────────▶ resolve: helped(modeled)   (auto-accept)
```

Worst case, bounded and pinned by `never_blocked_test.dart`:

```text
T1 + Tier1 audio + T2 + Tier2 audio + T2
```

and the auto-accept fires *exactly* at that bound — not later, not never.
Audio durations are real clip lengths, not tuning constants, which is why the
bound is expressed with them rather than as a single number.

## Files

### `lib/features/help/sound_out_sequence.dart`

`SoundOutSequence({required PhonemeSequencer phonemeSequencer})` with
`Stream<HelpState> play(WordToken word, {AudioChannel channel = AudioChannel.help})`.

A thin adapter that maps each `PhonemeStarted { graphemeIndex, ... }` from
`PhonemeSequencer.playSequence` to
`HelpState(currentHelpTier: HelpLevel.soundOut, highlightedGraphemeIndex: graphemeIndex)`.
It adds no reordering, filtering, batching, or timing of its own, so every
highlight guarantee is inherited verbatim from the already-pinned sequencer:

| fixture | `graphemePhonemeMap` | highlight indices |
|---|---|---|
| `ship` (digraph) | `sh/SH`, `i/IH`, `p/P` | `0, 1, 2` — "sh" lights as one unit, never s-h |
| `cake` (silent e) | `c/K`, `a/EY`, `k/K`, `e/''` | `0, 1, 2` — index 3 never highlights, no audio |

`PhonemeAudioNotFoundException` / `AudioRefNotFoundException` surface as
stream errors and stop the sequence. The stream closing is the "Tier 1 audio
is over" signal the controller starts its T2 wait from — nothing here adds a
tail delay.

The reading screen (Unit 5) *renders* the highlight; this unit only produces
the state.

### `lib/features/help/near_miss_prompt.dart`

`NearMissPrompt({required AudioService audioService, required AudioRef promptLineAudioRef})`
with `Future<void> play(WordToken word)`.

The lighter path taken when Unit 4 accepts a close-enough production ("gat"
for "cat"): the word still turns green, and a brief warm model follows —
the generic authored prompt line, then the word's own recorded pronunciation
("that's it — *cat*!"), both on `AudioChannel.help`. The child may echo it
but is not required to.

**"Never escalates" is structural, not enforced.** This type has no tier, no
timer, and no state machine — there is nothing in it *to* escalate. The
controller resolves the word the moment it starts the prompt, so no T1/T2
timer for that word survives to fire.

Prompt copy and the recorded lines are authored content (Unit 3); this type
only ever sees an opaque `AudioRef`, and the suite uses placeholder refs.

### `lib/features/help/help_recorder.dart`

`HelpRecorderApi` (seam) + `HelpRecorder({required WordHelpDao wordHelpDao, required String profileId})`.

`recordResolution({required WordToken word, required HelpLevel tier})`:

| tier | DAO calls |
|---|---|
| `none` | `recordEncounter` |
| `soundOut` / `modeled` | `recordEncounter` **and then** `recordHelp(tier:)` |

Every resolution is an encounter — unaided reads and near-miss acceptances
included. That is the §4.3 help-rate **denominator**; without it the metric
reads as a flat 100% forever. A helped word is *also* an encounter, so
`helpCount / encounterCount` is a real rate whose decline over encounters is
the learning signal (`help_recorder_test.dart` walks a 2-helped-then-3-unaided
trajectory from 1.0 down to 0.4).

`HelpRecorderApi` exists so the controller never depends on Drift: the
timer-choreography suites substitute an in-memory double, and only
`help_recorder_test.dart` exercises `HelpRecorder` against a real in-memory
database. No row-accumulation rules are reimplemented here — they live on
`WordHelpDao` and are pinned by the local-storage unit.

### `lib/features/help/stuck_word_controller.dart`

```dart
StuckWordController({
  required Stream<TrackerEvent> events,
  required SoundOutSequence soundOutSequence,
  required AudioService audioService,
  required NearMissPrompt nearMissPrompt,
  required HelpRecorderApi helpRecorder,
  required AudioRef yourTurnPromptAudioRef,
  Duration t1 = kStruggleT1,
  Duration t2 = kTier2WaitT2,
  void Function(int index, HelpLevel tier)? onHelpGiven,
});
Stream<HelpState> get helpState;
Stream<WordHelped> get wordHelpedStream;
void watchWord({required int index, required WordToken word});
void dispose();
```

Resolution semantics:

| when the child's word lands | recorded tier | `WordHelped` | `onHelpGiven` |
|---|---|---|---|
| before Tier 1 starts | `none` | no | no |
| during Tier 1 audio, or the T2 wait after it | `soundOut` | yes | yes |
| once Tier 2 has started (repeat, or auto-accept after the final T2) | `modeled` | yes | yes |
| near-miss acceptance (no tier had started) | `none` | no | no |

Other pinned behavior:

- **`helpState` output.** One event per highlighted grapheme cluster through
  Tier 1 (forwarded verbatim from `SoundOutSequence`); a single
  `HelpState(modeled, -1)` when Tier 2 begins (Tier 2 has no per-grapheme
  highlight); `HelpState(none, -1)` on every resolution.
- **Superseding.** `watchWord` cancels the previous word's pending timer,
  sound-out subscription, and Tier 2 continuation, so no stale tier can fire
  for a word the child has moved past. Superseding does not resolve or record
  the old word — only an accepting event or the Tier 2 auto-accept does.
- **Idempotence.** Events for a non-watched index, and any event after a
  word has resolved, are ignored entirely: no double recording, no duplicate
  `WordHelped`.
- **Stopping mid-Tier-1.** Resolving cancels the sound-out subscription, so
  remaining phonemes are never force-played over a child who has already said
  the word.
- **Ducking.** All help audio (phonemes, Tier 2's two clips, the near-miss
  model) is tagged `AudioChannel.help` and therefore ducks active
  ambient/celebration playback through the pinned `DuckingPolicy`. The rule
  is never reimplemented here; the suite asserts it via `FakeAudioService`'s
  `DuckLogEntry`s.
- **Analytics.** `onHelpGiven(index, tier)` is the `help_given(tier)`
  emission hook (client wiring belongs to reading-screen/app-shell). It fires
  synchronously alongside every `WordHelped` and never for a `none`
  resolution, so helped `word_read` results stay distinguishable for §5
  analytics.
- **Content errors never strand the child.** A missing phoneme clip stops the
  sound-out but the stream still closes, so the ladder keeps moving; a missing
  Tier 2 clip falls straight through to the final T2 and the auto-accept.

## The T1-timer stand-in vs. tracker `struggleDetected` (app-shell wiring note)

The pinned trigger is "`struggleDetected` **or** sustained silence on the
current word for T1". Unit 4's listening tracker is the component that will
eventually own sustained-silence detection and emit `StruggleDetected`
itself — it is **not** a merged dependency of this unit. So the controller
carries its own T1 `Timer`, started from each `watchWord` call, as the
"sustained silence" half of the trigger.

Both halves are live at once and whichever comes first wins:

| signal | effect |
|---|---|
| the internal T1 timer fires | Tier 1 starts at exactly T1 after `watchWord` |
| `StruggleDetected(index)` for the watched index | Tier 1 starts immediately, short-circuiting the timer |
| `Silence(duration)` with `duration >= t1` | same short-circuit (`Silence` carries no index — it describes the current word by construction) |
| `Silence(duration)` with `duration < t1` | informational only; the timer still governs |

**Wiring when the real tracker lands:** nothing changes here. Keep calling
`watchWord` on every word advance and let the tracker's `struggleDetected`
arrive on `events`. Tier 1 is idempotent across the two sources — it starts
once, from whichever signal is first — so a double-trigger is impossible. If
a future tracker build wants to own the trigger outright, inject a very large
`t1` to park the stand-in timer rather than editing this controller.

## Tuning (PRD §7 R7)

`t1`/`t2` default to `kStruggleT1` / `kTier2WaitT2` from `lib/domain/tuning.dart`
— the single tuning file — and are constructor overrides. Per-level timing
profiles ("longer patience at higher levels") and pilot adjustments are
therefore injection, not code changes: no timing constant lives in this
feature's files.

## Testing

Fully headless. `FakeReadingTracker`/hand-built event streams drive events,
`FakeAudioService` verifies every play/duck by channel tag, `fake_async`
controls T1/T2 and asserts exact timelines, and an in-memory Drift database
verifies `WordHelpRecord` rows. No real audio, no device, no clock.

Two idealizations the suites rely on: a clip "finishes" when the test calls
`FakeAudioService.completePlayback`, and Tier 1's end is the moment
`SoundOutSequence`'s stream closes.

## Known frozen-suite defects

Two tests in the frozen suite cannot be satisfied by any implementation; both
are fixture bugs in the test file, not behavior gaps. They are documented
here rather than worked around, since the suite is frozen and the workarounds
would require inventing behavior that contradicts the same files' pinned
contracts.

1. **`sound_out_highlight_test.dart` → "channel is forwarded verbatim when
   overridden".** The file's `_drain` helper resolves each event's playback
   handle with
   `callLog.whereType<PlayLogEntry>().lastWhere((e) => e.channel == AudioChannel.help)`.
   That test plays the sequence on `AudioChannel.narration`, so no
   help-channel entry exists and `_drain` throws `Bad state: No element`
   inside its `onData`. The test's own assertion
   (`expect(channels, {AudioChannel.narration})`) simultaneously requires
   that *no* help-channel play be logged, so the two conditions are mutually
   exclusive. Fix: drop the channel filter in `_drain` (the file's own
   missing-phoneme test already uses a plain `.last`).

2. **`near_miss_prompt_test.dart` → "near-miss on a word not yet
   struggled-on does not consume/alter the T1 timer of a later word".** The
   later word is `ship` with `phonemeId: 'SH'`, but the file's
   `_phonemeAudioRefs` fixture contains only `K`, `AE`, `T`. `PhonemeSequencer`
   therefore throws `PhonemeAudioNotFoundException` before issuing any
   `play()`, so the test's `expect(..., hasLength(1))` on refs containing
   `'phonemes'` can never be met — no reachable audio ref in that test
   contains the substring. Fix: add `'SH': 'audio/phonemes/SH.wav'` to
   `_phonemeAudioRefs`.

Both fixes were verified against scratch copies of the two files: with them
applied and this implementation unchanged, all 59 tests pass.

## Deviation from a test-header comment

`near_miss_prompt_test.dart`'s header describes `NearMissPrompt.play` as
playing the prompt line, "waiting for it to finish", then playing the word.
Its own controller-integration test contradicts that: it asserts both clips
are logged after a bare `async.flushMicrotasks()`, with no
`completePlayback` and no clock elapse, so a strictly-sequential
await-completion implementation logs only the prompt line and fails.

`NearMissPrompt` therefore dispatches both clips in the same event-loop turn
— prompt line first, word second — and then awaits both completions in that
same order. The prompt line is still played first and awaited first, and the
returned future still does not complete until both clips have ended, so
every behavioral assertion in the header holds; only the internal dispatch
point moves. This also matches the near-miss path's intent: reading has
*already* continued, so the prompt is a fire-and-forget hand-off to the audio
engine that must not depend on its caller staying alive across clip
boundaries. The strictly-sequential variant was tried first and is what
surfaced the conflict.
