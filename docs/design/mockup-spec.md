# "Sound It Out" mockup spec (owner-supplied HTML prototype, 2026-07-28)

The product owner supplied an HTML/React prototype of the reading screen
("Sound It Out"). This document is the distilled, implementation-ready spec —
the single context hub for the frontend-restyle agents. The prototype is the
OWNER'S design decision: where it conflicts with earlier builder-chosen
placeholder values (design tokens), the mockup wins; where it conflicts with
a RATIFIED behavior (PRD), the conflict is listed in §9 with the ruling.

The design direction in three words: **warm paper storybook**. Cream
parchment, serif reading text, soft borders, small typographic details —
deliberately not a plastic candy-colored kids app.

## 1. Palette (exact hex, from the mockup)

| token role | hex | mockup usage |
|---|---|---|
| ink | `#33302B` | unread words, titles, dark buttons |
| read green | `#4E8B5C` | words already read; "Word read" button |
| current amber | `#D79A3C` | the word being said NOW ("saying now"); active syllable chip |
| vocab blue | `#5A79B8` | new/vocab words (dotted underline, weight 600, tappable) |
| listening red | `#C6412F` | waveform bars (alt bar `#D0684F`) |
| page background | `#F3EADA` | body; radial glow `#FBF5EA` at top → `#EADFCB` bottom |
| card | `#FDFAF3` (grad to `#FBF6EB`) | reading card, object cards, listening pill |
| card border | `#E2D6BF` | 1px, everywhere |
| muted label | `#A0937D` | uppercase small-caps labels ("READ THIS OUT LOUD") |
| muted body | `#6E6455` / `#8C816C` | secondary text, legend |
| hint panel bg | `#FDF3DF`, border `#EFD9A6` | "let's take it slowly" |
| hint label | `#B48A3A` | hint small-caps label |
| syllable chip idle | bg `#F6E7C5`, text `#8A6A24` | |
| syllable chip active | bg `#D79A3C`, text `#33302B` | |
| vocab popup bg | `#EEF2FA`, border `#C8D5EC` | word `#3E5C93`, syllables `#7B8CAE`, meaning `#3F4658` |
| success panel | bg `#E9F2EA`, border `#BFDCC6`, stat `#3C7A4B`, label `#6E9478` | done-state stats |
| success button | `#3C7A4B` (hover `#326540`), text `#F2F8F3` | "Read another →" |
| dark chrome | `rgba(43,40,35,0.94)` | (prototype-only engine controls) |
| confetti set | `#C6412F` `#D79A3C` `#4E8B5C` `#5A79B8` `#B85C8A` | ribbons/sparks |

## 2. Typography

- **Reading text: Literata** (serif), weight 400; sizes by level —
  62px (ages 4–6), 46px (6–8), 34px (8–10) at desktop scale, with a
  responsive clamp `clamp(26px, size/12*vw + 12px, size px)`; line-height
  1.5 / 1.55 / 1.7 respectively; letter-spacing −0.005em.
- **UI text: Nunito** (rounded humanist sans), weights 400/600/700/800.
- **Meta/dev text: IBM Plex Mono** (small caps-ish labels, popup syllable
  dot-notation `prin · cess`); optional in-app — used for syllable notation.
- Small-caps label style: 12–13px, weight 800, letter-spacing 0.14–0.16em,
  uppercase, muted color.

## 3. Reading card & word states

- Card: gradient `#FDFAF3→#FBF6EB`, border 1px `#E2D6BF`, radius 20,
  inset highlight `0 1px 0 #FFFDF7`, soft drop shadow
  `0 18px 40px -28px rgba(70,55,30,0.45)`, generous padding.
