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

**What is in here right now is borrowed and is not in the repository.**

`w_am_hose.ydr` / `.ytd` are copied from **SmartHose** so the hose has a nozzle in hand while
our own model is made. They are gitignored, so a clone of this repository contains the code and
none of somebody else's art — which means shipping them cannot happen by accident, only
deliberately.

The resource runs without them. The prop does not load, `MIFireHose.visuals.nozzleProp` logs a
warning, and the hose works with nothing in the hand.

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
