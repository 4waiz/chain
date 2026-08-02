"""Hero asset kit — the models that define the game's visual identity.

Everything here is modelled to match `logo.png` directly: the light-blue
faceted cannon with its darker octagonal wheels, the chunky faceted yellow
cannonball, the four pip-faced dominoes, the stacked window blocks with the
green roof, the little yellow car, and the celebration capsules.

Orientation convention: assets that have a "forward" face **+X in Blender**,
which stays +X after the glTF Y-up conversion. Blender +Z becomes runtime +Y.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toykit as tk  # noqa: E402

R = math.radians


# =========================================================== blue toy cannon
def build_cannon():
    """Three parts, because the barrel recoils and the wheels turn."""

    # ---- barrel ---------------------------------------------------------
    # Faceted tube, slightly tapered, with a flared muzzle ring and a domed
    # breech. Pivot ends up at the trunnion so recoil is a pure -X slide and
    # aiming is a pure Y rotation.
    tube = tk.cyl("c_tube", radius=0.082, depth=0.34, verts=10,
                  loc=(0.02, 0, 0), rot=(0, R(90), 0), colour="cannon_body")
    muzzle = tk.cyl("c_muzzle", radius=0.099, depth=0.052, verts=10,
                    loc=(0.185, 0, 0), rot=(0, R(90), 0), colour="cannon_light")
    band = tk.cyl("c_band", radius=0.091, depth=0.030, verts=10,
                  loc=(0.06, 0, 0), rot=(0, R(90), 0), colour="cannon_light")
    breech = tk.ico("c_breech", radius=0.088, subdiv=1, loc=(-0.152, 0, 0),
                    colour="cannon_body")
    knob = tk.ico("c_knob", radius=0.034, subdiv=1, loc=(-0.222, 0, 0),
                  colour="cannon_mount")
    # Fuse: a stubby brown wick angled up out of the breech.
    fuse = tk.cyl("c_fuse", radius=0.014, depth=0.075, verts=6,
                  loc=(-0.145, 0, 0.085), rot=(0, R(-28), 0), colour="fuse")
    fuse_tip = tk.ico("c_fusetip", radius=0.020, subdiv=1,
                      loc=(-0.168, 0, 0.118), colour="red")

    barrel = tk.join([tube, muzzle, band, breech, knob, fuse, fuse_tip], "cannon_barrel")
    tk.bevel(barrel, width=0.006, segments=1, angle=32)
    tk.recentre(barrel)
    tk.export(barrel, "cannon_barrel", collider="box",
              purpose="Cannon barrel. Recoils on fire and rotates to aim.",
              extra={"pivot": "trunnion (bbox centre)", "forward": "+X"})

    # ---- carriage -------------------------------------------------------
    # Chunky darker-blue cradle plus the axle the wheels ride on.
    cradle = tk.box("cc_body", size=(0.24, 0.15, 0.095), loc=(-0.02, 0, -0.055),
                    colour="cannon_mount")
    front = tk.box("cc_front", size=(0.07, 0.13, 0.075), loc=(0.115, 0, -0.035),
                   colour="cannon_mount")
    tail = tk.box("cc_tail", size=(0.13, 0.075, 0.055), loc=(-0.175, 0, -0.085),
                  colour="cannon_wheel")
    axle = tk.cyl("cc_axle", radius=0.020, depth=0.24, verts=8,
                  loc=(-0.03, 0, -0.10), rot=(R(90), 0, 0), colour="cannon_wheel")
    carriage = tk.join([cradle, front, tail, axle], "cannon_carriage")
    tk.bevel(carriage, width=0.008, segments=1, angle=32)
    tk.recentre(carriage)
    tk.export(carriage, "cannon_carriage", collider="box",
              purpose="Cannon cradle and axle. Static body the barrel mounts to.",
              extra={"forward": "+X"})

    # ---- wheel ----------------------------------------------------------
    # Octagonal like the reference, with a raised hub and a bolt cap.
    rim = tk.cyl("cw_rim", radius=0.108, depth=0.042, verts=8,
                 rot=(R(90), 0, 0), colour="cannon_wheel")
    hub = tk.cyl("cw_hub", radius=0.045, depth=0.062, verts=8,
                 rot=(R(90), 0, 0), colour="cannon_mount")
    cap = tk.cyl("cw_cap", radius=0.020, depth=0.074, verts=6,
                 rot=(R(90), 0, 0), colour="cannon_light")
    wheel = tk.join([rim, hub, cap], "cannon_wheel")
    tk.bevel(wheel, width=0.005, segments=1, angle=32)
    tk.recentre(wheel)
    tk.export(wheel, "cannon_wheel", collider="cylinder",
              purpose="Cannon wheel. Instanced twice, spins about local Z.",
              extra={"spin_axis": "z"})


# =========================================================== yellow cannonball
def _ball(slug, radius, colour, subdiv, purpose):
    """Balls are deliberately *not* bevelled.

    An angle-limited bevel on an icosphere cuts every facet edge and shrinks
    the silhouette by ~10%, which would put the visual radius out of step with
    the sphere collider. The icosphere's own facets already give the chunky
    faceting the reference has, so the true radius is preserved instead.
    """
    o = tk.ico(slug, radius=radius, subdiv=subdiv, colour=colour)
    tk.recentre(o)
    # Icosphere circumradius is the requested radius; the inscribed radius is
    # smaller. Use the mean so rolling contact matches the silhouette.
    lo, hi = tk.bbox_local(o)
    effective = round(((hi.x - lo.x) + (hi.y - lo.y) + (hi.z - lo.z)) / 6.0, 4)
    tk.export(o, slug, collider="sphere", purpose=purpose,
              extra={"radius": effective})
    return o


def build_cannonball():
    """80-triangle icospheres.

    Blender's `subdivisions=1` is the bare 20-face icosahedron, which reads as
    a gem rather than a ball. `subdivisions=2` gives 80 faces: still obviously
    faceted at mobile size, matching the reference, and still trivially cheap.
    """
    _ball("cannonball", 0.075, "yellow", 2,
          "Primary projectile fired by the cannon. Sphere collider.")
    _ball("ball_heavy", 0.098, "grey_deep", 2,
          "Heavy ball. Higher mass, used to break barriers.")
    _ball("ball_small", 0.048, "red", 2,
          "Light ball for tight tracks and pinball-style bounces.")
    _ball("ball_crystal", 0.072, "cyan", 1,
          "Faceted crystal ball. Deliberately coarse - reads as cut crystal.")


# ================================================================= dominoes
def _domino(slug, colour, w=0.20, h=0.42, t=0.075, pips=3, purpose=""):
    """Thickness runs along X (the fall direction), width along Y, height Z.
    Pips go on both wide faces so the piece reads correctly from either side."""
    body = tk.box(f"{slug}_b", size=(t, w, h), colour=colour)
    parts = [body]

    if pips > 0:
        span = h * 0.62
        step = span / max(1, pips - 1) if pips > 1 else 0
        start = -span / 2 if pips > 1 else 0.0
        for i in range(pips):
            z = start + step * i
            for sx in (1, -1):
                d = tk.cyl(
                    f"{slug}_p{i}{sx}", radius=0.030, depth=0.014, verts=8,
                    loc=(sx * (t / 2 - 0.003), 0, z), rot=(0, R(90), 0),
                    colour="white",
                )
                parts.append(d)

    o = tk.join(parts, slug)
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, slug, collider="box", purpose=purpose,
              extra={"fall_axis": "+X"})
    return o


def build_dominoes():
    _domino("domino_red", "red", purpose="Standard domino, red.")
    _domino("domino_blue", "blue", purpose="Standard domino, blue.")
    _domino("domino_yellow", "yellow", purpose="Standard domino, yellow.")
    _domino("domino_green", "green", purpose="Standard domino, green.")
    _domino("domino_tall", "blue", w=0.20, h=0.62, t=0.075, pips=4,
            purpose="Tall domino. Longer reach, slower topple.")
    _domino("domino_wide", "green", w=0.32, h=0.42, t=0.075, pips=3,
            purpose="Wide domino. Can push two neighbours at once.")
    _domino("domino_heavy", "grey_deep", w=0.24, h=0.44, t=0.12, pips=2,
            purpose="Weighted domino. High mass, needs a strong hit.")
    _domino("domino_split", "orange", w=0.30, h=0.40, t=0.070, pips=2,
            purpose="Split domino. Seeds two branches of a chain.")

    # Curved-chain variant: a wedge-shaped piece that redirects a run.
    body = tk.box("dc_b", size=(0.075, 0.22, 0.42), colour="purple")
    wedge = tk.box("dc_w", size=(0.075, 0.10, 0.42), loc=(0.0, 0.145, 0.0),
                   rot=(R(14), 0, 0), colour="purple")
    o = tk.join([body, wedge], "domino_curved")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "domino_curved", collider="box",
              purpose="Curved-chain domino. Angled face turns a run by ~20 degrees.")

    # Bridge domino: spans a gap so a chain can cross it.
    deck = tk.box("db_d", size=(0.46, 0.20, 0.045), colour="wood")
    l1 = tk.box("db_l1", size=(0.05, 0.20, 0.16), loc=(-0.19, 0, -0.10), colour="wood")
    l2 = tk.box("db_l2", size=(0.05, 0.20, 0.16), loc=(0.19, 0, -0.10), colour="wood")
    o = tk.join([deck, l1, l2], "domino_bridge")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "domino_bridge", collider="box",
              purpose="Bridge piece a domino run crosses.")


# ================================================================ toy car
def build_car():
    """Chunky compact body, oversized wheels, white bumpers — straight from
    the reference. Body and wheels export separately so the wheels roll."""
    body = tk.box("car_lower", size=(0.34, 0.20, 0.105), loc=(0, 0, 0.028),
                  colour="yellow")
    cabin = tk.box("car_cabin", size=(0.185, 0.185, 0.095), loc=(-0.012, 0, 0.122),
                   colour="yellow")

    # Windows: thin white slabs proud of the cabin on all four sides.
    wf = tk.box("car_wf", size=(0.012, 0.150, 0.058), loc=(0.078, 0, 0.128),
                colour="white")
    wb = tk.box("car_wb", size=(0.012, 0.150, 0.058), loc=(-0.102, 0, 0.128),
                colour="white")
    wl = tk.box("car_wl", size=(0.140, 0.012, 0.058), loc=(-0.012, 0.090, 0.128),
                colour="white")
    wr = tk.box("car_wr", size=(0.140, 0.012, 0.058), loc=(-0.012, -0.090, 0.128),
                colour="white")

    bf = tk.box("car_bf", size=(0.028, 0.205, 0.048), loc=(0.176, 0, 0.010),
                colour="off_white")
    bb = tk.box("car_bb", size=(0.028, 0.205, 0.048), loc=(-0.176, 0, 0.010),
                colour="off_white")
    # Headlights
    hl = tk.cyl("car_hl", radius=0.020, depth=0.014, verts=8,
                loc=(0.190, 0.062, 0.045), rot=(0, R(90), 0), colour="yellow_light")
    hr = tk.cyl("car_hr", radius=0.020, depth=0.014, verts=8,
                loc=(0.190, -0.062, 0.045), rot=(0, R(90), 0), colour="yellow_light")

    o = tk.join([body, cabin, wf, wb, wl, wr, bf, bb, hl, hr], "toy_car_body")
    tk.bevel(o, width=0.010, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_car_body", collider="box",
              purpose="Yellow toy car body. Rolls down ramps, presses buttons.",
              extra={"forward": "+X", "wheel_offsets": [
                  [0.105, -0.052, 0.105], [0.105, -0.052, -0.105],
                  [-0.105, -0.052, 0.105], [-0.105, -0.052, -0.105]]})

    tyre = tk.cyl("cw_t", radius=0.058, depth=0.040, verts=10,
                  rot=(R(90), 0, 0), colour="tyre")
    hub = tk.cyl("cw_h", radius=0.026, depth=0.048, verts=8,
                 rot=(R(90), 0, 0), colour="off_white")
    w = tk.join([tyre, hub], "toy_car_wheel")
    tk.bevel(w, width=0.004, segments=1, angle=32)
    tk.recentre(w)
    tk.export(w, "toy_car_wheel", collider="cylinder",
              purpose="Toy car wheel. Instanced four times, spins about local Z.",
              extra={"spin_axis": "z", "radius": 0.058})


# ========================================================== building blocks
def _window_block(slug, colour, size=0.26, rows=1, cols=2, purpose=""):
    """A cube with white window slabs on all four faces, exactly like the
    stacked buildings in the reference."""
    half = size / 2
    body = tk.box(f"{slug}_b", size=(size, size, size), colour=colour)
    parts = [body]

    ww = size * 0.20
    wh = size * 0.30
    for face in range(4):
        ang = face * math.pi / 2
        nx, ny = math.cos(ang), math.sin(ang)
        for r in range(rows):
            for c in range(cols):
                u = (c - (cols - 1) / 2) * (size * 0.34)
                v = (r - (rows - 1) / 2) * (size * 0.40)
                px = nx * (half - 0.004) - ny * u
                py = ny * (half - 0.004) + nx * u
                w = tk.box(
                    f"{slug}_w{face}{r}{c}",
                    size=(abs(nx) * 0.012 + abs(ny) * ww, abs(ny) * 0.012 + abs(nx) * ww, wh),
                    loc=(px, py, v),
                    colour="white",
                )
                parts.append(w)

    o = tk.join(parts, slug)
    tk.bevel(o, width=0.011, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, slug, collider="box", purpose=purpose)
    return o


def build_blocks():
    _window_block("block_red", "red", purpose="Stackable building block, red.")
    _window_block("block_blue", "blue", purpose="Stackable building block, blue.")
    _window_block("block_green", "green", purpose="Stackable building block, green.")
    _window_block("block_yellow", "yellow", purpose="Stackable building block, yellow.")

    # Plain stackable cube (no windows) for towers and walls.
    for name, col in (("cube_red", "red"), ("cube_blue", "blue"),
                      ("cube_yellow", "yellow"), ("cube_green", "green")):
        c = tk.box(name, size=(0.26, 0.26, 0.26), colour=col)
        tk.bevel(c, width=0.014, segments=2, angle=32)
        tk.recentre(c)
        tk.export(c, name, collider="box", purpose=f"Plain stackable cube, {col}.")

    # Green roof cap: the flat-topped pyramid that finishes the tower in the logo.
    slab = tk.box("roof_slab", size=(0.30, 0.30, 0.045), loc=(0, 0, -0.055),
                  colour="green")
    cap = tk.cone("roof_cap", r1=0.145, r2=0.105, depth=0.085, verts=4,
                  loc=(0, 0, 0.010), rot=(0, 0, R(45)), colour="green")
    top = tk.box("roof_top", size=(0.155, 0.155, 0.022), loc=(0, 0, 0.062),
                 colour="green_light")
    o = tk.join([slab, cap, top], "block_roof")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "block_roof", collider="box",
              purpose="Green roof cap that tops a block tower.")

    # Tower section: three blocks pre-stacked, for tall set pieces.
    a = tk.box("ts_a", size=(0.26, 0.26, 0.26), loc=(0, 0, -0.27), colour="red")
    b = tk.box("ts_b", size=(0.26, 0.26, 0.26), loc=(0, 0, 0.0), colour="blue")
    c = tk.box("ts_c", size=(0.26, 0.26, 0.26), loc=(0, 0, 0.27), colour="yellow")
    o = tk.join([a, b, c], "block_tower_section")
    tk.bevel(o, width=0.012, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "block_tower_section", collider="box",
              purpose="Pre-stacked three-high tower section for large set pieces.")


# ======================================================= celebration pieces
def build_celebration():
    """The bouncing capsules, stars, confetti and reward pieces that fill the
    screen when a level completes."""
    for name, col in (
        ("capsule_yellow", "yellow"), ("capsule_green", "green"),
        ("capsule_blue", "blue"), ("capsule_red", "red"),
        ("capsule_orange", "orange"), ("capsule_purple", "purple"),
    ):
        c = tk.capsule(name, radius=0.036, length=0.070, verts=8, colour=col)
        tk.recentre(c)
        tk.export(c, name, collider="capsule",
                  purpose="Celebration capsule. Pooled, spawned on level complete.",
                  extra={"radius": 0.036})

    # Two-tone capsule, like the split-colour pieces in the logo.
    a = tk.cyl("tc_a", radius=0.036, depth=0.035, verts=8, loc=(0, 0, 0.0175),
               colour="blue")
    a2 = tk.ico("tc_a2", radius=0.036, subdiv=1, loc=(0, 0, 0.035), colour="blue")
    b = tk.cyl("tc_b", radius=0.036, depth=0.035, verts=8, loc=(0, 0, -0.0175),
               colour="red")
    b2 = tk.ico("tc_b2", radius=0.036, subdiv=1, loc=(0, 0, -0.035), colour="red")
    o = tk.join([a, a2, b, b2], "capsule_duo")
    tk.recentre(o)
    tk.export(o, "capsule_duo", collider="capsule",
              purpose="Two-tone celebration capsule.", extra={"radius": 0.036})

    # Five-point star.
    pts = []
    for i in range(5):
        ang = R(90) + i * R(72)
        pts.append(tk.box(f"st_{i}", size=(0.030, 0.086, 0.020),
                          loc=(math.cos(ang) * 0.040, math.sin(ang) * 0.040, 0),
                          rot=(0, 0, ang - R(90)), colour="yellow"))
    core = tk.cyl("st_c", radius=0.036, depth=0.020, verts=10, colour="yellow")
    o = tk.join(pts + [core], "star")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "star", collider="box",
              purpose="Star reward piece. Used in HUD bursts and the results screen.")

    # Confetti strip.
    s = tk.box("confetti", size=(0.048, 0.014, 0.004), colour="white")
    tk.bevel(s, width=0.0015, segments=1, angle=32)
    tk.recentre(s)
    tk.export(s, "confetti", collider="none",
              purpose="Confetti strip. Recoloured per instance from the palette.")

    # Coin.
    c = tk.cyl("coin", radius=0.052, depth=0.014, verts=12, colour="yellow")
    inner = tk.cyl("coin_i", radius=0.034, depth=0.019, verts=12, colour="yellow_light")
    o = tk.join([c, inner], "coin")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "coin", collider="cylinder", purpose="Coin pickup and reward piece.")


def run():
    tk.reset_scene()
    build_cannon()
    build_cannonball()
    build_dominoes()
    build_car()
    build_blocks()
    build_celebration()
    tk.save_blend("hero_kit")
    return tk.manifest_flush("hero_kit")