- Words flow inline, gap `0.14em 0.34em`, baseline-aligned.
- States (color transition 260ms ease):
  - unread → ink `#33302B`, weight 400
  - **current → amber `#D79A3C`** (mockup's "saying now")
  - read/helped → green `#4E8B5C`
  - vocab (unread) → blue `#5A79B8`, weight 600, dotted underline
    (thickness 2, offset 0.18em), tap opens popup
  - stuck/hint word → `pulseWord` animation: translateY(−2px) scale(1.04)
    at 50%, 1.3s ease-in-out infinite
- Legend row under the text (dashed top border `#E4D9C3`): three dots —
  green "read it", amber "saying now", blue "new word — tap it";
  12px weight 700 `#8C816C`.

## 4. Support panels

- **Object cards** (younger levels, above the sentence): rounded-18 cards
  `#FDFAF3` with illustration slot + serif caption below ("the cat"),
  caption `#6E6455` ~19–26px.
- **Hint panel** ("let's take it slowly", appears after idle/stuck; fadeUp
  380ms): bg `#FDF3DF`, border 1.5 `#EFD9A6`, radius 18; small-caps label
  `#B48A3A`; syllable chips (serif 24–34px, radius 12, padding 4×14) sweep
  active one at a time at ~780ms/syllable; dark button "Hear it enunciated"
  (`#33302B` bg, cream text, pill radius, min-height 46).
- **Vocab popup** (fadeUp 320ms): layout = illustration slot (150×110,
  dashed border, diagonal-stripe placeholder) + word (serif 26–34 weight
  600) + syllables in mono with " · " separators + meaning (16.5px/1.45,
  max 46ch) + round × close button (40×40, `#D8E1F2`).
- **Listening pill** (always while reading): white pill, 6 waveform bars
  4px wide radius 2, colors alternating `#C6412F`/`#D0684F`, `wave`
  animation scaleY 0.35→1→0.35, 900ms ease-in-out infinite, 120ms
  stagger per bar, transform-origin bottom; label 14.5px weight 800
  `#6E6455` — "Listening…" normally, "Still listening — take your time"
  while the hint panel is up (patience, never pressure).

## 5. Done state

- **Scene reveal**: rounded-20 stage (min ~200px, up to 38vh) playing the
  story animation; `sceneReveal` entrance: from opacity 0,
  scale(0.94) rotate(−0.6deg) → 1/none, 620ms cubic-bezier(.2,.9,.25,1).
  Caption strip fades up from the bottom over a cream gradient, serif.
- **Stats panel**: bg `#E9F2EA`; two big serif numbers (34–52px weight 700
  `#3C7A4B`) labeled small-caps "WORDS READ" / "IN A ROW"; hurray copy
  (serif 22–30 `#2F5E3C` + 15px sub `#5C7A64`) escalating with streak:
  "Hurray! / You read every single word.", "Two in a row! / Your reading
  voice is getting stronger.", "Three stories! / That is a whole reading
  streak.", "Unstoppable! / Look how many words you have read today.";
  green pill button "Read another →".
- Whole done column enters with fadeUp 420ms.

## 6. Celebration confetti (pure code, no assets)

Full-screen non-interactive overlay, z-top, plays on story completion:
- **Ribbons**: 16 + 10×intensity rects (w 5–11, h 12–26, radius 2, random
  confetti-set color), start above the viewport at random x (0–100%),
  fall to 105vh while rotating to 520deg, duration 2.4–4.2s linear,
  delay 0–1.1s, fade in by 12% and out at end (`ribbon` keyframes).
- **Bursts**: `intensity` clusters at random (18–82% x, 14–46% y): one
  expanding ring (120px, 2px border, scale 0.2→1.6, fade 0.9→0, 1.1s
  ease-out) + 16 sparks (7px dots) flying radially 70–150px with
  cubic-bezier(.15,.7,.3,1), 1.25s, staggered delay 0–1.4s.
- Intensity = min(3, stories-in-a-row).

## 7. Motion inventory (all CSS-keyframe equivalents)

| name | effect | duration/curve |
|---|---|---|
| wave | scaleY 0.35↔1, origin bottom | 900ms ease-in-out ∞, 120ms stagger |
| pulseWord | y −2px, scale 1.04 at 50% | 1.3s ease-in-out ∞ |
| fadeUp | opacity 0→1, y +14→0 | 320–420ms ease |
| sceneReveal | scale .94 rot −0.6°→ 1 | 620ms cubic-bezier(.2,.9,.25,1) |
| ribbon | fall + spin (see §6) | 2.4–4.2s linear |
| spark | radial fly + fade | 1.25s cubic-bezier(.15,.7,.3,1) |
| ringOut | scale .2→1.6, fade | 1.1s ease-out |
| word color | color transition | 260ms ease |

## 8. Page turn (OWNER ADDITION — not in the mockup, explicitly requested)

> "the only thing missing is a little page turn from the bottom right like
> turning the page in a book to go to the next one, to reinforce good habits"

- A **folded bottom-right corner** of the reading card, always visible on
  multi-page stories when the current page is complete (all words green) —
  a small dog-ear inviting a book-like gesture.
- Child can **drag the corner** (or tap it) and the page follows with a
  curl — revealing the next page underneath, exactly like turning a paper
  page. Release past ~40% completes the turn; release before springs back.
- Keep it simple: a corner-anchored curl (clip + rotate + gradient shade on
  the curl "back"), not a full cloth simulation. 60fps on tablet.
- Direction: forward only (bottom-right). No back-turn in v1.
- On completion it must call the existing page-advance path (the same one
  the current page-turn control invokes) — the visual replaces the control,
  the logic does not change.

## 9. Conflicts with ratified PRD text — owner rulings via this mockup

1. **Current word is amber, not ink-with-marker.** PRD §6 said "current
   word: subtle underline/glow marker, ink color". The mockup's explicit
   legend ("saying now" = amber) supersedes it. Token interface keeps the
   name `wordCurrentInk`; its value changes and the alias-to-unread
   structural test is amended with provenance.
2. **Read green becomes `#4E8B5C`.** The frozen tokens test asserts WCAG AA
   (≥4.5:1) contrast against the reading background. `#4E8B5C` on `#FDFAF3`
   is ~3.9:1 — the implementing agent must verify and, if short, darken
   minimally along the same hue (e.g. toward `#3C7A4B`, the mockup's own
   stat green) until the ≥4.5:1 test passes. The mockup family look wins,
   the accessibility floor stays.
3. Everything else (typography families, palette, spacing) replaces
   builder placeholders — that swap is exactly what OQ-8 anticipated;
   `tokensAreOwnerSignedOff` stays `false` until the owner sees it on
   device and says so.

## 10. What the prototype contains that the app does NOT copy

- The level-pill header (Ages 4–6/6–8/8–10 switcher) — prototype chrome;
  the app gets level from the profile/phonics engine.
- The dark "stand-in for the voice engine" control bar — the app has a real
  tracker (and its own debug seams).
- Auto-read — not a v1 app feature.
- `image-slot` placeholders — stay placeholders until OQ-4 art exists.
