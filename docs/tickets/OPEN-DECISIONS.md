# Open decisions — for the product owner

Status after the PRD amendment adding Unit 15 (Sound Garden) and pinned
defaults A-12..A-17: most of the original open decisions are RESOLVED by the
PRD and transcribed into the tickets. What remains is owner-supplied
material that blocks pilot distribution or content authoring — none of it
blocks unit builds (fixtures/placeholders are specified per ticket).

## Resolved (transcribed into tickets — no longer open)

| # | Was | Resolved by |
|---|-----|-------------|
| ~~OD-1~~ | Sound-mode (twister/Sound Garden) threshold defaults | **A-13**: accept when ≥ 60% of the target phoneme sequence matched with per-phoneme distance ≤ 1, target-phoneme instances weighted double; tunable. → word-matcher, twister-flow, sound-garden, domain-models tuning file. |
| ~~OD-2~~ | `struggleDetected` semantics beyond silence | **A-12**: two consecutive finalized hypothesis bursts with speech failing to match the current word, or sustained silence ≥ T1; tunable. → listening-tracker, domain-models tuning file. |
| ~~OD-5b~~ | Analytics word-hash algorithm | **A-14**: SHA-256 of lowercased word text, truncated to 16 hex chars. → analytics. |
| ~~OD-6b~~ | "Signed checksum" vs plain checksum | **A-15**: SHA-256 checksum listed in the catalog satisfies §5 in v1; cryptographic signing is post-POC hardening. → pack-build-cli, content-delivery. |
| ~~OD-7~~ | Rive input validation without headless `.riv` introspection | **A-16**: declared-inputs sidecar JSON committed alongside each `.riv` is authoritative; runtime introspection supplementary. Fully headless-testable. → pack-build-cli. |
| ~~OD-8~~ | Audio playback plugin choice | **A-17**: `just_audio` + `audio_session`, added centrally to pubspec by the orchestrator. → audio-playback. |

## Remaining — owner-supplied, NOT build-blocking

| # | Unit(s) | Item | PRD home |
|---|---------|------|----------|
| OD-3 | design-tokens | Final typeface selections (early-reader reading face, display face) and concrete design-token values; owner token-review gate before UI build sign-off. Builders use placeholder tokens behind the pinned token interface. | **OQ-8** (blocks the owner review gate, not unit builds) |
| OD-4 | design-tokens, celebration-sequence, audio-playback | Min-spec Android tablet concrete model (A-6, "picked at Unit 1 build") — needed for [DEVICE] 60fps/latency measurements. | §9 A-6 |
| OD-5a / OD-6a | analytics, content-delivery | Hosting choices: anonymous-analytics endpoint (A-5) and pack CDN/catalog host. Units build/test against fakes and local fixture servers. | **OQ-6** (blocks pilot distribution, not build) |
| OD-9 | profiles-parent-corner | Privacy policy, contact, licenses URLs; placeholders until supplied. | **OQ-7** (blocks pilot distribution, not build) |
| OD-10 | phonics-engine, pack-build-cli, sound-garden | PRD OQ-4 (illustrator/animator sourcing + budget) and OQ-5 (final scope-&-sequence table, heart-word lists, **grapheme inventory + example words for the Sound Garden**) gate REAL content; all tickets run on fixtures until delivered. | §10 OQ-4 / OQ-5 |

## Owner-run items (external blockers, not decisions)

- **Unit 0 spike verdict** (blocks `platform-asr-adapter`): owner runs
  `spike-asr-app` on a physical device with >= 3 real children and writes the
  in-repo verdict (go/no-go on A-10; phone-level detail availability —
  the latter now also matters to Sound Garden echo, Unit 15).
- **[DEVICE] acceptance items** across tickets: goldens (4 layout classes,
  now incl. Sound Garden), color-vision simulation screenshots, 60 fps
  celebration on min-spec, phoneme playback latency < 150 ms, native ASR
  behavior, phoneme-set and style-guide/token sign-offs.
