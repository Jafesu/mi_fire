"""Export the built nozzle mesh as a GTA V drawable (.ydr) through Sollumz.

Run headless:

    blender -b --python tools/assets/nozzle/export_ydr.py -- --blend <mi_nozzle.blend> --out <dir>

Separate from `build_nozzle.py` on purpose. The build is pure Blender and always works; this
half depends on the Sollumz add-on being installed, and keeping them apart means a Sollumz
problem never costs the geometry work.

Sollumz is an *extension* rather than a legacy add-on, so its module is
`bl_ext.repo_sollumz_org.sollumz`.

**Do not pass `--factory-startup` to this one.** It does not merely disable add-ons, it
discards the extension *repository* list, so the module cannot even be resolved and the
enable fails with `extension repository "repo_sollumz_org" doesn't exist`. `build_nozzle.py`
uses factory startup happily because it needs nothing but stock Blender; this half needs the
user's configured repositories, so it runs against the normal startup and enables the add-on
explicitly in case it is installed but switched off.
"""

import bpy
import os
import sys

SOLLUMZ_MODULE = "bl_ext.repo_sollumz_org.sollumz"

# Sollumz names the exported file after the drawable object, and the game finds the model by
# the name in `data/weaponarchetypes.meta`. They have to agree, so the rename happens here
# rather than being left to whatever the blend file was called.
DRAWABLE_NAME = "w_mi_nozzle"

# Diffuse and a spec map, which is what a metal object wants and what the AO bake feeds.
# Ordered by preference: the first one this Sollumz build actually offers is used.
SHADER_PREFERENCE = ("normal_spec.sps", "spec.sps", "default.sps")


def step(msg):
    print("[ydr] " + msg, flush=True)


def parse_args():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"blend": None, "out": None}
    i = 0
    while i < len(args):
        if args[i] == "--blend":
            out["blend"] = args[i + 1]
            i += 2
        elif args[i] == "--out":
            out["out"] = args[i + 1]
            i += 2
        else:
            i += 1
    if not out["blend"] or not out["out"]:
        raise SystemExit("need --blend <file> and --out <dir>")
    return out


def enable_sollumz():
    bpy.ops.preferences.addon_enable(module=SOLLUMZ_MODULE)
    if not hasattr(bpy.ops, "sollumz"):
        raise SystemExit("Sollumz enabled but registered no operators")
    step("Sollumz enabled")


def pick_shader():
    from bl_ext.repo_sollumz_org.sollumz.ydr.shader_materials import shadermats
    available = {m.value for m in shadermats}
    for name in SHADER_PREFERENCE:
        if name in available:
            step("shader {} (of {} available)".format(name, len(available)))
            return name
    raise SystemExit("none of {} available; Sollumz offers {}".format(
        SHADER_PREFERENCE, sorted(available)[:20]))


def attach_diffuse(mat, image):
    """Point the shader's diffuse sampler at the baked map.

    Sollumz names its texture nodes after the RAGE shader parameter, so the diffuse one is
    `DiffuseSampler`. Matching on the name rather than the first image node matters: these
    shaders also carry spec and bump samplers, and writing the diffuse into the bump slot
    produces a nozzle that renders but looks wrong in a way that is hard to trace back.
    """
    candidates = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]
    named = [n for n in candidates if "diffuse" in n.name.lower()]
    target = named[0] if named else (candidates[0] if candidates else None)
    if target is None:
        step("WARNING: shader has no image node; texture not attached")
        return None
    target.image = image

    # The name the drawable refers to its texture by is read-only and derived: Sollumz takes
    # the image's file name, lowercased. So it comes from what `build_nozzle.py` wrote, and the
    # only thing that matters here is that it is not blank -- the exporter skips blank ones.

    # Embed rather than ship a separate .ytd. One file instead of two, and no second name to
    # keep in step with the archetype. `txdName` in the archetype still names the model, which
    # is the convention whether or not the textures live inside the drawable.
    try:
        target.texture_properties.embedded = True
        step("diffuse -> node '{}' (embedded)".format(target.name))
    except AttributeError:
        step("diffuse -> node '{}' (NOT embedded -- a .ytd will be needed)".format(target.name))
    return target


