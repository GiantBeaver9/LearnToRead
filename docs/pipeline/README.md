# Content pipeline — authoring flow & pack build

Unit 3 (PRD §8) is the content pipeline: how a story goes from an idea to a
versioned, checksummed bundle the app can load. This document is the authoring
guide for that flow, and the reference for what `dart run tool/pack_build.dart`
enforces and why.

The pipeline is **CLI tooling in this repo, in Dart** — the PRD granted
builder's choice of Dart or Python and Dart was ratified in the
`pack-build-cli` ticket, so one toolchain covers both the app and its tooling
and the validators consume `lib/domain/` directly rather than a re-typed copy
of the content schema.

---

## 1. The authoring flow (PRD §8 Unit 3, pinned)

Per story, in order:

1. **AI-drafted text against the level's decodability constraint.** The draft
   is written to use only graphemes the reader has met by that level.
2. **Human edit & approval.** Every published word is human-approved. This step
   is not optional and not automatable — the linter catches decodability, not
   whether a sentence is good.
3. **Automatic tagging.** Grapheme-phoneme mapping per word
   (`WordToken.graphemePhonemeMap`, digraphs as single units — `sh` is one
   entry, never `s` + `h`), vocab word selection, and vocab card authoring.
4. **Audio ingestion.** Word pronunciations, definition audio, sentence
   narration and tongue-twister audio, from product-owner-supplied recordings.
   Refs are **source-agnostic**: the pipeline never asks where a file came
   from, which is what keeps TTS available as a post-v1 substitute (R4's
   escape hatch) without a code change.
5. **Rive animation + collectible**, commissioned per the style guide, each
   accompanied by its declared-inputs sidecar (see §4).
6. **Pack build** — `tool/pack_build.dart`, described below.

Owner-supplied assets (sentence narrations, twister text + audio) enter at
steps 3–4 and flow through exactly the same validation and loudness pipeline as
everything else. There is no bypass lane.

---

## 2. The content directory

A pack is authored as a directory:

```
my-pack/
  manifest.json                    # StoryPack.toJson() — the §5 manifest
  audio/
    words/sat.wav
    narration/story.1.wav
    celebration/story.1.wav
    defs/sat.wav
    twisters/1.wav
  rive/
    story.1.riv
    story.1.riv.inputs.json        # A-16 declared-inputs sidecar
    collectibles/sat.riv
    collectibles/sat.riv.inputs.json
```

Rules:

- `manifest.json` sits at the root and is the raw manifest as
  `StoryPack.toJson()` produces it. Its `checksum` field must be **present**
  (a `""` placeholder is fine) — the build ignores its value and recomputes it.
- Every audio and Rive ref in the manifest is a `/`-separated path **relative
  to the content directory**. `audio/words/sat.wav`, never an absolute path and
  never `./`-prefixed.
- `assetRefs` in an authored manifest is ignored: the build recomputes it from
  the refs the content actually uses, so it can never drift from reality.
- `Level` and `PhonicsSkill` do **not** live in the manifest (PRD §5 — scope &
  sequence is data loaded separately by Unit 2). They are handed to the build
  via `--levels`.

---

## 3. Running a build

```
dart run tool/pack_build.dart <content-dir> <out-file> --levels=<levels.json> \
    [--heart-words=<file>] [--starter-levels=level.1,level.5,level.10] \
    [--loudness-target=-16.0] [--loudness-tolerance=1.0]
```

Exit codes: `0` built, `1` content errors, `2` usage/input error.

`levels.json` is a list mirroring `Level`/`PhonicsSkill`:

```json
[
  {
    "id": "level.1",
    "ordinal": 1,
    "format": "sentence",
    "vocabEnabled": false,
    "newSkills": [
      {
        "id": "skill.1",
        "name": "s a t",
        "sequenceOrder": 1,
        "introducesGraphemes": ["s", "a", "t"]
      }
    ]
  }
]
```

`--heart-words` is `{"level.1": ["said", "the"]}`: words whitelisted as heart
words at a level (and, cumulatively, every level above it).

The CLI is a thin wrapper. All of the build's judgement lives in
`lib/pipeline/pack_builder.dart`'s `buildPack`, which is the function to call
from tests or from any other tool.

---

## 4. What the build enforces

Every stage **aggregates** — one run reports every problem in the pack, so an
author fixes a batch rather than replaying the build once per error. Errors
carry `stage`, `entityType`, `entityId`, `field` and a message.

