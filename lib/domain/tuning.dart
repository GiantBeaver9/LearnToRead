/// The single tuning file (PRD §8 Unit 6, pinned design): "Timings T1/T2,
/// struggle sensitivity, and phonetic-closeness thresholds (Unit 4) are
/// constants in one tuning file; pilot adjustments touch only that file."
///
/// Every value below is a genuine compile-time `const` (not `final`), so a
/// pilot tuning pass is a single-file, no-code-elsewhere change. Do not add
/// tuning constants anywhere else in the codebase -- this file is the one
/// place downstream units (matching, struggle detection, Sound Garden) read
/// them from.
library;

/// T1: sustained-silence threshold that (together with
/// [kStruggleConsecutiveNonMatchingBursts]) drives `struggleDetected`
/// (PRD §8 Unit 6, A-12b).
const Duration kStruggleT1 = Duration(seconds: 4);

/// T2: wait time before the tier-2 stuck-word scaffold engages
/// (PRD §8 Unit 6).
const Duration kTier2WaitT2 = Duration(seconds: 4);

/// Word-mode (story reading) phonetic-closeness thresholds (PRD §8 Unit 4).
/// A word of at most this many phonemes is "short" for closeness-matching
/// purposes; the boundary is inclusive on the short side (a
/// [kWordModeShortWordMaxPhonemes]-phoneme word is short, one phoneme longer
/// is long).
const int kWordModeShortWordMaxPhonemes = 4;

/// Max substituted phonemes tolerated for a short word (<=
/// [kWordModeShortWordMaxPhonemes] phonemes) to still count as a
/// close-enough (near-miss) match.
const int kWordModeMaxSubstitutedPhonemesShortWord = 1;

/// Max substituted phonemes tolerated for a longer word to still count as a
/// close-enough (near-miss) match.
const int kWordModeMaxSubstitutedPhonemesLongWord = 2;

/// A-12(a): number of consecutive finalized non-matching speech-hypothesis
/// bursts that trigger `struggleDetected`. A-12(b) (sustained silence) reuses
/// [kStruggleT1] directly rather than a separate constant.
const int kStruggleConsecutiveNonMatchingBursts = 2;

/// A-13: sound-mode (tongue twister / Sound Garden echo) acceptance
/// threshold -- the minimum fraction of the target phoneme sequence that
/// must be matched (with per-phoneme distance <= [kSoundModePerPhonemeMaxDistance],
/// target-phoneme instances weighted [kSoundModeTargetPhonemeWeight]x) for
/// an echo attempt to be accepted.
const double kSoundModeMatchThreshold = 0.60;

/// A-13: max per-phoneme edit distance tolerated within a sound-mode match.
const int kSoundModePerPhonemeMaxDistance = 1;

/// A-13: weight applied to matches of the twister/card's target phoneme when
/// scoring a sound-mode echo attempt against [kSoundModeMatchThreshold].
const int kSoundModeTargetPhonemeWeight = 2;

/// PRD §8 Unit 16 (Phonics flashcards, MVP Leitner scheduling): the number
/// of Leitner boxes. "got it" advances a card one box, capped here;
/// "practice again" always returns a card to box 1 (due immediately,
/// re-queued after the remaining due cards this session).
const int kFlashcardMaxBox = 3;

/// PRD §8 Unit 16: how far ahead a card is scheduled when "got it" promotes
/// it into box 2 — "dues: box 2 = +1 day".
const Duration kFlashcardBox2Due = Duration(days: 1);

/// PRD §8 Unit 16: how far ahead a card is scheduled when "got it" promotes
/// it into box 3 — "box 3 = +3 days".
const Duration kFlashcardBox3Due = Duration(days: 3);

/// PRD §8 Unit 16: how far ahead a card already in box 3 is re-scheduled on
/// each subsequent "got it" — "then +7 day re-dues".
const Duration kFlashcardBox3Redue = Duration(days: 7);

/// Sound Garden practice loop (docs/design/mockup-spec.md §10a, ratified
/// 2026-07-28): how long the grapheme holds green (with the confetti burst)
/// after an accepted echo before the card resets to amber with a fresh echo
/// attempt. Pinned: 1000 ms.
///
/// Home rationale: motion/visual durations conventionally live in
/// `DesignTokens` (lib/design/tokens.dart), but this value paces the
/// practice-loop *behavior* (like [kStruggleT1]/[kTier2WaitT2] pace theirs),
/// and this file's contract is that Sound Garden reads its tuning constants
/// from here and nowhere else.
const Duration kSoundGardenGreenHold = Duration(milliseconds: 1000);
