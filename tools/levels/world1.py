"""World 1 - Toy Street.

Teaches the whole game with almost no text: tap the cannon, watch the ball
knock the dominoes, watch the last domino shove the car, watch the car press
the button and raise the flag.

Levels 1-5 keep to one obvious starter and a short readable chain. 6-10 add a
second possible starter, ramps, fans, springs and destructibles.
"""

from builder import Level, radius, rest_y


# ============================================================ 1. First Shot
def level_1():
    """The vertical slice. Every beat from the brief and nothing more:
    cannon -> ball -> dominoes -> car -> button -> flag -> celebration."""
    L = Level("w1_l1", 1, 1, "First Shot",
              hint="Tap the blue cannon. It is the only thing you can start.",
              teaches=["cannon", "dominoes", "car", "button"],
              par_chain=12, par_time=9.0)
    L.camera(yaw=-0.86, pitch=0.48, pad=1.05, bias=0.06)

    run, car, bx, flag = L.classic_chain(x0=-1.62, count=5,
                                         colours=("blue", "yellow", "green", "red"))

    # Block tower beside the run, exactly as it sits in the reference art.
    # A falling domino trips a hidden volume which pops the roof and frees the
    # star — a controlled hand-off, because a physical nudge across that gap
    # would be knife-edge.
    L.tower("t", x=-0.34, z=0.52)
    L.star("star1", -0.34, 1.10, 0.52)
    L.trip("tower_trip", -0.30, 0.22, 0.0, ["tower_push", "tower_shove"])
    L.nudge("tower_push", -0.34, 0.95, 0.52, target="troof", impulse=(0.0, 0.50, 0.14))
    L.nudge("tower_shove", -0.34, 0.68, 0.52, target="t2", impulse=(0.03, 0.10, 0.34))

    L.decal("road", "road_straight", 0.30)
    L.prop("lamp", "lamp_post", -1.30, -0.78)
    L.prop("tree1", "park_tree", 1.30, 0.90)
    L.prop("sign", "street_sign", 0.40, -0.82)

    L.classic_stages(run, car, run[-2])
    L.stage("s_tower", "troof", after=["s_hit"], trigger="moved", threshold=0.08,
            focus="troof", label="Tower pops open", timeout=8.0)

    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.bonus("b_time", "under_time", "Finish in under 9 seconds", value=9.0)
    L.goal(flag)
    return L


def _street(L, road_x=0.30, road="road_straight"):
    """Shared World 1 dressing, kept clear of the reaction line."""
    L.decal("road", road, road_x)
    L.prop("lamp", "lamp_post", -1.20, -0.85)
    L.prop("tree1", "park_tree", 1.15, 0.95)


# ============================================================ 2. Traffic Cones
def level_2():
    L = Level("w1_l2", 1, 2, "Traffic Cones",
              hint="Everything on the street is part of the chain.",
              teaches=["dominoes", "scatter"], par_chain=13, par_time=9.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=6,
                                         colours=("red", "yellow", "blue", "green"))
    for i, (x, z) in enumerate(((0.10, 0.42), (0.40, 0.50), (0.70, 0.44))):
        L.prop(f"cone{i}", "traffic_cone", x, z, kind="dynamic", mass=0.06)
    L.trip("cone_trip", 0.05, 0.22, 0.0, ["cone_push"])
    L.nudge("cone_push", 0.10, 0.12, 0.42, target="cone0", impulse=(0.02, 0, 0.05))
    L.coin("c1", -0.30, 0.55)
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.stage("s_cones", "cone0", after=["s_hit"], trigger="moved", threshold=0.05,
            focus="cone0", label="Cones scatter", timeout=8.0)
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.bonus("b_chain", "chain_at_least", "Activate at least 11 objects", value=11)
    L.goal(flag)
    return L


