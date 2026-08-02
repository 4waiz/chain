# Renderer and physics decision

**Status:** decided, implemented, measured on device.
**Date:** 2026-08-03
**Toolchain:** Flutter 3.44.8 stable · Dart 3.12.2 · Android SDK 35/36 · NDK 28.2 · JDK 17

---

## Summary

| Layer | Choice |
| --- | --- |
| Renderer | Custom flat-shaded 3D renderer built on `Canvas.drawVertices`, in-repo |
| Physics | Custom deterministic fixed-step rigid-body engine, in-repo |
| Model format | glTF binary (`.glb`) exported from Blender, parsed by an in-repo loader |
| Native dependencies | **None** |

The whole 3D stack is pure Dart. There is no platform view, no texture bridge,
no FFI, and no native build step beyond what stock Flutter already does.

---

## Candidates evaluated

All three candidates were installed and actually built. Nothing below is
inferred from documentation.

### 1. `flutter_scene` 0.20.0 — rejected, does not compile

The most promising option on paper: an Impeller/Flutter GPU scene renderer with
glTF support, authored by a Flutter engine developer.

It resolves cleanly and pulls in `flutter_gpu` from the SDK. It does not
compile. `flutter build apk --release` fails in the kernel snapshot step:

```
flutter_scene-0.20.0/lib/src/texture/compressed_texture.dart:198:50:
  Error: Undefined name 'TextureCompressionFamily'.
flutter_scene-0.20.0/lib/src/texture/compressed_texture.dart:198:19:
  Error: The method 'supportsTextureCompression' isn't defined for the type 'GpuContext'.
flutter_scene-0.20.0/lib/src/gpu/impeller/shader_library_inline.dart:35:17:
  Error: Member not found: 'ShaderLibrary.reinitialize'.
Target kernel_snapshot_program failed: Exception
```

The published package is written against a newer `flutter_gpu` than the one
bundled with Flutter 3.44.8. `flutter_gpu` is an explicitly experimental,
unversioned SDK package, so this class of breakage is structural rather than a
one-off: the renderer's API surface can drift out from under the app on any
Flutter upgrade. Disqualified.

### 2. `three_js` 0.3.0 — builds, but rejected

A Dart port of three.js. Resolves to **32 transitive packages** and renders
through `flutter_angle`, an OpenGL ES/ANGLE binding with a native Android
component.

First release build failed:

```
Execution failed for task ':flutter_angle:configureCMakeRelWithDebInfo[arm64-v8a]'.
> [CXX1300] CMake '3.31.4' was not found in SDK, PATH, or by cmake.dir property.
```

After installing `cmake;3.31.4` via `sdkmanager`, it **does** build — a 22.1 MB
arm64 release APK. It was given a fair second chance and passed.

It was still rejected, for reasons that outweigh "it builds":

- It requires a native CMake toolchain that stock Flutter does not install, so
  the build is not reproducible on a clean machine without extra setup.
- Gradle reports `flutter_angle` as incompatible with Flutter 3.44's Built-in
  Kotlin and asks that the plugin be migrated. That is an unresolved
  upstream-maintenance risk on the critical path of a shipping game.
- A general-purpose PBR scene graph is the wrong shape for this art direction.
  The reference art is untextured, flat-shaded, solid-colour low-poly. Almost
  everything `three_js` spends memory and CPU on — texture pipelines, smooth
  normals, material graphs — is dead weight here.
- Determinism and reset behaviour would sit behind a large third-party surface
  that this project does not control.

### 3. Custom `drawVertices` renderer — selected

The insight that makes this the right call: **the art direction is flat-shaded
low-poly with solid colours.** A face needs exactly one colour. That means the
entire scene — every toy, every domino, every piece of confetti — can be
transformed and lit on the CPU into a single vertex buffer and submitted as
**one `drawVertices` call per frame**.

How it works (`lib/engine/render/renderer.dart`):

