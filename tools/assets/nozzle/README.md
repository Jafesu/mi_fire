# The nozzle

A fog nozzle of our own, built from a CAD model rather than borrowed. This is the answer to
`ASSET-001`, and the reason it can be answered is that nothing here comes from another
resource — the source is a CAD file, and every step from it to a `.ydr` is in this directory.

## What the source is

An **ASCII STL**, 47 MB, `183,404` triangles, in millimetres, measuring 296 × 214 × 122 mm —
which is 11.7 × 8.4 × 4.8 inches, the size of a real nozzle. Two `.dwg` files (AutoCAD 2010
format) and three renderings come with it. Neither the DWGs nor the renderings are used by the
build; the STL is the only input.

The STL is **not in this repository**. It is 47 MB, it never changes, and it is not ours to
redistribute. It lives outside the repo and its path is passed in on the command line.

What an STL does *not* carry matters as much as what it does: **no UVs, no materials, no
textures, no normals worth keeping, and no scale unit.** It is a bag of triangles. Everything a
game needs is added by `build_nozzle.py`, which is why that script is longer than it looks like
it should be.

## Running it

Two steps, deliberately separate. The first is pure Blender and always works; the second needs
the Sollumz add-on. Keeping them apart means a Sollumz problem never costs the geometry work.

```sh
BLENDER="/d/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"
SRC="C:/Users/<you>/Downloads/fire-hose-nozzle/079.stl"
OUT="build/nozzle"

# 1. geometry: orient, scale, decimate, unwrap, bake
"$BLENDER" -b --factory-startup --python tools/assets/nozzle/build_nozzle.py -- --src "$SRC" --out "$OUT"

# 2. drawable: Sollumz shader material, convert, export .ydr
#    NOTE: no --factory-startup on this one. See below.
"$BLENDER" -b --python tools/assets/nozzle/export_ydr.py -- --blend "$OUT/mi_nozzle.blend" --out "$OUT"
```

`--tris N` overrides the triangle budget on step 1 if 8,000 turns out to be the wrong call.

### Do not pass `--factory-startup` to step 2

It does not merely disable add-ons — it discards the extension *repository* list, so Sollumz
cannot even be resolved:

> Add-on not loaded: "bl_ext.repo_sollumz_org.sollumz", cause: extension repository
> "repo_sollumz_org" doesn't exist

Step 1 uses factory startup happily because it needs nothing but stock Blender.

## The three things that were hard

**Orientation.** The source has the fog tip toward **+Y** and the bale handle toward **−X**.
GTA wants the tip forward and the handle up. The mapping is `(x, y, z) -> (z, y, -x)` with a
0.001 scale, written as a single matrix because the chained-rotation version was wrong twice
and a matrix can be checked against a bounding box by eye.

This was settled by rendering the model with a red cube at +Y and a blue cube at +Z and
*looking at it*. Reading axes off part centroids gave the wrong answer twice — the down-barrel
view shows the far end of the nozzle filling the silhouette, so the end that looks like the tip
is the end that isn't.

**Triangle count.** `183,404` down to `8,000`, keeping 4.4%. The triangles are not where you
would expect: a **23 mm ring carries 28,904 of them** and the bale handle carries 47,116. That
is ordinary CAD tessellation, which spends its budget on curvature rather than on what reads at
arm's length. Collapse decimation rather than planar — planar merges coplanar faces, which
looks tempting on CAD, but it leaves n-gons and does nothing for the cylinders where the
triangles actually live.

**No texture at all.** An STL has none, and a script is not going to hand-paint one. What it
can do is bake **ambient occlusion** — the creases between the flutes, under the bale handle,
inside the teeth — and tint it by a body colour. That contact shading is most of what makes a
metal object read as solid, and it costs one bake.

## What comes out

| File | What it is |
|---|---|
| `mi_nozzle.blend` | The working file. Open it to change anything by hand. |
| `mi_nozzle_d.png` | 1024² baked diffuse. |
| `mi_nozzle.ydr` | The drawable. `RSC7`, resource version 165 — a real RAGE container. |

## What is not done yet

The `.ydr` exists and is a valid resource. It is **not yet a working weapon in game.** Still
needed, in order:

1. **The texture has to reach the game.** Either embedded in the drawable or shipped as a
   `.ytd` beside it. An unembedded texture renders untextured, which looks like a broken model
   rather than a missing file.
2. **`weapons.meta`** — a `CWeaponInfo` naming the model and `DamageType FIRE_EXTINGUISHER`,
   which is the type SmartHose gave its own nozzle and a fair signal it is what the game
   expects for a sprayer.
3. **`weaponarchetypes.meta`** — required here, because this *is* a new model. A weapon that
   reuses a base game model needs no archetype; ours does.
4. **Both declared with `data_file` and listed in `files`.** Declaring alone sends nothing to
   the client and looks exactly like a missing archetype. `conventions_spec` tests this.
5. **`MIFireHose.visuals.nozzleWeapon`** set to the new weapon name. That is the only line of
   Lua that changes — everything else needed to hold, attach, and clean up a nozzle is already
   written and is currently pointed at `WEAPON_FIREEXTINGUISHER`.

Until then the fallback stays, and the fallback is fine: a base game extinguisher that sprays.
