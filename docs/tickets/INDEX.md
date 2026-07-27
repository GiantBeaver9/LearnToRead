# Ticket index — LearnToRead build loop

Decomposition of PRD.md §8 Units 0–15 into 25 leaf-first tickets. PRD units
were split (never merged) where they contained independently buildable
halves. Every ticket is headlessly buildable/testable with `flutter test` in
this container via the fakes it specifies; `[DEVICE]` acceptance items are
owner-routed. File ownership is pairwise disjoint; `lib/main.dart` + router
belong to `app-shell` only; `pubspec.yaml` is owned by no ticket (new deps go
through the orchestrator — see notes below).

Remaining owner-supplied items live in
[OPEN-DECISIONS.md](OPEN-DECISIONS.md) — the former OD-1/2/5b/6b/7/8 are now
resolved by PRD A-12..A-17 and transcribed into tickets.

## Dependency order

Waves are topological: everything in a wave depends only on earlier waves.

### Wave 0 — foundations (no deps)

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [domain-models](domain-models.json) | §5 (incl. GraphemeSound), tuning file (A-12/A-13) | standard | — |
| [design-tokens](design-tokens.json) | Unit 1 (tokens/layout/Rive contract) | standard | — |
| [spike-asr-app](spike-asr-app.json) | Unit 0 (owner-coordinated) | standard | — |

### Wave 1 — leaf logic & services

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [listening-contracts](listening-contracts.json) | Unit 4 (interface + fakes) | simple | domain-models |
| [phonics-engine](phonics-engine.json) | Unit 2 | standard | domain-models |
| [local-storage](local-storage.json) | §5 user models (Drift) | standard | domain-models |
| [decodability-linter](decodability-linter.json) | Unit 3 (linter half) | standard | domain-models |
| [audio-playback](audio-playback.json) | Unit 13 (app half; A-17) | standard | domain-models |
| [analytics](analytics.json) | Unit 12 (+ sound_card events; A-14) | hard | domain-models |
| [parental-gate](parental-gate.json) | Unit 10 (gate half) | simple | design-tokens |

### Wave 2 — core engines & pipeline

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [word-matcher](word-matcher.json) | Unit 4 (matching core; sound mode per A-13) | **intensive** | domain-models, listening-contracts |
| [word-state-machine](word-state-machine.json) | Unit 5 (logic half) | standard | domain-models, listening-contracts |
| [pack-build-cli](pack-build-cli.json) | Unit 3 (CLI, Dart; A-15/A-16; U15 content validation) | hard | domain-models, decodability-linter |
| [platform-asr-adapter](platform-asr-adapter.json) | Unit 4 (engine; **blocked on spike verdict**) | standard | listening-contracts, spike-asr-app |

### Wave 3 — orchestration & screens

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [listening-tracker](listening-tracker.json) | Unit 4 (tracker/fallback/cap; struggle per A-12) | hard | domain-models, listening-contracts, word-matcher |
| [stuck-word-scaffold](stuck-word-scaffold.json) | Unit 6 | hard | domain-models, listening-contracts, audio-playback, local-storage |
| [reading-screen](reading-screen.json) | Unit 5 (UI half) | hard | design-tokens, domain-models, listening-contracts, word-state-machine, audio-playback, analytics |
| [progress-map-collection](progress-map-collection.json) | Unit 9 | standard | design-tokens, domain-models, local-storage, phonics-engine |
| [profiles-parent-corner](profiles-parent-corner.json) | Unit 10 | hard | design-tokens, domain-models, local-storage, phonics-engine, parental-gate |
| [celebration-sequence](celebration-sequence.json) | Unit 8 | standard | design-tokens, domain-models, audio-playback, local-storage, analytics |
| [content-delivery](content-delivery.json) | Unit 11 (+ U15 inventory/extension loading; A-15) | hard | domain-models, pack-build-cli |
| [sound-garden](sound-garden.json) | Unit 15 | standard | design-tokens, domain-models, phonics-engine, listening-contracts, word-matcher, audio-playback, analytics |

### Wave 4 — composite features

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [vocab-cards](vocab-cards.json) | Unit 7 | standard | design-tokens, domain-models, audio-playback, analytics, reading-screen |
| [twister-flow](twister-flow.json) | Unit 14 (thresholds per A-13) | hard | design-tokens, domain-models, listening-contracts, word-matcher, word-state-machine, audio-playback, local-storage, analytics |

### Wave 5 — integration

| Ticket | PRD | Tier | Deps |
|---|---|---|---|
| [app-shell](app-shell.json) | Unit 1 (shell; four child destinations) + wiring | standard | design-tokens, reading-screen, progress-map-collection, profiles-parent-corner, vocab-cards, celebration-sequence, twister-flow, sound-garden, content-delivery, analytics, listening-tracker, stuck-word-scaffold |

## Orchestrator notes

- **pubspec (central):** add `just_audio` + `audio_session` per A-17;
  optionally `fake_async`/`clock` as explicit dev_dependencies
  (timing-heavy tickets use them; they ship transitively with flutter_test).
  No ticket edits pubspec.yaml.
- **External blockers:** `platform-asr-adapter` blocks on the owner-run
  Unit 0 spike verdict. Real content/assets (fonts, .riv + A-16 sidecars,
  recordings, scope-&-sequence table, Sound Garden grapheme inventory +
  example words) are owner deliverables (OQ-4/5/8); all tickets run on
  generated fixtures until then. Hosting (OQ-6) and parent-corner URLs
  (OQ-7) block pilot distribution only.
- **PRD-unit → ticket map:** U0→spike-asr-app; U1→design-tokens+app-shell;
  U2→phonics-engine; U3→decodability-linter+pack-build-cli;
  U4→listening-contracts+word-matcher+listening-tracker+platform-asr-adapter;
  U5→word-state-machine+reading-screen; U6→stuck-word-scaffold;
  U7→vocab-cards; U8→celebration-sequence; U9→progress-map-collection;
  U10→parental-gate+profiles-parent-corner; U11→content-delivery;
  U12→analytics; U13→audio-playback (+loudness check in pack-build-cli);
  U14→twister-flow (+pack validation in pack-build-cli);
  U15→sound-garden (+inventory/example-word validation in pack-build-cli,
  loading/merge in content-delivery, GraphemeSound model in domain-models,
  route in app-shell). §5 models → domain-models + local-storage.
