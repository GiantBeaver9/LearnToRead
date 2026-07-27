# Profiles & Parent Corner — Unit 10

**Unit:** 10 (Profile picker, parent corner, pilot progress, consent, erasure)
**References:** PRD §8 Unit 10, §5 Profile / WordHelpRecord, §8 Unit 2 (placement), §8 Unit 4 (consent gating), §6 POC posture, §9 A-4 / A-10, §10 OQ-4 / OQ-7
**Ticket:** `docs/tickets/profiles-parent-corner.json`

**Implementation**

| File | Role |
| --- | --- |
| `lib/features/profiles/profile_picker_screen.dart` | Child-facing launch picker |
| `lib/features/profiles/profile_avatar.dart` | Deterministic icon-first identity mark |
| `lib/features/parent/parent_corner_screen.dart` | Gated corner + the four inline sections |
| `lib/features/parent/profile_editor.dart` | Profile create / edit / delete |
| `lib/features/parent/pilot_progress_view.dart` | Per-child plain progress screen |
| `lib/features/parent/consent_controller.dart` | Mic + cloud consent, reading-mode resolution |
| `lib/features/parent/parent_links.dart` | Privacy policy / licenses / contact |

The parental gate itself (`parental_gate.dart`, `gate_challenge.dart`) is the
`parental-gate` unit's work and is reused unchanged.

---

## 1. The child-facing picker

`ProfilePickerScreen` renders one tile per profile, in the order given. Two
properties are load-bearing:

* **Nothing about selection requires reading.** Identification is by icon:
  `ProfileAvatar` maps `Profile.localId` through a fixed palette of concrete
  silhouettes (pets, rocket, flower, star, …). The mapping is deterministic by
  construction — a small explicit hash rather than Dart's `String.hashCode`,
  which is not guaranteed stable across runs. A child who learns "I'm the
  rocket" must find the rocket every launch, on every device.
* **The tile reports an ordinal, not just an identity.**
  `onProfileSelected(profile, profileOrdinal)` passes the **1-based** position
  within the list — exactly the `profileOrdinal` input `SessionTracker`'s
  `startSession` needs (PRD §5 "profile ordinal (1–4)"). Selecting a profile is
  what enters that child's map and starts their session; the picker owns
  neither, it only reports.

`onVoicePrompt` is an optional hook fired **before** `onProfileSelected`, so a
recorded name plays as the screen changes rather than after it. The audio refs
themselves are owner-recorded content (PRD notes), hence a nullable hook rather
than an audio-system dependency.

The `kMaxProfilesPerDevice` cap of 4 is enforced upstream in `ProfilesDao`, not
here; the picker renders whatever list it is handed.

## 2. Reaching the parent corner

`ParentCornerScreen` *is* the gate. It renders the real `ParentalGate` (hold two
opposite corners for 3 s, then solve a multiplication challenge — PRD §9 A-4)
and swaps in the corner contents only on unlock.

There is deliberately **no bypass**: no "already unlocked" constructor flag, no
debug seam, no persisted unlock. The unlock bit lives in the `State` object, so
dismounting and remounting the screen — leaving and re-navigating to the corner
— starts back at the gate. Re-entry requires re-passing, which is the entire
point: a corner that stays open is a corner a child walks into.

## 3. Corner scope: four sections, and that is the whole list

`ParentCornerContents` composes exactly four sections and nothing else:

| Key | Contents |
| --- | --- |
| `parent-corner-section-profiles` | `ProfileEditor` |
| `parent-corner-section-progress` | one `PilotProgressView` per child |
| `parent-corner-section-consent` | one `ConsentController` per child |
| `parent-corner-section-links` | `ParentLinks` |

That is PRD §8 Unit 10's list in full ("all of it — nothing more in v1"), and
the shape enforces it. All four are **inline on one screen**: there is no
drawer, tab bar, nav rail, or nested route. Adding a fifth destination would
mean adding a fifth visible region rather than quietly adding a menu entry, and
the section-key set is asserted exhaustively in the frozen suite.

Sections are laid out as four equal vertical regions, each scrolling within its
own bounds, so the corner fits every layout class without any section being
able to push another off-screen.

### Reads are futures, not query streams

The corner loads its profile list and per-child rows with plain `Future`s and
reloads after every mutation, rather than subscribing to Drift query streams.
A live stream would give the same freshness, but its subscription teardown
schedules work that outlives the widget tree — dangling background work a
parent screen should not leave behind (and which surfaces immediately as a
pending-timer failure under `flutter_test`).