1. Each mesh's vertices are projected model→clip→screen once per instance.
2. Triangles are back-face culled by signed screen area — free, and exact.
3. Lighting is a three-point studio rig. The key/fill/up vectors are rotated
   *into object space* once per instance, so shading a face costs two dot
   products and no per-face matrix work.
4. Triangles are depth-sorted with an **O(n) counting sort** over quantised
   depth, which is both faster than a comparator sort and fully deterministic.
5. Positions and colours are packed into reused `Float32List`/`Int32List`
   buffers and submitted in one call with `BlendMode.modulate` against a white
   paint, which passes vertex colours through untouched.

Soft contact shadows are a separate cheap pass: each object's bounding box is
projected onto the ground plane along the key light, hulled in screen space,
and filled through a blur. Height above the floor widens and fades it, which is
what sells an object as airborne mid-reaction.

---

## Measured performance

Release build, `android-x64`, Android 16 emulator, portrait 1080×2400.
CPU time is the renderer's own transform + light + sort + pack cost per frame.

| Scene | Instances | Tris drawn | Tris submitted | p50 | p95 | max |
| --- | --- | --- | --- | --- | --- | --- |
| Reference composition ×1 | 25 | 3,134 | 7,532 | **0.41 ms** | 0.60 ms | 0.60 ms |
| Stress ×16 | 400 | 50,334 | 120,512 | **6.98 ms** | 10.87 ms | 12.79 ms |

Back-face culling removes ~58% of submitted triangles.

A real gameplay level sits at roughly 60–120 instances and 8–15k triangles,
which interpolates to **~1.5–2.5 ms** of renderer CPU against a 16.6 ms
60 FPS budget. The remaining headroom is what the physics step spends.

The ×16 case — 400 objects and 50k triangles, far past anything the game
builds — still holds 60 FPS at p50 and only grazes the budget at p95.

---

## Why this also settles physics

No maintained 3D rigid-body engine exists for Dart (`forge2d`, the obvious
candidate, is 2D only). Binding a native engine would reintroduce exactly the
native-dependency risk that ruled out `three_js`.

More importantly, the brief requires that **"physics should be deterministic
enough that the same setup gives a consistent result"** and that a level reset
be exact. That is a property of the whole loop — timestep, iteration order,
contact ordering, warm-start caching — not something that can be bolted onto a
third-party engine after the fact.

So physics is also in-repo (`lib/engine/physics/`): a fixed-timestep,
sequential-impulse rigid-body solver with sphere and oriented-box colliders,
split-impulse position correction for stable stacking, warm-started contacts,
and island sleeping. Determinism is structural — fixed substep, bodies iterated
in index order, contact pairs generated in sorted order, no hash-order
iteration, no RNG anywhere in the step.

Two shapes cover the entire game: every toy is either round or blocky.

---

## Consequences accepted

- **Painter's algorithm, not a depth buffer.** Triangles are sorted per frame
  rather than z-tested per pixel. For convex, well-separated toys this is
  correct; back-face culling means intra-object order cannot be wrong for a
  convex mesh. Deeply interpenetrating concave geometry could show ordering
  artefacts. Mitigated by keeping colliders and models convex, and by the
  per-instance `sortBias` for deliberate co-planar cases such as floor plates.
- **No per-pixel lighting, shadow mapping, or post-processing.** Not wanted —
  the reference art has none of it.
- **CPU-side transform cost scales with vertex count**, not screen area. This
  is the right trade for low-poly art on mobile GPUs, and the measurements
  above show the ceiling is comfortably far away.
- **16-bit indices** cap a single merged model at 65,535 vertices. The loader
  raises a clear error rather than silently wrapping. No asset is close.

## Re-evaluation triggers

Revisit this decision if any of these become true:

- `flutter_gpu` stabilises and `flutter_scene` ships a version that compiles
  against the pinned Flutter release.
- A level genuinely needs more than ~500 simultaneous rigid bodies.
- Textured or smooth-shaded art is introduced, which would invalidate the
  one-colour-per-face assumption the single-batch design rests on.
