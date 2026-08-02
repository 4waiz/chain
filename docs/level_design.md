# Level design

## The schema

Levels are JSON under `assets/levels/`, authored by Python in `tools/levels/`
and parsed into `LevelSpec` (`lib/game/level/level_spec.dart`).

```jsonc
{
  "id": "w1_l1", "world": 1, "index": 1, "name": "First Shot",
  "camera": { "yaw": -0.86, "pitch": 0.48, "pad": 1.05, "fov": 0.75 },
  "objects": [ /* every body, prop, trigger and collectible */ ],
  "stages":  [ /* the expected reaction, as a dependency graph */ ],
  "bonus":   [ /* secondary objectives */ ],
  "goal": "finish_flag",
  "parChain": 12, "parTime": 9.0, "hint": "Tap the blue cannon."
}
```

### Objects

An object carries a model, a body kind (`static` / `kinematic` / `dynamic`), a
collider (`auto` derives a box from the model's bounds), mass and material
properties, and optionally a **device**, **attachments**, or a **collectible**
marker. `hidden: true` spawns it disabled — used for cannon ammo and for debris
waiting inside a breakable.

### Devices

A device is a scripted behaviour. Devices exist so a reaction stays *readable*:
raw simulation handles what it is good at — toppling, rolling, tipping — and a
device takes over wherever pure physics would be fragile or random.

`cannon` · `button` · `spring` · `fan` · `magnet` · `conveyor` · `rotator` ·
`lifter` · `balloon` · `breakable` · `target` · `pusher` · `nudge` · `buoyancy`

`nudge` is the explicit escape hatch: a single authored impulse applied when
triggered. Where a physical hand-off across a gap would be knife-edge, a nudge
guarantees the chain continues with exactly the momentum the level was designed
around. The brief calls for this ("use controlled gameplay events where pure
physics would create unstable or random outcomes") and it is used sparingly —
side branches and cross-gap hand-offs, never the main line.

### The reaction graph

Stages **do not drive the simulation** — physics does. The graph describes the
chain so the game can do four things it cannot do from raw physics:

1. point the camera at whatever is currently happening,
2. score chain length and drive the multiplier,
3. detect that the reaction has stalled, and say *where*,
4. validate at author time that the level is actually connected.

Each stage watches objects and fires on a trigger: `moved` (displacement),
`fell` (tilt from spawn), `impact` (impulse), `activated`, `destroyed`,
`entered`. Stages depend on other stages via `after`, forming a DAG.

A design lesson that cost real debugging time: **`s_chain` watches the heavy
end-piece on displacement, not the last standard domino on tilt.** The final
domino in a run leans against the heavy piece instead of toppling flat, so a
tilt threshold strands the graph even though the chain plainly arrived.

---

## Validation

`LevelValidator` runs over every level in tests and catches:

- missing or unknown models, duplicate or empty object ids
- no starter, no goal, a goal no stage watches
- stages referencing unknown objects or unknown dependencies
- **disconnected stages** — a stage unreachable from any root
- **cycles** in the stage graph
- device references to objects that do not exist; a cannon with no ammo
- bonus objectives targeting unknown objects
- dynamic objects starting below the floor, or with non-positive mass
- objects spawned deeply interpenetrating

Everything it flags is something that would otherwise be discovered by a player
getting stuck.

---

## Authoring, and why it is code

`tools/levels/builder.py` gives level scripts a vocabulary — `cannon()`,
`domino_run()`, `car()`, `flag()`, `tower()`, `breakable()`, `trip()`,
`nudge()` — that places pieces at the correct rest height by **reading the real
exported model dimensions** out of `art/exports/*.json`. Change a model and
every level that uses it re-derives instead of silently floating or sinking.

### Measured constants

`classic_chain()` encodes the backbone that the vertical slice validated. The
numbers in it are measured, not guessed — `test/segment_test.dart` asserts
them:

| Measurement | Value |
| --- | --- |
| Fired cannonball reach | 9.63 m |
| Domino run at 0.26 m spacing | fully topples at 5, 6, 7, 8, 10, 12 pieces |
| Heavy domino → light car shove | 1.085 m of travel |

Two tuning facts worth recording, both of which cost a debugging cycle:

- **A ball's friction must be low (0.05, not 0.35).** The collider is a sphere
  resolved with Coulomb friction at a contact point, which models sliding, not
  rolling. At a crate-like 0.35 a fired ball scrubs off all its speed within a
  metre.
- **A car's friction must be low (0.025).** Its collider is a box standing in
  for four free-spinning wheels; realistic box friction makes it behave like a
  crate and refuse to roll.
- **Flat scenery must have no collider.** A road tile is a few millimetres
  thick; as a solid box it sits *under* everything standing on it and shoves
  those objects up and out at spawn, quietly breaking the whole reaction.
  `builder.decal()` exists for exactly this.

---

## Difficulty plan

The intended shape, from the brief. Levels 1–10 are authored against it;
11–50 are not yet written.

| Levels | Introduces |
| --- | --- |
| 1–5 | One obvious starter. Cannon, dominoes, toy car, large targets, short chains |
| 6–15 | Multiple possible starters, fans, balloons, bridges, seesaws, buttons |
| 16–30 | Magnets, pulleys, cranes, moving platforms, destructibles, alternative paths |
| 31–40 | Water, wind, timed reactions, branching, hidden bonuses, longer sequences |
| 41–50 | Large memorable chains: vehicles, tall towers, cranes, destruction, landmarks |

Difficulty comes from observation, more possible starters, timing and
interaction between mechanics — not from speed, and not from making every level
a longer domino run.

### Scoring

- **One star** — complete the level
- **Two stars** — complete a bonus objective
- **Three stars** — complete every bonus, with no stall

Score rewards chain length, collected stars, an uninterrupted chain, using the
intended starter, and speed against par, all multiplied by a chain multiplier
that grows as the reaction runs (capped at 9.9× so late levels stay legible).

---

## Current state

**10 of 50 levels authored; 3 of those 10 pass the automated completability
test.** `test/campaign_test.dart` plays every shipped level headlessly and fails
if the reaction cannot reach the goal. The failure is specific, reproducible,
and correlates exactly with domino-run length — yet the isolated segment
measurements contradict it. That contradiction is unresolved and is documented
in `docs/known_limitations.md` §1. It should be diagnosed before any further
levels are authored.
