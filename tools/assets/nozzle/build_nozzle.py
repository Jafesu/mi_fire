"""Turn the CAD nozzle into a game-ready mesh.

Run headless:

    blender -b --python tools/assets/nozzle/build_nozzle.py -- --src <079.stl> --out <dir>

The source is a CAD export: 183,404 triangles, millimetres, and no UVs or materials at all --
an STL carries nothing but triangles. Roughly 96% of those triangles have to go, and
everything a game needs has to be added. Each step below says why it is there, because the
next person to run this will want to change the numbers rather than rediscover them.

Orientation, which cost three test renders to pin down: the source has the fog tip toward +Y
and the bale handle toward -X. GTA wants the tip forward and the handle up, so the whole
mapping is (x, y, z) -> (z, y, -x), scaled by 0.001 for millimetres to metres. Written as one
matrix rather than three chained rotations because it can be checked by eye against a
bounding box, and the chained version was wrong twice.
"""

import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

# A weapon the player holds and looks straight at. GTA V handguns sit near 2-4k triangles and
# rifles near 6-10k, so this is deliberately at the generous end of normal.
TARGET_TRIS = 8000

# 0.1 mm. STL stores every triangle's corners independently, so the mesh arrives as loose
# triangles that merely touch. Without this there are no shared edges: nothing is smoothable
# and decimation has nothing to collapse along.
WELD_DISTANCE = 0.0001

TEXTURE_SIZE = 1024
AO_SAMPLES = 24

# Anodized-aluminium body. The occlusion bake supplies the shading; this is only the colour
# it gets multiplied by.
BASE_COLOUR = (0.42, 0.44, 0.47)


def parse_args():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"src": None, "out": None, "tris": TARGET_TRIS}
    i = 0
    while i < len(args):
        if args[i] == "--src":
            out["src"] = args[i + 1]
            i += 2
        elif args[i] == "--out":
            out["out"] = args[i + 1]
            i += 2
        elif args[i] == "--tris":
            out["tris"] = int(args[i + 1])
            i += 2
        else:
            i += 1
    if not out["src"] or not out["out"]:
        raise SystemExit("need --src <stl> and --out <dir>")
    return out


def mesh_size(ob):
    lo, hi = mesh_bounds(ob)
    return tuple(round(hi[i] - lo[i], 3) for i in range(3))


def mesh_bounds(ob):
    lo = Vector((1e30,) * 3)
    hi = Vector((-1e30,) * 3)
    for v in ob.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    return lo, hi


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def step(msg):
    print("[build] " + msg, flush=True)


def main():
    args = parse_args()
    os.makedirs(args["out"], exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    # ---- import -------------------------------------------------------------------------
    step("importing " + args["src"])
    bpy.ops.wm.stl_import(filepath=args["src"])
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    ob.name = "mi_nozzle"
    ob.data.name = "mi_nozzle"
    step("imported {:,} triangles".format(tri_count(ob)))

    # ---- orient and scale ---------------------------------------------------------------
    # Columns are where each source axis ends up.
    M = Matrix((
        (0.0, 0.0, 0.001, 0.0),      # X comes from source Z
        (0.0, 0.001, 0.0, 0.0),      # Y comes from source Y -- tip stays forward
        (-0.001, 0.0, 0.0, 0.0),     # Z comes from negated source X -- handle goes up
        (0.0, 0.0, 0.0, 1.0),
    ))
    ob.data.transform(M)
    ob.matrix_world = Matrix.Identity(4)
    # Straight off the mesh data. `ob.dimensions` reads the evaluated bounding box, which has
    # not refreshed this early and reports the pre-transform size -- which looks exactly like
    # the transform silently failing.
    step("oriented; size now {} m".format(mesh_size(ob)))

    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob

    # ---- weld and fix normals -----------------------------------------------------------
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=WELD_DISTANCE)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    step("welded to {:,} triangles".format(tri_count(ob)))

    # ---- decimate -----------------------------------------------------------------------
    # Collapse rather than planar. Planar merges coplanar faces and looks tempting on CAD, but
    # it leaves n-gons and does nothing for the cylinders -- which is where the triangles
    # actually are. A 23 mm ring in this model carries 28,904 of them.
    before = tri_count(ob)
    target = args["tris"]
    if before > target:
        mod = ob.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = float(target) / float(before)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(ob)
    step("decimated {:,} -> {:,} triangles ({:.1f}% kept)".format(
        before, after, 100.0 * after / before))

    # Smooth shading with a 30 degree break, so cylinders read as round and machined edges
    # stay crisp. Flat shading on a decimated cylinder shows every facet.
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(30))
    except Exception as exc:
        step("auto smooth unavailable, using plain smooth ({})".format(exc))

    # ---- UVs ----------------------------------------------------------------------------
    # An STL has no UVs, so there is nothing to preserve and a projection is the only option.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    step("unwrapped; {} UV layer(s)".format(len(ob.data.uv_layers)))

    # ---- bake ambient occlusion into a diffuse map --------------------------------------
    # The model has no texture and will not get a hand-painted one from a script. What it can
    # have is real contact shading -- creases between the flutes, under the bale handle,
    # inside the teeth -- which is most of what makes a metal object read as solid.
    img = bpy.data.images.new("mi_nozzle_d", TEXTURE_SIZE, TEXTURE_SIZE)

    mat = bpy.data.materials.new("mi_nozzle_bake")
    mat.use_nodes = True
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = img
    mat.node_tree.nodes.active = tex_node
    ob.data.materials.clear()
    ob.data.materials.append(mat)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        scene.cycles.device = "CPU"
        scene.cycles.samples = AO_SAMPLES
        scene.cycles.use_denoising = False
    except Exception as exc:
        step("cycles tuning skipped ({})".format(exc))
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 8

    step("baking ambient occlusion at {}px, {} samples".format(TEXTURE_SIZE, AO_SAMPLES))
    bpy.ops.object.bake(type="AO")

    # Tint the occlusion by the body colour. Straight AO is greyscale; this is what turns it
    # into a usable diffuse map rather than a shading pass.
    px = list(img.pixels)
    r, g, b = BASE_COLOUR
    for i in range(0, len(px), 4):
        ao = px[i]
        px[i] = ao * r
        px[i + 1] = ao * g
        px[i + 2] = ao * b
        px[i + 3] = 1.0
    img.pixels = px

    tex_path = os.path.join(args["out"], "mi_nozzle_d.png")
    img.filepath_raw = tex_path
    img.file_format = "PNG"
    img.save()
    step("wrote " + tex_path)

    # ---- save ---------------------------------------------------------------------------
    blend_path = os.path.join(args["out"], "mi_nozzle.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    step("wrote " + blend_path)

    lo, hi = mesh_bounds(ob)
    print("[build] final: {:,} tris, {:,} verts, bounds {} .. {}".format(
        tri_count(ob), len(ob.data.vertices),
        tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi)))
    print("BUILD-OK")


main()
