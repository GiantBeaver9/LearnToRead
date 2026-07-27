# PRD — LearnToRead (working title)

A mobile app (iOS + Android, Flutter) that teaches children ages 5–10 to read by
listening to them read aloud, scaffolding them when they struggle, and rewarding
every completed story with a hand-crafted animation of what they just read.

Every design decision in this document was ratified by the product owner
(Adam) during authoring. Builders implement what is pinned here; deviations
require a new decision from the product owner, not builder judgment.

---

## 1. Why

Learning to read is the highest-leverage skill a child acquires, and the
5–10 window is when it happens (or doesn't). Most reading apps either
passively read *to* the child, or gamify letter-matching without ever hearing
the child read. The core insight of this product: **the child reads aloud, the
app listens, and the text itself responds** — words turn from black to green as
they are read correctly, and finishing a story makes its scene come to life.
Reading becomes a performance with an immediate, magical payoff instead of a
chore checked by a tired parent.

The product owner's explicit quality bar: this must not look or feel like a
generic, template-assembled app ("AI slop"). Craft — in illustration,
animation, voice, and typography — is a first-class requirement, not polish.

## 2. Users & stakes

| User | Description | Stakes |
|---|---|---|
| Child, emergent reader (5–7) | Sounding out CVC words and short sentences. Cannot read UI text; navigates by icon, color, and voice. | If the app misjudges their reading or shames mistakes, it damages confidence at the most fragile stage. |
| Child, developing reader (8–10) | Reads paragraphs; growing vocabulary. Bores easily; detects condescension instantly. | If content feels babyish or the reward loop is weak, they churn to games. |
| Parent | Sets up profiles, grants microphone/cloud-processing consent, hands over the device. Not present for most sessions. | Trusts the app with their child's voice data and unsupervised screen time. A single privacy misstep or inappropriate moment destroys trust permanently. |
| Product owner / content author | Writes and approves all story text, commissions art and voice recording, publishes content drops. | Content pipeline cost per story determines whether the library can grow. |

There is no teacher/classroom user in v1 (see Non-scope).

## 3. Scope & non-scope

### In scope (v1)

- Single reading continuum from single-sentence stories to paragraph stories,
  driven by a phonics scope & sequence (Unit 2).
- Live read-aloud tracking: words turn black → green as the child reads them
  (Units 4, 5).
- Automatic tiered stuck-word scaffolding: phoneme sound-out, then the app
  models the word (Unit 6).
- Tappable blue vocabulary words with curated, read-aloud definition cards at
  higher levels (Unit 7).
- Per-story hand-authored Rive reward animation + celebration audio (Unit 8).
- Collection meta-layer (earned collectibles in a persistent scene) + progress
  map (Unit 9).
- Up to 4 local child profiles; minimal parent corner behind a parental gate,
  including per-child microphone/cloud-ASR consent (Unit 10).
- Content delivery: starter pack bundled in the binary, additional story packs
  downloaded from a CDN. No user accounts, no server-side user data (Unit 11).
- Anonymous, COPPA-safe analytics for the success metrics in §4 (Unit 12).
- Storybook-illustrated design system; fully responsive layouts, both
  orientations, phones and tablets (Unit 1).
- English (US) only.
- Completely free. No ads, no purchases, no monetization infrastructure.

### Non-scope (v1)

- Monetization of any kind (paywall, subscriptions, IAP, ads). Deliberately
  deferred until the product is validated.
- Parent progress dashboards / reports (parent corner is settings + consent
  only).
- User accounts, cloud sync of progress, multi-device continuity.
- Teacher/classroom features, assessments, or reports.
- Languages other than English (US).
- User-generated or AI-generated-at-runtime content. All content is authored,
  edited, and shipped through the pipeline in Unit 3.
- Handwriting, spelling, or letter-formation exercises.
- Social features of any kind.

## 4. Success criteria

v1 is a free validation release. It succeeds if, measured over the first 90
days after launch via the anonymous analytics in Unit 12:

1. **Retention:** ≥ 35% of new child profiles have at least one reading
   session 7 days after their first session (D7 profile retention).
2. **Real usage:** median completed stories per reading session ≥ 3.
3. **Learning signal:** for words a child needed help with, the help-rate on
   subsequent encounters of the same word declines — target ≥ 30% relative
   reduction by the third encounter, aggregated across profiles.
4. **Reliability of the core loop:** < 5% of reading sessions end with the
   child abandoning mid-story after a stuck-word event (proxy for "the ASR or
   scaffold frustrated the child").

These four metrics define the instrumentation contract for Unit 12.

## 5. Data & domain model

All models are local-first (device storage); no server holds user data.
Content models are authored in the pipeline (Unit 3) and shipped as versioned
story packs.

### Content models (authored, immutable once published)

- **PhonicsSkill** — `id`, `name` (e.g. "short a", "digraph sh"), `sequenceOrder`.
  The ordered list is the scope & sequence (Unit 2).
- **Level** — `id`, `ordinal`, `newSkills: [PhonicsSkill]`, `format`
  (`sentence` | `multiSentence` | `paragraph`), `vocabEnabled: bool`.
- **Story** — `id`, `levelId`, `title`, `pages: [Page]`, `riveAnimationRef`,
  `celebrationAudioRef`, `collectibleRef`, `skillsExercised: [PhonicsSkill]`,
  `packId`, `contentVersion`.
- **Page** — `sentences: [Sentence]`. Sentence-format stories have exactly one
  page with one sentence.
- **Sentence** — `words: [WordToken]`.
- **WordToken** — `text`, `graphemePhonemeMap: [(graphemes, phonemeId)]`
  (drives sound-out highlighting), `pronunciationAudioRef` (TTS-generated),
  `vocabCardId?` (present ⇒ rendered blue when `Level.vocabEnabled`).
- **VocabCard** — `id`, `word`, `definitionText` (kid-friendly, authored),
  `definitionAudioRef` (TTS), `illustrationRef?`.
- **Phoneme** — `id` (one of the 44 English phonemes), `humanAudioRef`
  (recorded voice actor, fixed set shipped in binary).
- **Collectible** — `id`, `storyId`, `riveRef`, `sceneSlot` (where it lives in
  the collection scene).
- **StoryPack** — `id`, `version`, `minAppVersion`, manifest of stories +
  assets, signed checksum.

### Device-local user models

- **Profile** — `localId`, `displayName`, `ageBand` (5–6 | 7–8 | 9–10),
  `currentLevelId`, `micConsent: bool`, `cloudAsrConsent: bool`,
  `createdAt`. Max 4 per device.
- **StoryProgress** — `profileId`, `storyId`, `status`
  (`locked` | `available` | `completed`), `completedAt?`, `timesRead`.
- **WordHelpRecord** — `profileId`, `wordText`, `encounterCount`,
  `helpCount`, `lastHelpLevel` (`none` | `soundOut` | `modeled`). Powers the
  learning-signal metric and adaptive review.
- **CollectionState** — `profileId`, `earnedCollectibles: [Collectible.id]`.

### Analytics events (anonymous — see Unit 12 for the privacy contract)

`session_start`, `story_started`, `word_read` (correct/helped),
`help_given` (tier), `story_completed`, `story_abandoned`,
`vocab_card_opened`, `collectible_earned`. Events carry a random per-install
ID and profile ordinal only — never names, audio, or device identifiers.

## 6. Constraints & dependencies

- **Platforms:** Flutter; iOS 16+ and Android 10 (API 29)+; phones and
  tablets; both orientations fully supported on every screen (ratified —
  the design tax is accepted).
- **Speech recognition:** primary = a cloud ASR service specialized for
  children's speech with word/phoneme-level confidence; fallback = on-device
  recognition (iOS Speech framework / Android SpeechRecognizer) used when
  offline, when cloud consent is not granted, or on service failure; final
  fallback = discreet tap-the-word advance so a child is never hard-blocked.
  Vendor selection is Open Question OQ-1.
- **COPPA / GDPR-K:** sending a child's voice to a cloud service requires
  verifiable parental consent. The parent corner must capture consent per
  child before any audio leaves the device; with consent absent or revoked
  the app silently uses on-device recognition only. Consent method is
  Open Question OQ-2. No ads, no third-party trackers, no behavioral
  profiling. App ships in the App Store Kids Category and Google Play
  Families program and must satisfy both policy sets.
- **Cost ceiling:** the app is free while cloud ASR bills per use. ASR spend
  must be capped (per-profile daily cap, then graceful fallback to on-device
  — see Unit 4). Budget threshold is Assumption A-7.
- **Art & audio pipeline:** one commissioned illustrator/animator working in
  Rive against a style guide (Unit 1); one voice actor for the fixed phoneme
  set + celebration lines; premium neural TTS for per-story word
  pronunciations and definition read-alouds (vendor = OQ-3).
- **Content:** ~30 stories at launch (~20 sentence/multi-sentence,
  ~10 paragraph), AI-drafted then human-edited — every published word is
  approved by a human editor. Decodability constraint: a story at level N may
  only use words decodable with skills introduced at levels ≤ N, plus that
  level's explicitly-tagged heart words (common irregular words taught as
  exceptions).
- **Offline:** the bundled starter pack (~8 stories) and all core loops work
  fully offline (on-device recognition mode). CDN packs require a connection
  to download, then work offline.

## 7. Risks & failure modes

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Child-speech ASR accuracy is insufficient even from a specialized vendor; words don't turn green when read correctly. | Core magic breaks; children frustrated. | Forgiving match policy (Unit 4 pins it); tiered fallback to sound-out help rather than "wrong!"; tap fallback; metric §4.4 watches this directly. Vendor bake-off before build (OQ-1) with recordings of real children. |
| R2 | Cloud ASR cost scales with free usage. | Product owner funds unbounded bill. | Hard per-profile daily cloud-ASR cap with silent downgrade to on-device (Unit 4); cap value A-7. |
| R3 | COPPA violation via voice data handling. | Legal exposure; app-store removal. | Consent gate before any cloud audio (Unit 10); on-device default; no audio retention (Unit 4 pins "no recording storage"); counsel review before launch (OQ-2). |
| R4 | Content pipeline too slow/expensive per story (illustration + Rive + editing + TTS). | Library stalls at launch size; retention decays. | Pipeline is a first-class unit (Unit 3) with per-story cost tracked from story #1; style guide constrains art scope; hybrid voice strategy avoids per-story recording sessions. |
| R5 | Decodable text authored with AI drifts off the phonics constraint. | Stories unteachable at their level. | Pipeline includes an automated decodability linter (Unit 3 acceptance) — every word checked against the level's cumulative grapheme set; human editor approves. |
| R6 | "Fully responsive both orientations" doubles design/QA effort and delays launch. | Schedule risk. | Accepted knowingly by product owner. Design system (Unit 1) defines layout rules once; Rive stages composed for a safe-area aspect range rather than per-orientation rebuilds. |
| R7 | Struggle detection (when to intervene) tuned wrong: too eager feels condescending, too slow feels absent. | Teaching interaction fails both age ends. | Timings are pinned as tunable constants (Unit 6) and adjusted in pilot; per-level timing profiles allowed. |
| R8 | App-store Kids Category review rejects the parental gate or analytics. | Launch blocked. | Gate + analytics designed to each store's published policy (Units 10, 12); pre-review checklist in Unit 13 acceptance. |

## 8. Units

Each unit lists its **pinned design** (ratified decisions — not builder
latitude) and **testable acceptance**. Units are ordered roughly
build-first-to-last; Units 1–4 are the critical path.

---

### Unit 1 — Design system & app shell

**Pinned design**
- Visual direction: **storybook illustrated** — warm, hand-illustrated,
  textured; soft palette; characters with personality; the UI feels drawn,
  not assembled from Material/Cupertino components. No stock component
  styling may be visible in child-facing screens.
- Typography: a purpose-built early-reader typeface for all reading text
  (unambiguous a/g forms, generous x-height); a friendly display face for
  titles. Reading text minimum sizes: 28pt (phone) / 36pt (tablet) at
  sentence levels; 20pt/24pt at paragraph levels.
- Word color states (single source of truth, used by Units 5–7):
  - Unread: near-black ink (not pure #000; warm ink tone from palette).
  - Current word: subtle underline/glow marker, ink color.
  - Read-correct: **green** (palette green, WCAG AA against background).
  - Vocabulary word (unread): **blue**, visually distinct from green at a
    glance for color-typical and protan/deutan viewers (blue chosen partly
    for this; verify with simulation).
  - Helped word: green with a small dot marker beneath (records "we helped
    here" without shaming — used by review logic, visible only subtly).
- Layout: every screen defines phone-portrait, phone-landscape,
  tablet-portrait, tablet-landscape. Reading screen: text region and
  animation stage; in landscape they sit side-by-side (book-like), in
  portrait stacked text-above-stage.
- All child-facing navigation is icon + voice prompt; no reading required to
  navigate. Child-facing screens: Home/progress map, Reading, Collection.
- App shell: Flutter, Riverpod for state (A-2), go_router navigation,
  Rive runtime. Product owner co-develops frontend; design tokens
  (colors, type scale, spacing, motion durations) live in one Dart file
  reviewed by the product owner before UI build starts.

**Acceptance**
- Golden tests render library, reading, and collection screens in all four
  layout classes without overflow or clipped Rive stages.
- Design-token file exists; no child-facing widget references a color/font
  outside it (lint rule enforced in CI).
- Color-vision simulation screenshots (protanopia, deuteranopia) show
  green-read vs blue-vocab distinguishable; attached to the design review.
- Product owner has signed off the style guide + tokens (recorded in repo).

---

### Unit 2 — Phonics engine (scope & sequence, levels, unlocking)

**Pinned design**
- A single ordered scope & sequence of PhonicsSkills, science-of-reading
  aligned, stored as data (not code): CVC short vowels → consonant digraphs →
  blends → long vowels/silent-e → vowel teams → r-controlled → multisyllable,
  with heart words introduced per level (exact table authored in Unit 3 and
  reviewed by the product owner; the *structure* is pinned here).
- One continuum, no named modes: `Level.format` moves
  sentence → multiSentence → paragraph; `Level.vocabEnabled` turns on blue
  vocabulary words at the first paragraph level.
- Profile start level from age band: 5–6 → level 1; 7–8 → first
  multiSentence level; 9–10 → first paragraph level. Parent can override in
  parent corner. (Placement test is v2 — Non-scope.)
- Unlock rule: completing any story at the profile's current level unlocks
  the next story; completing the level's story set advances
  `currentLevelId`. Earlier stories remain replayable forever.
- Engine exposes: `storiesFor(profile)`, `advance(profile, story)`,
  `isUnlocked(profile, story)` — pure functions over Profile + content data.

**Acceptance**
- Unit tests: age-band placement, sequential unlock, level advancement, and
  replayability of completed stories.
- Property test: no reachable state where a profile has zero available
  stories.
- Scope & sequence loads from data files; changing story order requires no
  code change (test swaps a fixture sequence).

---

### Unit 3 — Content pipeline & story packs

**Pinned design**
- Authoring flow per story: (1) AI-drafted text against the level's
  decodability constraint → (2) human edit & approval (every published word
  human-approved) → (3) automatic tagging: grapheme-phoneme mapping per word,
  vocab word selection + card authoring → (4) TTS generation for word
  pronunciations + definition audio → (5) Rive animation + collectible
  commissioned per the style guide → (6) pack build.
- **Decodability linter** (pinned as a build-time tool, not a runtime
  feature): rejects any story containing a word not decodable from the
  cumulative grapheme set at its level, unless whitelisted as a heart word
  for that level.
- Story pack format: versioned bundle (JSON manifest per §5 models + Rive +
  audio assets), checksummed. Starter pack (~8 stories spanning early
  levels) ships in the app binary; remaining launch content ships as CDN
  packs (Unit 11).
- Launch content: ~30 stories (~20 sentence/multiSentence, ~10 paragraph),
  each with animation, collectible, celebration audio; paragraph stories
  have 2–4 vocab cards each.
- Pipeline is CLI tooling in this repo (Dart or Python — builder's choice,
  recorded); not an app or CMS in v1.

**Acceptance**
- Linter test-suite: rejects a fixture story with an out-of-level word;
  accepts the same story once the word is whitelisted as a heart word or the
  level provides the grapheme.
- `pack build` produces a bundle the app loads end-to-end in an integration
  test (text renders, audio plays, Rive stage loads).
- Round-trip test: manifest schema validates all launch stories; a story
  failing schema validation fails the pack build with a per-field error.
- Per-story pipeline cost sheet (time + spend) exists after the first 5
  stories (process acceptance, tracked in repo docs).

---

### Unit 4 — Listening pipeline (ASR integration & word matching)

**Pinned design**
- Primary engine: specialized child-speech cloud ASR (vendor OQ-1) streaming
  with word-level (phoneme-level where available) confidence. Fallbacks in
  order: on-device recognition (offline / no cloud consent / service error /
  daily cap reached) → tap-the-word (child taps the current word to advance;
  always available but visually discreet).
- **No audio is ever stored** — not on device, not by us server-side; the
  cloud vendor must be configurable for no-retention processing (vendor
  requirement in OQ-1).
- Forgiving match policy (pinned): the tracker holds a cursor on the current
  word; a word is accepted (→ green) when ASR confidence for it exceeds an
  acceptance threshold **or** a near-miss threshold is met and the word is
  ≤ 4 phonemes; self-corrections and repeats are always accepted;
  recognition may accept the next word appearing before the current word is
  confirmed (lookahead 1) and back-fill the skipped word as correct.
  Thresholds are tunable constants with pinned defaults (accept 0.60,
  near-miss 0.40) calibrated during vendor bake-off.
- The tracker emits a single event stream consumed by Units 5–6:
  `wordAccepted(index)`, `struggleDetected(index)`, `silence(duration)`.
  Engine choice (cloud/on-device/tap) is invisible above this interface.
- Cloud usage cap: per-profile daily cloud-ASR minute cap (default A-7);
  when reached, silently switch to on-device for the rest of the day.
- Microphone lifecycle: mic active only on the reading screen; a small,
  non-alarming "listening" indicator (design system) is always visible while
  the mic is open.

**Acceptance**
- Contract tests against a recorded fixture set: child recordings (clear
  read, hesitant read, mispronunciation, silence, background noise) drive
  the tracker; expected event streams asserted. Fixture set built during
  vendor bake-off with real child audio recorded with parental permission.
- Fallback tests: airplane mode → on-device engine selected; consent revoked
  → cloud engine never instantiated (asserted via dependency injection);
  cap reached mid-session → engine swaps without UI interruption.
- Static/dynamic check: no code path writes audio buffers to storage.
- Tap fallback: tapping the current word emits `wordAccepted` identically to
  ASR acceptance.

---

### Unit 5 — Reading screen (text rendering & word state)

**Pinned design**
- Renders the story text per the design-system word states (Unit 1). One
  sentence (early levels) up to one paragraph (later levels) per page;
  multi-page stories page with a full-bleed page-turn transition.
- Word state machine per WordToken:
  `unread → current → (accepted | helped) → done(green)`; driven solely by
  Unit 4's event stream — the screen contains no recognition logic.
- Green transition is a per-word animated sweep (~250 ms, motion token from
  Unit 1), not an instant recolor; a subtle progress feel, no sound per
  word (sound is reserved for help and celebration to keep the child's own
  voice the primary audio).
- Blue vocab words are tappable at `vocabEnabled` levels **at any time**
  (before, during, after being read); tap pauses listening, opens the
  definition card (Unit 7), and on close restores the cursor exactly where
  it was.
- When the last word of the story turns green: listening stops and control
  hands to the celebration sequence (Unit 8) after a ~400 ms beat.
- The reading screen never displays "wrong", red coloring, error sounds, or
  any negative feedback. The only responses to imperfect reading are
  patience and help (Unit 6).

**Acceptance**
- Widget tests: fixture event streams produce the exact expected word-state
  sequence, including lookahead back-fill and helped-word markers.
- Golden tests for all four layout classes at sentence and paragraph levels.
- Vocab tap mid-listening: state restored to the same cursor position after
  card close (integration test).
- Grep-level check: no red/error asset or string is reachable from the
  reading screen.

---

### Unit 6 — Stuck-word scaffold (tiered help)

**Pinned design** (ratified verbatim from product owner)
- Trigger: `struggleDetected` or sustained silence on the current word for
  **T1 = 4 s** (tunable constant; per-level profiles allowed, e.g. longer at
  higher levels).
- **Tier 1 — sound it out:** the app sounds out the word's phonemes using the
  recorded human phoneme audio ("kuh… aah… tuh"), highlighting each
  grapheme cluster in the word as its phoneme plays (using
  `graphemePhonemeMap`). The child is then given **T2 = 4 s** to say the
  word.
- **Tier 2 — model it:** if the child still doesn't produce the word after
  T2, the app says the whole word (TTS pronunciation audio), gently prompts
  "your turn" (recorded line), and accepts the child's repeat — or, after
  one more T2 with no repeat, accepts the word and moves on (never
  hard-blocks).
- Any word that received Tier 1 or Tier 2 is marked `helped` (subtle dot,
  Unit 1) and recorded in WordHelpRecord with the tier reached.
- Phoneme audio is the recorded 44-phoneme human set (clean phonemes,
  minimal schwa tail — recording direction pinned in the audio brief,
  Unit 13). Sound-out order and grouping come from the story's authored
  `graphemePhonemeMap`, so digraphs highlight as one unit ("sh" lights
  together, never s-h separately).
- Timings T1/T2 and struggle sensitivity are constants in one tuning file;
  pilot adjustments touch only that file.

**Acceptance**
- Integration tests with fixture event streams: silence → Tier 1 at T1;
  continued silence → Tier 2 at T1+T2+phoneme duration; child speaks after
  Tier 1 → no Tier 2 and word accepted as helped.
- Grapheme highlighting matches `graphemePhonemeMap` exactly for fixture
  words including digraph and silent-e cases ("ship", "cake").
- WordHelpRecord rows written with correct tier; verified by §4.3 metric
  query in a test.
- No path exists where the child is blocked > (T1 + Tier1 + T2 + Tier2 + T2)
  without the story advancing.

---

### Unit 7 — Vocabulary definition cards

**Pinned design**
- Blue words open a **playful popover card** over the reading screen
  (storybook style, Unit 1): the word large at top, the authored
  kid-friendly definition beneath, optional small illustration.
- The definition auto-plays as audio (TTS, same voice as word
  pronunciations) on open; a replay button repeats it; the word itself is
  tappable to hear just the word.
- Card dismisses by tap-outside or a single clear close affordance; on
  close, reading resumes exactly where it paused (Unit 5 contract).
- Definitions are authored per story (usage-specific — "enormous" defined the
  way this story uses it), stored as VocabCards in the pack.
- Opening a card logs `vocab_card_opened`. No quiz/check in v1 (ratified:
  curated cards, no mini-check).

**Acceptance**
- Widget test: tap blue word → card opens, audio autoplay invoked, listening
  paused; close → listening resumed, cursor unchanged.
- Cards render within safe areas in all four layout classes (golden tests).
- A story with zero vocab words renders no blue styling; a
  `vocabEnabled=false` level renders vocab-tagged words in normal ink
  (unit tests).

---

### Unit 8 — Celebration: story animation & audio

**Pinned design**
- On story completion the animation stage plays the story's hand-authored
  Rive animation depicting **what the child just read** (caterpillar climbs
  the plant), synchronized with the celebration audio: a happy musical
  sting + one recorded celebration voice line (from a fixed recorded set,
  rotated randomly so it doesn't repeat verbatim every story).
- The stage is present during reading (showing the story's idle scene —
  same Rive artboard, idle state machine) so the payoff transforms the scene
  the child has been looking at, rather than cutting to a new screen.
- After the animation: the earned collectible flies to the collection icon
  (motion pinned in Unit 1 tokens), then the app returns to the map with the
  next story highlighted. Total post-completion sequence ≤ 10 s and
  skippable by tap after the first 2 s.
- Rive integration contract: every story artboard exposes the same state
  machine inputs (`idle`, `celebrate`, `collect`) — pinned as the animator's
  technical spec so app code never special-cases a story.

**Acceptance**
- Integration test with a fixture story: completion triggers `celebrate`
  input, celebration audio plays, collectible persisted to CollectionState,
  navigation returns to map.
- A story whose Rive file lacks the required inputs fails pack validation
  (Unit 3 linter), not runtime.
- Skip works after 2 s and still persists the collectible (test).
- Performance: stage holds 60 fps during celebration on the min-spec device
  (A-6); measured in profile mode, recorded in repo.

---

### Unit 9 — Collection & progress map

**Pinned design**
- **Progress map** (child home screen): the level path drawn as an
  illustrated trail; completed stories shown by their thumbnail, current
  story highlighted with a gentle idle animation, future stories visible
  but visually "asleep". Tapping any completed story allows re-reading.
- **Collection scene**: one persistent illustrated scene (e.g. a garden)
  where every earned collectible lives, placed by its authored `sceneSlot`;
  collectibles are individually tappable for a small reaction animation
  (Rive `collect`/poke state). The scene fills as the child progresses —
  this is the child's owned space.
- Both screens are per-profile. No global/comparative elements (no
  leaderboards, no cross-profile visibility).
- Scene capacity covers all launch collectibles; the scene design must
  define how it extends for future packs (scrollable/expanding — direction
  pinned with the illustrator in the style guide, recorded in Unit 1).

**Acceptance**
- Map reflects StoryProgress exactly for fixture profiles (locked /
  available / completed states) — widget tests.
- Completing a story adds exactly one collectible at its authored slot;
  re-reading adds none (tests).
- Profile switch swaps map + collection state completely (integration test).
- Golden tests, four layout classes, for both screens.

---

### Unit 10 — Profiles & parent corner

**Pinned design**
- Up to 4 local profiles; child-facing profile picker at launch (icon/avatar
  based, no reading required).
- **Parental gate** guards the parent corner: hold-to-enter plus a spoken/
  written age-appropriate challenge that satisfies both Apple Kids Category
  and Google Families requirements (exact mechanism A-4; must be one of the
  store-accepted patterns).
- Parent corner contents (all of it — nothing more in v1):
  - Create/edit/delete profiles: name, age band (sets starting level per
    Unit 2), optional level override.
  - Per-child consent toggles: microphone use; cloud speech processing
    (explains in plain language what is sent, that nothing is stored, and
    names the vendor). Cloud toggle disabled until mic granted. Defaults:
    both **off** until explicitly enabled.
  - Links: privacy policy, licenses, contact.
- Consent state changes take effect immediately (Unit 4 reads them per
  session start and on change).
- Deleting a profile erases all its local data (progress, help records,
  collection) — irreversibly, with a plain confirmation.

**Acceptance**
- Gate blocks child-plausible interaction patterns (automated test taps/
  random input never passes the gate).
- Consent matrix tests: (mic off) → tap-only mode, mic never requested;
  (mic on, cloud off) → on-device only; (both on) → cloud engine allowed.
  OS-level mic permission denial handled gracefully → tap mode.
- Profile CRUD + data erasure verified (deleted profile leaves zero rows).
- Store-policy checklist for both stores completed and recorded in repo
  (process acceptance).

---

### Unit 11 — Content delivery (CDN packs)

**Pinned design**
- Story packs hosted as static, versioned, checksummed bundles on a CDN
  (no dynamic backend, no user data flows upward — download-only).
- App checks a static `catalog.json` on launch (when online), downloads new
  packs in the background on Wi-Fi by default, verifies checksum before
  install; a failed/partial download never corrupts installed content
  (atomic install: verify → swap).
- Starter pack always present from the binary; the app is fully functional
  having never seen the network.
- Pack/catalog versioning respects `minAppVersion` — a pack requiring a
  newer app is hidden, never downloaded-and-broken.

**Acceptance**
- Corrupt/truncated pack fixture → rejected, installed content untouched.
- Catalog with a too-new `minAppVersion` pack → pack not offered.
- Fresh install in airplane mode: full starter-pack experience end-to-end
  (integration test).
- Download resumes/retries across app restarts (test with simulated
  interruption).

---

### Unit 12 — Anonymous analytics

**Pinned design**
- Events exactly as listed in §5; payloads carry: event name, timestamp,
  random per-install UUID, profile ordinal (1–4), level ordinal, story id,
  and event-specific fields (help tier, word *hash* — never raw child-typed
  or spoken data; word text is hashed because the word list is content, but
  hashing keeps payloads inert).
- Never collected: names, age beyond age band, audio, transcripts, device
  identifiers (IDFA/AAID), location, or any third-party tracker SDK.
- Transport: batched HTTPS to a self-controlled endpoint or a
  privacy-first service configured anonymous (vendor/self-host = A-5);
  queued offline, dropped (not persisted forever) after 30 days unsent.
- A single build flag disables all analytics (for review builds and as a
  kill switch).
- The four §4 metrics each have a defined query over these events, written
  down with the schema (metrics are part of this unit's deliverable, not an
  afterthought).

**Acceptance**
- Schema tests: every emitted event validates; any PII-shaped field (name
  string, raw word text, identifier) fails schema in CI.
- Airplane-mode queue/flush behavior verified; 30-day drop verified with
  clock manipulation.
- Kill-switch build emits zero network calls to the analytics endpoint
  (network-recording test).
- The four §4 metric queries run against fixture event data and return
  correct values (tests are the executable definition of success criteria).

---

### Unit 13 — Audio system & voice pipeline

**Pinned design**
- Hybrid voice strategy (ratified): **recorded human voice actor** for the
  fixed sets — 44 phonemes (clean articulation, minimal schwa; recording
  brief is part of this unit), celebration lines (~10), and the handful of
  fixed prompts ("your turn"); **premium neural TTS** (vendor OQ-3) for
  per-story word pronunciations and vocab definition read-alouds, generated
  at pack-build time (Unit 3) — never at runtime.
- One consistent app voice: the TTS voice is selected to blend with the
  actor's warmth (both auditioned together, product owner approves — the
  same approval gate as the style guide).
- Playback engine: low-latency (phoneme sound-out must feel instant),
  gapless sequential phoneme playback, ducking rules (help audio ducks
  ambient/celebration audio; nothing ducks the microphone processing).
- All audio assets normalized to a loudness target (pinned: -16 LUFS
  integrated) in the pipeline.

**Acceptance**
- Phoneme sequence playback latency < 150 ms from trigger on min-spec
  device (measured, recorded).
- All shipped audio passes the loudness check in pack build (Unit 3 linter
  extension).
- TTS assets exist for every WordToken and VocabCard in every launch story
  (pack validation).
- Product owner sign-off on the recorded phoneme set and TTS voice pairing
  (recorded in repo).

---

## 9. Assumptions (proceeding on these; override any of them)

- **A-1:** English (US) only; single narrator voice gender/character chosen
  at audition, product owner decides.
- **A-2:** State management Riverpod, navigation go_router, local storage
  Drift (SQLite) — conventional Flutter choices; swap is cheap before build,
  expensive after.
- **A-3:** Working title "LearnToRead"; real name + app-store identity
  decided before store submission (not blocking build).
- **A-4:** Parental gate mechanism: hold-two-corners-for-3-seconds plus a
  written multiplication challenge — accepted pattern in both stores; final
  mechanism checked against current store policy at Unit 10 build time.
- **A-5:** Analytics via self-hosted endpoint (simplest COPPA posture);
  a privacy-first hosted service may substitute if it supports fully
  anonymous mode.
- **A-6:** Min-spec performance devices: iPhone SE 2nd gen; a 2019-era
  budget Android tablet (concrete model picked at Unit 1 build).
- **A-7:** Cloud-ASR daily cap default: 20 minutes per profile per day;
  revisit once vendor pricing is known (OQ-1).
- **A-8:** Story length bounds: sentence levels 3–8 words; paragraph levels
  40–90 words across 1–3 pages.
- **A-9:** The ~8-story starter pack spans the first 3 levels so every age
  band's starting level has bundled content offline on first run.

## 10. Open questions (block their units, not the whole build)

- **OQ-1 (blocks Unit 4 vendor integration; interface work can proceed):**
  Which child-speech ASR vendor? Requirements: word/phoneme-level streaming
  confidence, children's-voice training, contractual no-retention
  processing, COPPA-compatible DPA, workable per-minute price for a free
  app. Action: bake-off with real child recordings before Unit 4's vendor
  adapter is built. (Candidates to evaluate at that time; the market moves —
  e.g. SoapBox-class child ASR, Azure Pronunciation Assessment.)
- **OQ-2 (blocks launch, not build):** COPPA verifiable-parental-consent
  method for cloud voice processing in a free app with no accounts —
  needs counsel confirmation that the chosen in-app consent flow meets the
  "verifiable" bar, or we add a lightweight verification step (e.g.
  email-plus) to Unit 10.
- **OQ-3 (blocks Unit 13/3 asset generation):** TTS vendor whose voice
  blends with the chosen actor; auditioned together, product-owner
  approval.
- **OQ-4 (blocks Unit 3 art commissions):** Illustrator/animator sourcing
  and budget per story; style guide contract deliverable defined in Unit 1.
- **OQ-5 (content):** Final scope & sequence table (which skills at which
  level, heart-word lists) — authored in Unit 3, reviewed by product owner
  before story writing begins.

---

## Self-check against the review rubric

- Why / Users & stakes / Scope & non-scope / Success criteria / Data model /
  Constraints / Risks / Units: present.
- Every unit has pinned design + testable acceptance; no unit leaves a
  design decision to the builder — remaining unknowns are explicitly OQ-1..5
  and block only their own units.
- Criteria satisfied by assumption rather than decision are listed in §9,
  each individually overridable.
- Known-weakest points, flagged honestly: OQ-1 (ASR vendor viability at
  free-app economics) and OQ-2 (consent method) are the two existential
  unknowns; both have pre-build actions attached.
