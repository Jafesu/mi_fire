### `ASSET-001` — a nozzle of our own, half done

**The model exists.** Built from a CAD nozzle, not borrowed from anyone, and the whole recipe is
in `tools/assets/nozzle/` -- see the README there. `183,404` triangles of millimetre-scale CAD
down to `8,000`, oriented for GTA, unwrapped, with ambient occlusion baked to a diffuse map, and
exported through Sollumz to `mi_nozzle.ydr`: `RSC7`, resource version 165, a genuine RAGE
drawable container. Both halves run headless and are reproducible from the STL.

**It is not yet a weapon in game.** What remains is the wiring, and it is the part already
written down below:

1. Get the texture to the client -- embedded in the drawable, or a `.ytd` beside it. An
   unembedded texture renders untextured, which reads as a broken model rather than a missing
   file.
2. `weapons.meta` and `weaponarchetypes.meta`. The archetype **is** required here, because this
   is a new model; a weapon reusing a base game model needs none.
3. Declare both with `data_file` *and* list them in `files`.
4. Point `MIFireHose.visuals.nozzleWeapon` at it. One line.

Until then `WEAPON_FIREEXTINGUISHER` stays, and it is a reasonable stand-in: base game, sprays,
right stance, nothing shipped.

**Nothing from SmartHose can be borrowed. This is settled, not open.** Copying the model and its
four weapon metas made FiveM refuse to start the resource at all:

> Couldn't find asset key for encrypted resource mi_fire

Their assets are escrow-encrypted and tied to their own asset key. Readable from disk and
completely unusable anywhere else, which is exactly what escrow is for. Earlier notes in this
repository said escrow covered the Lua and not the stream folder; that was wrong, and the error
above is the proof. **Do not try again**, with these or with `Supply-Line`'s water pump.

**It wants to be a weapon, not a prop**, because a nozzle sprays and a prop cannot be fired.
Everything needed to *use* one is already written and waiting on the metas:

- `MIFireHose.visuals.nozzleWeapon` takes the name; nothing else changes.
- `CreateWeaponObject` makes a world object from the hash and attaches it to `SKEL_R_Hand`, so
  nothing is ever equipped and no inventory strips it. That last part matters: ox_inventory owns
  the ped's weapons and removes anything handed over with `GiveWeaponToPed` within a second.
- A weapon asset loads like a model -- `RequestWeaponAsset`, then wait on
  `HasWeaponAssetLoaded` -- and skipping that returns 0 in a way that looks exactly like a
  missing archetype.
- It needs a `weaponarchetypes.meta` and a `weapons.meta`, declared with `data_file` **and**
  listed in `files`. Only declaring them sends nothing to the client, which also looks exactly
  like a missing archetype.

Those four are written down because each cost a round of testing and none is guessable from the
native names. `conventions_spec` holds the last two as tests.

### `HOSE-010` — the hose should lie where it was walked, parked

Working, but the rope follows the firefighter rather than staying where it was laid. Pulling a
line away from the rig drags the whole hose with you instead of leaving it on the ground
behind you.

**Do not start by adjusting slack or rope length.** That ground is covered: the rope is created
short and paid out, both ends are pinned every frame rather than attached, and three vertices
are pinned along the outlet axis at the rig. That is the shape SmartHose uses and it is correct
as far as it goes. More slack makes a longer rope between the same two moving points; it does
not make the hose stay put.

The reason is structural. Only two points are held — the coupling and the hand — so everything
between them is a free-hanging catenary that moves whenever either end does. A hose that stays
where it was laid needs the **path** recorded, not just the ends:

- Sample the nozzle holder's position as they walk, dropping a world point every metre or so.
- Pin intermediate rope vertices along that trail rather than leaving them free.
- Drop trail points when the crew moves *away* from the rig; consume them when they walk back,
  so the line takes itself in rather than doubling up.
