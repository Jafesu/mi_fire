# data

Game data files declared with `data_file` in `fxmanifest.lua`. **Empty.**

Four weapon metas were copied here from **SmartHose** to define its hose nozzle, and removed
again: they are escrow-encrypted and made FiveM refuse to start the resource.

> Couldn't find asset key for encrypted resource mi_fire

Two things learned along the way are worth keeping, because a nozzle of our own will need both:

**A weapon model is inert without its archetype.** Copying a `.ydr` alone leaves the weapon
unknown to every client no matter how many refreshes and reconnects it is given — which reads
exactly like a streaming failure and is not one.

**`data_file` declares; `files` ships.** A meta declared but not listed in `files` never reaches
a client at all, which also reads exactly like a missing archetype. `conventions_spec` now pairs
the two blocks so that gap fails the build.

See `ASSET-001` in `docs/internal/TASKS.md`.
