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

## The things that were hard

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
inside the teeth — which is most of what makes a metal object read as solid, and it costs one
bake.

**Material zones, because the nozzle is not one colour.** Black rubber bumper and handle grip,
olive-drab anodized body, a polished ring. Two bakes — occlusion, and a flat colour pass — are
multiplied together, so either can be retuned without redoing the other.

Placing the zones needs both geometry *and* connectivity. The bale handle arrives as a single
CAD island covering its olive arms and its black ribbed grip, so only a height threshold splits
it; and the handle passes straight through the slice of barrel where the polished ring belongs,
so a rule written in coordinates alone paints fragments of the handle chrome. Grouping faces
into connected islands first removes the ambiguity. The positions came off a colour-coded
render of the CAD parts, not from guesswork.

**Sollumz will only embed DDS.** This is the one that wastes an afternoon. Hand it a PNG and it
logs a warning, skips the texture, and **still reports a successful export** — the only visible
symptom is a .ydr that did not grow. Nothing on this machine converts to DDS and Blender cannot
write one, so `build_nozzle.py` writes it directly: uncompressed A8R8G8B8, thirty lines of
header and a numpy array.

Two traps sit next to it. An image made with `images.new` has source `GENERATED`, which stores
the parameters it would be regenerated from and *not* the pixels — so saving the blend and
reopening it in the export step hands back a blank image. And Sollumz prefers packed bytes over
the file path, so packing a PNG wins over the DDS on disk and gets rejected. File-backed,
unpacked, `.dds`.

## What comes out

| File | What it is |
|---|---|
| `mi_nozzle.blend` | The working file. Open it to change anything by hand. |
| `mi_nozzle_d.png` | Baked diffuse, for looking at. Not shipped. |
| `mi_nozzle_d.dds` | The same map as uncompressed DDS. **This is the one that gets embedded.** |
| `w_mi_nozzle.ydr` | The drawable. `RSC7`, resource version 165 — a real RAGE container. |

Copy the `.ydr` into `stream/`. The texture rides inside it, so nothing else needs shipping.

## Wired up

All of it is in place:

| Piece | Where |
|---|---|
| Model | `stream/w_mi_nozzle.ydr`, texture embedded |
| Archetype | `data/weaponarchetypes.meta` — makes the model exist |
| Weapon | `data/weapons.meta` — `WEAPON_MINOZZLE` |
| Manifest | `data_file` **and** `files` for both metas |
| Config | `MIFireHose.visuals.nozzleWeapon = 'WEAPON_MINOZZLE'` |

`conventions_spec` asserts the model name agrees across all three files and that the config
points at the right weapon — a mismatch there is invisible until someone picks up a line.

The weapon's behaviour is inherited from the base game fire extinguisher
(`AMMO_FIREEXTINGUISHER`, `FIRE_EXT_STRAFE`, `DamageType FIRE_EXTINGUISHER`). Those are
Rockstar's identifiers, so the meta defines a new weapon without carrying anyone's content. It
does no damage — water knocking a fire down is mi_fire's own simulation, applied server-side.

**Not yet tested in game.** Everything above is verified on disk and by the test suite; none of
it has been loaded by FiveM. Restart the resource and reconnect, then `/fire nozzle`.

## Worth improving later

- **The texture is uncompressed**, so it costs width x height x 4 bytes and every player
  downloads it. 512 is 1 MB. A BC1 encoder would allow 1024 at 512 KB, and is maybe a hundred
  lines of block packing — skipped because a wrong encoder looks like a texture bug rather than
  an encoder bug, and there was no DDS reader here to check it against.
- **The teeth on the bumper get chewed** by decimation at 4.4%. Raising `--tris` helps; so
  would keeping the tip at full density and decimating the rest.
- **No collision or LODs.** Neither matters for something attached to a hand.
