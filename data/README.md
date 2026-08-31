# data

Game data files declared with `data_file` in `fxmanifest.lua`.

| File | What it does |
|---|---|
| `weaponarchetypes.meta` | Declares the model `w_mi_nozzle`, making it exist as far as the game is concerned. |
| `weapons.meta` | Defines `WEAPON_MINOZZLE` and points it at that model. |

Both are **ours**, written from the schema and naming our own model. The nozzle they describe
is built from a CAD file by `tools/assets/nozzle/` and shipped as `stream/w_mi_nozzle.ydr` with
its texture embedded.

Everything about how the weapon *behaves* is inherited from the base game fire extinguisher —
`AMMO_FIREEXTINGUISHER`, `FIRE_EXT_STRAFE`, `DamageType FIRE_EXTINGUISHER`,
`FireType VOLUMETRIC_PARTICLE`. Those are Rockstar's own identifiers, so a new weapon gets
defined here without carrying anyone else's content. It does no damage on purpose: water
knocking a fire down is mi_fire's own simulation, applied server-side from the hose module.

## Three things that each cost a round of testing

**A weapon model is inert without its archetype.** Shipping a `.ydr` alone leaves the weapon
unknown to every client no matter how many refreshes and reconnects it is given — which reads
exactly like a streaming failure and is not one. An archetype is only needed because this is a
*new* model; a weapon reusing a base game model needs none.

**`data_file` declares; `files` ships.** A meta declared but not listed in `files` never reaches
a client at all, which also reads exactly like a missing archetype. `conventions_spec` pairs the
two blocks so that gap fails the build.

**The three files have to agree.** `<Model>` here, `<modelName>` in the archetype, and the
`.ydr` in `stream/` all name the same thing, and `config/hose.lua`'s `nozzleWeapon` matches
`<Name>`. Nothing in Lua notices when they drift and the symptom is a weapon that silently never
appears, so `conventions_spec` asserts all four.

## Nothing here is borrowed

Four weapon metas were copied from **SmartHose** and removed again — its assets are
escrow-encrypted and made FiveM refuse to start this resource:

> Couldn't find asset key for encrypted resource mi_fire

The schema of a `CWeaponInfo` is Rockstar's, not anyone's to own; the values in these files are
ours. See `ASSET-001` in `docs/internal/TASKS.md`.
