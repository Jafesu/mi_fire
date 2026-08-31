"""Turn the CAD nozzle into a game-ready mesh.

Run headless:

    blender -b --factory-startup --python tools/assets/nozzle/build_nozzle.py \
        -- --src <079.stl> --out <dir>

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
import struct
import sys
from mathutils import Matrix, Vector

# A weapon the player holds and looks straight at. GTA V handguns sit near 2-4k triangles and
# rifles near 6-10k, so this is deliberately at the generous end of normal.
TARGET_TRIS = 8000

# Where the right hand goes.
#
# For an *equipped* weapon this is the only control there is: GTA puts the model origin at the
# hand bone and the animation does the rest. There are no attach offsets to tune in Lua, so
# this constant is the one knob, and it is why the origin is not simply the centre.
#
# On the barrel axis (z = 0) because a hand wrapping a cylinder sits on its centreline, and a
# little behind the middle so the bale handle ends up above and slightly forward of the fist,
# which is where it belongs. This model has no pistol grip -- the disc underneath is the bale
# handle's pivot plate, not something to hold.
GRIP_ORIGIN = (0.0, -0.015, 0.0)

# 0.1 mm. STL stores every triangle's corners independently, so the mesh arrives as loose
# triangles that merely touch. Without this there are no shared edges: nothing is smoothable
# and decimation has nothing to collapse along.
WELD_DISTANCE = 0.0001

# 512, not 1024. The texture is written uncompressed, so it costs width x height x 4 bytes
# and every player downloads it: 512 is 1 MB, 1024 is 4 MB, for an object the size of a fist.
# A BC1 encoder would give 1024 at 512 KB and is the obvious later improvement.
TEXTURE_SIZE = 512
AO_SAMPLES = 24

# Ambient occlusion goes fully black in a deep crease, which on a small object reads as a hole
# rather than a shadow. Compressing it into this range keeps the contact shading while letting
# the zone colour stay legible everywhere.
AO_FLOOR = 0.45

# --------------------------------------------------------------------------------------------
# Material zones
#
# The nozzle is not one colour. It is a black rubber bumper and handle grip, an olive-drab
# anodized body, and a polished band around the barrel. Colours are given in sRGB because that
# is what a colour picker shows and what the reference render was matched against; Blender
# works in linear, so they are converted on the way in. Setting linear values directly here is
# the usual way this ends up looking washed out.
ZONES = {
    "rubber": (0.16, 0.16, 0.16),   # matte black bumper and grip
    "olive":  (0.38, 0.38, 0.29),   # anodized body
    "chrome": (0.85, 0.86, 0.88),   # polished band
}

# Where each zone lives, in metres, in final orientation (tip +Y, up +Z). These came off a
# colour-coded render of the CAD parts (`zonemap`), not from guesswork -- the layout along the
# barrel is, front to back: toothed tip, big drum, bale handle, mid-body, body, coupling stem.
GRIP_MIN_Z = 0.100          # above this is the ribbed handle grip, below is its olive arm

# The black bumper is two CAD parts, not one: a drum of radius 0.058 and the toothed tip of
# radius 0.038 in front of it. An earlier threshold of 0.045 caught the drum and left the tip
# olive, which is why this is 0.030 -- low enough for both, high enough to leave the bore alone.
COLLAR_MIN_Y = 0.019
COLLAR_MIN_RADIUS = 0.030

# The polished ring. This is the flange at the base of the bumper -- a genuine disc in the CAD,
# radius 0.027 out to 0.061, sitting at y 0.012 -- rather than a slice of arbitrary barrel.
# Two earlier attempts cut a band through whatever happened to be at a chosen depth and caught
# small fittings and the handle mount, which rendered as torn white fragments. Landing it on a
# part that is actually a ring is what makes it read as one.
CHROME_Y = (0.008, 0.016)
CHROME_RADIUS = (0.026, 0.065)

def linear_to_srgb_np(a):
    import numpy as np
    return np.where(a <= 0.0031308, a * 12.92,
                    1.055 * np.power(np.clip(a, 0.0, None), 1.0 / 2.4) - 0.055)


def write_dds(path, pixels, width, height):
    """Write an uncompressed 32-bit DDS.

    Sollumz will only embed DDS. It checks that the packed bytes begin with `DDS ` or that the
    file ends in `.dds`, and warns and skips anything else -- so a PNG produces an export that
    reports success and silently carries no texture at all, recognisable only by a .ydr that
    did not grow. Nothing on this machine converts to DDS and Blender cannot write one, so it
    is written here.

    Uncompressed A8R8G8B8 rather than BC1, deliberately: a block compressor is a hundred lines
    of bit packing that cannot be validated without a reader, and being wrong there would look
    like a texture bug rather than an encoder bug. This is thirty lines that are either right
    or obviously not.

    Blender stores pixels bottom-up and linear; DDS wants top-down, and a diffuse map wants
    sRGB. Both conversions happen here.
    """
    import numpy as np

    a = np.array(pixels, dtype=np.float32).reshape(height, width, 4)[::-1]
    srgb = linear_to_srgb_np(a[..., :3])

    out = np.empty((height, width, 4), dtype=np.uint8)
    out[..., 0] = np.clip(srgb[..., 2] * 255.0 + 0.5, 0, 255)   # B
    out[..., 1] = np.clip(srgb[..., 1] * 255.0 + 0.5, 0, 255)   # G
    out[..., 2] = np.clip(srgb[..., 0] * 255.0 + 0.5, 0, 255)   # R
    out[..., 3] = np.clip(a[..., 3] * 255.0 + 0.5, 0, 255)      # A

    header = struct.pack(
        "<4sIIIIIII44sIIIIIIIIIIIII",
        b"DDS ",
        124,                 # header size
        0x0000100F,          # caps | height | width | pitch | pixelformat
        height, width,
        width * 4,           # pitch
        0,                   # depth
        1,                   # mip levels
        bytes(44),           # reserved
        32,                  # pixel format size
        0x00000041,          # DDPF_RGB | DDPF_ALPHAPIXELS
        0,                   # fourCC -- zero, because this is uncompressed
        32,                  # bits per pixel
        0x00FF0000,          # red mask
        0x0000FF00,          # green
        0x000000FF,          # blue
        0xFF000000,          # alpha
        0x00001000,          # DDSCAPS_TEXTURE
        0, 0, 0, 0,          # caps 2-4, reserved
    )
    assert len(header) == 128, "DDS header must be 128 bytes, got {}".format(len(header))

    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(out.tobytes())


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


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


def mesh_bounds(ob):
    lo = Vector((1e30,) * 3)
    hi = Vector((-1e30,) * 3)
    for v in ob.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    return lo, hi


def mesh_size(ob):
    lo, hi = mesh_bounds(ob)
    return tuple(round(hi[i] - lo[i], 3) for i in range(3))


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def step(msg):
    print("[build] " + msg, flush=True)


def face_components(mesh):
    """Group faces into connected islands.

    Worth the code because a purely positional rule cannot get this right. The bale handle
    passes straight through the slice of barrel where the polished ring belongs, so any rule
    written in coordinates alone paints fragments of the handle chrome -- which is exactly what
    the first attempt did. Knowing which faces belong to the handle removes the ambiguity.
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()

    comp_of = [-1] * len(bm.faces)
    comps = []
    for face in bm.faces:
        if comp_of[face.index] != -1:
            continue
        cid = len(comps)
        stack = [face]
        members = []
        comp_of[face.index] = cid
        while stack:
            cur = stack.pop()
            members.append(cur.index)
            for edge in cur.edges:
                for nb in edge.link_faces:
                    if comp_of[nb.index] == -1:
                        comp_of[nb.index] = cid
                        stack.append(nb)
        comps.append(members)
    bm.free()
    return comp_of, comps


