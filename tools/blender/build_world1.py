"""World 1 "Toy Street" kit, plus the shared trigger/ramp/target pieces that
every later world reuses.

Same rules as the hero kit: chunky low-poly, gentle bevels, solid palette
colours, forward is +X.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toykit as tk  # noqa: E402

R = math.radians


# ================================================================= triggers
def build_triggers():
    # Large push button: the workhorse finish trigger.
    base = tk.cyl("pb_base", radius=0.145, depth=0.055, verts=12, colour="grey")
    ring = tk.cyl("pb_ring", radius=0.125, depth=0.075, verts=12, loc=(0, 0, 0.02),
                  colour="white")
    cap = tk.cyl("pb_cap", radius=0.105, depth=0.085, verts=12, loc=(0, 0, 0.052),
                 colour="red")
    o = tk.join([base, ring, cap], "push_button")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "push_button", collider="box",
              purpose="Large push button. Latches once when struck; the standard finish trigger.")

    # Pressure plate: flat, wide, easy to land on.
    p = tk.box("pp_plate", size=(0.34, 0.34, 0.030), colour="yellow")
    frame = tk.box("pp_frame", size=(0.40, 0.40, 0.018), loc=(0, 0, -0.020), colour="grey")
    o = tk.join([p, frame], "pressure_plate")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "pressure_plate", collider="box",
              purpose="Wide pressure plate. Triggers on any weight landing on it.")

    # Lever: a post with a swinging arm.
    post = tk.box("lv_post", size=(0.07, 0.07, 0.22), colour="grey_deep")
    arm = tk.box("lv_arm", size=(0.26, 0.055, 0.045), loc=(0.09, 0, 0.115),
                 rot=(0, R(-22), 0), colour="red")
    knob = tk.ico("lv_knob", radius=0.045, subdiv=1, loc=(0.20, 0, 0.155), colour="yellow")
    o = tk.join([post, arm, knob], "lever")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "lever", collider="box", purpose="Lever. Knocked over to trigger a chain.")

    # Rotating handle / valve wheel.
    hub = tk.cyl("rh_hub", radius=0.045, depth=0.07, verts=10, rot=(0, R(90), 0),
                 colour="grey_deep")
    rim = tk.torus("rh_rim", major=0.115, minor=0.022, major_segs=12, minor_segs=6,
                   rot=(0, R(90), 0), colour="blue")
    spokes = []
    for i in range(3):
        spokes.append(tk.box(f"rh_s{i}", size=(0.030, 0.215, 0.030),
                             rot=(R(i * 60), R(90), 0), colour="blue_light"))
    o = tk.join([hub, rim] + spokes, "rotating_handle")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "rotating_handle", collider="cylinder",
              purpose="Valve-style handle. Spun by a passing object to open a gate.")

    # Pull switch: hanging cord with a ball.
    plate = tk.box("ps_plate", size=(0.14, 0.14, 0.035), loc=(0, 0, 0.30), colour="grey")
    cord = tk.cyl("ps_cord", radius=0.010, depth=0.24, verts=6, loc=(0, 0, 0.16),
                  colour="grey_deep")
    ball = tk.ico("ps_ball", radius=0.045, subdiv=1, loc=(0, 0, 0.03), colour="orange")
    o = tk.join([plate, cord, ball], "pull_switch")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "pull_switch", collider="box",
              purpose="Hanging pull switch. Triggered by something swinging into the ball.")

    # Spring trigger / launcher pad.
    pad = tk.box("sp_pad", size=(0.22, 0.22, 0.030), loc=(0, 0, 0.115), colour="red")
    coils = []
    for i in range(4):
        coils.append(tk.torus(f"sp_c{i}", major=0.075, minor=0.017,
                              major_segs=10, minor_segs=5,
                              loc=(0, 0, 0.022 + i * 0.026), colour="grey_dark"))
    foot = tk.cyl("sp_foot", radius=0.115, depth=0.030, verts=12, colour="grey_deep")
    o = tk.join([pad, foot] + coils, "spring_launcher")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "spring_launcher", collider="box",
              purpose="Coiled spring pad. Launches whatever lands on it.")

    # Fuse starter.
    body = tk.cyl("fs_body", radius=0.075, depth=0.13, verts=10, colour="orange")
    wick = tk.cyl("fs_wick", radius=0.012, depth=0.10, verts=6, loc=(0, 0, 0.10),
                  rot=(0, R(20), 0), colour="fuse")
    spark = tk.ico("fs_spark", radius=0.028, subdiv=1, loc=(0.035, 0, 0.155), colour="yellow")
    o = tk.join([body, wick, spark], "fuse_starter")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "fuse_starter", collider="cylinder",
              purpose="Fuse starter. Tappable ignition point for a timed chain.")

    # Launch button: bigger, green, unmistakably 'go'.
    base = tk.cyl("lb_base", radius=0.17, depth=0.06, verts=12, colour="white")
    cap = tk.cyl("lb_cap", radius=0.135, depth=0.10, verts=12, loc=(0, 0, 0.055),
                 colour="green")
    arrow = tk.cone("lb_arrow", r1=0.06, r2=0.0, depth=0.07, verts=8, loc=(0, 0, 0.135),
                    colour="white")
    o = tk.join([base, cap, arrow], "launch_button")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "launch_button", collider="box",
              purpose="Green launch button. Primary tappable starter in later worlds.")

    # Fan switch and magnetic trigger share a compact wall-box silhouette.
    for slug, col, mark_col, purpose in (
        ("fan_switch", "cyan", "white", "Switch that turns a fan on."),
        ("magnetic_trigger", "purple", "white", "Switch that energises a magnet."),
    ):
        box = tk.box(f"{slug}_b", size=(0.13, 0.10, 0.17), colour=col)
        toggle = tk.box(f"{slug}_t", size=(0.05, 0.075, 0.075), loc=(0.075, 0, 0.030),
                        rot=(0, R(-18), 0), colour=mark_col)
        o = tk.join([box, toggle], slug)
        tk.bevel(o, width=0.006, segments=1, angle=32)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose)


# ==================================================================== ramps
def _ramp(slug, length, width, rise, colour, purpose, thickness=0.045):
    """A wedge: a tilted deck on a triangular support so it reads as solid."""
    angle = math.atan2(rise, length)
    deck_len = math.hypot(length, rise)
    deck = tk.box(f"{slug}_d", size=(deck_len, width, thickness),
                  rot=(0, -angle, 0), colour=colour)
    # Side skirts fill the wedge underneath.
    skirt = tk.box(f"{slug}_s", size=(length * 0.96, width * 0.92, rise * 0.9),
                   loc=(-0.01, 0, -rise * 0.5 - thickness * 0.2), colour=colour)
    lip = tk.box(f"{slug}_l", size=(0.05, width, 0.030),
                 loc=(length * 0.5, 0, -rise * 0.5), colour="white")
    o = tk.join([deck, skirt, lip], slug)
    tk.bevel(o, width=0.006, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, slug, collider="box", purpose=purpose,
              extra={"rise": rise, "run": length, "angleDeg": round(math.degrees(angle), 2)})
    return o


def build_ramps():
    _ramp("ramp_short", 0.62, 0.34, 0.20, "blue", "Short ramp. Gets a roller moving.")
    _ramp("ramp_long", 1.15, 0.34, 0.34, "blue", "Long ramp for a longer run-up.")
    _ramp("ramp_steep", 0.55, 0.34, 0.38, "blue_dark", "Steep ramp for a fast drop.")
    _ramp("ramp_gentle", 1.20, 0.40, 0.16, "blue_light",
          "Gentle ramp. Keeps a car rolling without launching it.")

    # Curved ramp: chained segments turning through 60 degrees.
    segs = []
    ang = 0.0
    x, y = 0.0, 0.0
    for i in range(6):
        s = tk.box(f"cr_{i}", size=(0.24, 0.32, 0.04), loc=(x, y, -i * 0.045),
                   rot=(0, R(-9), ang), colour="blue")
        segs.append(s)
        ang += R(11)
        x += math.cos(ang) * 0.21
        y += math.sin(ang) * 0.21
    o = tk.join(segs, "ramp_curved")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "ramp_curved", collider="box",
              purpose="Curved ramp. Bends a rolling path sideways.")

    # Spiral ramp.
    segs = []
    for i in range(14):
        a = R(i * 26)
        segs.append(tk.box(f"sr_{i}", size=(0.26, 0.20, 0.035),
                           loc=(math.cos(a) * 0.34, math.sin(a) * 0.34, 0.42 - i * 0.030),
                           rot=(R(9), 0, a + R(90)), colour="blue"))
    post = tk.cyl("sr_post", radius=0.055, depth=0.50, verts=10, loc=(0, 0, 0.10),
                  colour="grey")
    o = tk.join(segs + [post], "ramp_spiral")
    tk.bevel(o, width=0.004, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "ramp_spiral", collider="box",
              purpose="Spiral ramp. Drops a ball through a full turn.")

    # Narrow beam and launch track.
    o = tk.box("narrow_beam", size=(1.05, 0.09, 0.05), colour="yellow")
    tk.bevel(o, width=0.006, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "narrow_beam", collider="box",
              purpose="Narrow beam. A precise path a ball must stay on.")

    floor = tk.box("lt_f", size=(0.90, 0.24, 0.035), colour="grey")
    l1 = tk.box("lt_l", size=(0.90, 0.030, 0.075), loc=(0, 0.105, 0.050), colour="red")
    l2 = tk.box("lt_r", size=(0.90, 0.030, 0.075), loc=(0, -0.105, 0.050), colour="red")
    o = tk.join([floor, l1, l2], "launch_track")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "launch_track", collider="box",
              purpose="Guided launch track with side rails.")

    # Flat platforms used for tilting / rotating / lifting.
    for slug, size, col, purpose in (
        ("platform_small", (0.42, 0.42, 0.05), "green", "Small platform. Tilts or rises."),
        ("platform_wide", (0.85, 0.42, 0.05), "green", "Wide platform for seesaws and lifts."),
        ("platform_long", (1.20, 0.30, 0.05), "green_dark", "Long platform / bridge deck."),
    ):
        o = tk.box(slug, size=size, colour=col)
        tk.bevel(o, width=0.007, segments=1, angle=34)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose)

    # Seesaw: deck plus a visible fulcrum.
    deck = tk.box("ss_d", size=(0.95, 0.28, 0.05), loc=(0, 0, 0.115), colour="orange")
    piv = tk.cone("ss_p", r1=0.14, r2=0.05, depth=0.19, verts=6, loc=(0, 0, 0.0),
                  colour="grey_deep")
    o = tk.join([deck, piv], "seesaw")
    tk.bevel(o, width=0.006, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "seesaw", collider="box",
              purpose="Seesaw. Deck is a separate hinged body in levels that tilt it.")

    o = tk.box("seesaw_deck", size=(0.95, 0.28, 0.05), colour="orange")
    tk.bevel(o, width=0.006, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "seesaw_deck", collider="box",
              purpose="Seesaw deck alone, for hinged setups.")

    o = tk.cone("seesaw_pivot", r1=0.14, r2=0.05, depth=0.19, verts=6, colour="grey_deep")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "seesaw_pivot", collider="box", purpose="Seesaw fulcrum.")

    # Trapdoor and conveyor.
    frame = tk.box("td_f", size=(0.50, 0.50, 0.030), colour="grey_deep")
    leaf = tk.box("td_l", size=(0.44, 0.44, 0.028), loc=(0, 0, 0.028), colour="red")
    o = tk.join([frame, leaf], "trapdoor")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "trapdoor", collider="box", purpose="Trapdoor. Drops away when triggered.")

    belt = tk.box("cv_b", size=(1.10, 0.36, 0.055), colour="grey_deep")
    rollers = []
    for sx in (-0.53, 0.53):
        rollers.append(tk.cyl(f"cv_r{sx}", radius=0.048, depth=0.38, verts=10,
                              loc=(sx, 0, 0), rot=(R(90), 0, 0), colour="yellow"))
    legs = []
    for sx in (-0.44, 0.44):
        legs.append(tk.box(f"cv_l{sx}", size=(0.06, 0.30, 0.16), loc=(sx, 0, -0.105),
                           colour="blue"))
    o = tk.join([belt] + rollers + legs, "conveyor")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "conveyor", collider="box",
              purpose="Conveyor belt. Carries objects along its surface.")

    # Bridges.
    deck = tk.box("db_d", size=(0.80, 0.34, 0.045), colour="wood")
    for i in range(4):
        tk.box(f"db_p{i}", size=(0.035, 0.34, 0.012), loc=(-0.30 + i * 0.20, 0, 0.028),
               colour="wood")
    planks = [o for o in __import__("bpy").data.objects if o.name.startswith("db_p")]
    o = tk.join([deck] + planks, "drawbridge")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "drawbridge", collider="box",
              purpose="Drawbridge leaf. Rotates up or down to open a path.")

    deck = tk.box("cb_d", size=(0.95, 0.32, 0.040), colour="orange")
    p1 = tk.box("cb_1", size=(0.06, 0.32, 0.20), loc=(-0.44, 0, -0.12), colour="grey")
    p2 = tk.box("cb_2", size=(0.06, 0.32, 0.20), loc=(0.44, 0, -0.12), colour="grey")
    o = tk.join([deck, p1, p2], "collapsible_bridge")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "collapsible_bridge", collider="box",
              purpose="Bridge that gives way under enough weight.")

    ropes = []
    for sy in (0.16, -0.16):
        ropes.append(tk.cyl(f"rb_r{sy}", radius=0.012, depth=1.00, verts=6,
                            loc=(0, sy, 0.14), rot=(0, R(90), 0), colour="wood"))
    slats = []
    for i in range(7):
        slats.append(tk.box(f"rb_s{i}", size=(0.075, 0.30, 0.022),
                            loc=(-0.42 + i * 0.14, 0, 0), colour="yellow"))
    o = tk.join(ropes + slats, "rope_bridge")
    tk.bevel(o, width=0.004, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "rope_bridge", collider="box", purpose="Rope-slat toy bridge.")


# ============================================================ final targets
def build_targets():
    # Flag launcher: the vertical-slice finish. Pole and flag export
    # separately so the flag can rise on cue.
    base = tk.cyl("fl_base", radius=0.19, depth=0.065, verts=12, colour="white")
    ring = tk.cyl("fl_ring", radius=0.145, depth=0.040, verts=12, loc=(0, 0, 0.048),
                  colour="red")
    pole = tk.cyl("fl_pole", radius=0.022, depth=0.62, verts=8, loc=(0, 0, 0.35),
                  colour="grey_deep")
    o = tk.join([base, ring, pole], "flag_base")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "flag_base", collider="box",
              purpose="Flag pole and base. Static half of the flag target.")

    cloth = tk.box("fg_c", size=(0.030, 0.26, 0.17), loc=(0, 0.13, 0), colour="red")
    tip = tk.cone("fg_t", r1=0.085, r2=0.0, depth=0.11, verts=4, loc=(0, 0.26, 0),
                  rot=(R(-90), 0, 0), colour="red")
    o = tk.join([cloth, tip], "flag_cloth")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "flag_cloth", collider="none",
              purpose="Flag itself. Slides up the pole when the level is won.")

    # Bell.
    dome = tk.cone("bl_d", r1=0.17, r2=0.075, depth=0.24, verts=12, colour="yellow")
    lip = tk.torus("bl_l", major=0.165, minor=0.028, major_segs=12, minor_segs=6,
                   loc=(0, 0, -0.115), colour="yellow_dark")
    top = tk.torus("bl_t", major=0.045, minor=0.016, major_segs=8, minor_segs=5,
                   loc=(0, 0, 0.14), rot=(R(90), 0, 0), colour="orange")
    o = tk.join([dome, lip, top], "bell")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "bell", collider="box", purpose="Large bell. Rings when struck.")

    # Treasure chest: base and lid separate so it can open.
    body = tk.box("tc_b", size=(0.36, 0.26, 0.20), colour="wood")
    b1 = tk.box("tc_b1", size=(0.38, 0.045, 0.21), loc=(0, 0.10, 0), colour="yellow")
    b2 = tk.box("tc_b2", size=(0.38, 0.045, 0.21), loc=(0, -0.10, 0), colour="yellow")
    lock = tk.box("tc_lk", size=(0.030, 0.075, 0.075), loc=(0.19, 0, 0.02), colour="yellow")
    o = tk.join([body, b1, b2, lock], "chest_base")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "chest_base", collider="box", purpose="Treasure chest body.")

    lid = tk.cyl("tc_l", radius=0.135, depth=0.36, verts=10, rot=(0, R(90), 0),
                 colour="wood", scale=(1, 1, 1))
    band = tk.cyl("tc_lb", radius=0.140, depth=0.045, verts=10, rot=(0, R(90), 0),
                  colour="yellow")
    o = tk.join([lid, band], "chest_lid")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "chest_lid", collider="box",
              purpose="Chest lid. Hinges open on completion.")

    # Fireworks box and celebration machine.
    crate = tk.box("fw_c", size=(0.30, 0.30, 0.26), colour="red")
    for i, col in enumerate(("yellow", "blue", "green")):
        tk.cyl(f"fw_t{i}", radius=0.045, depth=0.22, verts=8,
               loc=(-0.08 + i * 0.08, 0, 0.20), colour=col)
    tubes = [o for o in __import__("bpy").data.objects if o.name.startswith("fw_t")]
    o = tk.join([crate] + tubes, "fireworks_box")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "fireworks_box", collider="box",
              purpose="Fireworks box. Fires celebration bursts on completion.")

    body = tk.box("cm_b", size=(0.42, 0.34, 0.30), colour="blue")
    funnel = tk.cone("cm_f", r1=0.075, r2=0.155, depth=0.20, verts=10, loc=(0, 0, 0.24),
                     colour="yellow")
    knob = tk.ico("cm_k", radius=0.05, subdiv=1, loc=(0.17, 0, 0.20), colour="red")
    o = tk.join([body, funnel, knob], "celebration_machine")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "celebration_machine", collider="box",
              purpose="Confetti machine. Primary celebration target.")

    # Finish tower and city beacon.
    tiers = []
    for i, (w, col) in enumerate(((0.34, "red"), (0.28, "blue"), (0.22, "yellow"))):
        tiers.append(tk.box(f"ft_{i}", size=(w, w, 0.24), loc=(0, 0, 0.12 + i * 0.245),
                            colour=col))
    cap = tk.cone("ft_c", r1=0.13, r2=0.0, depth=0.20, verts=6, loc=(0, 0, 0.82),
                  colour="green")
    o = tk.join(tiers + [cap], "finish_tower")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "finish_tower", collider="box",
              purpose="Finish tower landmark. Large, unmistakable final target.")

    base = tk.cyl("cbn_b", radius=0.17, depth=0.30, verts=10, colour="white")
    mid = tk.cyl("cbn_m", radius=0.115, depth=0.26, verts=10, loc=(0, 0, 0.27),
                 colour="red")
    lamp = tk.ico("cbn_l", radius=0.115, subdiv=1, loc=(0, 0, 0.47), colour="yellow")
    o = tk.join([base, mid, lamp], "city_beacon")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "city_beacon", collider="box",
              purpose="City beacon. Lights up when the chain completes.")


# ============================================================ street dressing
def build_street():
    # Road tiles.
    for slug, size, purpose in (
        ("road_straight", (1.20, 0.70, 0.022), "Straight road tile."),
        ("road_wide", (1.20, 1.10, 0.022), "Wide road tile / plaza."),
    ):
        base = tk.box(f"{slug}_b", size=size, colour="grey")
        marks = []
        n = 4
        for i in range(n):
            marks.append(tk.box(f"{slug}_m{i}",
                                size=(0.16, 0.030, 0.006),
                                loc=(-size[0] / 2 + 0.20 + i * (size[0] - 0.40) / max(1, n - 1), 0, 0.014),
                                colour="white"))
        o = tk.join([base] + marks, slug)
        tk.bevel(o, width=0.004, segments=1, angle=40)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose)

    # Traffic barrier.
    plank = tk.box("tb_p", size=(0.52, 0.055, 0.11), loc=(0, 0, 0.145), colour="white")
    s1 = tk.box("tb_s1", size=(0.10, 0.055, 0.11), loc=(-0.16, 0, 0.145), colour="red")
    s2 = tk.box("tb_s2", size=(0.10, 0.055, 0.11), loc=(0.16, 0, 0.145), colour="red")
    l1 = tk.box("tb_l1", size=(0.055, 0.12, 0.20), loc=(-0.21, 0, 0.05), colour="red")
    l2 = tk.box("tb_l2", size=(0.055, 0.12, 0.20), loc=(0.21, 0, 0.05), colour="red")
    o = tk.join([plank, s1, s2, l1, l2], "traffic_barrier")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "traffic_barrier", collider="box",
              purpose="Traffic barrier. Blocks or is knocked aside.")

    # Cone.
    body = tk.cone("tc_b", r1=0.085, r2=0.022, depth=0.22, verts=10, loc=(0, 0, 0.12),
                   colour="orange")
    band = tk.cyl("tc_bd", radius=0.062, depth=0.035, verts=10, loc=(0, 0, 0.145),
                  colour="white")
    foot = tk.box("tc_f", size=(0.17, 0.17, 0.022), colour="orange")
    o = tk.join([body, band, foot], "traffic_cone")
    tk.bevel(o, width=0.004, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "traffic_cone", collider="box", purpose="Traffic cone. Light scatter prop.")

    # Street sign.
    post = tk.cyl("sg_p", radius=0.018, depth=0.42, verts=6, loc=(0, 0, 0.21),
                  colour="grey_deep")
    face = tk.box("sg_f", size=(0.020, 0.24, 0.17), loc=(0, 0, 0.46), colour="blue")
    o = tk.join([post, face], "street_sign")
    tk.bevel(o, width=0.004, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "street_sign", collider="box", purpose="Street sign. Scenery and light obstacle.")

    # Lamp post.
    post = tk.cyl("lp_p", radius=0.024, depth=0.66, verts=8, loc=(0, 0, 0.33),
                  colour="grey_deep")
    arm = tk.box("lp_a", size=(0.16, 0.045, 0.040), loc=(0.07, 0, 0.665), colour="grey_deep")
    head = tk.ico("lp_h", radius=0.058, subdiv=1, loc=(0.14, 0, 0.645), colour="yellow_light")
    foot = tk.cyl("lp_f", radius=0.065, depth=0.045, verts=8, colour="grey_deep")
    o = tk.join([post, arm, head, foot], "lamp_post")
    tk.bevel(o, width=0.004, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "lamp_post", collider="box", purpose="Street lamp. Vertical scenery.")

    # Tree and bench for the park.
    trunk = tk.cyl("tr_t", radius=0.045, depth=0.26, verts=8, loc=(0, 0, 0.13),
                   colour="wood")
    c1 = tk.ico("tr_c1", radius=0.155, subdiv=1, loc=(0, 0, 0.36), colour="green")
    c2 = tk.ico("tr_c2", radius=0.115, subdiv=1, loc=(0.075, 0.05, 0.47), colour="green_light")
    o = tk.join([trunk, c1, c2], "park_tree")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "park_tree", collider="box", purpose="Park tree. Scenery.")

    seat = tk.box("bn_s", size=(0.36, 0.14, 0.030), loc=(0, 0, 0.11), colour="wood")
    back = tk.box("bn_b", size=(0.36, 0.030, 0.12), loc=(0, -0.055, 0.185), colour="wood")
    l1 = tk.box("bn_l1", size=(0.035, 0.13, 0.10), loc=(-0.15, 0, 0.05), colour="grey_deep")
    l2 = tk.box("bn_l2", size=(0.035, 0.13, 0.10), loc=(0.15, 0, 0.05), colour="grey_deep")
    o = tk.join([seat, back, l1, l2], "park_bench")
    tk.bevel(o, width=0.005, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "park_bench", collider="box", purpose="Park bench. Scenery.")

    # Pedestrian bridge.
    deck = tk.box("pbr_d", size=(1.00, 0.30, 0.040), loc=(0, 0, 0.40), colour="white")
    r1 = tk.box("pbr_r1", size=(1.00, 0.025, 0.085), loc=(0, 0.14, 0.47), colour="red")
    r2 = tk.box("pbr_r2", size=(1.00, 0.025, 0.085), loc=(0, -0.14, 0.47), colour="red")
    s1 = tk.box("pbr_s1", size=(0.30, 0.30, 0.040), loc=(-0.60, 0, 0.24), rot=(0, R(28), 0),
                colour="white")
    s2 = tk.box("pbr_s2", size=(0.30, 0.30, 0.040), loc=(0.60, 0, 0.24), rot=(0, R(-28), 0),
                colour="white")
    c1 = tk.box("pbr_c1", size=(0.07, 0.24, 0.40), loc=(-0.42, 0, 0.20), colour="grey")
    c2 = tk.box("pbr_c2", size=(0.07, 0.24, 0.40), loc=(0.42, 0, 0.20), colour="grey")
    o = tk.join([deck, r1, r2, s1, s2, c1, c2], "pedestrian_bridge")
    tk.bevel(o, width=0.006, segments=1, angle=34)
    tk.recentre(o)
    tk.export(o, "pedestrian_bridge", collider="box",
              purpose="Pedestrian bridge. Elevated path across a street.")

    # City buildings in three heights.
    for slug, h, col, purpose in (
        ("building_small", 0.55, "red", "Small toy building."),
        ("building_mid", 0.85, "blue", "Mid-height toy building."),
        ("building_tall", 1.25, "yellow", "Tall toy building landmark."),
    ):
        body = tk.box(f"{slug}_b", size=(0.42, 0.42, h), loc=(0, 0, h / 2), colour=col)
        wins = []
        rows = max(1, int(h / 0.26))
        for r in range(rows):
            for f in range(4):
                a = f * math.pi / 2
                nx, ny = math.cos(a), math.sin(a)
                for c in (-1, 1):
                    u = c * 0.10
                    wins.append(tk.box(
                        f"{slug}_w{r}{f}{c}",
                        size=(abs(nx) * 0.012 + abs(ny) * 0.075,
                              abs(ny) * 0.012 + abs(nx) * 0.075, 0.085),
                        loc=(nx * 0.208 - ny * u, ny * 0.208 + nx * u, 0.13 + r * 0.26),
                        colour="white"))
        roof = tk.box(f"{slug}_r", size=(0.46, 0.46, 0.045), loc=(0, 0, h + 0.02),
                      colour="green")
        o = tk.join([body, roof] + wins, slug)
        tk.bevel(o, width=0.009, segments=1, angle=34)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose)


def run():
    tk.reset_scene()
    build_triggers()
    build_ramps()
    build_targets()
    build_street()
    tk.save_blend("world1_kit")
    return tk.manifest_flush("world1_kit")
