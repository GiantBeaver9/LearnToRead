# Voice recording brief (Unit 13 — for the product owner's narrator)

This is the recording direction for every piece of human-recorded voice
audio in LearnToRead v1. It is a content/production document, not code: it
transcribes the pinned decisions from PRD §8 Unit 13 and OQ-3 into direction
a narrator and engineer can record against. Nothing in the app generates
speech at runtime — every clip named or implied here is a shipped asset the
app plays back verbatim through `AudioService` (`lib/features/audio/`).

## The narrator

**One narrator, throughout, for all v1 content** (ratified, OQ-3). Every
category below — phonemes, celebrations, prompts, sentence narrations,
twisters, word pronunciations, definition read-alouds — is recorded by the
same voice. Do not mix voices across sessions or categories; a child should
hear one consistent, warm, friendly adult voice across the entire app.
Book the same narrator for every follow-up session (new stories, corrections,
expansion packs) for as long as the app ships v1-style recorded content.

Target delivery: warm, encouraging, unhurried — this is a read-aloud for a
5-10 year old learning to sound out words, not a broadcast announcer read.
Avoid a "kids' show" caricature voice; natural warmth reads better across
repeated listens than exaggerated cheerfulness.

## 1. The 44 phonemes (the core deliverable)

Each phoneme is recorded as **one isolated sound**, not a syllable and not a
word. This is the single most important instruction in this brief — get
this wrong and every gapless sound-out sequence in the app (Unit 6 stuck-word
help, Unit 15 Sound Garden) sounds glued-together or draggy.

- **Clean articulation:** produce the sound clearly and simply, the way a
  patient teacher would say it in isolation ("mmm", "sss", "aaa") — not
  embedded in a carrier word, not exaggerated into a cartoon sound.
- **Minimal schwa tail:** consonant sounds must **not** trail into an "uh"
  (schwa). "B" is a clean "b" stop/release, not "buh"; "T" is a light "t"
  tap, not "tuh"; "SH" is a clean hiss, not "shuh". A trailing schwa is the
  single most common recording defect for isolated consonants — listen back
  for it on every take and re-record any clip that has one. Vowel phonemes
  are recorded as the pure vowel sound itself (no leading or trailing schwa
  either).
- **No leading/trailing silence beyond a clean edit:** each clip should
  start essentially at the onset of the sound and end essentially at its
  natural decay, so the playback engine can queue phoneme clips back-to-back
  with no perceptible gap and no perceptible click (PhonemeSequencer plays
  these gaplessly, in `graphemePhonemeMap` order — see
  `docs/audio-playback.md`).
- **Consistent loudness and tone across all 44:** these clips are heard
  back-to-back inside one word (e.g. "ship" = SH + IH + P) and must sound
  like one continuous voice, not 44 separately-leveled takes. Record the
  full set in one session if possible, with consistent mic distance and
  level throughout.

### The fixed set (24 consonants + 20 vowels = 44)

Recording ids below are the exact content-facing tokens the app uses
(`kEnglishPhonemeIds` in `lib/domain/models/content_models.dart`); treat
them as opaque filenames, not as pronunciation guides — direction for each
sound is in the "say it like" column.

**Consonants (24):**

| id | say it like (example word, sound only) |
|----|------------------------------------------|
| B | **b**at (clean stop, no "buh") |
| D | **d**og (clean stop, no "duh") |
| F | **f**an (voiceless hiss, no "fuh") |
| G | **g**o (clean stop, no "guh") |
| HH | **h**at (breathy exhale) |
| JH | **j**am (soft "j" affricate) |
| K | **c**at / **k**ite (clean stop, no "kuh") |
| L | **l**ap (clean liquid, no held "luh") |
| M | **m**at (hum, can hold briefly, no "muh" release) |
| N | **n**et (hum, can hold briefly, no "nuh" release) |
| NG | so**ng** (nasal hum, back of throat) |
| P | **p**at (clean stop/release, no "puh") |
| R | **r**at (clean liquid, no held "ruh") |
| S | **s**at (voiceless hiss, no "suh") |
| SH | **sh**ip (voiceless hiss, no "shuh") |
| T | **t**op (light tap, no "tuh") |
| TH | **th**in (voiceless, tongue between teeth) |
| DH | **th**is (voiced, tongue between teeth) |
| V | **v**an (voiced hiss, no "vuh") |
| W | **w**et (clean glide, no "wuh") |
| Y | **y**es (clean glide, no "yuh") |
| Z | **z**ip (voiced hiss, no "zuh") |
| ZH | vi**s**ion (voiced "zh" hiss) |
| CH | **ch**ip (affricate, no "chuh") |

**Vowels (20 — monophthongs, diphthongs, r-controlled):**

| id | say it like (example word, sound only) |
|----|------------------------------------------|
| AA | h**o**t |
| AE | c**a**t |
| AH | c**u**p |
| AO | d**o**g / c**au**ght |
| AW | c**ow** |
| AY | k**i**te |
| EH | b**e**d |
| ER | b**ir**d (r-colored) |
| EY | c**a**ke |
| IH | sh**i**p |
| IY | s**ee** |
| OW | b**oa**t |
| OY | c**oi**n |
| UH | b**oo**k |
| UW | bl**ue** |
| AX | schwa — the unstressed "**a**bout" vowel (this is the ONE place a light schwa is correct — it is the schwa phoneme itself) |
| AIR | ch**air** (r-colored) |
| EAR | d**ear** (r-colored) |
| URE | c**ure** (r-colored) |
| ARE | c**ar** (r-colored) |

