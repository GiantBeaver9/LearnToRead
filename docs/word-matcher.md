# Word Matcher (Unit 4 core — hybrid matching layer)

## Overview

The product's core-risk unit (R1): the close-enough phonetic matching layer that decides whether a child's production counts as reading the word. Fully headless — no audio ever reaches this layer. Inputs are `Hypothesis` strings (word and optional phone hypotheses) from any engine behind the listening-contracts interface; outputs are typed `MatchResult`s. Emitting tracker events (`wordAccepted`, `wordAcceptedNearMiss`, `struggleDetected`) is listening-tracker's job — this unit only classifies.

Two modes, per PRD §8 Unit 4:

- **Word mode** (`WordMatcher`) — story reading: close-enough word acceptance against the known sentence, expected-text hybrid recognition (KidSpeak-style, OQ-1 ratified). The matcher always knows the target; hypotheses are scored against the known next word, never open-ended transcription.
- **Sound mode** (`SoundModeScorer`) — tongue twisters (Unit 14) and Sound Garden echo (Unit 15): listens for the SOUNDS, not word identity, with the drilled phoneme weighted most and the separate looser A-13 threshold set.

All thresholds are read from `lib/domain/tuning.dart` (word mode: `kWordModeShortWordMaxPhonemes` 4, `kWordModeMaxSubstitutedPhonemesShortWord` 1, `kWordModeMaxSubstitutedPhonemesLongWord` 2; sound mode A-13: `kSoundModeMatchThreshold` 0.60, `kSoundModePerPhonemeMaxDistance` 1, `kSoundModeTargetPhonemeWeight` 2). They are injectable constructor parameters (mirrored by getters) so tests prove behavior follows the constants — never hardcoded.

## Files

### match_result.dart

- `enum MatchKind { exact, nearMiss, reject }` — the two acceptance grades are deliberately distinguishable (drives `wordAccepted` vs `wordAcceptedNearMiss` and the §5 `word_read` correct/near_miss analytics split).
- `class MatchResult { MatchKind kind; int wordIndex; int? phonemeDistance; }` — `phonemeDistance` is 0 for a textual exact match, the measured distance for a near-miss, the failed distance for a reject (feeds struggle detection), and null only where no distance is meaningful (a lookahead back-filled word that had no hypothesis of its own).

### phoneme_distance.dart

`int phonemeEditDistance(List<String> a, List<String> b)` — standard Levenshtein edit distance over phoneme-id sequences: unit cost for substitution, insertion, deletion; symmetric; zero iff equal. Canonical anchors: `[G,AE,T]` vs `[K,AE,T]` = 1 ("gat"/"cat" near-miss), `[D,AO,G]` vs `[K,AE,T]` = 3 ("dog"/"cat" reject).

### grapheme_to_phoneme.dart

`List<String> graphemesToPhonemes(String word)` — matcher-internal comparison G2P for hypothesis words that have no authored map ("gat"). Letterwise-regular decoding (short/lax vowels, one phoneme per letter) plus a tiny greedy digraph set (sh, ch, th, ng, ck); `x` → K,S. Total and deterministic: any input accepted, non-letters ignored, empty in → empty out; output drawn only from `kEnglishPhonemeIds`.

**Limits (deliberate, per ticket — not a linguistics project):** no silent-e, vowel teams, r-controlled vowels, stress, or context sensitivity. It is never applied to target words — closeness is always measured against the AUTHORED `graphemePhonemeMap` — and is adequate only for comparing short, letterwise-regular productions near a known target.

### word_matcher.dart

`WordMatcher({required List<WordToken> sentence, shortWordMaxPhonemes, maxSubstitutedPhonemesShortWord, maxSubstitutedPhonemesLongWord})` with `List<MatchResult> onHypothesis(Hypothesis h)`, `int currentIndex` (next expected word; == length when done), `bool isComplete`.

Per-burst decision order:

1. **Junk filter.** Each word hypothesis is whitespace-split into candidate tokens, lowercased, stripped of non-letters. No surviving candidates (empty list, `""`, `"!!!"`) → no results, no state change — non-speech must not feed struggle detection (A-12a). Hypotheses after completion are likewise no-ops.
2. **Current word.** Any candidate textually equal to the target (case/punctuation-insensitive, both sides) → `exact` (distance 0). Otherwise the best phoneme distance vs the target's authored phonemes decides: 0 → `exact`; within the target's threshold → `nearMiss`; the threshold is the short-word one when the target has ≤ `shortWordMaxPhonemes` phonemes (inclusive), else the long-word one. An exact candidate anywhere in the list wins over an earlier near-miss.
3. **Lookahead 1 with back-fill.** Only if the current word rejected: the same policy is run against the next word. A hit accepts BOTH — emission order pinned current-first: `[MatchResult(exact, currentIndex, distance: null), MatchResult(<own grade>, currentIndex+1, <distance>)]`. The back-filled word is graded `exact` (tracker routes it to plain `wordAccepted`). Depth is exactly 1 — `currentIndex+2` is never consulted.
4. **Repeat.** A candidate matching the most recently accepted word (same policy: exact or near-miss-shaped) is a non-event: no acceptance, no reject, no state change.
5. **Reject.** Otherwise one `MatchResult(reject, currentIndex, phonemeDistance: <min failed distance vs current word>)`. Rejects never advance and never poison the word — a later correct or close-enough production (self-correction) accepts normally.

