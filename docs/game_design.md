# Game design

## The idea

Each level is a miniature toy diorama photographed in a bright white studio.
The player studies it, taps **one** starting object, and watches a chain
reaction play out. That is the whole interaction: no joystick, no movement
controls, no tutorial text.

**One tap. Total chaos.**

The design goal is that a level teaches itself through composition. Valid
starters pulse, the final target is visually obvious, and the objects between
them are arranged so the intended route reads at a glance. The only instruction
the game ever shows is "Tap to start", and it disappears on first tap.

---

## The loop

1. **Inspect.** The camera frames the whole set and drifts a few degrees so the
   depth reads. The player can drag to look around within clamped limits.
   Tappable starters pulse.
2. **Tap.** One object. The reaction begins.
3. **Watch.** The camera follows the live stage, punches in on impacts, and
   drops into brief slow motion for the final hit.
4. **Result.** Stars, chain length, multiplier, score, coins, bonus objectives.
5. **Retry or continue.** Retry is the largest control on the failure screen and
   is one tap away — the brief's under-two-seconds requirement is met by
   resetting in place rather than reloading the level.

### Failure

A run fails when the reaction **stalls**: nothing is meaningfully in motion and
no new object has joined the chain for 2.4 s. The failure screen names the stage
that was still pending — "It stopped at: Car rolls away" — so the player learns
something rather than just losing. A hint appears only after two failures.

---

## Determinism

The same tap in the same level always produces the same reaction. This is not a
nice-to-have; the entire design depends on it. A player who retries is testing a
hypothesis, and that only works if the simulation is repeatable.

It is achieved structurally: a fixed 1/240 s physics substep driven by an
accumulator, bodies iterated in index order, contact pairs generated in sorted
order, warm-start impulses matched by feature id, no hash-order iteration, and
no RNG anywhere in the step. Even the particle effects use a counter-driven hash
seeded per level rather than `Random()`, so two replays look identical.

`test/physics_test.dart` and `test/level_play_test.dart` assert bit-identical
results across repeated runs and across resets.

---

## Scoring

| Stars | Condition |
| --- | --- |
| 1 | Complete the level |
| 2 | Complete a bonus objective |
| 3 | Complete every bonus, with no stall |

Score rewards chain length, collected stars, an uninterrupted chain, using the
intended starter, and speed against par — all multiplied by a **chain
multiplier** that climbs as the reaction runs (`1 + 0.22 × chain`, capped at
9.9× so late levels stay legible). The multiplier appears in the HUD only once
a chain is actually running, so the pre-tap screen stays as clean as the
reference art.

Bonus objective types: collect all stars, activate a specific object, break
every destructible, use the intended starter, finish without stalling, finish
under a time, reach a chain length.

---

## Worlds

Each world keeps the white studio foundation and changes props, floor shapes and
accent colours rather than the rendering style.

| World | Setting | Main mechanics |
| --- | --- | --- |
| 1 | Toy Street | Cannon, dominoes, cars, traffic buttons, ramps, barriers |
| 2 | Playroom Factory | Conveyors, gears, pistons, magnets, cranes, breakables |
| 3 | Mini Harbour | Boats, drawbridges, water, wind, pulleys, floating objects |
| 4 | Carnival Table | Balloons, cannons, springs, rotating rides, timed switches, bells |
| 5 | Builder City | Long domino chains, cranes, trucks, destruction, multi-stage reactions |

Difficulty grows through observation, more possible starters, timing and
interaction between mechanics — deliberately **not** through speed, and not by
making every level a longer domino run.

---

## Camera

A three-quarter isometric rig, described as target + yaw + pitch + distance so
every move is an interpolation between two states and the camera can never roll
or flip.

- **Before the tap** — frames the whole set, drifts a few degrees.
- **During** — sits between the whole-scene framing and the active stage's focus
  object, biasing towards the wide shot as the chain grows. Re-targets no more
  often than 0.35 s so the eye can follow.
- **Impacts** — a small rotational nudge. Translating the camera on a white
  background reads as a glitch; a tiny yaw/pitch wobble reads as impact.
- **Final hit** — brief slow motion, which dilates the simulation and the
  effects together.

Portrait framing is the hard part: levels are wide and shallow, screens are tall
and narrow. Two things fix it. The camera fits the **projected screen-space
extent** of the level's bounding box rather than a bounding sphere (a sphere
wastes an enormous amount of a portrait screen). And the default yaw is angled
far enough round that the level's long axis runs diagonally across the frame
instead of straight across its narrow width.

---

## Feel

- **Audio intensity grows with the chain.** Hits get louder and brighter as the
  reaction lengthens; a per-sound rate limit stops a domino run turning into a
  wall of noise.
- **Haptics** on cannon fire, hard impacts, button presses and completion.
- **Effects** are split by what reads best on white: impact dust and pops are
  soft translucent screen-space discs; confetti, capsules and stars are real 3D
  instances, so the celebration is made of the same toys as the game.
- **Reduced motion** flattens the lighting, disables shake and slow motion, and
  stops the idle orbit.

---

## Meta systems

- **Level map** — nodes snake down a sine path with per-world banners. A world
  unlocks at 70% of the previous one, so no single awkward level is a hard block.
- **Daily Challenge** — generated from the calendar date alone, so it needs no
  server and works offline. Every player gets the same puzzle on the same day.
  Streak counter, escalating coin reward.
- **Reaction Lab** — unlocks after ten campaign levels. Modular reaction
  sections chained end to end; each completed run makes the next one longer. The
  goal is the longest chain, not just finishing.
- **Toy City** — one landmark per completed level, laid out on a golden-angle
  spiral so it composes at any count. Deliberately not a management game: there
  is nothing to tap, spend or optimise. It exists so progress accumulates
  somewhere visible.
- **Shop** — cosmetics only, bought with coins earned by playing. Cannon, car,
  ball and domino skins, celebration effects, city decorations. No real-money
  purchases.

---

## Art direction

`logo.png` is the art bible, and `lib/engine/render/palette.dart` holds the
values sampled from it. Soft low-poly toy diorama; near-white studio backdrop;
chunky playful proportions; gentle bevels catching a soft three-point studio
light; matte solid-colour plastic; soft contact shadows.

Top faces read almost white, front faces read as the true hue, side faces sit a
little darker. Those three tiers are what make the toys look moulded rather than
flat, and they are produced by rotating the light vectors into object space and
taking two dot products per face.

The UI uses the same palette and the same lighting logic: white cards, soft
downward shadows, chunky rounded buttons that press down into their own shadow,
and Nunito — a rounded geometric sans that matches the wordmark.
