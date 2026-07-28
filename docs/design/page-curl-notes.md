# Page-curl research notes (spec §8, 2026-07-28)

Survey of viable techniques for a corner-anchored, 60fps page curl in pure
Flutter (no pub dependency), plus the visual language that makes a fold read
as paper. Sources: `turn_page_transition` source (Shoryu-Y/turn_page_transition,
`lib/src/turn_page_transition.dart`), fluttercommunity/`page_turn`,
codewithandrea's PageFlipBuilder articles, and CSS folded-corner/page-curl
demos (Nicolas Gallagher's pure-CSS folded corner, CodePen page-curl pens by
JoostKiens / saslam / martinlex).

## Techniques considered

1. **Two-layer clip + painted overleaf** (the `turn_page_transition`
   technique): the top page widget is clipped by a `CustomClipper<Path>` to
   the not-yet-turned region; the folded-back face ("overleaf") is a plain
   polygon painted by a `CustomPainter` — no 3D at all, pure 2D geometry.
   Cheapest possible per frame (one clip + one poly fill), trivially 60fps.
2. **Clip + `Transform` of a mirrored widget copy**: same clip, but the
   curl-back is the actual page widget mirrored/rotated about the fold line
   so the back shows ghosted content. Two renderings of the page per frame
   and matrix bookkeeping; only worth it if the back must show content —
   real paper backs are blank, so not needed here.
3. **CustomPainter cylinder approximation** (the `page_turn` package style):
   quadratic-bezier fold edge + radial/linear gradients approximating a
   cylindrical curl. Prettier fold edge, noticeably more path math, still
   raster-cheap. A refinement of (1), not a different architecture.
4. **Fragment-shader page curl** (GLSL/FragmentProgram, flutterFX-style):
   the only physically-true cylindrical curl. Explicitly out of scope per
   spec ("NOT a cloth physics simulation") and the heaviest option.
5. **CSS dog-ear visual language** (for the resting corner): a folded corner
   reads as paper when three cues are present — (a) the fold line is the
   hypotenuse of a corner triangle at 45°; (b) the folded-back face is a
   *slightly lighter* shade than the page (it faces the light) with a subtle
   gradient darkening toward the crease; (c) a small soft shadow is cast
   along/under the fold onto the layer beneath. The cut corner behind the
   fold shows the page underneath.

## Chosen: (1) two-layer clip + painted overleaf, with (5) for shading

Geometry: drag progress `t` moves the fold line, parameterised by its
intersections with the bottom edge (`a`) and right edge (`b`), lerped from
the resting dog-ear size (`a = b = 48px`, a 45° corner fold) to `2·width` /
`2·height` at `t = 1` (at which point the fold has swept past the top-left
corner and the page is fully turned). The visible top-page region is the
rectangle clipped to the far side of the fold line (one-edge
Sutherland–Hodgman, ≤5 vertices); the overleaf is the near-side polygon
reflected across the fold line, filled with a fold-perpendicular linear
gradient (lightest at the lifted tip, slightly darker at the crease) plus a
blurred cast shadow beneath it. The resting dog-ear is simply the curl
evaluated at `t = 0` — so the drag grows the exact same shape continuously,
with zero special-casing.

Why: it is the only approach that is simultaneously (a) cheap enough to
guarantee 60fps on tablet (one Path clip, one poly fill, one blur per
frame), (b) drives directly off a single 0..1 `AnimationController` value so
drag / spring-back / tap-to-turn all share one code path, and (c) matches
the spec's own instruction ("clip + rotate + gradient shade", not cloth).

Network note: GitHub raw fetches for `page_turn` internals 404'd behind the
proxy; the `turn_page_transition` source was successfully read and confirmed
the two-layer clip+overleaf architecture. Remaining shading details were
taken from the CSS demos' visual language and first principles.

Token-lint note: `test/design/token_lint_test.dart` scans **all** of
`lib/design/` except `tokens.dart`, so `page_curl.dart` may not contain raw
color literals. All curl shades are therefore derived from the nearest
`DesignTokens` members (`readingBackground` for the paper-back face — it is
already slightly lighter than the card; `surfaceBackground` lerped in for
the crease shade; `wordUnreadInk` at low alpha for shadows).
