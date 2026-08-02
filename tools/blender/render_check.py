"""Art-direction validation render.

Rebuilds the exact composition from `logo.png` out of the exported hero kit and
renders it in a white studio. Used to confirm proportions, palette and read at
a glance before any of it reaches the game. Output goes to
`art/exports/hero_check.png`.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toykit as tk  # noqa: E402
import build_hero  # noqa: E402

R = math.radians


def studio():
    """Bright, soft, shadow-catching white room — the look of the reference."""
    scene = bpy.context.scene
    # The EEVEE enum identifier moved between Blender versions; pick whichever
    # this build actually offers.
    engines = scene.render.bl_rna.properties["engine"].enum_items.keys()
    for candidate in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        if candidate in engines:
            scene.render.engine = candidate
            break
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1100
    scene.render.film_transparent = False

    eevee = scene.eevee
    for attr, val in (("use_raytracing", True), ("use_shadows", True),
                      ("taa_render_samples", 64)):
        if hasattr(eevee, attr):
            setattr(eevee, attr, val)

    # Blender 4+/5 default to the AgX view transform, which deliberately
    # desaturates highlights. The art bible wants saturated toy plastic, so
    # render through Standard instead.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0

    world = bpy.data.worlds.new("studio")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.90, 0.90, 0.91, 1.0)
        bg.inputs[1].default_value = 0.55

    # Infinite white floor.
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "studio_floor"
    m = bpy.data.materials.new("studio_floor")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.90, 0.90, 0.91, 1.0)
    b.inputs["Roughness"].default_value = 0.85
    floor.data.materials.append(m)

    # Key from upper-left-front, big and soft.
    bpy.ops.object.light_add(type="AREA", location=(-2.4, -2.8, 3.6))
    key = bpy.context.active_object
    key.data.energy = 320
    key.data.size = 5.0
    key.rotation_euler = (R(38), R(-18), R(-30))

    # Weak fill from the right to keep shadow sides from going flat grey.
    bpy.ops.object.light_add(type="AREA", location=(3.2, -1.6, 1.6))
    fill = bpy.context.active_object
    fill.data.energy = 70
    fill.data.size = 4.5
    fill.rotation_euler = (R(70), 0, R(62))

    # Long lens, three-quarter view — the miniature product-render camera.
    # Pulled back far enough to hold the whole 3.4m-wide composition.
    bpy.ops.object.camera_add(location=(-2.35, -6.15, 3.05))
    cam = bpy.context.active_object
    cam.data.lens = 78
    cam.rotation_euler = (R(75.0), 0, R(-21.0))
    scene.camera = cam
    return cam


def place(slug, loc, rot=(0, 0, 0), scale=1.0):
    """Re-imports an exported GLB so the render validates the shipped file,
    not the in-memory mesh it came from."""
    path = os.path.join(tk.MODELS_DIR, f"{slug}.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    root = meshes[0] if meshes else new[0]
    # glTF import brings the file in Y-up wrapped in a rotated empty; bake that
    # out so placement below can be authored in plain Blender Z-up terms.
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    root.location = Vector(loc)
    root.rotation_euler = Vector(rot)
    root.scale = Vector((scale, scale, scale))
    return root


def compose():
    """The logo scene: cannon left, ball in flight, tower, toppling dominoes,
    car being nudged at the right, capsules bursting out."""
    # Cannon, aimed slightly up and to the right.
    place("cannon_carriage", (-1.28, 0.0, 0.115))
    place("cannon_barrel", (-1.18, 0.0, 0.245), rot=(0, R(-12), 0))
    place("cannon_wheel", (-1.31, 0.115, 0.108))
    place("cannon_wheel", (-1.31, -0.115, 0.108))

    # Cannonball mid-flight.
    place("cannonball", (-0.72, 0.0, 0.47))

    # Block tower with the green roof.
    place("block_red", (-0.30, 0.10, 0.132))
    place("block_blue", (-0.30, 0.10, 0.396))
    place("block_red", (-0.30, 0.10, 0.660))
    place("block_roof", (-0.30, 0.10, 0.868))

    # Domino run, progressively toppling towards the car.
    run = [
        ("domino_blue", -0.02, 0),
        ("domino_yellow", 0.20, 16),
        ("domino_green", 0.43, 38),
        ("domino_red", 0.70, 62),
    ]
    for slug, x, tilt in run:
        # Pivot the lean about the bottom edge so pieces stay on the floor.
        h, t = 0.42, 0.083
        a = R(tilt)
        cx = x + (h / 2) * math.sin(a) - (t / 2) * (1 - math.cos(a))
        cz = (h / 2) * math.cos(a) + (t / 2) * math.sin(a)
        place(slug, (cx, -0.16, cz), rot=(0, a, 0))

    # Toy car, plus the little grey plate it sits on in the reference.
    plate = tk.plate("logo_plate", size=(0.46, 0.40), thickness=0.018,
                     loc=(1.12, -0.28, 0.009), colour="grey", radius=0.006)
    plate.rotation_euler = (0, 0, R(-8))
    place("toy_car_body", (1.10, -0.30, 0.128), rot=(0, 0, R(-6)))
    for dx, dy in ((0.105, 0.105), (0.105, -0.105), (-0.105, 0.105), (-0.105, -0.105)):
        place("toy_car_wheel", (1.10 + dx, -0.30 + dy, 0.058), rot=(0, 0, R(-6)))

    # Celebration capsules bursting out to the upper right.
    caps = [
        ("capsule_yellow", (1.32, 0.30, 0.86), (R(20), R(70), 0)),
        ("capsule_green", (1.55, 0.22, 0.72), (R(-30), R(50), 0)),
        ("capsule_duo", (1.42, 0.10, 0.58), (R(10), R(-40), 0)),
        ("capsule_red", (1.68, 0.34, 0.50), (R(60), R(25), 0)),
        ("capsule_blue", (1.24, 0.42, 0.66), (0, R(85), R(20))),
    ]
    for slug, loc, rot in caps:
        place(slug, loc, rot)


def run():
    tk.reset_scene()
    studio()
    compose()
    out = os.path.join(tk.REPO, "art", "exports", "hero_check.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    return {"render": out, "objects": len(bpy.data.objects)}
