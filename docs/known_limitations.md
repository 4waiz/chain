# Known limitations

Written against the state of the build at the end of the first implementation
pass. This is a factual list of what is **not** finished or **not** verified,
so that nothing here is mistaken for working.

---

## 1. The campaign is not complete: 10 levels exist, 3 of them pass

**Status: incomplete.**

The brief asks for 50 handcrafted levels across five worlds. What exists:

| World | Levels authored | Levels passing the automated completability test |
| --- | --- | --- |
| 1 — Toy Street | 10 | 3 (`w1_l1`, `w1_l3`, `w1_l8`) |
| 2 — Playroom Factory | 0 | – |
| 3 — Mini Harbour | 0 | – |
| 4 — Carnival Table | 0 | – |
| 5 — Builder City | 0 | – |

`test/campaign_test.dart` plays every shipped level headlessly from its
intended starter and fails if the reaction cannot reach the goal. Seven of the
ten World 1 levels currently fail that test. They are shipped in the repository
but they are **not finishable**, and the campaign index therefore does not
describe a playable 50-level game.

### What is actually wrong

The failure is specific and reproducible. In every failing level the domino
run propagates, the player sees a chain, and then the reaction stops before the
heavy end-piece is displaced:

```
w1_l4  phase=failed t=3.37s chain=11
  s_fire     fired @0.03s
  s_hit      fired @0.18s
  s_chain    pending          <- the heavy end piece never moved
  s_car      waiting
  s_btn      waiting
```

The confusing part, and the reason this is not yet fixed: `test/segment_test.dart`
measures the same geometry in isolation and it works. At 0.26 m spacing a run
of 5, 6, 7, 8, 10 and 12 dominoes **all topple completely** (`fell=count`,
final tilt 90°). A fired ball travels 9.63 m. A heavy domino shoves the light
car 1.085 m, far more than the 0.13 m it needs to reach the button.

So each segment is sound in isolation, and the composed level fails. The
difference between the passing levels (`count=5`) and the failing ones
(`count>=6`) is real and perfectly correlated, but the isolated measurement
contradicts it, which means the cause is an interaction between the run and the
rest of the level rather than the run itself. Candidates not yet eliminated:

- the trip sensors used for side branches are placed on the domino line in some
  levels (`w1_l2`'s `cone_trip` at x=0.05 overlaps `d3` at x=0.06) — but `w1_l4`
  has no trip sensors and fails identically, so this is at most a second bug;
- the broadphase sweep prunes on the X axis only, and a long run plus a wide
  static floor may be interacting with the sort order;
- `_isQuiet()` combined with the 2.4 s stall timer may be ending the run while
  a slow hand-off is still in progress.

**This needs to be diagnosed properly with a per-body trace of a failing
level before any more levels are authored.** Authoring the remaining 40 on top
of an unexplained failure mode would multiply the problem rather than solve it.

---

## 2. Meta systems are built but only partly exercised

**Status: implemented, thinly verified.**

Level map, Daily Challenge, Reaction Lab, Toy City, shop and settings all exist
and are wired into the navigation graph. They compile, they analyze clean, and
the app runs. What has **not** been done:

- No screenshot or manual pass over the map, shop, city, daily or lab screens
  on device. Only the home screen and the play screen have been visually
  verified.
- The Daily Challenge and Reaction Lab generate their levels procedurally from
  `ProceduralLevels`. `campaign_test.dart` contains tests that play twelve
  daily seeds and five lab runs, but **those tests have not been run to
  completion**, so procedural levels are not known to be finishable.
- Shop purchases, equipping and the cosmetic recolour path have no tests.
  `Mesh.recoloured` is implemented and `ObjectSpec.colourOverride` is plumbed
  through `LevelRuntime`, but no level or cosmetic actually exercises it, so
  equipping a skin currently changes the shop UI and nothing in the 3D scene.
- Toy City unlocks one landmark per completed level and has 30 landmarks
  defined against a 50-level campaign, so the last 20 levels award nothing.

---

## 3. Integration tests were not written

**Status: not done.**

The brief lists a specific integration suite (launch app, open Level 1, tap
cannon, complete, fail and retry, unlock Level 2, restart and restore progress,
open level map, equip cosmetic). None of it exists. `integration_test/` is an
empty directory.

What does exist and does run:

- `test/physics_test.dart` — 10 tests: resting, stacking, domino chains, ramps,
  bit-identical determinism, frame-pacing independence, raycasting, sleeping.
- `test/level_play_test.dart` — 8 tests over the vertical slice, including a
  full playthrough, the three-star path, the side branch, and determinism
  across resets.
- `test/segment_test.dart` — 3 measurement tests characterising the chain
  segments.
- `test/campaign_test.dart` — written, **currently failing** (see §1).

---

## 4. Performance is measured on an emulator, not a device

**Status: measured, but not on the target hardware.**

All renderer numbers in `docs/renderer_decision.md` come from an Android 16
x86_64 emulator on a desktop GPU. That is a fair measure of the *CPU* cost of
the transform/light/sort pass, which is what the renderer's design hinges on,
but it says nothing reliable about:

- fill rate on a real mobile GPU at 1080×2400;
- thermal behaviour over a long session;
- the 30 FPS low-end fallback, which is implemented as a quality tier but never
  tested on low-end hardware.

No physical Android device was available in this environment.

---

## 5. Renderer trade-offs that are working as designed

These are deliberate and documented in `docs/renderer_decision.md`, listed here
so they are not mistaken for defects:

- **Painter's algorithm, not a depth buffer.** Triangles are depth-sorted per
  frame. Correct for convex, separated toys; deeply interpenetrating concave
  geometry can show ordering artefacts.
- **16-bit indices** cap one merged model at 65,535 vertices. The loader raises
  a clear error rather than wrapping. No asset is near the limit.
- **No shadow mapping.** Contact shadows are projected, hulled and blurred
  bounding boxes. Correct for the art direction, wrong for anything that needs
  a shadow to fall accurately across complex geometry.

---

## 6. Audio and haptics are implemented but unverified by ear

28 sounds and a music loop are synthesised by `tools/make_audio.py` and wired
through `AudioService` with pooling, rate limiting and chain-intensity scaling.
The app plays them at runtime. Nobody has listened to them, and the emulator
audio path was not checked, so mix balance is unproven.

---

## 7. Signing is debug-only

`android/app/build.gradle.kts` reads an upload keystore from
`android/key.properties` when present and **falls back to the debug keystore**
when it is not. No `key.properties` exists in this repository, so the release
APK and AAB produced here are debug-signed and cannot be uploaded to Play as-is.
See `docs/play_store_release.md`.

---

## 8. Smaller gaps

- `RenderQuality.low` disables shadows entirely rather than degrading them.
- The level validator's overlap check skips objects whose collider is derived
  from model bounds at load time, so it cannot catch every spawn-overlap case
  statically.
- `flutter_scene` and `three_js` evaluations are recorded in
  `docs/renderer_decision.md`; the `three_js` spike required installing
  `cmake;3.31.4` into the Android SDK, which is a side effect on this machine.
- The `art/exports/*.json` manifests are build artefacts committed alongside the
  models; they are regenerated by the Blender scripts and are the source for
  `docs/asset_manifest.md`.
