"""Level authoring helpers for Chain Reaction City.

Levels ship as JSON under `assets/levels/`, but hand-typing that JSON for 50
handcrafted levels would be miserable and error-prone. This module gives the
level scripts a small vocabulary — `cannon()`, `domino_run()`, `car()`,
`flag()` — that places pieces at the right rest heights by reading the real
exported model dimensions out of `art/exports/*.json`.

Coordinates are the runtime's: +X right, +Y up, +Z towards the viewer.
Everything sits on the floor plane at y = 0.
"""

import json
import math
import os

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORTS = os.path.join(REPO, "art", "exports")
LEVELS_OUT = os.path.join(REPO, "assets", "levels")


# --------------------------------------------------------------- asset sizes
def _load_manifest():
    sizes = {}
    for name in sorted(os.listdir(EXPORTS)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(EXPORTS, name), encoding="utf-8") as f:
            for e in json.load(f):
                sizes[e["slug"]] = e
    return sizes


ASSETS = _load_manifest()


def size(slug):
    a = ASSETS.get(slug)
    if a is None:
        raise KeyError(f"unknown model '{slug}' — was its kit exported?")
    return a["size"]


def half(slug):
    s = size(slug)
    return [s[0] / 2, s[1] / 2, s[2] / 2]


def rest_y(slug):
    """Centre height at which a model's bounding box sits flat on the floor."""
    return size(slug)[1] / 2


def radius(slug):
    a = ASSETS.get(slug, {})
    if "radius" in a:
        return a["radius"]
    return size(slug)[1] / 2