Freshness is preserved instead by `_NotifyingProfilesDao`, a `ProfilesDao`
subclass that reports every **successful** mutation back to the corner. Both
`ProfileEditor` and `ConsentController` mutate through their injected DAO, so
the notification is taken at the one place every mutation must pass through —
no pinned widget API had to grow a "something changed" callback. A failed
mutation (the 5th-profile cap) throws before the hook runs, so nothing reloads
when nothing changed.

## 4. Profile CRUD

### Age band places the level; editing never re-places it

Creation calls `placeStartingLevel` (PRD §8 Unit 2):

| Age band | Starting level |
| --- | --- |
| 5–6 | lowest-ordinal level ("level 1") |
| 7–8 | first `multiSentence`-format level |
| 9–10 | first `paragraph`-format level |

An optional **level override** is passed verbatim as
`parentOverrideLevelId` and wins outright over the band. An override naming no
real level is reported in the form rather than silently ignored.

Editing a profile changes **name and band only**. It does not re-place the
level, and it preserves `currentLevelId`, `micConsent`, `cloudAsrConsent`,
`localId`, and `createdAt` exactly. Placement is a *starting* decision: once a
child has read at a level, correcting a typo in their birthday must not move
them. A parent who wants to move them has the override on create, and the level
the child is actually on afterwards.

### The 5th-profile cap is surfaced, not prevented

