# Performance report

All numbers measured, none projected. **Caveat up front: the device is an
Android 16 x86_64 emulator on a desktop GPU, not a phone.** See §5.

---

## 1. Renderer

Release build, portrait 1080×2400. "CPU ms" is the renderer's own
transform + light + cull + sort + pack cost per frame, measured with a
`Stopwatch` around `Renderer.render` and reported as a rolling distribution.

| Scene | Instances | Tris drawn | Tris submitted | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Reference composition | 25 | 3,134 | 7,532 | **0.41 ms** | 0.60 ms | 0.60 ms |
| Stress ×8 | 200 | ~25,000 | ~60,000 | ~3.4 ms | — | — |
| Stress ×16 | 400 | 50,334 | 120,512 | **6.98 ms** | 10.87 ms | 12.79 ms |

Back-face culling removes about **58%** of submitted triangles.

Against a 16.6 ms budget for 60 FPS, the reference scene uses 2.5% of the
frame. The ×16 stress case — 400 objects, far beyond anything the game
builds — still holds 60 FPS at p50.

Scaling is close to linear in triangle count, which is expected: the work is
one pass over vertices, one pass over triangles, an O(n) counting sort, and one
`drawVertices` call.

### Why it is this cheap

The whole scene is **one draw call**. The art direction is flat-shaded and
untextured, so a face needs exactly one colour, which means every object in the
level can be packed into a single vertex buffer regardless of how many distinct
models it contains. There is no per-object state change to pay for.

Supporting decisions that show up in the numbers:

- Light vectors are rotated **into object space** once per instance, so shading
  a face is two dot products and no matrix work.
- Depth sorting is a **counting sort** over quantised depth — O(n), and
  deterministic, which matters because a replayed level must look identical.
- Back-face culling is the signed screen area of the projected triangle: exact,
  and free because the projection already happened.
- All buffers are reused `Float32List`/`Int32List` and grow-only. The render
  path allocates nothing per frame.

---

## 2. Physics

Fixed 1/240 s substep with an accumulator, capped at 12 substeps per frame.

A vertical-slice level runs **31 bodies**. A full campaign level is expected to
sit at 40–90. The step cost was not isolated with a profiler; what is known is
that the whole frame — physics, devices, reaction tracking, FX and render —
sustains 60 FPS on the emulator with the reference level.

Cost controls that are in place:

- **Sort-and-sweep broadphase** on the X axis, so a level laid out left-to-right
  prunes well.
- **Island sleeping** — a settled stack stops being integrated entirely.
- **Two collider shapes only** (sphere, oriented box). Every toy is round or
  blocky, so nothing needs a general convex hull.
- **Warm-started contacts** mean the solver converges in 8 velocity iterations
  instead of needing far more.

---

## 3. Memory and size

| Item | Size |
| --- | --- |
| All 172 models | 41,042 tris · ~430 KB of GLB |
| All 28 sounds + music loop | 1,518 KB |
| Debug APK | 150.0 MB |
| **Release APK** (all ABIs) | **49.8 MB** |
| **Release AAB** | **49.5 MB** |
| Release APK, single ABI (`android-x64`) | 21.6 MB |

The fat release APK carries three ABIs. The AAB splits per ABI and density at
install time, so the actual download will be close to the single-ABI figure.

Meshes are immutable and shared: a level with forty dominoes holds one domino
mesh. `ModelCache` never evicts during a session — the whole library is under
half a megabyte of geometry.

---

## 4. Quality tiers

`Settings.quality` maps to `RenderQuality`, which trades shadow work first,
because on a white studio backdrop shadows cost the most and are noticed least.

| Tier | Shadows |
| --- | --- |
| High | Shape-aware: bounding box projected to the ground, convex-hulled in screen space, blurred |
| Medium | Blurred ellipse per object |
| Low | Off |

`Settings.reducedMotion` additionally flattens the lighting rig, disables camera
shake and slow motion, and stops the idle orbit.

---

## 5. What these numbers do not tell you

The measurements above are from an **emulator on a desktop GPU**. They are a
fair measure of the renderer's CPU cost, which is the axis the whole design
rests on. They say nothing reliable about:

- **Fill rate on a real mobile GPU.** The scenes are geometrically tiny but they
  cover a full 1080×2400 screen. Mobile tiled renderers behave differently.
- **Thermals.** No sustained-load test was run.
- **The 30 FPS low-end fallback.** Implemented as a quality tier, never tested
  on low-end hardware.
- **Startup and level-load time.** Not instrumented.

No physical Android device was available in this environment. Before shipping,
the reference level and the ×16 stress case should both be re-measured on a
mid-range phone.
