"""Chain Reaction City — shared Blender asset toolkit.

Every model in the game is built by code in this repository so the whole art
set is reproducible: delete `assets/models/` and re-run the build scripts and
you get byte-comparable geometry back.

Art bible is `logo.png`. The rules encoded here:

  * soft low-poly toy diorama, chunky playful proportions
  * gently bevelled edges on everything (that bevel is what catches the light
    and makes a plain box read as moulded plastic)
  * simple solid-colour matte materials, no textures
  * faceted rather than smooth — the renderer shades per face
  * pivots at the bounding-box centre so physics bodies and meshes agree

Conventions
-----------
Units are metres. Blender is Z-up; the glTF exporter converts to the Y-up
convention the runtime uses, so build everything Z-up here and think Y-up in
Dart.
"""

import bmesh
import bpy
import json
import math
import os
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
# Sampled directly from logo.png. Keep in sync with lib/engine/render/palette.dart.
PALETTE = {
    "red":          "#E8453C",
    "red_dark":     "#C4342C",
    "red_light":    "#F26A62",
    "yellow":       "#F5C518",
    "yellow_dark":  "#D9A806",
    "yellow_light": "#FFD84A",
    "blue":         "#2A7FD4",
    "blue_dark":    "#1F63A8",
    "blue_light":   "#5BA3E8",
    "green":        "#3DAE55",
    "green_dark":   "#2E8A42",
    "green_light":  "#63C878",
    "white":        "#FFFFFF",
    "off_white":    "#F4F5F6",
    "grey":         "#C9CBCD",
    "grey_dark":    "#9AA0A6",
    "grey_deep":    "#6E747A",
    "cannon_body":  "#6EC6E8",
    "cannon_light": "#93D8F2",
    "cannon_mount": "#3B7FB5",
    "cannon_wheel": "#2F6B9E",
    "fuse":         "#8A5A3C",
    "orange":       "#F2882E",
    "purple":       "#8B5FCF",
    "cyan":         "#35BFD4",
    "pink":         "#EF6EA8",
    "tyre":         "#33383D",
    "metal":        "#B6BCC4",
    "wood":         "#C98A4B",
    "water":        "#57B7E8",
    "water_deep":   "#2E8FC4",
}

REPO = os.environ.get("CRC_REPO", r"C:\Users\awaiz\OneDrive\Desktop\chain")
MODELS_DIR = os.path.join(REPO, "assets", "models")
BLEND_DIR = os.path.join(REPO, "art", "blender")


# ------------------------------------------------------------------ colour
def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)


_MAT_CACHE = {}


def mat(name, roughness=0.55):
    """Returns (creating if needed) a flat matte-plastic material.

    `name` is a PALETTE key, or a raw #RRGGBB string.
    """
    key = (name, round(roughness, 3))
    if key in _MAT_CACHE and _MAT_CACHE[key].name in bpy.data.materials:
        return _MAT_CACHE[key]

    hexcol = PALETTE.get(name, name)
    matname = f"toy_{name}"
    m = bpy.data.materials.get(matname)
    if m is None:
        m = bpy.data.materials.new(matname)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = hex_to_linear(hexcol)
        bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.35
    m.diffuse_color = hex_to_linear(hexcol)
    _MAT_CACHE[key] = m
    return m


# ------------------------------------------------------------------ scene
def reset_scene():
    """Empties the file back to a clean slate."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                  bpy.data.cameras, bpy.data.lights, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    _MAT_CACHE.clear()


def deselect_all():
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = None


def activate(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# -------------------------------------------------------------- primitives
def _finish(obj, colour, name):
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat(colour))
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def box(name, size=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), colour="white"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = Vector(size)
    apply_transforms(o)
    return _finish(o, colour, name)


def cyl(name, radius=0.5, depth=1.0, verts=12, loc=(0, 0, 0), rot=(0, 0, 0),
        colour="white", scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot
    )
    o = bpy.context.active_object
    if scale != (1, 1, 1):
        o.scale = Vector(scale)
    apply_transforms(o)
    return _finish(o, colour, name)


def cone(name, r1=0.5, r2=0.2, depth=1.0, verts=12, loc=(0, 0, 0), rot=(0, 0, 0),
         colour="white"):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot
    )
    o = bpy.context.active_object
    apply_transforms(o)
    return _finish(o, colour, name)


def ico(name, radius=0.5, subdiv=2, loc=(0, 0, 0), colour="white", scale=(1, 1, 1)):
    """Faceted sphere. Subdiv 1 = 80 tris, 2 = 320 tris — the logo's cannonball
    sits at subdiv 2, which is the sweet spot for readable faceting."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.active_object
    if scale != (1, 1, 1):
        o.scale = Vector(scale)
    apply_transforms(o)
    return _finish(o, colour, name)


def uvsphere(name, radius=0.5, segs=12, rings=8, loc=(0, 0, 0), colour="white",
             scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segs, ring_count=rings, radius=radius, location=loc
    )
    o = bpy.context.active_object
    if scale != (1, 1, 1):
        o.scale = Vector(scale)
    apply_transforms(o)
    return _finish(o, colour, name)


def torus(name, major=0.5, minor=0.12, major_segs=12, minor_segs=6,
          loc=(0, 0, 0), rot=(0, 0, 0), colour="white"):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=major_segs, minor_segments=minor_segs,
        location=loc, rotation=rot,
    )
    o = bpy.context.active_object
    apply_transforms(o)
    return _finish(o, colour, name)