The add button stays enabled; `MaxProfilesExceededException` from the DAO is
caught and rendered as `profile-cap-error` ("This device already has 4
profiles. Delete one to make room."). A silently disabled button teaches the
parent nothing. The cap lives in exactly one place — storage — so the UI cannot
drift from it, and freeing a slot by deleting a profile immediately allows a
create again.

### Deletion: two steps, and the first one is inert

Tapping the delete icon opens a confirmation dialog and **touches nothing**.
Only confirming calls `profilesDao.deleteProfile`, which erases the profile and
every row it owns — story progress, word-help records, twister progress,
collection — in a single transaction. Erasure is irreversible and total for
that child, and strictly scoped: a sibling profile's rows are untouched.

The dialog is not barrier-dismissible: a stray tap outside it is a no-op rather
than an ambiguous dismissal of an irreversible decision. Repeated taps on the
delete icon are not a bypass — they can only ever re-open the confirmation.

## 5. Pilot progress view

One plain screen per child: the stories they finished, and the words that
needed help with the tier of help given.

| `HelpLevel` | Label |
| --- | --- |
| `soundOut` | `Sound-out help` |
| `modeled` | `Modeled help` |

The view filters its own inputs — `StoryStatus.completed` for stories,
`helpCount > 0` for words — so callers can hand it raw DAO output. A word that
was merely *encountered* never needed help and is recognised and excluded, not
crashed on.

**No charts, no trends, anywhere.** This is a product decision, not an
omission. The screen exists so a pilot parent can say something concrete —
"she finished three stories and got stuck on 'elephant'". A trend line would
invite comparison and gamified reading of a two-week pilot's noise, which
PRD §8 Unit 9 rules out ("no global/comparative elements").

## 6. Consent

### The controls

* **Microphone toggle, per child, default OFF.** Off by construction:
  `micConsent` is a non-nullable field a profile is created with as `false`, so
  there is no "unset" state that could be read optimistically.
* **Cloud-processing toggle, only when a cloud engine is in use.** With the POC
  default of on-device recognition (PRD §9 A-10) the toggle is not rendered at
  all. An absent control cannot mislead a parent into thinking audio might
  leave the device.

Every toggle writes through to storage on the spot. There is no Save button,
because a consent screen with unsaved state can leave a parent believing they
turned the microphone off when they did not.

`onConsentChanged` fires with the changed profile — the "tracker hook re-read
on change" seam (PRD §8 Unit 10 / Unit 4). It fires as the write is issued
rather than after the write's future resolves: storage is a local SQLite file
whose statements are serialised in call order, so the next read cannot observe
a stale value, whereas deferring the notification would leave a live reading
session running under withdrawn consent for as long as the disk took to answer.
**Consent withdrawal must win the race.**

### The reading-mode matrix

`resolveReadingMode` is a pure combinator over a resolved permission status:

| `micConsent` | Permission | Cloud engine | Cloud consent | Result |
| --- | --- | --- | --- | --- |
| off | any | any | any | `tapOnly` |
| on | `denied` | any | any | `tapOnly` |
| on | `notDetermined` | any | any | `tapOnly` |
| on | `granted` | no | — | `deviceRecognition` |
| on | `granted` | yes | no | `deviceRecognition` |
| on | `granted` | yes | yes | `cloudRecognition` |

Two properties worth naming. A denial (or a not-yet-determined answer) is a
**graceful fallback, never an error**: tap-only is a complete way to read the
app, not a degraded one. And a cloud engine without cloud consent falls back to
on-device recognition — it never silently uploads audio.

`resolveReadingModeWithPermissionCheck` is the flow a reading-screen entry (or
a session start) runs. It calls `MicPermissionService.requestPermission()`
**only** when `micConsent` is true, so with consent off the OS is never asked
and the child never sees a microphone prompt they were not opted into. That is
the concrete form of "the mic is never requested".

### Why this seam lives here

This unit does not depend on the listening-pipeline unit, so
`MicPermissionService`, `MicPermissionStatus`, `ReadingMode`, and the two
resolvers are defined and owned in `consent_controller.dart`. The listening
pipeline consumes them rather than inventing its own: there must be exactly one
answer to "may we open the microphone?".

`FakeMicPermissionService` records `wasRequested`. The only way to hold a
promise about a call *not* happening is to observe the call site.

### POC posture

This is a plain-language in-app toggle and nothing more. **Verifiable parental
consent (COPPA) is an explicit post-POC ship gate** (PRD §6), recorded here and
deliberately not built. The parental gate in front of the corner is what keeps
a child from flipping their own microphone on.

## 7. Links

`ParentLinks` renders three rows — privacy policy, licenses, contact — and
reports taps through `onLinkTap(kind, url)`. It does not open anything itself:
launching is left to the host app, which keeps the unit headlessly testable (no
`url_launcher` platform channel) and keeps the placeholder URLs from ever being
navigated to by accident.

**OQ-7 status: destinations are owner-supplied and are not known at build
time.** `kParentLinkPlaceholderUrls` holds obviously-fake targets under the
reserved `.invalid` TLD, so a placeholder that escapes into a build is inert
and obvious rather than silently pointing somewhere wrong. The UI carries a
visible "Link destinations are placeholders until supplied" note. Supplying the
real URLs is a one-map edit; it blocks **pilot distribution**, not the build.

## 8. Styling

Every colour, font, and spacing value in these files flows through
`DesignTokens` (PRD §8 Unit 1 token-lint rule: no `Color(0x…)`, no `Colors.*`,
no inline `TextStyle(fontFamily: '…')` under `lib/features/`). Token *values*
remain owner-unsigned-off placeholders (OQ-8); the token interface is what
these widgets bind to.

Illustrated avatar artwork is owner-commissioned (OQ-4); `ProfileAvatar` paints
a token-styled placeholder disc until it arrives.

## 9. Recorded, not built (post-POC)

Per the ticket, recorded here and deliberately out of scope for v1 — not
blocking, not tested:

* Store-policy checklist for both app stores.
* Verifiable parental consent (COPPA) flow.

## 10. Test coverage

Frozen suite, 57 tests:

| Suite | Covers |
| --- | --- |
| `test/features/profiles/profile_picker_test.dart` | tile rendering, icon-first avatars, ordinal reporting, voice-prompt ordering, 4-profile cap edge |
| `test/features/parent/parent_corner_test.dart` | gate-first rendering, random-tap fuzz, real-gate pass, re-entry re-locks, exhaustive section set, links |
| `test/features/parent/profile_crud_test.dart` | all three band placements, override precedence, 5th-create cap, edit preserves level/consent/identity, cancel discards |
| `test/features/parent/pilot_progress_view_test.dart` | completed-story filtering, exact tier labels, encounters-only exclusion, no charts, empty fixtures |
| `test/features/parent/consent_matrix_test.dart` | full reading-mode matrix, mic-never-requested, default-off, immediate persistence, cloud toggle in both engine configurations |
| `test/features/parent/erasure_test.dart` | single tap never deletes, cancel is inert, confirm cascades to zero rows, scoped erasure, empty-profile delete |

The corner suite drives the **real** `ParentalGate` end to end — no bypass seam
exists to drive instead.