- The trail is also the honest source for hose length used: distance along the path, not the
  straight line to the rig, which is what a real stretch around a corner costs.

Worth doing at the same time: a **dropped** line currently is not drawn at all, because nothing
records where it is when nobody is holding it. The trail solves that too -- the last point is
where the nozzle was put down.

`Supply-Line` on this drive lays a hose along a road and may already do the trail part; read it
before writing this, the way SmartHose should have been read before the rope.

**This and the texture problem have the same answer.** A hose that stays where it was walked is
a *path*, and a path is rendered as a chain of segments rather than as a rope -- at which point
it is our own model with our own texture, looking like hose, affecting nobody else's ropes, and
lying where it was laid. Three problems, one rewrite. Worth doing that way rather than solving
the rope's appearance first and throwing it away.

**Rope type stops mattering after this.** There are no ropes afterwards, so the choice of 6 is
temporary by construction -- it is the best of a bad set, taken because it costs nothing while
the rewrite waits.

### `HOSE-011` — crew slots, unverified in game

The state, the flow ceiling and the interactions are all written. **None of it has run with two
players.**

Working by inspection and by test: crew tracked per line, join, leave, take nozzle, the flow
ceiling (two on a 2.5 inch are capped at 179 gpm and told so), and a line surviving one hand
short when someone disconnects.

Fixed but unconfirmed: "Back up this line" was registered with `addGlobalPed`, which never
fires on a player ped, so it could not have appeared at all. Now on `addGlobalPlayer`. The
crew list was also sent as a set keyed by server id, which does not arrive at a client with one
meaning; it is a list now. Neither fix has been seen working.

Still modelled and wired to nothing -- correct, tested, unreachable, which is the same shape as
the gear that never burned through:

| | |
|---|---|
| `Hose.aimDrift` | the nozzle should wander when short-handed |
| `Hose.lossChance` | the line should get away, whip, and hurt |
| `Hose.dragWeight` / `dragSpeed` | charged hose should slow a crew down |

Wiring those is what makes a 2.5 inch a three-person line rather than a number in a config
file. `/fire hose` returns both the server's view and the client's in one block, which is the
tool for the next attempt.

### `ASSET-001` — replace the borrowed models

`stream/` holds three files copied from **SmartHose**: `w_am_hose.ydr` and `.ytd` for the
nozzle in hand, and `rope.ytd`, which is the hose texture.

They are copied rather than referenced because those resources are not running on this server,
and a streamed model can only be used by name while the resource that streams it is loaded.

**They are gitignored.** A clone gets the code and none of somebody else's art, so shipping
them cannot happen by accident -- only deliberately. Their escrow covers the Lua rather than
the stream folder, so the files were readable; that is a fact about the packaging and not
permission, and the gitignore is what keeps the distinction from mattering.

The resource runs without them. The prop does not load, the server warns naming the model and
its owner, and the hose works with nothing in the hand.

**`rope.ytd` was tested in game and is global.** Every rope changed, not only ours, so it is
gone. That answer is worth keeping: the texture question is settled, it is not a matter of
finding the right rope type or the right file, and nobody needs to try it again.

The rope is type **6** now, picked by looking at all eight with `/fire ropetypes` -- it is the
thickest, which is as close to hose as a built-in type gets. Thickness is the whole of what is
available without abandoning ropes.

Two things make forgetting hard rather than merely discouraged: the server warns on every start,
and `conventions_spec` fails if a model is used that is neither base game nor declared in
`visuals.borrowed`.

### Remaining phases

| Phase | Scope |
|---|---|
| 3 | Hoses: pull, carry, lay, connect, charge, nozzles, crew slots |
| 4 | Pump operations, hydraulics on live lines, the React panel |
| 5 | Supply, relay, transfer, drafting, ground ladders |
| 6 | SCBA, PASS, hazmat |
| 6b | Station alerting |
| 6c | Sprinkler systems |
| 7 | Water rescue |
| 8 | Polish |
