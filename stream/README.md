# stream

Streamed assets for mi_fire.

## `w_mi_nozzle.ydr`

The fire hose nozzle, and it is **ours**. Built from a CAD model by `tools/assets/nozzle/` —
183,404 triangles of millimetre-scale STL reduced to 8,000, oriented for GTA, unwrapped, with
material zones and ambient occlusion baked into an embedded texture. Read that directory's
README to rebuild or retune it.

The texture is **embedded in the drawable**, so there is no `.ytd` here to keep in step with
the archetype's `txdName`. Sollumz will only embed DDS, so `build_nozzle.py` writes one
directly — a PNG is silently skipped and produces a model that arrives in game untextured.

Three files have to agree for the game to load it, and nothing in Lua notices when they drift:

| File | Says |
|---|---|
| `stream/w_mi_nozzle.ydr` | the model |
| `data/weaponarchetypes.meta` | `modelName` / `txdName` — makes the model exist at all |
| `data/weapons.meta` | `<Model>` — points the weapon at it |

`conventions_spec` asserts all three match, and that `config/hose.lua`'s `nozzleWeapon` matches
the weapon's `<Name>`. That test exists because a mismatch is invisible until someone picks up
a line in game, where it looks exactly like a missing archetype.

## Nothing here is borrowed, and nothing can be

`w_am_hose.ydr` / `.ytd` were copied from **SmartHose** and removed again. They are
escrow-encrypted, and putting them here made FiveM refuse to start this resource:

> Couldn't find asset key for encrypted resource mi_fire

That is what escrow is for. The files are readable from disk and tied to their owner's asset
key, so they are unusable anywhere else — including here. Earlier notes claimed escrow covered
only the Lua and not the stream folder. That was wrong, and the error above is the proof.

**Do not try again**, with those or with `Supply-Line`'s water pump. Building our own took an
afternoon and the result is not encumbered by anyone.
