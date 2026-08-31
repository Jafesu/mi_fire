# data

Weapon metadata, declared with `data_file` in `fxmanifest.lua`.

**Borrowed and gitignored.** These four files come from **SmartHose** and define `WEAPON_HOSE`,
the hose nozzle a firefighter holds. They are development only.

They matter more than they look. A weapon model is inert without its archetype, so
`stream/w_am_hose.ydr` does nothing at all unless `weaponarchetypes.meta` is present *and*
declared. Copying only the model leaves the weapon unknown to every client no matter how many
times the server is refreshed or a player reconnects — which reads exactly like a streaming
failure and is not one.

A clone of this repository has the `data_file` declarations and none of these files. FiveM warns
about a missing data file and starts anyway, so the resource runs and the nozzle is simply
absent.

Replace before release. See `ASSET-001` in `docs/internal/TASKS.md`.
