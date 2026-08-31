# stream

Streamed assets for mi_fire.

> **New files here need two things, and the second is the one people miss.**
>
> On the server: `refresh`, then `ensure mi_fire`. The asset index is built on refresh;
> restarting a resource that already exists reuses the index it had.
>
> On the client: **reconnect**. A client keeps the asset list it was given when it joined, so a
> server-side refresh does not reach anyone already in the server. F8 → `reconnect` is enough;
> a full game restart is slower and does the same thing.
>
> If a model survives both, it is not being streamed at all — check the filename matches the
> model name exactly, and that both the `.ydr` and its `.ytd` are present.

**Nothing is in here right now.**

`w_am_hose.ydr` and `.ytd` were copied from **SmartHose** and then removed, because they do not
work on their own and the reason is worth keeping.

`w_am_hose` is not a prop. It is a **weapon archetype**, defined in SmartHose's
`weaponarchetypes.meta` and registered through four `data_file` declarations in its manifest.
Copying the `.ydr` gives the game a mesh with no archetype to hang it on, so it stays unknown to
every client no matter how many times anyone refreshes or reconnects — which is exactly what
happened, twice, before anyone read the other manifest.

Making it work would mean copying four meta files and registering a custom weapon into the
game's weapon tables. Larger borrow, a collision with SmartHose if it were ever enabled, and —
the deciding point — it would build the nozzle around a weapon when the replacement will be a
prop. That is a pipeline to throw away.

The nozzle is a base game prop instead. `/fire nozzle` tries the candidates in turn and attaches
each for two seconds, which is the quickest way to find one that does not look absurd.

## `rope.ytd` — tested, global, removed

It was here to answer one question: does it retexture only the rope type SmartHose uses, or the
whole dictionary?

**Tested in game. Every rope changed**, including the rappel rescue line in `mi_utils`. So it is
gone, and the question is settled — this is not a matter of finding the right file or the right
rope type. GTA resolves rope textures through `ropedata.xml` against one shared dictionary and
nothing scopes that.

The hose uses rope type **6** instead, the thickest of the eight built-in types, which is as
close to hose as is available without abandoning ropes. `/fire ropetypes` lays them all out if
you want to see for yourself.

Looking like actual hose waits for `HOSE-010`, which replaces the rope with a chain of our own
segments and makes rope type irrelevant.

---

Replace the nozzle before release, and this too if it stays. See `ASSET-001` in
`docs/internal/TASKS.md`.