def capsule(name, radius=0.1, length=0.3, verts=10, loc=(0, 0, 0), rot=(0, 0, 0),
            colour="white"):
    """Rounded pill — the celebration pieces in logo.png are exactly this."""
    body = cyl(f"{name}_b", radius=radius, depth=length, verts=verts, colour=colour)
    top = ico(f"{name}_t", radius=radius, subdiv=1, loc=(0, 0, length / 2), colour=colour)
    bot = ico(f"{name}_o", radius=radius, subdiv=1, loc=(0, 0, -length / 2), colour=colour)
    o = join([body, top, bot], name)
    o.location = Vector(loc)
    o.rotation_euler = Vector(rot)
    apply_transforms(o)
    return _finish(o, colour, name)


def plate(name, size=(1, 1), thickness=0.04, loc=(0, 0, 0), colour="grey", radius=0.0):
    """A thin ground plate. `radius` rounds the corners via bevel."""
    o = box(name, size=(size[0], size[1], thickness), loc=loc, colour=colour)
    if radius > 0:
        bevel(o, width=min(radius, thickness * 0.49), segments=2, angle=70)
    return o


# ------------------------------------------------------------------ modify
def apply_transforms(obj):
    activate(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def bevel(obj, width=0.01, segments=1, angle=40, clamp=True):
    """The signature soft edge. Angle-limited so flat continuations are left
    alone and only real corners get rounded."""
    activate(obj)
    m = obj.modifiers.new(name="Bevel", type="BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.miter_outer = "MITER_ARC"
    if hasattr(m, "use_clamp_overlap"):
        m.use_clamp_overlap = clamp
    bpy.ops.object.modifier_apply(modifier=m.name)
    return obj


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    deselect_all()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


def move(obj, loc):
    obj.location = Vector(loc)
    return apply_transforms(obj)


def rotate(obj, rot):
    obj.rotation_euler = Vector(rot)
    return apply_transforms(obj)


def mirror_x(obj, name=None):
    """Duplicates across X. Used for wheel pairs, symmetric props."""
    activate(obj)
    bpy.ops.object.duplicate()
    d = bpy.context.active_object
    d.name = name or f"{obj.name}_m"
    d.scale = Vector((-1, 1, 1))
    apply_transforms(d)
    # Negative scale inverts normals; recover outward-facing geometry.
    me = d.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    return d


def recentre(obj, mode="bbox", ground=False):
    """Moves the mesh so its pivot is at the bounding-box centre (the
    convention physics bodies assume). `ground=True` instead puts the pivot on
    the floor plane, used for props that are authored resting on the ground."""
    activate(obj)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    if ground:
        lo = bbox_local(obj)[0]
        me = obj.data
        for v in me.vertices:
            v.co.z -= lo[2]
    obj.location = Vector((0, 0, 0))
    apply_transforms(obj)
    return obj


def bbox_local(obj):
    cs = [Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    hi = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    return lo, hi


def dot_inset(obj, positions, radius=0.028, depth=0.012, colour="white", axis="Y"):
    """Domino pips. Shallow discs sunk a hair into the face and given their own
    material — cheaper and cleaner at mobile size than boolean insets."""
    made = []
    for i, (a, b, c) in enumerate(positions):
        rot = (math.radians(90), 0, 0) if axis == "Y" else (0, math.radians(90), 0)
        d = cyl(f"{obj.name}_pip{i}", radius=radius, depth=depth, verts=8,
                loc=(a, b, c), rot=rot, colour=colour)
        made.append(d)
    return made


def tri_count(obj):
    me = obj.data
    n = 0
    for p in me.polygons:
        n += max(0, len(p.vertices) - 2)
    return n


# ------------------------------------------------------------------ export
_MANIFEST = []


def export(obj, slug, purpose="", collider="box", extra=None):
    """Writes `assets/models/<slug>.glb` and records manifest metadata."""
    os.makedirs(MODELS_DIR, exist_ok=True)
    path = os.path.join(MODELS_DIR, f"{slug}.glb")

    activate(obj)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=False,
        export_texcoords=False,
        export_tangents=False,
        export_skins=False,
        export_morph=False,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_attributes=False,
        export_shared_accessors=True,
    )

    lo, hi = bbox_local(obj)
    entry = {
        "slug": slug,
        "object": obj.name,
        "path": f"assets/models/{slug}.glb",
        "tris": tri_count(obj),
        "materials": len(obj.data.materials),
        "collider": collider,
        "purpose": purpose,
        # Y-up runtime sizes (Blender Z -> runtime Y, Blender Y -> runtime -Z).
        "size": [round(hi.x - lo.x, 4), round(hi.z - lo.z, 4), round(hi.y - lo.y, 4)],
        "bytes": os.path.getsize(path),
    }
    if extra:
        entry.update(extra)
    _MANIFEST.append(entry)
    return entry


def save_blend(name):
    os.makedirs(BLEND_DIR, exist_ok=True)
    path = os.path.join(BLEND_DIR, f"{name}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
    return path


def manifest_flush(kit_name):
    """Appends this run's entries to art/exports/<kit>.json for the docs step."""
    out = os.path.join(REPO, "art", "exports")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, f"{kit_name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(_MANIFEST, f, indent=2)
    data = list(_MANIFEST)
    _MANIFEST.clear()
    return {"path": path, "count": len(data), "entries": data}