# ============================================================ 3. Roadworks
def level_3():
    L = Level("w1_l3", 1, 3, "Roadworks",
              hint="The barrier will not stop a domino chain.",
              teaches=["breakable"], par_chain=14, par_time=10.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=5)
    L.breakable("wall", "wood_barrier", bx + 0.95, threshold=0.020, flavour="wood")
    L.star("s1", -0.20, 0.62, 0.60)
    L.trip("star_trip", -0.24, 0.22, 0.0, ["star_pop"])
    L.nudge("star_pop", -0.20, 0.30, 0.60, target="s1_hint", impulse=(0, 0.30, 0))
    # A small block that flies up through the star when the chain passes.
    L.add("s1_hint", "cube_yellow", kind="dynamic", pos=(-0.20, 0.13, 0.60),
          shape="box", mass=0.12, friction=0.5, tag="block")
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# =========================================================== 4. Long Street
def level_4():
    L = Level("w1_l4", 1, 4, "Long Street",
              hint="One tap topples the whole street.",
              teaches=["long_chain"], par_chain=18, par_time=12.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=9,
                                         colours=("red", "blue", "yellow", "green"))
    L.coin("c1", -0.20, 0.55)
    L.coin("c2", 0.85, 0.55)
    _street(L, road_x=0.60, road="road_wide")
    L.prop("sign", "street_sign", -0.50, -0.85)

    L.classic_stages(run, car, run[-2])
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.bonus("b_chain", "chain_at_least", "Activate at least 14 objects", value=14)
    L.goal(flag)
    return L


# ============================================================ 5. Tower Block
def level_5():
    L = Level("w1_l5", 1, 5, "Tower Block",
              hint="Watch the tower as the dominoes go past.",
              teaches=["blocks"], par_chain=16, par_time=11.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=6)
    L.tower("t", x=0.05, z=0.62, blocks=("block_blue", "block_red", "block_yellow"))
    L.star("star1", 0.05, 1.10, 0.62)
    L.trip("tower_trip", 0.01, 0.22, 0.0, ["tpop", "tshove"])
    L.nudge("tpop", 0.05, 0.95, 0.62, target="troof", impulse=(0.0, 0.50, 0.14))
    L.nudge("tshove", 0.05, 0.68, 0.62, target="t2", impulse=(0.03, 0.10, 0.34))
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.stage("s_tower", "troof", after=["s_hit"], trigger="moved", threshold=0.08,
            focus="troof", label="Tower pops open", timeout=8.0)
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# =========================================================== 6. Two Cannons
def level_6():
    L = Level("w1_l6", 1, 6, "Two Cannons",
              hint="Look at where each cannon points before you tap.",
              teaches=["multiple_starters"], par_chain=14, par_time=11.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=6)
    # Decoy: set back off the line and aimed steeply, so its shot arcs clean
    # over the run and lands in empty street.
    L.cannon("decoy", x=-1.55, z=-0.85, aim_deg=54.0, power=3.0, intended=False)
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.bonus("b_intended", "intended_starter", "Use the right cannon")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# ============================================================ 7. Fresh Air
def level_7():
    L = Level("w1_l7", 1, 7, "Fresh Air",
              hint="The fan starts blowing when the chain reaches it.",
              teaches=["fan"], par_chain=15, par_time=12.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=5)
    L.add("fan", "toy_fan", pos=(-0.30, 0.28, 0.95), rot=(0, -90, 0), shape="box",
          device={"type": "fan", "dir": [0.0, 0.10, -1.0], "force": 5.0,
                  "range": 1.3, "width": 0.45})
    L.trip("fan_trip", -0.34, 0.22, 0.0, ["fan"])
    L.add("puck", "ball_small", kind="dynamic", shape="sphere",
          pos=(-0.30, radius("ball_small"), 0.62), radius=radius("ball_small"),
          mass=0.04, friction=0.04, restitution=0.20, tag="ball")
    L.star("s1", -0.30, 0.30, 0.10)
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.stage("s_fan", "fan", after=["s_hit"], trigger="activated",
            focus="fan", label="Fan switches on", timeout=8.0)
    L.stage("s_puck", "puck", after=["s_fan"], trigger="moved", threshold=0.10,
            focus="puck", label="Ball blows across", timeout=8.0)
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# ========================================================= 8. Spring Street
def level_8():
    L = Level("w1_l8", 1, 8, "Spring Street",
              hint="The spring pad throws whatever lands on it.",
              teaches=["spring"], par_chain=15, par_time=12.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=5)
    L.add("spring", "spring_launcher", pos=(-0.20, rest_y("spring_launcher"), 0.72),
          shape="box",
          device={"type": "spring", "power": 3.2, "dir": [0.35, 0.85, 0]})
    L.add("hopper", "ball_crystal", kind="dynamic", shape="sphere",
          pos=(-0.20, 0.30, 0.72), radius=radius("ball_crystal"),
          mass=0.10, friction=0.05, restitution=0.30, tag="ball")
    L.star("s1", 0.30, 0.85, 0.85)
    _street(L)

    L.classic_stages(run, car, run[-2])
    L.stage("s_spring", "hopper", after=["s_fire"], trigger="moved", threshold=0.25,
            focus="hopper", label="Spring launches the ball", timeout=9.0)
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# =========================================================== 9. Rush Hour
def level_9():
    L = Level("w1_l9", 1, 9, "Rush Hour",
              hint="Two cars, but only one is on the route.",
              teaches=["branching"], par_chain=18, par_time=13.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=7)
    L.car("car2", 0.20, z=0.78, mass=0.20, friction=0.03)
    L.trip("trip2", 0.16, 0.22, 0.0, ["push2"])
    L.nudge("push2", 0.20, 0.11, 0.78, target="car2", impulse=(0.12, 0, 0.05))
    L.star("s1", 1.05, 0.14, 0.90)
    _street(L, road_x=0.50, road="road_wide")

    L.classic_stages(run, car, run[-2])
    L.stage("s_side", "car2", after=["s_hit"], trigger="moved", threshold=0.08,
            focus="car2", label="Second car rolls", timeout=9.0)
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.goal(flag)
    return L