def classify_face(centre, is_handle):
    """Which material zone a face belongs to.

    The handle arrives from CAD as a single island covering both its olive arms and its black
    ribbed grip, so no per-island rule can separate them -- but a height threshold can.
    """
    radius = math.hypot(centre.x, centre.z)

    if is_handle:
        return "rubber" if centre.z > GRIP_MIN_Z else "olive"

    if centre.y > COLLAR_MIN_Y and radius > COLLAR_MIN_RADIUS:
        return "rubber"
    if (CHROME_Y[0] <= centre.y <= CHROME_Y[1]
            and CHROME_RADIUS[0] <= radius <= CHROME_RADIUS[1]):
        return "chrome"
    return "olive"


def build_zone_materials(ob, image):
    """One material per zone, each with the bake target as its active image node."""
    ob.data.materials.clear()
    index_of = {}
    for name, srgb in ZONES.items():
        mat = bpy.data.materials.new("mi_nozzle_" + name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            lin = tuple(srgb_to_linear(c) for c in srgb)
            bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.name = "bake_target"
        mat.node_tree.nodes.active = tex
        index_of[name] = len(ob.data.materials)
        ob.data.materials.append(mat)
    return index_of


def set_bake_target(ob, image):
    for mat in ob.data.materials:
        node = mat.node_tree.nodes.get("bake_target")
        if node is not None:
            node.image = image
            mat.node_tree.nodes.active = node


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

    # Move the mesh so GRIP_ORIGIN lands on (0, 0, 0).
    ob.data.transform(Matrix.Translation((-GRIP_ORIGIN[0], -GRIP_ORIGIN[1], -GRIP_ORIGIN[2])))

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

    # ---- assign zones -------------------------------------------------------------------
    # After decimation, because decimation changes which faces exist.
    img_ao = bpy.data.images.new("mi_nozzle_ao", TEXTURE_SIZE, TEXTURE_SIZE)
    img_col = bpy.data.images.new("mi_nozzle_col", TEXTURE_SIZE, TEXTURE_SIZE)
    index_of = build_zone_materials(ob, img_ao)

    # The bale handle is the only island that reaches this high, which is what identifies it.
    comp_of, comps = face_components(ob.data)
    handle_comp = -1
    best_z = GRIP_MIN_Z
    for cid, members in enumerate(comps):
        top = max(ob.data.polygons[i].center.z for i in members)
        if top > best_z:
            best_z = top
            handle_comp = cid
    step("{} islands; handle is #{} (reaches z {:.3f})".format(
        len(comps), handle_comp, best_z))

    tally = dict.fromkeys(ZONES, 0)
    for poly in ob.data.polygons:
        zone = classify_face(poly.center, comp_of[poly.index] == handle_comp)
        poly.material_index = index_of[zone]
        tally[zone] += 1
    step("zones: " + ", ".join("{} {}".format(v, k) for k, v in tally.items()))

    # ---- bake -----------------------------------------------------------------------------
    # Two passes into two images, multiplied together. Ambient occlusion supplies the contact
    # shading -- the creases between the flutes, under the bale handle, inside the teeth --
    # which is most of what makes a metal object read as solid. The colour pass supplies the
    # zones. Baking them separately means either can be retuned without redoing the other.
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

    step("baking occlusion at {}px, {} samples".format(TEXTURE_SIZE, AO_SAMPLES))
    set_bake_target(ob, img_ao)
    bpy.ops.object.bake(type="AO")

    step("baking zone colours")
    set_bake_target(ob, img_col)
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE")

    ao = list(img_ao.pixels)
    col = list(img_col.pixels)
    out = [0.0] * len(col)
    for i in range(0, len(col), 4):
        shade = AO_FLOOR + (1.0 - AO_FLOOR) * ao[i]
        out[i] = col[i] * shade
        out[i + 1] = col[i + 1] * shade
        out[i + 2] = col[i + 2] * shade
        out[i + 3] = 1.0

    img = bpy.data.images.new("mi_nozzle_d", TEXTURE_SIZE, TEXTURE_SIZE)
    img.pixels = out

    # The drawable wants one material, not three. The zones have done their job -- they are
    # baked into the map now, and three shader materials would mean three draw calls for a
    # thing the size of a fist.
    for mat in list(ob.data.materials):
        mat.node_tree.nodes.active = None
    ob.data.materials.clear()
    flat = bpy.data.materials.new("mi_nozzle_baked")
    flat.use_nodes = True
    tex = flat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    flat.node_tree.links.new(
        flat.node_tree.nodes["Principled BSDF"].inputs["Base Color"], tex.outputs["Color"])
    ob.data.materials.append(flat)
    for poly in ob.data.polygons:
        poly.material_index = 0

    png_path = os.path.join(args["out"], "mi_nozzle_d.png")
    img.filepath_raw = png_path
    img.file_format = "PNG"
    img.save()
    step("wrote " + png_path + " (preview)")

    dds_path = os.path.join(args["out"], "mi_nozzle_d.dds")
    write_dds(dds_path, out, TEXTURE_SIZE, TEXTURE_SIZE)
    step("wrote {} ({:,} bytes)".format(dds_path, os.path.getsize(dds_path)))

    # Point the image at the DDS, and do not pack it.
    #
    # Both halves matter. An image made with `images.new` has source GENERATED, which stores
    # the parameters it would be regenerated from and not the pixels -- so reopening the blend
    # in the export step handed back a blank image. And Sollumz prefers packed bytes over the
    # file path, so packing a PNG here would win over the DDS and be rejected. File-backed,
    # unpacked, .dds: the exporter reads the bytes straight off disk.
    #
    # It doubles as a check on the header. If the preview render still shows the texture,
    # Blender parsed the DDS this script wrote.
    img.source = "FILE"
    img.filepath = dds_path
    img.reload()

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
