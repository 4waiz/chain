"""Remaining reaction asset kits: mechanical, air, water, electrical,
destructible, vehicles and the world 2-5 environment dressing.

Same art rules throughout — chunky low-poly, gentle bevels, solid palette
colours, forward is +X.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toykit as tk  # noqa: E402

R = math.radians


def _named(prefix):
    return [o for o in bpy.data.objects if o.name.startswith(prefix)]


# ============================================================ moving objects
def build_movers():
    o = tk.cyl("roll_cylinder", radius=0.085, depth=0.30, verts=12,
               rot=(R(90), 0, 0), colour="orange")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "roll_cylinder", collider="box",
              purpose="Rolling cylinder. Travels along its side.")

    body = tk.cyl("br_b", radius=0.115, depth=0.26, verts=12, rot=(R(90), 0, 0),
                  colour="wood")
    for i, sy in enumerate((-0.08, 0.0, 0.08)):
        tk.torus(f"br_h{i}", major=0.121, minor=0.014, major_segs=12, minor_segs=5,
                 loc=(0, sy, 0), rot=(R(90), 0, 0), colour="grey_deep")
    o = tk.join([body] + _named("br_h"), "toy_barrel")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_barrel", collider="box", purpose="Wooden-style toy barrel.")

    body = tk.box("cr_b", size=(0.26, 0.26, 0.26), colour="wood")
    for i, (sx, sy) in enumerate(((0.132, 0), (-0.132, 0), (0, 0.132), (0, -0.132))):
        tk.box(f"cr_p{i}", size=(0.012 if sx else 0.24, 0.012 if sy else 0.24, 0.05),
               loc=(sx, sy, 0.07), colour="yellow_dark")
    o = tk.join([body] + _named("cr_p"), "sliding_crate")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "sliding_crate", collider="box",
              purpose="Sliding crate. Pushed along conveyors and floors.")

    tub = tk.box("dc_t", size=(0.34, 0.24, 0.16), loc=(0, 0, 0.14), colour="red")
    base = tk.box("dc_b", size=(0.36, 0.26, 0.03), loc=(0, 0, 0.05), colour="grey_deep")
    o = tk.join([tub, base], "delivery_cart")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "delivery_cart", collider="box",
              purpose="Open toy cart. Carries a payload along a track.",
              extra={"wheel_offsets": [[0.12, -0.07, 0.13], [0.12, -0.07, -0.13],
                                       [-0.12, -0.07, 0.13], [-0.12, -0.07, -0.13]]})

    body = tk.box("tc_b", size=(0.40, 0.24, 0.20), loc=(0, 0, 0.16), colour="blue")
    cab = tk.box("tc_c", size=(0.16, 0.22, 0.14), loc=(0.12, 0, 0.33), colour="blue_light")
    stack = tk.cyl("tc_s", radius=0.035, depth=0.10, verts=8, loc=(0.16, 0, 0.45),
                   colour="grey_deep")
    o = tk.join([body, cab, stack], "train_cart")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "train_cart", collider="box", purpose="Toy train cart.")

    hull = tk.box("bt_h", size=(0.42, 0.24, 0.14), loc=(0, 0, 0.07), colour="white")
    bow = tk.cone("bt_bw", r1=0.13, r2=0.03, depth=0.16, verts=6,
                  loc=(0.26, 0, 0.07), rot=(0, R(90), 0), colour="white")
    cabin = tk.box("bt_c", size=(0.16, 0.18, 0.12), loc=(-0.06, 0, 0.20), colour="red")
    o = tk.join([hull, bow, cabin], "toy_boat")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_boat", collider="box",
              purpose="Floating toy boat. Buoyant, carries cargo across water.")

    body = tk.cyl("rk_b", radius=0.085, depth=0.34, verts=10, colour="white")
    nose = tk.cone("rk_n", r1=0.085, r2=0.0, depth=0.14, verts=10, loc=(0, 0, 0.24),
                   colour="red")
    for i, a in enumerate((0, 120, 240)):
        tk.box(f"rk_f{i}", size=(0.020, 0.10, 0.12), loc=(math.cos(R(a)) * 0.075,
               math.sin(R(a)) * 0.075, -0.14), rot=(0, 0, R(a)), colour="red")
    o = tk.join([body, nose] + _named("rk_f"), "toy_rocket")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_rocket", collider="box",
              purpose="Toy rocket. Launches upward when triggered.")

    o = tk.ico("metal_ball", radius=0.062, subdiv=2, colour="metal")
    tk.recentre(o)
    tk.export(o, "metal_ball", collider="sphere",
              purpose="Steel-look ball. The only thing magnets attract.",
              extra={"radius": 0.062})


# ================================================================ mechanical
def build_mechanical():
    arm = tk.box("pd_a", size=(0.045, 0.045, 0.52), loc=(0, 0, -0.26), colour="grey_deep")
    bob = tk.ico("pd_b", radius=0.10, subdiv=1, loc=(0, 0, -0.56), colour="blue")
    o = tk.join([arm, bob], "pendulum")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "pendulum", collider="box",
              purpose="Swinging pendulum. Pivot is at the top of the arm.")

    arm = tk.box("ha_a", size=(0.40, 0.06, 0.06), colour="grey_deep")
    head = tk.box("ha_h", size=(0.14, 0.14, 0.16), loc=(0.22, 0, 0), colour="red")
    o = tk.join([arm, head], "toy_hammer")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_hammer", collider="box",
              purpose="Swinging toy hammer. Delivers a large single hit.")

    o = tk.box("rotating_arm", size=(0.50, 0.08, 0.06), colour="orange")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "rotating_arm", collider="box",
              purpose="Rotating arm. Sweeps objects off a platform.")

    for slug, r_, teeth, col in (("gear_small", 0.13, 8, "blue"),
                                 ("gear_large", 0.21, 12, "orange")):
        hub = tk.cyl(f"{slug}_h", radius=r_ * 0.72, depth=0.06, verts=12,
                     rot=(R(90), 0, 0), colour=col)
        for i in range(teeth):
            a = R(360 / teeth * i)
            tk.box(f"{slug}_t{i}", size=(r_ * 0.26, 0.055, r_ * 0.22),
                   loc=(math.cos(a) * r_ * 0.85, 0, math.sin(a) * r_ * 0.85),
                   rot=(0, -a, 0), colour=col)
        centre = tk.cyl(f"{slug}_c", radius=r_ * 0.22, depth=0.075, verts=8,
                        rot=(R(90), 0, 0), colour="grey_deep")
        o = tk.join([hub, centre] + _named(f"{slug}_t"), slug)
        tk.bevel(o, width=0.004, segments=1, angle=32)
        tk.recentre(o)
        tk.export(o, slug, collider="cylinder",
                  purpose=f"Toothed gear ({slug.split('_')[1]}). Rotates to drive a chain.")

    rim = tk.torus("pu_r", major=0.115, minor=0.028, major_segs=12, minor_segs=6,
                   rot=(R(90), 0, 0), colour="yellow")
    hub = tk.cyl("pu_h", radius=0.045, depth=0.075, verts=8, rot=(R(90), 0, 0),
                 colour="grey_deep")
    o = tk.join([rim, hub], "pulley")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "pulley", collider="cylinder", purpose="Pulley wheel for rope systems.")

    drum = tk.cyl("wi_d", radius=0.085, depth=0.20, verts=10, rot=(R(90), 0, 0),
                  colour="orange")
    frame = tk.box("wi_f", size=(0.22, 0.26, 0.05), loc=(0, 0, -0.10), colour="grey_deep")
    o = tk.join([drum, frame], "winch")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "winch", collider="box", purpose="Winch drum. Raises and lowers a hook.")

    base = tk.box("cn_b", size=(0.34, 0.34, 0.10), colour="yellow")
    mast = tk.box("cn_m", size=(0.09, 0.09, 0.92), loc=(0, 0, 0.50), colour="yellow")
    jib = tk.box("cn_j", size=(0.70, 0.07, 0.07), loc=(0.28, 0, 0.94), colour="yellow_dark")
    counter = tk.box("cn_c", size=(0.16, 0.12, 0.12), loc=(-0.22, 0, 0.94), colour="grey_deep")
    o = tk.join([base, mast, jib, counter], "crane")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "crane", collider="box",
              purpose="Tower crane. Static structure with a moving hook.")

    hook = tk.torus("hk_t", major=0.055, minor=0.016, major_segs=10, minor_segs=5,
                    rot=(R(90), 0, 0), colour="grey_deep")
    block = tk.box("hk_b", size=(0.075, 0.075, 0.09), loc=(0, 0, 0.09), colour="red")
    o = tk.join([hook, block], "crane_hook")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "crane_hook", collider="box",
              purpose="Crane hook. Kinematic; carries a payload down a rope.")

    base = tk.box("ct_b", size=(0.34, 0.28, 0.10), colour="wood")
    arm = tk.box("ct_a", size=(0.44, 0.07, 0.05), loc=(0.06, 0, 0.20), rot=(0, R(-32), 0),
                 colour="orange")
    cup = tk.cyl("ct_c", radius=0.075, depth=0.05, verts=10, loc=(0.24, 0, 0.34),
                 colour="red")
    o = tk.join([base, arm, cup], "catapult")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "catapult", collider="box",
              purpose="Catapult. Flings its payload on a high arc.")

    body = tk.box("pi_b", size=(0.20, 0.20, 0.20), colour="blue_dark")
    rod = tk.cyl("pi_r", radius=0.045, depth=0.22, verts=8, loc=(0.19, 0, 0),
                 rot=(0, R(90), 0), colour="metal")
    head = tk.box("pi_h", size=(0.05, 0.17, 0.17), loc=(0.31, 0, 0), colour="red")
    o = tk.join([body, rod, head], "piston")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "piston", collider="box",
              purpose="Piston. Punches along +X when triggered.")

    hub = tk.cyl("ww_h", radius=0.075, depth=0.16, verts=10, rot=(R(90), 0, 0),
                 colour="wood")
    for i in range(8):
        a = R(45 * i)
        tk.box(f"ww_p{i}", size=(0.055, 0.20, 0.24),
               loc=(math.cos(a) * 0.22, 0, math.sin(a) * 0.22), rot=(0, -a, 0),
               colour="blue")
    o = tk.join([hub] + _named("ww_p"), "water_wheel")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "water_wheel", collider="cylinder",
              purpose="Water wheel. Turns when water or objects hit its paddles.")

    tower = tk.cone("wm_t", r1=0.16, r2=0.09, depth=0.62, verts=8, loc=(0, 0, 0.31),
                    colour="white")
    hub = tk.cyl("wm_h", radius=0.05, depth=0.10, verts=8, loc=(0.10, 0, 0.62),
                 rot=(0, R(90), 0), colour="red")
    for i in range(4):
        a = R(90 * i)
        tk.box(f"wm_b{i}", size=(0.045, 0.09, 0.34),
               loc=(0.14, math.cos(a) * 0.17, 0.62 + math.sin(a) * 0.17),
               rot=(a, 0, 0), colour="red")
    o = tk.join([tower, hub] + _named("wm_b"), "windmill")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "windmill", collider="box",
              purpose="Windmill. Rotating sails driven by a fan.")

    deck = tk.box("lf_d", size=(0.42, 0.42, 0.05), loc=(0, 0, 0.12), colour="green")
    col = tk.box("lf_c", size=(0.10, 0.10, 0.14), colour="grey_deep")
    o = tk.join([deck, col], "lift_platform")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "lift_platform", collider="box",
              purpose="Lift platform. Rises when activated.")

    frame = tk.box("sd_f", size=(0.06, 0.44, 0.52), colour="grey_deep")
    leaf = tk.box("sd_l", size=(0.05, 0.40, 0.44), loc=(0.02, 0, 0), colour="red")
    o = tk.join([frame, leaf], "sliding_door")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "sliding_door", collider="box",
              purpose="Sliding door. Blocks a path until opened.")

    arm = tk.box("ra_a", size=(0.30, 0.10, 0.10), colour="purple")
    claw1 = tk.box("ra_c1", size=(0.10, 0.03, 0.12), loc=(0.18, 0.05, -0.05), colour="purple")
    claw2 = tk.box("ra_c2", size=(0.10, 0.03, 0.12), loc=(0.18, -0.05, -0.05), colour="purple")
    base = tk.cyl("ra_b", radius=0.10, depth=0.09, verts=10, loc=(-0.17, 0, -0.05),
                  colour="grey_deep")
    o = tk.join([arm, claw1, claw2, base], "robot_arm")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "robot_arm", collider="box",
              purpose="Robotic toy arm. Sweeps or grabs on a timer.")


# ============================================================ air and water
def build_air_water():
    body = tk.cyl("fn_b", radius=0.15, depth=0.09, verts=12, rot=(0, R(90), 0),
                  colour="cyan")
    for i in range(4):
        a = R(90 * i)
        tk.box(f"fn_bl{i}", size=(0.03, 0.075, 0.20),
               loc=(0.045, math.cos(a) * 0.09, math.sin(a) * 0.09),
               rot=(a + R(22), 0, 0), colour="white")
    foot = tk.box("fn_f", size=(0.16, 0.20, 0.05), loc=(0, 0, -0.17), colour="blue_dark")
    post = tk.cyl("fn_p", radius=0.028, depth=0.16, verts=6, loc=(0, 0, -0.10),
                  colour="blue_dark")
    o = tk.join([body, foot, post] + _named("fn_bl"), "toy_fan")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_fan", collider="box",
              purpose="Toy fan. Blows dynamic objects along +X when switched on.")

    for slug, col in (("balloon_red", "red"), ("balloon_blue", "blue"),
                      ("balloon_yellow", "yellow"), ("balloon_green", "green")):
        body = tk.ico(f"{slug}_b", radius=0.13, subdiv=2, scale=(1, 1, 1.18),
                      colour=col)
        knot = tk.cone(f"{slug}_k", r1=0.04, r2=0.0, depth=0.06, verts=6,
                       loc=(0, 0, -0.17), rot=(0, R(180), 0), colour=col)
        o = tk.join([body, knot], slug)
        tk.recentre(o)
        tk.export(o, slug, collider="sphere",
                  purpose="Balloon. Floats upward until popped.",
                  extra={"radius": 0.13})

    envelope = tk.ico("hb_e", radius=0.26, subdiv=2, scale=(1, 1, 1.25), colour="orange")
    basket = tk.box("hb_b", size=(0.16, 0.16, 0.13), loc=(0, 0, -0.42), colour="wood")
    for i, (sx, sy) in enumerate(((0.06, 0.06), (0.06, -0.06), (-0.06, 0.06), (-0.06, -0.06))):
        tk.cyl(f"hb_r{i}", radius=0.008, depth=0.16, verts=4, loc=(sx, sy, -0.29),
               colour="wood")
    o = tk.join([envelope, basket] + _named("hb_r"), "hot_air_balloon")
    tk.recentre(o)
    tk.export(o, "hot_air_balloon", collider="sphere",
              purpose="Hot-air balloon. Lifts a payload in its basket.",
              extra={"radius": 0.26})

    o = tk.cyl("air_pipe", radius=0.10, depth=0.60, verts=10, rot=(0, R(90), 0),
               colour="grey")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "air_pipe", collider="box", purpose="Air pipe. Channels a fan's stream.")

    o = tk.torus("inflatable_tube", major=0.20, minor=0.075, major_segs=12,
                 minor_segs=8, colour="pink")
    tk.recentre(o)
    tk.export(o, "inflatable_tube", collider="box",
              purpose="Inflatable ring. Bouncy floating obstacle.")

    body = tk.box("al_b", size=(0.24, 0.24, 0.20), colour="cyan")
    nozzle = tk.cone("al_n", r1=0.10, r2=0.05, depth=0.16, verts=10, loc=(0, 0, 0.18),
                     colour="white")
    o = tk.join([body, nozzle], "air_launcher")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "air_launcher", collider="box",
              purpose="Air launcher. Blasts an object straight up.")

    # ---- water --------------------------------------------------------
    for slug, size, col, purpose in (
        ("water_pool", (1.20, 0.90, 0.10), "water", "Shallow water volume. Buoyant."),
        ("water_channel", (1.60, 0.40, 0.10), "water", "Narrow water channel."),
        ("water_tank", (0.60, 0.60, 0.36), "water_deep", "Deep water tank."),
    ):
        o = tk.box(slug, size=size, colour=col)
        tk.bevel(o, width=0.006, segments=1, angle=40)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose)

    body = tk.cyl("bu_b", radius=0.14, depth=0.20, verts=12, colour="blue")
    rim = tk.torus("bu_r", major=0.145, minor=0.018, major_segs=12, minor_segs=5,
                   loc=(0, 0, 0.10), colour="blue_dark")
    o = tk.join([body, rim], "water_bucket")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "water_bucket", collider="box",
              purpose="Water bucket. Tips its contents when knocked.")

    o = tk.box("tilting_container", size=(0.34, 0.26, 0.20), colour="green")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "tilting_container", collider="box",
              purpose="Container that tips over a pivot when filled.")

    o = tk.cyl("water_pipe", radius=0.085, depth=0.70, verts=10, rot=(0, R(90), 0),
               colour="blue_dark")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "water_pipe", collider="box", purpose="Water pipe segment.")

    deck = tk.box("fp_d", size=(0.46, 0.46, 0.06), loc=(0, 0, 0.05), colour="wood")
    floats = []
    for sx in (-0.17, 0.17):
        floats.append(tk.cyl(f"fp_f{sx}", radius=0.075, depth=0.44, verts=8,
                             loc=(sx, 0, -0.01), rot=(R(90), 0, 0), colour="white"))
    o = tk.join([deck] + floats, "floating_platform")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "floating_platform", collider="box",
              purpose="Floating platform. Rides on a water volume.")

    frame = tk.box("wg_f", size=(0.06, 0.46, 0.44), colour="grey_deep")
    gate = tk.box("wg_g", size=(0.05, 0.40, 0.36), loc=(0.02, 0, 0), colour="cyan")
    o = tk.join([frame, gate], "water_gate")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "water_gate", collider="box",
              purpose="Water gate. Lifts to release a flow.")

    base = tk.box("ws_b", size=(0.22, 0.22, 0.14), colour="blue_dark")
    spout = tk.cone("ws_s", r1=0.075, r2=0.11, depth=0.16, verts=10, loc=(0.14, 0, 0.10),
                    rot=(0, R(70), 0), colour="cyan")
    o = tk.join([base, spout], "waterfall_switch")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "waterfall_switch", collider="box",
              purpose="Waterfall switch. Opens a cascade when triggered.")


# ==================================================== magnetic and electrical
def build_electrical():
    left = tk.box("mg_l", size=(0.075, 0.09, 0.30), loc=(-0.10, 0, 0.02), colour="red")
    right = tk.box("mg_r", size=(0.075, 0.09, 0.30), loc=(0.10, 0, 0.02), colour="red")
    top = tk.box("mg_t", size=(0.28, 0.09, 0.075), loc=(0, 0, 0.20), colour="red")
    tipl = tk.box("mg_tl", size=(0.075, 0.09, 0.075), loc=(-0.10, 0, -0.15), colour="white")
    tipr = tk.box("mg_tr", size=(0.075, 0.09, 0.075), loc=(0.10, 0, -0.15), colour="white")
    o = tk.join([left, right, top, tipl, tipr], "horseshoe_magnet")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "horseshoe_magnet", collider="box",
              purpose="Horseshoe magnet. Attracts metal balls when energised.")

    core = tk.cyl("em_c", radius=0.075, depth=0.24, verts=10, rot=(0, R(90), 0),
                  colour="metal")
    for i in range(4):
        tk.torus(f"em_w{i}", major=0.095, minor=0.022, major_segs=10, minor_segs=5,
                 loc=(-0.06 + i * 0.04, 0, 0), rot=(0, R(90), 0), colour="orange")
    o = tk.join([core] + _named("em_w"), "electromagnet")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "electromagnet", collider="box",
              purpose="Electromagnet. Stronger pull, switched on by a relay.")

    body = tk.cyl("bt_b", radius=0.085, depth=0.26, verts=10, colour="green")
    cap = tk.cyl("bt_c", radius=0.035, depth=0.05, verts=8, loc=(0, 0, 0.15),
                 colour="grey_deep")
    band = tk.cyl("bt_bd", radius=0.088, depth=0.05, verts=10, loc=(0, 0, 0.05),
                  colour="white")
    o = tk.join([body, cap, band], "battery")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "battery", collider="box", purpose="Battery. Powers an electrical chain.")

    o = tk.cyl("cable", radius=0.022, depth=0.70, verts=6, rot=(0, R(90), 0),
               colour="orange")
    tk.recentre(o)
    tk.export(o, "cable", collider="box", purpose="Cable run between electrical parts.")

    body = tk.box("ps_b", size=(0.16, 0.12, 0.20), colour="grey_deep")
    lever = tk.box("ps_l", size=(0.06, 0.05, 0.13), loc=(0.09, 0, 0.06), rot=(0, R(-25), 0),
                   colour="green")
    o = tk.join([body, lever], "power_switch")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "power_switch", collider="box", purpose="Power switch. Energises a circuit.")

    base = tk.cyl("en_b", radius=0.115, depth=0.09, verts=10, colour="grey_deep")
    orb = tk.ico("en_o", radius=0.085, subdiv=2, loc=(0, 0, 0.14), colour="cyan")
    o = tk.join([base, orb], "energy_node")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "energy_node", collider="box",
              purpose="Energy node. Relays power onward when struck.")

    body = tk.box("rl_b", size=(0.20, 0.16, 0.16), colour="purple")
    light = tk.ico("rl_l", radius=0.045, subdiv=1, loc=(0, 0, 0.12), colour="yellow")
    o = tk.join([body, light], "electrical_relay")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "electrical_relay", collider="box",
              purpose="Relay. Switches a downstream device on.")

    body = tk.box("le_b", size=(0.20, 0.14, 0.14), colour="red")
    lens = tk.cyl("le_l", radius=0.05, depth=0.06, verts=10, loc=(0.12, 0, 0),
                  rot=(0, R(90), 0), colour="white")
    o = tk.join([body, lens], "laser_emitter")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "laser_emitter", collider="box", purpose="Laser emitter.")

    body = tk.box("lr_b", size=(0.16, 0.16, 0.20), colour="green")
    eye = tk.cyl("lr_e", radius=0.05, depth=0.06, verts=10, loc=(-0.10, 0, 0),
                 rot=(0, R(90), 0), colour="white")
    o = tk.join([body, eye], "laser_receiver")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "laser_receiver", collider="box",
              purpose="Laser receiver. Fires when the beam lands.")

    face = tk.box("mr_f", size=(0.025, 0.22, 0.22), colour="white")
    frame = tk.box("mr_fr", size=(0.05, 0.26, 0.26), loc=(-0.02, 0, 0), colour="blue")
    o = tk.join([face, frame], "rotating_mirror")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "rotating_mirror", collider="box", purpose="Rotating mirror. Redirects a beam.")

    frame = tk.box("pw_f", size=(0.06, 0.46, 0.50), colour="grey_deep")
    leaf = tk.box("pw_l", size=(0.05, 0.40, 0.42), loc=(0.02, 0, 0), colour="cyan")
    o = tk.join([frame, leaf], "powered_door")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "powered_door", collider="box",
              purpose="Powered door. Slides open when a circuit completes.")


# ============================================================== destructible
def build_destructible():
    """Each breakable ships with a matching lightweight debris piece, so a
    shatter costs a handful of small bodies rather than a bespoke model."""
    specs = (
        ("block_wall", (0.10, 0.60, 0.62), "red", "block", "Stacked block wall."),
        ("glass_panel", (0.05, 0.50, 0.56), "cyan", "glass", "Glass-style toy panel."),
        ("wood_barrier", (0.09, 0.62, 0.40), "wood", "block", "Wooden-style barrier."),
        ("brick_stack", (0.20, 0.42, 0.52), "orange", "block", "Stack of toy bricks."),
        ("ice_block", (0.28, 0.28, 0.32), "cyan", "glass", "Ice block."),
    )
    for slug, size, col, flavour, purpose in specs:
        o = tk.box(slug, size=size, colour=col)
        tk.bevel(o, width=0.008, segments=1, angle=32)
        tk.recentre(o)
        tk.export(o, slug, collider="box", purpose=purpose,
                  extra={"flavour": flavour})

    for slug, col in (("debris_block", "red"), ("debris_glass", "cyan"),
                      ("debris_wood", "wood"), ("debris_brick", "orange"),
                      ("debris_stone", "grey_dark")):
        o = tk.box(slug, size=(0.075, 0.075, 0.075), colour=col)
        tk.bevel(o, width=0.006, segments=1, angle=32)
        tk.recentre(o)
        tk.export(o, slug, collider="box",
                  purpose="Debris piece. Pooled, revealed when its parent breaks.")

    body = tk.cyl("po_b", radius=0.135, depth=0.24, verts=10, colour="orange")
    lip = tk.torus("po_l", major=0.13, minor=0.024, major_segs=10, minor_segs=5,
                   loc=(0, 0, 0.12), colour="red")
    o = tk.join([body, lip], "ceramic_pot")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "ceramic_pot", collider="box",
              purpose="Ceramic-style pot. Shatters on impact.",
              extra={"flavour": "glass"})

    tiers = []
    for i, (w, h) in enumerate(((0.34, 0.16), (0.24, 0.14), (0.15, 0.12))):
        tiers.append(tk.box(f"sc_{i}", size=(w, w, h), loc=(0, 0, 0.08 + i * 0.15),
                            colour="yellow_light"))
    o = tk.join(tiers, "sandcastle")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "sandcastle", collider="box", purpose="Sandcastle. Collapses when hit.",
              extra={"flavour": "block"})

    rocks = []
    for i, (x, y, z, r_) in enumerate(((0, 0, 0.08, 0.14), (0.14, 0.06, 0.06, 0.10),
                                       (-0.12, -0.05, 0.07, 0.11), (0.03, -0.13, 0.05, 0.09))):
        rocks.append(tk.ico(f"rp_{i}", radius=r_, subdiv=1, loc=(x, y, z),
                            colour="grey_dark"))
    o = tk.join(rocks, "rock_pile")
    tk.recentre(o)
    tk.export(o, "rock_pile", collider="box", purpose="Rock pile. Scatters when struck.",
              extra={"flavour": "block"})

    body = tk.box("tk_b", size=(0.28, 0.28, 0.28), colour="wood")
    for i, (sx, sy) in enumerate(((0.142, 0), (-0.142, 0), (0, 0.142), (0, -0.142))):
        tk.box(f"tk_p{i}", size=(0.012 if sx else 0.26, 0.012 if sy else 0.26, 0.055),
               loc=(sx, sy, 0.075), colour="orange")
    o = tk.join([body] + _named("tk_p"), "toy_crate")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_crate", collider="box", purpose="Breakable toy crate.",
              extra={"flavour": "block"})


# ========================================================== world dressing
def build_dressing():
    # Harbour.
    deck = tk.box("dk_d", size=(1.10, 0.60, 0.06), loc=(0, 0, 0.24), colour="wood")
    for i, (sx, sy) in enumerate(((-0.45, 0.22), (-0.45, -0.22), (0.45, 0.22), (0.45, -0.22))):
        tk.cyl(f"dk_p{i}", radius=0.045, depth=0.28, verts=8, loc=(sx, sy, 0.10),
               colour="grey_deep")
    o = tk.join([deck] + _named("dk_p"), "dock")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "dock", collider="box", purpose="Harbour dock platform.")

    body = tk.cone("lh_b", r1=0.20, r2=0.115, depth=0.70, verts=10, loc=(0, 0, 0.35),
                   colour="white")
    band = tk.cone("lh_bd", r1=0.175, r2=0.15, depth=0.16, verts=10, loc=(0, 0, 0.36),
                   colour="red")
    lamp = tk.cyl("lh_l", radius=0.10, depth=0.16, verts=10, loc=(0, 0, 0.78),
                  colour="yellow")
    cap = tk.cone("lh_c", r1=0.13, r2=0.0, depth=0.14, verts=8, loc=(0, 0, 0.92),
                  colour="red")
    o = tk.join([body, band, lamp, cap], "lighthouse")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "lighthouse", collider="box",
              purpose="Harbour lighthouse. World 3 landmark and final target.")

    o = tk.cone("buoy", r1=0.11, r2=0.05, depth=0.28, verts=8, colour="red")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "buoy", collider="box", purpose="Floating harbour buoy.")

    # Carnival.
    poles = []
    for i in range(6):
        a = R(60 * i)
        poles.append(tk.box(f"tt_p{i}", size=(0.035, 0.035, 0.44),
                            loc=(math.cos(a) * 0.30, math.sin(a) * 0.30, 0.22),
                            colour="white"))
    roof = tk.cone("tt_r", r1=0.42, r2=0.05, depth=0.34, verts=6, loc=(0, 0, 0.60),
                   colour="red")
    o = tk.join(poles + [roof], "carnival_tent")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "carnival_tent", collider="box", purpose="Carnival tent. World 4 dressing.")

    counter = tk.box("pb_c", size=(0.46, 0.26, 0.28), loc=(0, 0, 0.14), colour="purple")
    top = tk.box("pb_t", size=(0.52, 0.32, 0.04), loc=(0, 0, 0.30), colour="yellow")
    o = tk.join([counter, top], "prize_booth")
    tk.bevel(o, width=0.007, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "prize_booth", collider="box", purpose="Prize booth.")

    hub = tk.cyl("sr_h", radius=0.075, depth=0.42, verts=10, loc=(0, 0, 0.21),
                 colour="grey_deep")
    for i in range(6):
        a = R(60 * i)
        tk.box(f"sr_a{i}", size=(0.34, 0.05, 0.04),
               loc=(math.cos(a) * 0.17, math.sin(a) * 0.17, 0.40), rot=(0, 0, a),
               colour=("red", "yellow", "blue", "green", "orange", "purple")[i])
    o = tk.join([hub] + _named("sr_a"), "spinning_ride")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "spinning_ride", collider="box", purpose="Spinning carnival ride.")

    pole = tk.cyl("bn_p", radius=0.018, depth=0.52, verts=6, loc=(0, 0, 0.26),
                  colour="grey_deep")
    cloth = tk.box("bn_c", size=(0.02, 0.22, 0.15), loc=(0, 0.11, 0.44), colour="yellow")
    o = tk.join([pole, cloth], "bunting_flag")
    tk.bevel(o, width=0.004, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "bunting_flag", collider="box", purpose="Carnival flag.")

    # Builder city.
    body = tk.box("tt_b", size=(0.46, 0.26, 0.20), loc=(0, 0, 0.16), colour="orange")
    cab = tk.box("tt_c", size=(0.18, 0.24, 0.17), loc=(0.16, 0, 0.34), colour="orange")
    bed = tk.box("tt_bd", size=(0.28, 0.26, 0.03), loc=(-0.10, 0, 0.27), colour="grey_deep")
    o = tk.join([body, cab, bed], "toy_truck")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_truck", collider="box",
              purpose="Toy dump truck. Heavier than the car; shifts big loads.",
              extra={"wheel_offsets": [[0.15, -0.10, 0.15], [0.15, -0.10, -0.15],
                                       [-0.13, -0.10, 0.15], [-0.13, -0.10, -0.15]]})

    o = tk.box("scaffold", size=(0.06, 0.06, 0.90), colour="yellow")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "scaffold", collider="box", purpose="Scaffold pole.")

    slab = tk.box("cs_s", size=(0.70, 0.50, 0.06), colour="grey")
    o = tk.join([slab], "construction_slab")
    tk.bevel(o, width=0.006, segments=1, angle=40)
    tk.recentre(o)
    tk.export(o, "construction_slab", collider="box", purpose="Construction ground slab.")

    # Factory.
    body = tk.box("mc_b", size=(0.50, 0.40, 0.46), loc=(0, 0, 0.23), colour="blue")
    panel = tk.box("mc_p", size=(0.03, 0.24, 0.20), loc=(0.26, 0, 0.28), colour="white")
    pipe = tk.cyl("mc_pi", radius=0.05, depth=0.30, verts=8, loc=(0, 0, 0.60),
                  colour="grey_deep")
    o = tk.join([body, panel, pipe], "toy_machine")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "toy_machine", collider="box", purpose="Factory machine housing.")

    o = tk.box("loading_platform", size=(0.80, 0.60, 0.16), colour="green_dark")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "loading_platform", collider="box", purpose="Raised loading platform.")

    o = tk.cyl("factory_pipe", radius=0.075, depth=0.90, verts=10, rot=(0, R(90), 0),
               colour="grey_dark")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "factory_pipe", collider="box", purpose="Factory pipe run.")

    # Extra final targets.
    body = tk.box("gn_b", size=(0.38, 0.30, 0.34), loc=(0, 0, 0.17), colour="green")
    coil = tk.cyl("gn_c", radius=0.10, depth=0.20, verts=10, loc=(0, 0, 0.44),
                  colour="yellow")
    o = tk.join([body, coil], "power_generator")
    tk.bevel(o, width=0.008, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "power_generator", collider="box",
              purpose="Power generator. Spins up as a final target.")

    pad = tk.cyl("rp_p", radius=0.34, depth=0.07, verts=12, colour="grey")
    ring = tk.torus("rp_r", major=0.30, minor=0.025, major_segs=12, minor_segs=5,
                    loc=(0, 0, 0.05), colour="red")
    for i in range(4):
        a = R(90 * i)
        tk.box(f"rp_t{i}", size=(0.05, 0.05, 0.34),
               loc=(math.cos(a) * 0.28, math.sin(a) * 0.28, 0.20), colour="yellow")
    o = tk.join([pad, ring] + _named("rp_t"), "rocket_pad")
    tk.bevel(o, width=0.006, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "rocket_pad", collider="box",
              purpose="Rocket launch pad. Final target for World 5.")

    for i in range(4):
        a = R(90 * i)
        tk.box(f"rc_b{i}", size=(0.04, 0.30, 0.42) if i % 2 == 0 else (0.30, 0.04, 0.42),
               loc=(math.cos(a) * 0.15, math.sin(a) * 0.15, 0.21), colour="blue")
    floor = tk.box("rc_f", size=(0.34, 0.34, 0.04), loc=(0, 0, 0.02), colour="white")
    o = tk.join([floor] + _named("rc_b"), "rescue_cage")
    tk.bevel(o, width=0.005, segments=1, angle=32)
    tk.recentre(o)
    tk.export(o, "rescue_cage", collider="box",
              purpose="Rescue cage. Opens to free a trapped toy.")


def run():
    tk.reset_scene()
    build_movers()
    build_mechanical()
    build_air_water()
    build_electrical()
    build_destructible()
    build_dressing()
    tk.save_blend("reaction_kits")
    return tk.manifest_flush("reaction_kits")