def main():
    args = parse_args()
    os.makedirs(args["out"], exist_ok=True)

    enable_sollumz()
    bpy.ops.wm.open_mainfile(filepath=args["blend"])
    step("opened " + args["blend"])

    ob = bpy.data.objects.get("mi_nozzle")
    if ob is None:
        raise SystemExit("mi_nozzle not in the blend file")
    ob.name = DRAWABLE_NAME
    ob.data.name = DRAWABLE_NAME

    image = bpy.data.images.get("mi_nozzle_d")
    if image is None:
        step("WARNING: baked texture missing from the blend")

    # Swap the plain bake material for a real Sollumz shader material. The bake material is a
    # stock Principled BSDF, which Sollumz cannot export -- a drawable needs a RAGE shader.
    from bl_ext.repo_sollumz_org.sollumz.ydr.shader_materials import create_shader
    shader_name = pick_shader()
    mat = create_shader(shader_name)
    mat.name = DRAWABLE_NAME
    if image is not None:
        attach_diffuse(mat, image)

    ob.data.materials.clear()
    ob.data.materials.append(mat)

    # RAGE shaders read a UV map named "UVMap 0" and a colour attribute named "Color 1".
    # `create_shader` alone does not add them, because the interactive path does it in the
    # operator afterwards -- which this script bypasses. Without it the export still succeeds
    # and merely warns, and the nozzle arrives in game untextured.
    #
    # Sollumz's own helper is used rather than creating them here: it *renames* what the mesh
    # already has, by order, before adding anything. Creating a "UVMap 0" directly would leave
    # the real unwrap sitting on a layer named "UVMap" and export an empty one.
    from bl_ext.repo_sollumz_org.sollumz.ydr.operators.materials import (
        post_create_shader_update_object)
    post_create_shader_update_object(ob, mat)
    step("material assigned; uv maps {}, colour attrs {}".format(
        [uv.name for uv in ob.data.uv_layers],
        [c.name for c in ob.data.color_attributes]))

    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob

    bpy.ops.sollumz.converttodrawable()
    step("converted to drawable")

    # The convert wraps the mesh in a new Drawable empty; that parent is what exports, so the
    # selection has to move up to it. Exporting with the mesh selected produces nothing and
    # reports success, which is a confusing five minutes if you have not hit it before.
    drawable = None
    for obj in bpy.context.scene.objects:
        if getattr(obj, "sollum_type", "") == "sollumz_drawable":
            drawable = obj
            break
    if drawable is None:
        raise SystemExit("no drawable produced by converttodrawable")

    bpy.ops.object.select_all(action="DESELECT")
    drawable.select_set(True)
    bpy.context.view_layer.objects.active = drawable
    step("drawable '{}' selected".format(drawable.name))

    out_dir = os.path.abspath(args["out"])
    # `target_formats` is not a list of file extensions -- it is how to encode, and the only
    # values are NATIVE and CWXML. What kind of asset gets written is decided by the object's
    # `sollum_type`, which `converttodrawable` set. NATIVE gives the binary .ydr the game
    # loads; CWXML gives the CodeWalker XML, which is worth exporting alongside because it is
    # readable and diffable when something about the drawable needs checking.
    bpy.ops.sollumz.export_assets(
        directory=out_dir + os.sep,
        target_formats={"NATIVE"},
        limit_to_selected=True,
        apply_transforms=True,
        direct_export=True,
    )

    produced = [f for f in os.listdir(out_dir) if f.lower().endswith(".ydr")]
    if not produced:
        raise SystemExit("export reported no error but wrote no .ydr into " + out_dir)
    for f in produced:
        size = os.path.getsize(os.path.join(out_dir, f))
        print("[ydr] wrote {} ({:,} bytes)".format(f, size))
    print("YDR-OK")


main()
