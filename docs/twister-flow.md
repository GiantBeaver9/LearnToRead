# Unit 14 — Tongue-twister boosters (`twister-flow`)

PRD refs: §8 Unit 14, §5 `TongueTwister` / `TwisterProgress`, §8 Unit 4
(sound mode), §9 A-13, §5 Analytics events. Ticket:
`docs/tickets/twister-flow.json`.

A tongue twister is an **enunciation booster**, deliberately not a story:
the goal is clear, confident speech, not decoding. Every design decision in
this unit follows from that one distinction.

## Files

| File | Role |
| --- | --- |
| `lib/features/twister/twister_controller.dart` | Runtime orchestration of one attempt: narration → listening (or listen-then-tap) → completion effects. |
| `lib/features/twister/sparkle_celebration.dart` | The playful, story-celebration-free completion beat. |
| `lib/features/twister/faster_pass.dart` | The optional, skippable "say it again — a little faster!" second pass. |
| `lib/features/twister/twister_screen.dart` | Thin, token-styled composition over the controller. |

## Flow

1. **Booster node opened.** `TwisterController.start()`'s *synchronous*
   prefix — the same event-loop turn as the call, before any `await` — emits
   `twister_started` and calls
   `audioService.play(twister.narrationAudioRef, channel: AudioChannel.narration)`.
2. **Narration models the twister.** The owner-supplied recording plays to
   the end. Nothing touches the microphone until `completionOf(handle)`
   resolves — narration-before-listening is an ordering guarantee, not a
   convention.
3. **The child reads it.** With consent and a healthy engine, the controller
   starts the ASR engine biased with the twister's words and feeds every
   finalized hypothesis to one `SoundModeScorer`. Without either, the attempt
   degrades to listen-then-tap.
4. **Completion.** `TwisterProgress.timesCompleted` is incremented,
   `twister_completed` is emitted, `onCelebrate` fires, `isComplete` becomes
   true. No collectible.
5. **Optional faster pass.** One replay offer, skippable, granting nothing.
   The node is already done before the offer is made.

## Sound-level matching (A-13)

Tracking grades **sounds, not word identity** (PRD ratified). The controller
builds the target from the twister's authored phonemes:

```
targetPhonemeSequence = twister.words
    .expand((w) => w.graphemePhonemeMap.map((e) => e.phonemeId))
```

— one sequence for the whole twister, not one scorer per word — and hands it
to a single `SoundModeScorer` together with `twister.targetPhonemeId`. The
scorer is `lib/features/listening/matcher/sound_mode_scorer.dart`, reused
verbatim; the matcher is never forked here.

A-13's defaults are read from `lib/domain/tuning.dart`
(`kSoundModeMatchThreshold` 0.60, `kSoundModePerPhonemeMaxDistance` 1,
`kSoundModeTargetPhonemeWeight` 2) and are constructor-injectable, so a pilot
tuning pass touches one file. The three `matchThreshold` /
`perPhonemeMaxDistance` / `targetPhonemeWeight` getters expose what is
actually in effect, which is what proves config injection rather than
hardcoding.

**This is the twister threshold set, not the story set.** The word-mode
near-miss constants (`kWordModeMaxSubstitutedPhonemes*`) are never consulted
on this path — there is no `WordMatcher` in the controller at all. Twister
thresholds are looser on purpose: this is practice *saying*, not proof of
decoding.

**Two engine paths, one scorer.** Engines that surface phone-level detail
feed `Hypothesis.phoneHypotheses` straight in. Engines that expose only word
hypotheses are approximated by the scorer's comparison-G2P path — the drilled
sounds still register even when the recognized word text is nonsense. Whether
on-device engines expose usable phone detail is a Unit 0 spike question; if
the spike says no, the approximation path becomes the primary on-device path
(flag to the orchestrator when the verdict lands).

## No `ReadingTracker`

The controller takes an `AsrEngine` directly and runs its own
engine → `SoundModeScorer` loop (the `echo_session` pattern; the real engine
is injected by the app shell). It does **not** depend on the listening
tracker: word state machines, help tiers, the cloud-minute cap, silence
timers and struggle detection are all story-shaped concerns a twister does
not have. Green-word tracking on screen reuses `WordState.renderColor` from
`lib/features/reading/word_state.dart` so a twister's green can never drift
from a story's, but the *state machine* is not in the loop.

## Never hard-blocked (PRD §6)

