# Recording checklist — demo starter pack (122 clips)

This is the concrete, file-by-file companion to `docs/audio/recording-brief.md`
(read that first for voice direction and the phoneme table). Every clip below
already exists in `content/demo/` as a −16 LUFS placeholder tone. **Record the
real clip, overwrite the placeholder at the exact same path, done** — the
generator (`dart run tool/demo_content.dart`) never overwrites an existing
file, and the pack builder re-verifies loudness on every rebuild.

**Technical spec (all clips):** mono WAV, 44.1 kHz, 16-bit PCM,
**−16 LUFS integrated** (±1 LU — the pack build rejects anything outside),
silence trimmed at both ends. One narrator, one session if possible.

After dropping recordings in:

```sh
dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json \
  --levels=content/demo/levels.json --heart-words=content/demo/heart_words.json \
  --starter-levels=level.demo.1,level.demo.2,level.demo.3
```

Any clip that fails loudness or is missing is named in the error output.

## 1. Phonemes — 44 files, `content/demo/phonemes/<ID>.wav`

The precision-critical set: isolated sounds, **no schwa tails** ("b" not
"buh"), trimmed to onset/decay — these queue back-to-back inside words.
Say-it-like directions for every ID are in the brief's table
(`docs/audio/recording-brief.md` §1). Files:

`B D F G HH JH K L M N NG P R S SH T TH DH V W Y Z ZH CH` (consonants)
`AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW AX AIR EAR URE ARE` (vowels)

## 2. Words — 54 files, `content/demo/words/<word>.wav`

Say the word once, naturally and clearly (this is the whole-word
pronunciation played on tap — distinct from the phoneme sound-out, which the
app assembles from §1). One file per word, lowercase filename:

> a, and, ben, big, bud, bug, bugs, buzzing, by, can, car, cat, day, digs,
> fast, flits, full, garden, go, grins, has, he, his, hot, hums, in, is, it,
> leaf, mud, of, on, play, red, sad, sam, sat, sea, see, sells, she, shells,
> ship, shore, sips, sits, soup, sun, the, thin, tin, to, tree, up

("Ben"/"Sam" are names — record with their natural capital-letter reading;
the file is still lowercase `ben.wav` / `sam.wav`.)

## 3. Sentence narrations — 5 files, `content/demo/narration/`

Warm, unhurried read-aloud pace for an early reader following along:

| file | read exactly |
|------|--------------|
| `cat_p1_s1.wav` | "The cat sat in a tin." |
| `ship_p1_s1.wav` | "The ship is red." |
| `ship_p1_s2.wav` | "It can go fast." |
| `twister_shells.wav` | "She sells sea shells by the sea shore." — model it clearly; the repeated **sh** sound should be easy to hear and imitate |
| `twister_soup.wav` | "Sad Sam sips sea soup." — same, leaning on the **s** sounds |

## 4. Celebration lines — 10 files, `content/demo/celebrations/cheer_01.wav` … `cheer_10.wav`

Short (<2 s), upbeat, varied. Final copy is yours; suggested set:

1. "You did it!"
2. "Great reading!"
3. "Wow, you read that whole page!"
4. "Nice job sounding that out!"
5. "You're getting so good at this!"
6. "Amazing!"
7. "What a great story!"
8. "You read every word!"
9. "Super job!"
10. "That was wonderful reading!"

## 5. Fixed prompts — 2 files, `content/demo/prompts/`

| file | read exactly | direction |
|------|--------------|-----------|
| `your_turn.wav` | "Your turn" | warm and inviting; played after modeled help |
| `near_miss.wav` | "Good try! Listen —" | warm, zero disappointment; plays right before the app models the word after a close-but-not-quite reading. Final copy is yours; keep it under ~1.5 s |

## 5b. Navigation voice prompts — 5 files, `content/demo/audio/nav/`

Played as a non-reading child taps a destination, so they hear where they
are going. Short and plain:

| file | read exactly |
|------|--------------|
| `map.wav` | "The story map" |
| `collection.wav` | "Your collection" |
| `garden.wav` | "The Sound Garden" |
| `parent-corner.wav` | "The parent corner" |
| `flashcards.wav` | "Flash cards" |

## 6. Vocab definitions — 2 files, `content/demo/vocab/`

| file | read exactly |
|------|--------------|
| `garden_definition.wav` | "A garden is a place outside where plants and flowers grow." |
| `buzzing_definition.wav` | "Buzzing is the soft humming sound a bug makes with its wings." |

## Delivery

- [ ] 44 phonemes (§1) — the set most worth re-takes; listen for schwa tails
- [ ] 54 words (§2)
- [ ] 5 narrations (§3)
- [ ] 10 celebration lines (§4)
- [ ] 2 prompts (§5) + 5 nav prompts (§5b)
- [ ] 2 vocab definitions (§6)
- [ ] Everything −16 LUFS, trimmed, mono 44.1 kHz WAV
- [ ] Re-run the pack build; zero loudness/presence errors
