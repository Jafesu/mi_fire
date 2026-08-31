# stream

Streamed assets for mi_fire.

**What is in here right now is borrowed and is not in the repository.**

`w_am_hose.ydr` / `.ytd` and `rope.ytd` are copied from **SmartHose** so the hose has a nozzle
in hand and a hose-coloured rope while our own models are made. They are gitignored, so a clone
of this repository contains the code and none of somebody else's art — which means shipping
them cannot happen by accident, only deliberately.

The resource runs without them. The prop does not load, `MIFireHose.visuals.nozzleProp` logs a
warning, and the hose works with nothing in the hand.

`rope.ytd` is worth understanding separately: it replaces the game's rope texture dictionary,
so it changes the appearance of **every** rope on the server, not only ours. That is how
SmartHose recolours its own hose. If some other resource's ropes suddenly look like fire hose,
this is why.

Replace both before release. See `ASSET-001` in `docs/internal/TASKS.md`.
