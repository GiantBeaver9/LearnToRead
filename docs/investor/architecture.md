# LearnToRead — System Architecture

*Prepared for investor review. Every component named below exists in this repository today, with tests.*

LearnToRead is a Flutter app (iOS + Android) that teaches children ages 5–10 to read using structured phonics. The child reads a story aloud; the app listens and turns each word from ink to green as it is read, steps in with a graduated phonics scaffold when the child gets stuck, and rewards every finished story with a hand-authored animation of the scene the child just read. All content — story text, per-word phoneme maps, recorded human voice, animations — is authored offline, machine-validated, and shipped as versioned story packs. The app runs fully offline from first launch, keeps every piece of child data on the device, and sends only anonymous, hash-scrubbed telemetry. The engineering premise throughout: a child is never told they are wrong, and the system is built so it cannot accidentally do so.

---

## 1. System architecture

Three layers: a content pipeline that refuses to ship a bad story, an on-device app that owns the entire learning loop, and a hard privacy boundary with exactly one narrow, anonymous crossing.

```mermaid
flowchart TB
    subgraph PIPE["Authoring and content pipeline — runs off-device, before ship"]
        AUTH["Authored content: story text, phoneme maps,<br/>vocab cards, recorded narrator voice, Rive animations"]
        BUILD["Pack build CLI — tool/pack_build.dart"]
        LINT["Decodability linter: every word checked against the<br/>level's cumulative grapheme set, or a listed heart word"]
        LOUD["Loudness check: all audio normalized to -16 LUFS"]
        SCHEMA["Manifest schema + Rive state-machine inputs +<br/>asset-presence validation"]
        SUM["SHA-256 checksums per pack"]
        AUTH --> BUILD
        BUILD --> LINT --> LOUD --> SCHEMA --> SUM
    end

    SUM --> STARTER["Starter pack<br/>bundled in the app binary<br/>(works with zero network, ever)"]
    SUM --> CDN["CDN: static catalog.json + versioned packs<br/>download-only — no backend, no user data upstream"]

    subgraph DEVICE["On-device app — the privacy boundary: everything in this box stays on the device"]
        subgraph CONTENT["Content delivery — lib/data/content/"]
            DL["Catalog client + pack downloader"]
            INST["Checksum verify, then atomic install<br/>(a bad download can never corrupt installed stories)"]
            REPO["Content repository"]
            DL --> INST --> REPO
        end
        subgraph LOOP["Learning loop — lib/features/"]
            REC["Recognition stack<br/>ASR engine seam → phoneme-aware matcher<br/>(detail in section 2)"]
            READ["Reading screen: word state machine,<br/>ink → amber (saying now) → green (read)"]
            HELP["Stuck-word help ladder:<br/>sound it out → model it → move on"]
            CEL["Celebration: per-story Rive animation,<br/>narrated read-back, collectible earned"]
            EXTRA["Practice areas: Sound Garden,<br/>tongue twisters, phonics flashcards"]
            REC --> READ --> CEL
            REC --> HELP --> READ
            REC --> EXTRA
        end
        subgraph DATA["Local data — Drift over SQLite, per child profile"]
            DB["Profiles (max 4) · story progress · word-help records<br/>· collection · twister + flashcard progress"]
        end
        REPO --> LOOP
        LOOP --> DB
        AN["Analytics client: schema-validated events,<br/>word text replaced by truncated SHA-256 hash,<br/>PII-shaped payloads fail validation in CI"]
        LOOP --> AN
    end

    STARTER --> REPO
    CDN --> DL

    AN -- "batched HTTPS, offline-queued,<br/>dropped after 30 days unsent · one build flag kills it all" --> EP["Anonymous endpoint<br/>random install ID + profile ordinal only"]

    NEVER["NEVER leaves the device: audio (never even written to disk),<br/>names, transcripts, raw word text, device identifiers, location"]
    DEVICE -.- NEVER

    style DEVICE fill:#eef6ee,stroke:#2e7d32,stroke-width:3px
    style NEVER fill:#fdecea,stroke:#c62828,stroke-width:2px
    style EP fill:#fff8e1,stroke:#b28704
```

