### `ASSET-001` — a nozzle weapon of our own

`WEAPON_HOSE` and four meta files are borrowed from **SmartHose**, along with `w_am_hose.ydr`
and its texture. All of it is gitignored: a clone gets the `data_file` declarations and none of
the art, so the resource starts (FiveM warns about a missing data file rather than refusing) and
shipping somebody else's weapon cannot happen by accident.

**It has to be a weapon, not a prop.** A nozzle sprays, and a prop cannot be fired. A weapon
also gives the two-handed grip and the aiming stance, which is what holding a charged line looks
like. That makes the replacement a larger job than a model -- it needs an archetype in a
`weaponarchetypes.meta`, an entry in `weapons.meta`, and the `data_file` lines to register both.

**What cost four rounds of testing**, worth writing down because none of it is guessable:

The `.ydr` alone is inert -- a weapon needs its archetype, so copying only the model left it
unknown to every client no matter how many refreshes and reconnects it was given. That was twice
diagnosed as a streaming problem.

`IsWeaponValid` and `IsModelInCdimage` both answer about the base game, so a custom asset fails
them while working perfectly. Using either as a gate refuses to try and then reports the asset as
missing, which sends the search after the asset rather than the check.

And it is **not given as a weapon**. Equipping one means ox_inventory owns it -- it syncs the
hand to whatever is equipped from the inventory, so a weapon handed over directly is removed
within the second. `CreateWeaponObject` makes a world object from the weapon hash instead:
nothing is equipped, no inventory is involved, and the weapon archetype is exactly what it wants.
SmartHose's own config said so in one line -- `HoseModel = WEAPON_HOSE` beside a timeout for
"the hose model to be loaded" -- and reading it first would have saved all four rounds.

The boot check names every borrowed asset and its owner on each start, and `conventions_spec`
fails if something is used that is neither base game nor declared in `visuals.borrowed`.

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
