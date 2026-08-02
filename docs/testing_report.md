# Testing report

Generated from the actual runs at the end of the first implementation pass.
Nothing here is projected or assumed.

**Headline: 25 of 29 tests pass. 4 fail.** The failures are all in
`campaign_test.dart` and all trace back to the same unfinished work — the
campaign is 10 levels, not 50, and 7 of those 10 are not completable. See
`docs/known_limitations.md` §1.

---

## Static checks

| Command | Result |
| --- | --- |
| `dart format lib test tools` | clean (44 files) |
| `flutter analyze` | **No issues found** |

---

## Unit and integration-style tests

```
flutter test
25 passing, 4 failing
```

### `test/physics_test.dart` — 10/10 pass

The deterministic rigid-body engine.

| Test | Result |
| --- | --- |
| A sphere dropped on the floor comes to rest on its surface | pass |
| A box settles flat without sinking or jittering | pass |
| A three-block tower stays standing | pass |
| A nudged domino topples an eight-piece run | pass |
| A ball rolls down a ramp and keeps going along the floor | pass |
| Identical setups produce **bit-identical** results | pass |
| Variable frame pacing does not change the outcome | pass |
| A ray selects the nearest body it hits | pass |
| A ray that misses returns null | pass |
| A settled body sleeps, and a new impact wakes it | pass |

Two real engine bugs were caught by these tests during development and fixed:

1. **Inverted sign in the angular term of the contact effective mass.** Spheres
   rested correctly (a contact directly under the centre has no lever arm) but
   boxes exploded to y=37 m. Fixed by writing the term as the provably
   non-negative quadratic form `u . (I⁻¹ u)`, `u = r × n`.
2. **A static floor woke every resting body every step**, so nothing could ever
   sleep, and waking an already-awake neighbour reset its sleep timer so two
   settling bodies kept each other awake forever.

### `test/level_play_test.dart` — 8/8 pass

The vertical slice, played headlessly at a fixed 60 Hz.

| Test | Result |
| --- | --- |
| `w1_l1` validates cleanly | pass |
| Every referenced model exists on disk | pass |
| The full chain completes: cannon → flag | pass |
| Three stars are achievable in one clean run | pass |
| The side branch fires: tower pops and the star is collected | pass |
| The reaction is repeatable across resets (3 runs, bit-identical) | pass |
| A fresh runtime reproduces the same result as a reset one | pass |
| Every shipped level file parses and validates | pass |

### `test/segment_test.dart` — 3/3 pass

Measures the reusable chain segments so level authoring works from data rather
than guesswork. Measured values:

| Segment | Measurement |
| --- | --- |
| Fired cannonball reach | **9.63 m** |
| Domino run at 0.26 m spacing | fully topples at counts 5, 6, 7, 8, 10 and 12 |
| Heavy domino → light car shove | **1.085 m** of travel |

These measurements are what exposed the level-authoring bug: each segment is
sound in isolation, yet composed levels with runs of 6 or more fail. That
contradiction is unresolved and is the top open issue.

### `test/campaign_test.dart` — 4/8 pass

| Test | Result |
| --- | --- |
| Every level validates with no errors | pass |
| Every level is deterministic across two independent runs | pass |
| Daily challenges are completable and stable for a given date | pass |
| Different dates give different puzzles | pass |
| The campaign ships 5 worlds × 10 levels | **fail** — 10 levels exist, not 50 |
| Every level is completable from its intended starter | **fail** — 7 of 10 fail |
| No level finishes suspiciously fast or drags on | **fail** — follows from the above |
| Reaction Lab runs are completable at every unlocked length | **fail** |

The Daily Challenge passing is meaningful: twelve distinct daily seeds each
generate a level that validates and is finishable, and the same date always
produces the same puzzle. The Reaction Lab uses the same generator with more
sections and fails at the longer lengths, which is consistent with the same
run-length bug seen in the handcrafted levels.

---

## On-device verification

Android 16 emulator (`x86_64`), release build, portrait 1080×2400.

| Check | Result |
| --- | --- |
| App launches to the home screen | pass — verified by screenshot |
| Home screen matches the art bible | pass — logo, palette, chunky buttons |
| Level 1 loads and renders the full diorama | pass — verified by screenshot |
| Tapping the cannon starts the reaction | pass |
| Full chain plays out to the flag | pass — 2 stars, chain 13, 3.9× multiplier |
| Celebration confetti and result sheet appear | pass |
| Renderer performance | 3,134 tris at **p50 0.41 ms** CPU |
| Stress: 400 instances / 50,334 tris | **p50 6.98 ms**, p95 10.87 ms |

Two UI bugs were found and fixed by this on-device pass: the result sheet froze
at whatever opacity it had on the frame it appeared (it lives in the widget
tree, not the scene, so it needed an explicit rebuild while animating), and the
result scrim was tinted with the studio grey, which is invisible against a
near-white backdrop.

---

## Not tested

Listed so the gaps are explicit:

- **No integration tests.** `integration_test/` is empty. The suite the brief
  specifies (launch, play, fail, retry, unlock, restart-and-restore, open map,
  equip cosmetic) does not exist.
- **No test covers** the shop, settings persistence, save/restore round-trip,
  Toy City unlocks, or the cosmetic recolour path.
- **No physical device.** All device numbers are from an emulator on a desktop
  GPU, which does not represent mobile fill rate or thermals.
- **No audio verification.** 28 synthesised sounds play at runtime but the mix
  has not been listened to.

---

## Reproducing

```bash
flutter analyze
flutter test
flutter test test/segment_test.dart   # prints the measured segment values
```

Regenerating the content pipeline requires Blender 5.2 with the MCP add-on
connected:

```bash
python tools/make_audio.py
python tools/make_android_assets.py
python tools/levels/build_all.py
python tools/make_asset_manifest.py
```