| Situation | Behavior |
| --- | --- |
| `micConsent == false` | `engine.start` is **never called** — the microphone is not opened at all. The attempt enters tap mode the moment narration ends. |
| Engine fails to open | `engine.start` *is* attempted (the failure is a real one, not a guess), then the attempt falls back to tap mode. |
| Either | `tapWord()` walks the twister's words; the final tap completes the node through exactly the same path as an accepted mic attempt — same `TwisterProgress` write, same `twister_completed`, same celebration. |

`tapWord()` is available in every mode, not only the degraded ones: a child
who would rather tap is never forced through the microphone.

## No collectible, always replayable

`TwisterController`'s constructor takes a `TwisterProgressDao` and
deliberately **no `CollectionDao`** — there is structurally nowhere for a
collectible grant to come from. Collectibles stay story-tied (PRD §8 Unit 9).

One controller models one attempt; it is not restartable. Re-entry means a
fresh controller, which starts un-done and increments `timesCompleted` again.
Placement of the node on the map (≈1 per 3 stories, level-tagged, unlocked
with level) belongs to `progress-map-collection`; pack validation (narration
+ `targetPhonemeId` required, decodability exempt) belongs to
`pack-build-cli`.

## Analytics

`twister_started` and `twister_completed` only, both carrying the §5 base
fields and **never a `storyId`** (the schema forbids it for these events — a
twister does not happen inside a story). No word hashes, no transcripts: the
sound-mode path never puts recognized text anywhere near a payload.

## Sparkle celebration

`SparkleCelebration` is distinct from the story celebration by construction:
no Rive artboard, no collectible flight, no voice-line rotation, no skip
affordance, and its own shorter `kSparkleCelebrationDuration` (2 s) against
the story celebration's `kCelebrationDefaultAnimationDuration` (4 s). Its
constructor takes only `onFinished` and `duration` — there is no story stage
or collectible ref it *could* be handed. It finishes at exactly its own
duration, with no beat appended.

The painted sparkle burst is placeholder art (PRD §10 OQ-8); the shipped
treatment is owner-commissioned illustration/motion.

## Faster pass

`FasterPassPrompt` throws a `StateError` unless the primary controller is
already complete — the second pass can never substitute for the first. Its
status walks `offered → skipped` or `offered → inProgress → completed` and
then freezes; a resolved prompt cannot be re-offered, re-accepted, or
retroactively skipped.

"No extra reward" holds **by construction**: the prompt has no
`TwisterProgressDao`, no `onAnalyticsEvent`, and no `CollectionDao`. Whatever
`runReplay` does internally, the prompt itself has nowhere to record a second
completion or grant anything. `isNodeDone` mirrors the primary controller's
completion, which predates the prompt entirely — it is true at offer time and
stays true whether the offer is accepted, skipped, or simply left hanging.

## Known frozen-suite discrepancies

Three tests in the frozen suite encode timing assumptions that the frozen
fakes cannot satisfy. They are recorded here rather than worked around,
because working around them would require behavior that contradicts the PRD.

1. **`twister_flow_test.dart` — "mic indicator reflects isListening across
   the session".** The test reads `isListening` after two
   `flushMicrotasks()` calls (expecting `true`) and again after a third
   (expecting `false`, alongside `isComplete == true`).
   `FakeAsync.flushMicrotasks()` drains the microtask queue *to exhaustion*,
   including microtasks scheduled during the drain, so the state after the
   second and third calls is necessarily identical. The assertion pair is
   therefore unsatisfiable by any deterministic implementation. The test
   appears to assume `flushMicrotasks()` advances one async "step".

2. **`twister_flow_test.dart` — "twisters are always replayable"** and
   **`no_collectible_test.dart` — "three completions … timesCompleted
   reaching 3".** Both share one `FakeAudioService` across runs, and their
   `_passNarration` helper always completes
   `callLog.whereType<PlayLogEntry>().first.handle` — the **first** run's
   narration handle. On the second and later runs that handle is already
   finished, so `completePlayback` is a no-op and the new controller's own
   narration never ends. Since narration-before-listening is pinned (and
   separately asserted by "listening begins only after the narration finishes
   playing"), those runs cannot proceed. Using `.last` rather than `.first`,
   or a fresh harness per run, is the fix; both are test-side.

The replayability *behavior* itself is implemented and exercised: a fresh
controller carries no completed-lock, and `TwisterProgressDao.recordCompletion`
increments across runs (covered by `twister_progress_dao`'s own suite).