Note the one deliberate exception to the "no schwa" rule: `AX` **is** the
schwa sound itself (the vowel in the second syllable of "about") — record it
as that vowel, not as silence or a stop.

### Sign-off

Once the full 44-phoneme set is recorded and delivered, it goes to the
product owner for sign-off before it ships (PRD §8 Unit 13 acceptance:
"Product owner sign-off on the recorded phoneme set"). This sign-off is an
owner deliverable tracked in the repo/notes, not something this ticket
tests — flag the delivered set to the owner explicitly rather than assuming
silent approval.

## 2. Celebration lines (~10)

Short, upbeat, varied lines played after a completed story or twister (Unit
8 celebration sequence). Record roughly ten distinct lines so repeat plays
don't feel like the same clip on a loop — vary wording and energy slightly
across takes, but keep the same warm voice and a consistent celebratory
register. Examples of the kind of line (final wording is the product
owner's copy, not this brief's):

- "You did it!"
- "Great reading!"
- "Wow, you read that whole page!"
- "Nice job sounding that out!"
- "You're getting so good at this!"

Keep each line short (under ~2 seconds) — these play over a visual
celebration animation and should not hold up the moment.

## 3. Fixed prompts

Short, reusable UI prompts, recorded once each and reused everywhere they
apply. The pinned v1 example:

- **"Your turn"** — played after modeled help (Tier 2 scaffold) or after a
  twister's narration models the line, inviting the child to read/repeat.

Additional fixed prompts introduced later follow the same direction: short,
warm, consistent tone with the rest of the set, one clean take per prompt.

## 4. Per-story / per-content voice work

Everything below is authored per story/level by the content pipeline (Unit
3) and is out of scope for this brief to enumerate exhaustively, but is
recorded under the same voice and technical spec as the fixed sets above:

- **Sentence narrations** — one recording per sentence-level story sentence
  (`Sentence.narrationAudioRef`), required for every sentence-format story
  (A-11). Read at a natural, clear, unhurried pace appropriate for an early
  reader following along.
- **Tongue twisters** — one narration per twister that models the line
  before the child attempts it (Unit 14). Read clearly enough that the
  target phoneme's repeated sound is easy to hear and imitate.
- **Per-story word pronunciations** — one clip per `WordToken`
  (`pronunciationAudioRef`), the whole-word pronunciation played on tap
  (distinct from the phoneme-by-phoneme sound-out, which is assembled at
  runtime from the 44-phoneme set above).
- **Vocab definition read-alouds** — one clip per `VocabCard`
  (`definitionAudioRef`), reading the definition text clearly for a child
  who may not yet be able to read it themselves.

## 5. Technical delivery spec

- **Loudness target: -16 LUFS integrated**, for every clip in every
  category above. This is the single normalization target the pipeline
  checks against (Unit 3's pack-build linter owns the automated -16 LUFS
  check; this brief only states the target the narrator/engineer records
  and masters to). Deliver pre-normalized where practical, but the pipeline
  will reject anything that fails the check regardless of source level, so
  aim for -16 LUFS integrated at delivery rather than relying on downstream
  correction.
- **Format:** deliver as the pipeline's ingest format (owner/engineer to
  confirm current spec at delivery time — typically mono 44.1kHz+ WAV for
  source masters); the pipeline handles any further transcode needed for
  shipped pack assets.
- **File naming:** phoneme clips are named by their `kEnglishPhonemeIds`
  token (e.g. `SH.wav`, `EY.wav`) exactly as listed in the table above —
  these ids are consumed directly as map keys by `PhonemeSequencer`
  (`lib/features/audio/phoneme_sequencer.dart`); a misnamed or missing
  phoneme file is a content/pack bug that fails playback for every word
  using that sound. Naming for narration/pronunciation/definition clips
  follows the content pipeline's per-story/per-card asset id (Unit 3).
- **No mid-clip silence padding.** Trim leading/trailing silence per clip
  (see the phoneme gapless requirement above) — this matters most for the
  44 phonemes, but applies as good practice to every category.

## Delivery checklist

- [ ] One narrator across every category below.
- [ ] All 44 phonemes recorded: clean articulation, no consonant schwa
      tail (except `AX`, which *is* the schwa vowel).
- [ ] ~10 celebration lines, varied wording, consistent warm tone.
- [ ] Fixed prompts recorded ("your turn" for v1).
- [ ] Sentence narrations for every sentence-format story delivered.
- [ ] Tongue-twister narrations delivered per twister.
- [ ] Per-story word pronunciations delivered per `WordToken`.
- [ ] Vocab definition read-alouds delivered per `VocabCard`.
- [ ] Every clip at -16 LUFS integrated.
- [ ] Phoneme files named exactly by `kEnglishPhonemeIds` token.
- [ ] Delivered phoneme set flagged to the product owner for sign-off.