# ==================================================================== Level
class Level:
    def __init__(self, lid, world, index, name, hint="", teaches=None,
                 par_chain=8, par_time=12.0, gravity=-9.81):
        self.data = {
            "id": lid,
            "world": world,
            "index": index,
            "name": name,
            "hint": hint,
            "teaches": teaches or [],
            "parChain": par_chain,
            "parTime": par_time,
            "gravity": gravity,
            "camera": {},
            "objects": [],
            "stages": [],
            "bonus": [],
            "goal": "",
        }
        self._ids = set()

    # ------------------------------------------------------------ primitives
    def add(self, oid, model=None, kind="static", pos=(0, 0, 0), rot=(0, 0, 0),
            **kw):
        if oid in self._ids:
            raise ValueError(f"{self.data['id']}: duplicate object id '{oid}'")
        self._ids.add(oid)
        o = {"id": oid, "pos": [round(v, 4) for v in pos]}
        if model:
            o["model"] = model
        if kind != "static":
            o["kind"] = kind
        if any(rot):
            o["rot"] = [round(v, 3) for v in rot]
        o.update({k: v for k, v in kw.items() if v is not None})
        self.data["objects"].append(o)
        return o

    def camera(self, yaw=-0.86, pitch=0.50, pad=1.06, bias=0.10, fov=0.75, orbit=0.14):
        self.data["camera"] = {
            "yaw": yaw, "pitch": pitch, "pad": pad,
            "bias": bias, "fov": fov, "orbit": orbit,
        }

    def stage(self, sid, watch, after=None, trigger="moved", threshold=0.0,
              focus=None, label=None, timeout=6.0):
        s = {"id": sid, "watch": watch if isinstance(watch, list) else [watch],
             "trigger": trigger, "timeout": timeout}
        if after:
            s["after"] = after if isinstance(after, list) else [after]
        if threshold:
            s["threshold"] = threshold
        if focus:
            s["focus"] = focus
        if label:
            s["label"] = label
        self.data["stages"].append(s)
        return s

    def bonus(self, bid, btype, desc, target=None, value=0):
        b = {"id": bid, "type": btype, "desc": desc}
        if target:
            b["target"] = target
        if value:
            b["value"] = value
        self.data["bonus"].append(b)
        return b

    def goal(self, oid):
        self.data["goal"] = oid

    # ------------------------------------------------------------ assemblies
    def cannon(self, oid, x, z=0.0, aim_deg=14.0, power=4.6, ammo="cannonball",
               facing=1.0, intended=True, ammo_mass=0.26):
        """Blue toy cannon: carriage, two wheels, tilted barrel, and a hidden
        ball that the fire device wakes at the muzzle."""
        yaw = 0.0 if facing > 0 else 180.0
        tilt = aim_deg * facing

        self.add(f"{oid}_carriage", "cannon_carriage", pos=(x - 0.06 * facing, 0.115, z),
                 rot=(0, yaw, 0), shape="box", shadow=True)
        for sz in (0.115, -0.115):
            self.add(f"{oid}_wheel{'p' if sz > 0 else 'n'}", "cannon_wheel",
                     pos=(x - 0.09 * facing, 0.108, z + sz), rot=(0, yaw, 0),
                     shape="none")

        a = math.radians(aim_deg)
        self.add(oid, "cannon_barrel", pos=(x, 0.248, z), rot=(0, yaw, tilt),
                 shape="box", starter=True,
                 device={
                     "type": "cannon",
                     "power": power,
                     "aim": [round(math.cos(a) * facing, 4), round(math.sin(a), 4), 0],
                     "ammo": f"{oid}_ball",
                     "muzzle": [0.245 * facing, 0.02, 0],
                     "intended": intended,
                 })

        # Low friction on purpose. The collider is a sphere resolved with
        # Coulomb friction at the contact point, which models sliding, not
        # rolling — at a crate-like 0.35 a fired ball scrubs off all its speed
        # within a metre and no shot can ever reach a distant target.
        self.add(f"{oid}_ball", ammo, kind="dynamic", shape="sphere",
                 pos=(x + 0.245 * facing, 0.30, z),
                 radius=radius(ammo), mass=ammo_mass, friction=0.05,
                 restitution=0.24, hidden=True, tag="ball")
        return oid

    def domino_run(self, prefix, x0, z=0.0, count=5, spacing=0.26,
                   colours=("blue", "yellow", "green", "red"), model=None,
                   mass=0.13, dx=None, dz=0.0, rot_y=0.0):
        """A straight or angled run of dominoes. Returns the ids in order."""
        ids = []
        step_x = spacing if dx is None else dx
        for i in range(count):
            slug = model or f"domino_{colours[i % len(colours)]}"
            oid = f"{prefix}{i}"
            self.add(oid, slug, kind="dynamic",
                     pos=(x0 + step_x * i, rest_y(slug), z + dz * i),
                     rot=(0, rot_y, 0),
                     shape="box", mass=mass, friction=0.58, restitution=0.02,
                     tag="domino")
            ids.append(oid)
        return ids

    def car(self, oid, x, z=0.0, rot_y=0.0, mass=0.55, model="toy_car_body",
            friction=0.06, y=None):
        """Yellow toy car: one box body plus four visual wheels that roll.

        Friction defaults low because the collider is a box standing in for
        four free-spinning wheels — a realistic box friction would make the
        car behave like a crate and refuse to roll."""
        cy = 0.109 if y is None else y
        self.add(oid, model, kind="dynamic", pos=(x, cy, z), rot=(0, rot_y, 0),
                 shape="box", size=[0.193, 0.109, 0.102],
                 mass=mass, friction=friction, restitution=0.04, tag="car",
                 attach=[
                     {"model": "toy_car_wheel", "offset": [sx, -0.051, sz], "spin": "z"}
                     for sx in (0.105, -0.105) for sz in (0.105, -0.105)
                 ])
        return oid

    def button(self, oid, x, z=0.0, activates=None, min_impulse=0.03,
               model="push_button"):
        self.add(oid, model, pos=(x, rest_y(model), z), shape="box",
                 device={"type": "button", "minImpulse": min_impulse,
                         "activates": activates or []})
        return oid

    def flag(self, oid, x, z=0.0):
        """Flag target: static pole plus a cloth that slides up when raised."""
        self.add(f"{oid}_pole", "flag_base", pos=(x, rest_y("flag_base"), z),
                 shape="box")
        self.add(oid, "flag_cloth", kind="kinematic", shape="none",
                 pos=(x + 0.02, 0.16, z),
                 device={"type": "lifter", "travel": [0, 0.48, 0],
                         "duration": 0.85, "isFlag": True})
        return oid

    def tower(self, prefix, x, z=0.0, blocks=("block_red", "block_blue", "block_red"),
              roof=True, mass=0.30, kind="dynamic"):
        """Stacked window blocks with an optional green roof cap."""
        ids = []
        y = 0.0
        for i, slug in enumerate(blocks):
            h = size(slug)[1]
            oid = f"{prefix}{i}"
            self.add(oid, slug, kind=kind, pos=(x, y + h / 2, z), shape="box",
                     mass=mass, friction=0.6, restitution=0.02, tag="block")
            ids.append(oid)
            y += h
        if roof:
            h = size("block_roof")[1]
            oid = f"{prefix}roof"
            self.add(oid, "block_roof", kind=kind, pos=(x, y + h / 2, z), shape="box",
                     mass=mass * 0.7, friction=0.6, tag="block")
            ids.append(oid)
        return ids

    def star(self, oid, x, y, z=0.0):
        """Collectible star. Lies flat in its model, so it is stood upright.

        The trigger volume is deliberately fatter than the visible star: a
        collectible that demands pixel-accurate contact from a tumbling piece
        reads as broken rather than skilful."""
        self.add(oid, "star", pos=(x, y, z), rot=(90, 0, 0), shape="box",
                 size=[0.105, 0.105, 0.085], sensor=True, collect="star",
                 shadow=False)
        return oid

    def coin(self, oid, x, y, z=0.0):
        self.add(oid, "coin", pos=(x, y, z), rot=(90, 0, 0), shape="box",
                 size=[0.055, 0.055, 0.012], sensor=True, collect="coin",
                 shadow=False)
        return oid

    def ramp(self, oid, x, z=0.0, model="ramp_gentle", rot_y=0.0, flip=False):
        """Ramps are authored resting on the floor; `flip` mirrors the slope."""
        self.add(oid, model, pos=(x, rest_y(model), z),
                 rot=(0, rot_y + (180 if flip else 0), 0), shape="box",
                 friction=0.35)
        return oid

    def prop(self, oid, model, x, z=0.0, rot_y=0.0, kind="static", mass=0.3,
             y=None, shape="box", **kw):
        self.add(oid, model, kind=kind,
                 pos=(x, rest_y(model) if y is None else y, z),
                 rot=(0, rot_y, 0), shape=shape, mass=mass, **kw)
        return oid

    def decal(self, oid, model, x, z=0.0, rot_y=0.0, y=None):
        """Flat ground dressing — roads, plazas, painted markings.

        Deliberately collider-free. A road tile is a few millimetres thick, so
        as a solid box it would sit *under* everything standing on it and
        shove those objects up and out at spawn, which quietly breaks the
        whole reaction. Visually it makes no difference."""
        self.add(oid, model, pos=(x, rest_y(model) if y is None else y, z),
                 rot=(0, rot_y, 0), shape="none", shadow=False)
        return oid

    # ------------------------------------------------ proven chain segments
    # These encode the numbers validated against the physics engine. Reusing
    # them is what keeps 50 handcrafted levels reliable: a level author varies
    # layout and mechanics, not the tuning that makes a hand-off work.

    def finish(self, x, z=0.0, prefix="finish", min_impulse=0.008):
        """Standard finish: a push button that raises a flag."""
        self.button(f"{prefix}_btn", x, z, activates=[f"{prefix}_flag"],
                    min_impulse=min_impulse)
        self.flag(f"{prefix}_flag", x + 0.50, z)
        return f"{prefix}_btn", f"{prefix}_flag"

    def domino_to_car(self, prefix, x0, z=0.0, count=5, car_x=None, btn_x=None,
                      colours=("blue", "yellow", "green", "red")):
        """Domino run -> heavy domino -> light car -> button.

        The last piece is heavy and the car is light and slippery: a standard
        0.13 kg domino cannot move a car far enough to reach a button.
        """
        run = self.domino_run(prefix, x0, z, count=count, colours=colours)
        hx = x0 + 0.26 * count + 0.02
        self.add(f"{prefix}h", "domino_heavy", kind="dynamic",
                 pos=(hx, rest_y("domino_heavy"), z), shape="box",
                 mass=0.55, friction=0.58, restitution=0.02, tag="domino")
        cx = car_x if car_x is not None else hx + 0.35
        self.car(f"{prefix}_car", cx, z, mass=0.16, friction=0.025)
        bx = btn_x if btn_x is not None else cx + 0.47
        return run + [f"{prefix}h"], f"{prefix}_car", bx

    def classic_chain(self, x0=-1.62, count=5, z=0.0, colours=None,
                      aim=13.0, power=4.55, prefix="d", car=True,
                      first_gap=0.90):
        """The validated backbone: cannon -> ball -> domino run -> heavy
        domino -> light car -> button -> flag.

        Every constant here is measured, not guessed — see
        `test/segment_test.dart`, which asserts the ball's reach, the run
        length that stays reliable, and how far the car actually slides.

        Returns (run_ids, car_id, button_x, flag_id).
        """
        self.cannon("cannon", x=x0, aim_deg=aim, power=power)
        dx0 = x0 + first_gap
        run = self.domino_run(prefix, dx0, z, count=count,
                              colours=colours or ("blue", "yellow", "green", "red"))
        # The heavy end piece sits one *domino spacing* past the last standard
        # piece, not an arbitrary gap: the last domino has to actually reach
        # it. Deriving it from `count` keeps that true at any run length.
        hx = dx0 + 0.26 * (count - 1) + 0.28
        heavy = f"{prefix}h"
        self.add(heavy, "domino_heavy", kind="dynamic",
                 pos=(hx, rest_y("domino_heavy"), z), shape="box",
                 mass=0.55, friction=0.58, restitution=0.02, tag="domino")

        if not car:
            self.button("finish_btn", hx + 0.42, z, activates=["finish_flag"],
                        min_impulse=0.008)
            self.flag("finish_flag", hx + 0.92, z)
            return run + [heavy], None, hx + 0.42, "finish_flag"

        cx = hx + 0.35
        self.car("car", cx, z, mass=0.16, friction=0.025)
        bx = cx + 0.47
        self.button("finish_btn", bx, z, activates=["finish_flag"], min_impulse=0.008)
        self.flag("finish_flag", bx + 0.50, z)
        return run + [heavy], "car", bx, "finish_flag"

    def classic_stages(self, run, car, last_std, extra_after=None):
        """Stage graph matching `classic_chain`.

        `s_chain` watches the *heavy* end piece on displacement rather than
        the last standard domino on tilt. The final domino in a run leans
        against the heavy piece instead of toppling flat, so a tilt threshold
        strands the graph even though the chain plainly arrived. Displacement
        of the heavy piece is what "the chain reached the end" actually means.
        """
        self.stage("s_fire", "cannon_ball", trigger="moved", threshold=0.15,
                   focus="cannon_ball", label="Cannon fires")
        self.stage("s_hit", run[0], after=["s_fire"], trigger="fell", threshold=20,
                   focus=run[0], label="Dominoes start", timeout=8.0)
        self.stage("s_chain", run[-1], after=["s_hit"], trigger="moved", threshold=0.04,
                   focus=run[-1], label="Chain reaches the end", timeout=9.0)
        prev = "s_chain"
        if car:
            self.stage("s_car", car, after=[prev], trigger="moved", threshold=0.10,
                       focus=car, label="Car rolls away", timeout=8.0)
            prev = "s_car"
        self.stage("s_btn", "finish_btn", after=[prev], trigger="activated",
                   focus="finish_btn", label="Button pressed", timeout=9.0)
        self.stage("s_flag", "finish_flag", after=["s_btn"], trigger="activated",
                   focus="finish_flag", label="Flag raised")

    def trip(self, oid, x, y, z, activates, size=(0.05, 0.20, 0.09)):
        """Invisible tall trip volume.

        Tall on purpose: toppling dominoes lean on their neighbours instead of
        lying flat, so a floor-height pad sits underneath the whole chain and
        is never touched.
        """
        self.add(oid, None, pos=(x, y, z), shape="box", size=list(size),
                 sensor=True,
                 device={"type": "button", "minImpulse": 0.0,
                         "activates": activates})
        return oid

    def breakable(self, oid, model, x, z=0.0, debris=4, threshold=0.10,
                  flavour="block", activates=None, y=None):
        """A destructible plus its pooled debris, hidden until it shatters."""
        pieces = []
        for i in range(debris):
            pid = f"{oid}_p{i}"
            self.add(pid, f"debris_{flavour if flavour != 'glass' else 'glass'}",
                     kind="dynamic",
                     pos=(x + (i % 2) * 0.09 - 0.045,
                          0.05 + (i // 2) * 0.10, z + (i % 3) * 0.06 - 0.06),
                     shape="box", mass=0.05, friction=0.5, restitution=0.1,
                     hidden=True, tag="debris")
            pieces.append(pid)
        self.add(oid, model, kind="dynamic",
                 pos=(x, rest_y(model) if y is None else y, z), shape="box",
                 mass=1.4, friction=0.6, restitution=0.02, tag="breakable",
                 device={"type": "breakable", "threshold": threshold,
                         "flavour": flavour, "debris": pieces,
                         "activates": activates or []})
        return oid, pieces

    def nudge(self, oid, x, y, z, target, impulse, startable=False):
        """An invisible controlled hand-off. Used where a purely physical
        transfer would be knife-edge."""
        self.add(oid, None, pos=(x, y, z), shape="none",
                 starter=startable,
                 device={"type": "nudge", "target": target,
                         "impulse": list(impulse), "startable": startable})
        return oid

    # ---------------------------------------------------------------- output
    def save(self):
        os.makedirs(LEVELS_OUT, exist_ok=True)
        if not self.data["goal"]:
            raise ValueError(f"{self.data['id']}: no goal set")
        path = os.path.join(LEVELS_OUT, f"{self.data['id']}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.data, f, separators=(",", ":"))
        return path
