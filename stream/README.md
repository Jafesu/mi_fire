# stream

Streamed assets for mi_fire. **Empty, and deliberately so.**

`w_am_hose.ydr` / `.ytd` were copied from **SmartHose** and removed again. They are
escrow-encrypted, and putting them here made FiveM refuse to start this resource:

> Couldn't find asset key for encrypted resource mi_fire

That is what escrow is for. The files are readable from disk and tied to their owner's asset
key, so they are unusable anywhere else — including here. Earlier notes claimed escrow covered
only the Lua and not the stream folder. That was wrong.

**Do not copy assets out of an escrowed resource.** Not these, not `Supply-Line`'s water pump.
The result is not a licensing argument, it is a resource that will not load.

---

> **New files here need `refresh` on the server and a `reconnect` on the client.** The asset
> index is built on refresh; a client keeps the list it was given when it joined.

See `ASSET-001` in `docs/internal/TASKS.md`.
