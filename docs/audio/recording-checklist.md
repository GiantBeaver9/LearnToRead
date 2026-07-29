# Recording checklist — demo starter pack (192 clips)

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

## 2. Words — 94 files, `content/demo/words/<word>.wav`

Say the word once, naturally and clearly (this is the whole-word
pronunciation played on tap — distinct from the phoneme sound-out, which the
app assembles from §1). One file per word, lowercase filename:

> a, an, and, ant, at, ben, big, bud, bug, bugs, bus, buzzing, by, can, cap,
> car, cat, crab, day, digs, dog, drop, duck, fast, flits, frog, full, fun,
> garden, go, got, grabs, grins, gus, has, he, hen, hill, his, hops, hot,
> hugs, hums, hush, i, in, is, it, leaf, mud, naps, nat, nell, nest, of, on,
> pan, pat, pats, pin, pip, play, red, rock, runs, sad, sam, sand, sat, sea,
> see, sells, she, shell, shells, ship, shore, sips, sis, sits, snug, sock,
> soup, spin, sun, tan, tap, the, thin, tin, tips, to, tree, up

("Ben"/"Sam"/"Pat"/"Nat"/"Pip"/"Sis"/"Nell"/"Gus" are names — record with
their natural capital-letter reading; the file is still lowercase `ben.wav`,
`gus.wav`, etc. `i.wav` is the word "I", said as its letter name.)

## 3. Sentence narrations — 35 files, `content/demo/narration/`

Warm, unhurried read-aloud pace for an early reader following along:

| file | read exactly |
|------|--------------|
| `cat_p1_s1.wav` | "The cat sat in a tin." |
| `pat_p1_s1.wav` | "Pat pats a cat." |
| `nap_p1_s1.wav` | "Pip naps in a cap." |
| `ant_p1_s1.wav` | "An ant sits in a tin." |
| `pan_p1_s1.wav` | "Nat tips a tin pan." |
| `tap_p1_s1.wav` | "I can tap a tin can." |
| `sip_p1_s1.wav` | "Pip sips at the tap." |
| `catnap_p1_s1.wav` | "The cat naps in a cap." |
| `spin_p1_s1.wav` | "A tin pin can spin." |
| `taptap_p1_s1.wav` | "I tap, tap, tap a pan." |
| `sis_p1_s1.wav` | "Sis can spin, spin, spin." |
| `ship_p1_s1.wav` | "The ship is red." |
| `ship_p1_s2.wav` | "It can go fast." |
| `duck_p1_s1.wav` | "A duck sits in the mud." |
| `duck_p1_s2.wav` | "It digs and digs." |
| `duck_p1_s3.wav` | "The mud is fun!" |
| `frog_p1_s1.wav` | "A frog hops on a rock." |
| `frog_p1_s2.wav` | "The sun is hot." |
| `frog_p1_s3.wav` | "The frog naps." |
| `shell_p1_s1.wav` | "Nell got a big shell." |
| `shell_p1_s2.wav` | "It is red and tan." |
| `shell_p1_s3.wav` | "She hugs it." |
| `dog_p1_s1.wav` | "A dog got a sock." |
| `dog_p1_s2.wav` | "He runs and runs." |
| `dog_p1_s3.wav` | "Drop it, dog!" |
| `hen_p1_s1.wav` | "A red hen sits on a nest." |
| `hen_p1_s2.wav` | "Hush, the hen naps." |
| `bus_p1_s1.wav` | "Gus got on the big bus." |
| `bus_p1_s2.wav` | "The bus runs up the hill." |
| `bus_p1_s3.wav` | "Gus grins." |
| `crab_p1_s1.wav` | "A crab digs in the sand." |
| `crab_p1_s2.wav` | "It grabs a big shell." |
| `crab_p1_s3.wav` | "The crab is snug in it." |
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
- [ ] 94 words (§2)
- [ ] 35 narrations (§3)
- [ ] 10 celebration lines (§4)
- [ ] 2 prompts (§5) + 5 nav prompts (§5b)
- [ ] 2 vocab definitions (§6)
- [ ] Everything −16 LUFS, trimmed, mono 44.1 kHz WAV
- [ ] Re-run the pack build; zero loudness/presence errors