Candidate phonemes: engine `phoneHypotheses` are used for the top word hypothesis when it is a single token (they align with the top candidate per the contract); every other candidate is scored via the comparison G2P of its own text. The frozen suite's fixtures make both paths equivalent by construction.

### sound_mode_scorer.dart

`SoundModeScorer({required List<String> targetPhonemeSequence, required String targetPhonemeId, matchThreshold, perPhonemeMaxDistance, targetPhonemeWeight})` with `void onHypothesis(Hypothesis h)` (incremental), `double matchedFraction` (weighted, in [0, 1]), `bool accepted`.

Pinned A-13 formula — weight in numerator AND denominator, so double-weighting can flip the verdict in both directions:

```
matchedFraction = sum(weight_i for matched positions i) / sum(weight_i for all positions i)
weight_i = targetPhonemeWeight where targetPhonemeSequence[i] == targetPhonemeId, else 1
accepted = matchedFraction >= matchThreshold   (inclusive)
```

A position is matched when a produced phoneme aligns to it within `perPhonemeMaxDistance`. Matched positions persist across bursts; the fraction is monotone and capped at 1.0. Silence scores 0.0.

Production paths: `phoneHypotheses` when the engine surfaces them (a non-null-but-empty list means "phones supported, nothing heard" and contributes nothing — no word fallback); otherwise the comparison G2P of the top word hypothesis approximates by phonetic distance. Both paths are contract-tested to agree.

## Orchestrator-pinned defaults (transcribed from the ticket)

Behaviors the frozen suite deliberately leaves unasserted — recorded here, tunable, owner-vetoable:

1. **Uniform inter-phoneme distance** — any substitution/insertion/deletion costs 1 (plain Levenshtein over phoneme ids; no confusability weighting). In sound mode this means per-phoneme distance is 0 (same id) or 1 (different id), so the default `perPhonemeMaxDistance` of 1 credits any in-order production one-for-one; tightening it to 0 requires exact identity.
2. **Current-first precedence on collision** — a current-word near-miss is evaluated before an exact match of the next word; lookahead is consulted only after the current word rejects.
3. **Homophones grade as exact** — a distance-0 hypothesis with different spelling is `exact`, not `nearMiss`.
4. **Reject distance aggregates as MIN** across the burst's hypothesis candidates (measured against the current word).
5. **Repeats reach back one word** — "repeats always accepted" applies only to the most recently accepted word, and near-miss-shaped repeats are likewise non-events (no acceptance, no reject).
6. **Sound-mode alignment is greedy in-order** — each burst walks the sequence left-to-right claiming the first eligible unmatched position; out-of-order or surplus productions are ignored without penalty.
7. **Multi-word hypothesis candidates are whitespace-split** into individual candidate tokens.

One implementation-level degenerate guard (not covered by the defaults block or the suite): a `SoundModeScorer` built with an empty `targetPhonemeSequence` reports `matchedFraction` 0.0 and never accepts (conservative: no acceptance without evidence; avoids 0/0).

## Test Coverage

Frozen suite `test/features/listening/matcher/` — 91 tests, none edited by this unit:

- `phoneme_distance_test.dart` — Levenshtein identity/symmetry/bounds, canonical gat/cat=1 and dog/cat=3 anchors tied to the tuning constants.
- `word_matcher_test.dart` — exact (case/punctuation both sides), canonical near-miss/reject, authored-map-not-G2P targets, exact threshold boundaries at 4 vs 5 phonemes, tuning injection flips verdicts, multi-candidate bursts, junk/empty/after-completion edges, G2P black-box behavior on the fixture vocabulary.
- `lookahead_test.dart` — back-fill ordering (current first, graded exact), near-miss grade survives on the heard word, depth exactly 1, current beats next, no double-fire.
- `self_correction_test.dart` — rejects never poison, repeats are non-events, monotonic index, full hesitant-read integration script.
- `sound_mode_scorer_test.dart` — A-13 defaults, exact 60% inclusive boundary, double-weight flipping the verdict in both directions, incremental tracking, word-only approximation path equivalence, degenerate inputs.