Load-bearing properties of this layer cake:

- **The pipeline is the quality gate, not a convention.** A story whose words exceed its phonics level, whose audio misses the loudness target, whose animation lacks the required state-machine inputs, or whose manifest fails schema **cannot be built into a pack** (`lib/pipeline/` — `decodability_linter.dart`, `loudness_check.dart`, `manifest_validator.dart`, `rive_input_validator.dart`, `asset_presence_check.dart`). Content errors are caught at build time on the author's machine, never at runtime on a child's device.
- **Offline-first is structural.** The starter pack ships in the binary; an integration test installs the app in airplane mode and runs the full experience. CDN packs are static files verified by checksum and installed atomically — there is no server that can be down.
- **The privacy boundary is enforced in code and CI.** Audio buffers are never written to storage (checked by test). The analytics schema rejects PII-shaped fields in CI; word identity crosses the boundary only as a truncated SHA-256 hash. There are no accounts, no third-party SDKs, and a single build flag produces a zero-telemetry binary.

## 2. The recognition stack

This is the hardest problem in the product and the deepest engineering. Off-the-shelf speech recognition is documented to fail on young children — rendering a 4-year-old's "looking at the frog" as "recognize the fog." The stack is designed around a different question: not *"what did the child say?"* but *"is this a fair attempt at the word we know comes next?"*

```mermaid
flowchart TB
    MIC["Microphone — open only during active reading,<br/>with a visible listening indicator; off everywhere else"]
    subgraph SEAM["ASR engine seam — lib/features/listening/contracts/asr_engine.dart"]
        ENG["Any engine implementing one interface:<br/>start with expected-word biasing → stream of hypotheses<br/>(word candidates + optional phoneme detail)"]
        OND["Default: platform on-device recognizer,<br/>gated by a week-one validation spike (built; owner-run)"]
        TAP["Tap-the-word fallback engine:<br/>same interface, so no mic ever hard-blocks a child"]
    end
    MIC --> ENG
    OND -.implements.-> ENG
    TAP -.implements.-> ENG

    BIAS["Expected-text biasing: the matcher always knows the target<br/>sentence — never open-ended transcription"]
    ENG --> BIAS

    subgraph MATCH["Phoneme-aware matching — lib/features/listening/matcher/"]
        DIST["Phoneme-level edit distance against the word's<br/>authored grapheme-to-phoneme map"]
        WEIGHT["Child-speech confusability weighting (research-informed):<br/>15 documented confusion pairs cost half —<br/>gliding (wabbit → rabbit), th-fronting (fing → thing),<br/>velar fronting (tat → cat), voicing pairs,<br/>acoustic confusions (file heard for while)"]
        POLICY["Accept when distance is within threshold:<br/>1 substituted phoneme for short words, 2 for long<br/>— so gat is accepted for cat; dog is not"]
        DIST --> WEIGHT --> POLICY
    end
    BIAS --> MATCH

    POLICY --> OK["Exact match:<br/>word turns green"]
    POLICY --> NM["Near-miss: word STILL turns green,<br/>then a warm model of the word —<br/>that's it: cat! — echo optional,<br/>reading continues immediately"]
    POLICY --> STR["No match: struggle detector<br/>(2 non-matching bursts, or 4 s silence)"]

    subgraph LADDER["No-failure help ladder — lib/features/help/"]
        T1["Tier 1 — sound it out: recorded human phonemes play<br/>while each grapheme cluster highlights in the word<br/>(digraphs light as one unit: sh, never s-h)"]
        T2["Tier 2 — model it: the app says the word,<br/>invites — your turn — accepts the repeat,<br/>or accepts the word and moves on"]
        T1 --> T2
    end
    STR --> LADDER
    LADDER --> DONE["Word marked green, identical to any other —<br/>help recorded invisibly per profile<br/>for the learning signal and the parent view"]

    SOUND["Sound mode — sound_mode_scorer.dart:<br/>scores the SOUNDS, not word identity — accept at 60% of the<br/>phoneme sequence, drilled phoneme weighted double.<br/>Powers tongue twisters, Sound Garden echo, flashcards"]
    BIAS --> SOUND

    TUNE["One tuning file — lib/domain/tuning.dart:<br/>every threshold and timing is a constant here,<br/>so pilot calibration touches exactly one file"]
    MATCH -.reads.-> TUNE
    STR -.reads.-> TUNE
    SOUND -.reads.-> TUNE

    style LADDER fill:#eef6ee,stroke:#2e7d32,stroke-width:2px
    style WEIGHT fill:#fff8e1,stroke:#b28704,stroke-width:2px
    style SEAM fill:#eef1f8,stroke:#3b5b9a
```

