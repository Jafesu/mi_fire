### `ASSET-001` — a nozzle of our own, in game, being tuned

**Done on disk.** A real fog nozzle, built from a CAD model, with nothing borrowed:

- `stream/w_mi_nozzle.ydr` — 8,000 triangles from 183,404, texture embedded.
- `data/weaponarchetypes.meta` — the archetype, required because this is a new model.
- `data/weapons.meta` — `WEAPON_MINOZZLE`, behaviour inherited from the base game extinguisher.
- `fxmanifest.lua` — both metas declared with `data_file` **and** listed in `files`.
- `config/hose.lua` — `nozzleWeapon = 'WEAPON_MINOZZLE'`.

`tools/assets/nozzle/` holds the whole recipe in two headless scripts, and its README explains
the parts that were not obvious.

**It loads.** First in-game run reported `assetLoaded=1 object=true`, so the metas reach the
client and the model is real. Two things were wrong and are now fixed, pending a retest:

- **It was not equipped.** `CreateWeaponObject` makes a world object and attaches it to a bone,
  which cannot be fired and has no stance. Now `GiveWeaponToPed` + `SetCurrentPedWeapon`.
- **The model origin was its centre, and then its barrel.** For an equipped weapon the origin
  *is* the grip. It is now on the **bale handle**, which is what a bale handle is for — the grab
  handle a firefighter actually carries and works a nozzle by. Holding it by the barrel looked
  wrong for the same reason carrying a kettle by the spout would.

**The carrying stance is two clipsets, not one, and that was the T-pose.** A nozzle on a charged
line is braced at the waist in both hands — the minigun shape. Getting there means calling the
right native:

| Kind | Native | What it is | Names |
|---|---|---|---|
| **weapon** | `SetPedStrafeClipset` | how it is **held** and aimed | `weapons@heavy@minigun` |
| **movement** | `SetPedMovementClipset` | the walk, run and idle | usually `move_…` |

`weapons@heavy@minigun` is what the game's own `weaponanimations.meta` lists as the minigun
`WeaponClipSetHash`, so it is the right name — it was being passed to the wrong native. A weapon
clipset carries no walk or idle clips, so as a movement clipset there is nothing to stand in and
the skeleton falls back to its bind pose. `HasAnimSetLoaded` returns true either way, so there is
no check to write, only the right call to make.

`/fire nozzlehold <clipset|off> [move]` tries either kind live.

Still shipped as a native call rather than a `weaponanimations.meta`: that file replaces the
game's whole animation set instead of merging, which is why both resources here that ship one
carry a 13,000 line copy of the vanilla data.

**ox_inventory strips it, and the fix is one line of server config.** Measured, not guessed:
the weapon was equipped and gone again within seconds. The mechanism is `ox_inventory/client.lua`
around line 1408 —

```lua
elseif client.weaponmismatch and not client.ignoreweapons[weaponHash] then
    local weaponType = GetWeapontypeGroup(weaponHash)
    if weaponType ~= 0 and weaponType ~= `GROUP_UNARMED` then
        Weapon.Disarm(currentWeapon, true)
```

— any weapon the player did not equip *through the inventory* is disarmed unless it is in
`ignoreweapons`. That list is the escape hatch for exactly this case, and it is a convar:

```cfg
setr inventory:ignoreweapons ["WEAPON_MINOZZLE"]
```

Their `init.lua` already hardcodes `ignoreweapons[`WEAPON_HOSE`] = true` for SmartHose, which is
the same fix applied the messy way — a resource edit that a future ox_inventory update wipes.
The convar survives updates.

**`WEAPON_HOSE` is SmartHose's, and it is stale.** `failed to equip WEAPON_HOSE` is that item
trying to equip a weapon that no longer exists on the server; nothing to do with mi_fire. Our
nozzle is deliberately not an inventory item — it comes from taking the nozzle on a line, so
nobody walks around with one attached to nothing.

Five things that had to be right, each of which cost a round of testing:

- **`GiveWeaponToPed`, not `CreateWeaponObject`.** The opposite of what this list used to say.
  The claim that ox_inventory strips a directly-given weapon was measured while the weapon had
  no archetype -- and a weapon that does not exist is absent right after being given, which
  looks identical. It was never the inventory.
- The model origin is where the hand goes. There are no Lua offsets for an equipped weapon.
- `RequestWeaponAsset` then wait on `HasWeaponAssetLoaded`. Skipping it returns 0, which looks
  exactly like a missing archetype.
- The metas need `data_file` **and** `files`. Declaring alone ships nothing, which also looks
  exactly like a missing archetype.
- Sollumz will only embed **DDS**. A PNG is skipped with a warning and the export still reports
  success — recognisable only by a .ydr that did not grow.

`conventions_spec` now holds the last two as tests, along with the model name agreeing across
all three files.

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
