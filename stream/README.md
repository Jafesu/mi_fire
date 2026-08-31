# stream

Streamed assets for mi_fire.

**What is in here right now is borrowed and is not in the repository.**

`w_am_hose.ydr` / `.ytd` are copied from **SmartHose** so the hose has a nozzle in hand while
our own model is made. They are gitignored, so a clone of this repository contains the code and
none of somebody else's art — which means shipping them cannot happen by accident, only
deliberately.

The resource runs without them. The prop does not load, `MIFireHose.visuals.nozzleProp` logs a
warning, and the hose works with nothing in the hand.

`rope.ytd` was here and was removed. It replaces the game's rope texture dictionary, which
changes **every** rope on the server — including the rappel rescue rope in `mi_utils`. Nothing
scopes that: GTA resolves rope textures through `ropedata.xml` against one shared dictionary,
and no native overrides one rope's texture.

The hose therefore draws as a default GTA rope for now. Making it look like hose without
touching anyone else's means not using `AddRope` at all, which is `HOSE-010`.

Replace the nozzle before release. See `ASSET-001` in `docs/internal/TASKS.md`.
