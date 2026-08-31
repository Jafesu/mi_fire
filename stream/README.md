# stream

Streamed assets for mi_fire.

**What is in here right now is borrowed and is not in the repository.**

`w_am_hose.ydr` / `.ytd` are copied from **SmartHose** so the hose has a nozzle in hand while
our own model is made. They are gitignored, so a clone of this repository contains the code and
none of somebody else's art — which means shipping them cannot happen by accident, only
deliberately.

The resource runs without them. The prop does not load, `MIFireHose.visuals.nozzleProp` logs a
warning, and the hose works with nothing in the hand.

## `rope.ytd` — under test

Back in place to answer one question that cannot be answered from here.

A `.ytd` replaces textures **by name**. If this one contains only the entries for the rope type
SmartHose uses, it changes that type and nothing else. If it contains the whole dictionary, it
changes **every** rope on the server — including the rappel rescue rope in `mi_utils`.

The file is RSC7-compressed and unreadable, so the only way to find out is to look:

1. Pull a hose line. It should look like hose.
2. Use the rappel rope in `mi_utils`.
3. **Did the rappel rope change?**

- **No** — it is scoped, this stays, and `HOSE-010` loses one of its three reasons.
- **Yes** — it has to go. A hose that looks right at the cost of every other rope on the
  server is not a trade worth making, and the answer becomes the rewrite in `HOSE-010`.

Note the rope types were also moved off 7, which the rappel uses, so if the rappel *has*
changed it is the texture doing it rather than a shared type.

---

Replace the nozzle before release, and this too if it stays. See `ASSET-001` in
`docs/internal/TASKS.md`.