# ======================================================= 10. Street Party
def level_10():
    """World 1 finale: the longest street chain, ending at the city beacon."""
    L = Level("w1_l10", 1, 10, "Street Party",
              hint="Tap the cannon and watch the whole street go.",
              teaches=["long_chain", "destruction"], par_chain=24, par_time=15.0)
    L.camera()
    run, car, bx, flag = L.classic_chain(count=10)

    # The flag stays the goal; the beacon lights alongside it as a landmark.
    L.add("beacon", "city_beacon", pos=(bx + 1.05, rest_y("city_beacon"), 0.55),
          shape="box", device={"type": "target"})
    L.trip("beacon_trip", bx - 0.30, 0.14, 0.0, ["beacon"])

    L.tower("t", x=-0.20, z=0.72)
    L.star("s1", -0.20, 1.10, 0.72)
    L.trip("tower_trip", -0.24, 0.22, 0.0, ["tpop", "tshove"])
    L.nudge("tpop", -0.20, 0.95, 0.72, target="troof", impulse=(0.0, 0.50, 0.14))
    L.nudge("tshove", -0.20, 0.68, 0.72, target="t2", impulse=(0.03, 0.10, 0.34))

    L.breakable("crates", "toy_crate", bx + 0.55, z=-0.62, threshold=0.020)
    L.coin("c1", 0.60, 0.55)
    _street(L, road_x=0.60, road="road_wide")

    L.classic_stages(run, car, run[-2])
    L.stage("s_tower", "troof", after=["s_hit"], trigger="moved", threshold=0.08,
            focus="troof", label="Tower pops open", timeout=9.0)
    L.stage("s_beacon", "beacon", after=["s_btn"], trigger="activated",
            focus="beacon", label="Beacon lights up", timeout=8.0)
    L.bonus("b_star", "collect_all", "Collect the star")
    L.bonus("b_nostall", "no_stall", "Keep the chain going")
    L.bonus("b_chain", "chain_at_least", "Activate at least 18 objects", value=18)
    L.goal(flag)
    return L


def build_all():
    return [level_1(), level_2(), level_3(), level_4(), level_5(),
            level_6(), level_7(), level_8(), level_9(), level_10()]


if __name__ == "__main__":
    for L in build_all():
        print(L.save())