| Stage | Enforces | Source of truth |
|---|---|---|
| `schema` | §5 manifest schema, per-field, per-entity; A-11 narration on every sentence-format story; twister `narrationAudioRef` + `targetPhonemeId` | `lib/domain/models/pack_manifest.dart` |
| `decodability` | Every story word decodable from the cumulative grapheme set at its level, unless whitelisted as a heart word there; A-8 word/page bounds | `lib/pipeline/decodability_linter.dart` |
| `assetPresence` | Every audio ref has a file behind it (source-agnostic: presence only) | `lib/pipeline/asset_presence_check.dart` |
| `loudness` | Every audio asset measures −16 LUFS integrated ±1 LU, per ITU-R BS.1770 | `lib/pipeline/loudness_check.dart` |
| `riveInputs` | Every `.riv` declares `idle` / `celebrate` / `collect` in its sidecar (A-16) | `lib/pipeline/rive_input_validator.dart` |
| `graphemeSound` | Unit 15 inventory: `phonemeIds` in the 44-phoneme set, level refs resolve, example words have text + present audio + a valid `minLevelId` | `lib/pipeline/manifest_validator.dart` |

The one thing that **warns and never fails**: A-9 starter-pack composition. Pass
`--starter-levels` to declare the three age-band starting levels a starter pack
should cover; a level with no story is reported as a warning on the build
result. Composition is a property of a *pack selection*, and most builds are of
a single work-in-progress pack that was never meant to cover all three bands —
so the signal goes in the log and the decision stays with the product owner.

### Twisters (Unit 14)

Twisters are **wholly exempt from decodability** — modelled-first content may
use above-level words. Their required fields (`narrationAudioRef`,
`targetPhonemeId`) are enforced by the *schema* stage, not by a twister-only
code path, and their narration audio goes through presence and loudness like
any other asset.

### Rive sidecars (A-16)

`rive/foo.riv` declares its state-machine inputs in `rive/foo.riv.inputs.json`,
committed next to the binary so an art hand-off moves the pair together:

```json
{ "inputs": ["idle", "celebrate", "collect"] }
```

The sidecar is **authoritative**. A missing sidecar fails the build even if the
`.riv` itself would introspect fine — an undeclared contract is exactly what
A-16 exists to prevent. Extra inputs beyond the required three are allowed.
Runtime introspection may supplement this check where available; it never
replaces it.

### Loudness (Unit 13)

All shipped audio is normalized to **−16 LUFS integrated**, verified at build
time. `loudness_check.dart` implements the real BS.1770 chain in pure Dart —
K-weighting (a +4 dB high shelf above ~1.5 kHz plus an RLB high-pass at ~38 Hz,
both designed at the file's own sample rate), mean-square over 400 ms blocks
overlapped 75 %, an absolute gate at −70 LKFS and a relative gate 10 LU below,
then `−0.691 + 10·log10(mean gated power)`.

Two deviations from BS.1770-4 are deliberate and recorded in that file's header:
channel powers are **averaged rather than summed**, so a mono recording and its
dual-mono stereo encoding measure the same; and digital silence returns a finite
floor (−70 LUFS) rather than negative infinity.

To normalize a recording before ingesting it, `normalizeToTargetLoudness` in the
same file applies the single constant gain that lands the file on target
(round-trips well inside ±0.5 LU). Input must be 16-bit linear PCM WAV.

---

## 5. Pack integrity (A-15)

The built manifest carries a **SHA-256 checksum** over the UTF-8 bytes of the
manifest JSON with its own `checksum` field blanked to `""` — so the checksum
never depends on itself, and re-checksumming a signed manifest reproduces it.
Two builds of identical content produce an identical checksum; one changed byte
of content changes it.

- `computeManifestChecksum(manifestJson)` — compute.
- `verifyManifestChecksum(manifestJson)` — verify, false after any tampering.

§5's "signed checksum" is satisfied by this in v1. Cryptographic **signing** is
recorded post-POC hardening, not built.

---

## 6. Cost tracking

Per-story pipeline cost (time + spend) is a PRD §8 Unit 3 process acceptance
item, and R4's early-warning signal: if a story costs more than the library can
absorb, that shows up in the sheet before it shows up in a stalled launch
library. Use [`cost-sheet-template.md`](cost-sheet-template.md) from story #1 —
the filled sheet after the first five stories is a product-owner deliverable.

---

## 7. Known gaps

- Real launch content — the real grapheme inventory, example words, and art —
  depends on OQ-4 (art commissions) and OQ-5 (scope & sequence + Sound Garden
  inventory), both product-owner items. Everything above runs on fixtures until
  then.
- The end-to-end "bundle loads in the app" integration test lives in the
  content-delivery unit, which owns the loader.