What makes this stack unusual:

- **Acceptance widens exactly where children's speech actually varies, and nowhere else.** The confusability table in `phoneme_distance.dart` encodes documented child-speech error axes — a child who says "wabbit" is credited with reading *rabbit*, because R→W gliding is developmental, not a reading error. A clearly wrong word still doesn't pass. The design follows the expected-text hybrid approach from current children's-ASR research (KidSpeak): the recognizer is biased with the known target, and our matcher — not the engine — decides acceptance.
- **There is no failure state, by construction.** The reading screen contains no red, no error sounds, no "wrong" (verified by test). Imperfect reading routes to patience and help; the maximum time a child can be stuck before the story advances is bounded and tested. Helped words render identically to correct words — the finished sentence is purely triumphant, while help is logged privately for the learning signal.
- **The engine is a commodity behind the seam; the pedagogy is ours.** `AsrEngine` is one small interface (biased start, hypothesis stream, stop). The platform recognizer, a future phonetically-informed cloud model, and the tap fallback all sit behind it identically — the matcher, help ladder, and every test above the seam are engine-independent.
- **Sound mode turns the same stack into phonics practice.** Scoring phoneme sequences instead of word identity powers three additional practice surfaces (tongue twisters, the Sound Garden grapheme cards, spaced-repetition flashcards) from the same matcher and the same recorded 44-phoneme human voice set.

## 3. Why this is hard to copy

- **Test-first construction with frozen contracts.** The repo's build manifest records 25 units each planned, written red (failing tests first), then verified — 127 test files, ~1,700 tests. The tracker event stream, ASR seam, and word-state machine are pinned contracts: UI, matcher, and engine evolve independently without breaking each other.
- **Phoneme-level pedagogy lives in the data model, not in prompts or heuristics.** Every shipped word carries an authored grapheme-to-phoneme map that simultaneously drives matching tolerance, sound-out highlighting, decodability linting, and flashcard generation. Replicating the app's surface without this substrate reproduces none of its behavior.
- **The child-speech acceptance model is research-informed and empirically tunable.** The confusability-weighted distance metric plus the single tuning file mean pilot findings become one-line calibrations — a competitor gluing a stock speech API to a word list has no equivalent adjustment surface.
- **The engine seam de-risks the fastest-moving dependency.** Children's ASR is improving rapidly; the interface (word + phone hypotheses, contextual biasing) is shaped for the next generation of phonetically-informed engines. Swapping engines is an adapter, not a rewrite — and the engine decision is gated by a purpose-built validation spike that ships in this repo (awaiting its device run) rather than assumed.
- **COPPA compliance is architectural, not a policy document.** No accounts, no audio retention (tested), on-device-only child data, per-profile mic consent behind a parental gate, and analytics that structurally cannot carry PII. There is no server-side child data because there is no server-side user data at all.
- **The content pipeline makes the library compoundable.** Machine-enforced decodability, loudness, schema, and animation-contract checks mean each new story is a validated data drop — no app release, no engineering time — while per-story cost tracking keeps library growth economics visible from story one.

---

*Primary sources in this repository: `PRD.md` (ratified spec), `lib/features/listening/` (recognition stack), `lib/features/help/` (help ladder), `lib/pipeline/` + `tool/pack_build.dart` (content pipeline), `lib/data/` (local storage and pack delivery), `lib/features/analytics/` (anonymous telemetry), `docs/` (per-unit behavior contracts), `manifest.jsonl` (test-first build record).*
