# Open decisions — for the product owner

Questions the PRD does not pin, discovered while ticketing. Builders must NOT
invent answers; tickets that touch these use clearly-marked placeholders and
are flagged in their `notes`. The orchestrator takes these to the product
owner (Adam).

| # | Unit(s) | Question |
|---|---------|----------|
| OD-1 | word-matcher, twister-flow, domain-models | Sound-mode (tongue-twister) threshold DEFAULT VALUES. Unit 14 pins "a separate, looser set in the tuning file" but no numbers. Proposal needed (e.g. word-mode thresholds +1 substitution allowance, plus minimum weighted hit-rate on the drilled phoneme). Placeholders shipped in `lib/domain/tuning.dart`, marked. |
| OD-2 | listening-tracker | What, beyond sustained silence, emits `struggleDetected`? Unit 6 triggers on "struggleDetected OR sustained silence for T1" but the PRD never defines the non-silence struggle condition ("struggle sensitivity" is named as a tuning constant without semantics). Proposal: N consecutive rejected (not-close-enough) hypotheses on the current word, N tunable. Needs ratification. |
| OD-3 | design-tokens (Unit 1) | Concrete token VALUES (palette hexes, exact faces) and the two typefaces: the purpose-built early-reader reading face and the friendly display face are owner-supplied/licensed assets that do not exist in the repo. Tokens ship with placeholder values behind indirection; Unit 1 acceptance requires owner review of the token file before UI build — schedule it. |
| OD-4 | design-tokens, celebration-sequence | Min-spec Android tablet concrete model (A-6 says "picked at Unit 1 build"). Needed for the [DEVICE] 60fps and latency measurements. |
| OD-5 | analytics | (a) Analytics endpoint: self-hosted URL/deployment or which privacy-first vendor in anonymous mode (A-5)? Needed before any device build emits events. (b) Word-hash algorithm for `word_read` payloads — PRD pins "word hash" but not the function; proposal: SHA-256 of the lowercased word (crypto pkg already pinned). |
| OD-6 | content-delivery, pack-build-cli | (a) CDN base URL / catalog.json hosting (owner infrastructure). (b) §5 says "signed checksum" while Unit 11 says "checksummed": is a cryptographic signature (key management, signing step in CI) required for v1, or is SHA-256 integrity checking sufficient for the POC? Tickets implement SHA-256 verify; signing is unbuilt pending answer. |
| OD-7 | pack-build-cli | Rive input validation needs at least one real `.riv` fixture exposing `idle`/`celebrate`/`collect` (and one lacking them) to test end-to-end — must come from the owner/animator (OQ-4). Until then validation is tested behind a fake introspector. Also confirm: if the rive runtime cannot enumerate state-machine inputs headlessly, is a declared-inputs sidecar in the manifest acceptable as the build-time check? |
| OD-8 | audio-playback | Which audio playback plugin to add to pubspec (none is pinned; the pinned dependency list has no audio player). Orchestrator must add centrally; proposal: `just_audio` (gapless/low-latency oriented) — owner/orchestrator confirm. |
| OD-9 | profiles-parent-corner | Privacy policy, contact, and licenses link destinations (owner-supplied URLs/text). Placeholders shipped. |
| OD-10 | phonics-engine, pack-build-cli | PRD's own OQ-4 (illustrator/animator sourcing + budget) and OQ-5 (final scope-&-sequence table + heart-word lists) are owner items that gate REAL content; all tickets run on fixtures until delivered. |

## Owner-run items (not decisions, but external blockers)

- **Unit 0 spike verdict** (blocks `platform-asr-adapter`): owner runs
  `spike-asr-app` on a physical device with >= 3 real children and writes the
  in-repo verdict (go/no-go on A-10; phone-level detail availability).
- **[DEVICE] acceptance items** across tickets: goldens (4 layout classes),
  color-vision simulation screenshots, 60 fps celebration on min-spec,
  phoneme playback latency < 150 ms, native ASR behavior, phoneme-set and
  style-guide/token sign-offs.
