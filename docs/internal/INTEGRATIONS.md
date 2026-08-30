# Integrations

Verified facts about the resources `mi_fire` talks to. Every `file:line` here was read,
not assumed.

**Re-verify before you depend on one.** These resources get updated, and a fact that was
true in session 001 may not be true now. A stale row here is worse than no row.

---

## lb-tablet — dispatch

**Role:** the active MDT and dispatch system. Fire calls go to its board.

**Export:** `exports['lb-tablet']:AddDispatch(payload)` — server side, takes one table.

**Verified:** payload shape read from a working integration in
`[custom]/mi_gunrunner/server/shipments.lua:151-164`, and from lb-tablet's own
compatibility shims at `[lb]/lb-tablet/server/custom/functions/dispatch/dispatchCompatibility.lua:29`.

```lua
{
    job = 'fireman',            -- or an array of job names
    mdts = { ... },             -- takes precedence over `job` when non-empty
    priority = 'high',          -- 'high' | 'medium' | 'low'
    code = '10-70',
    title = 'Structure Fire',
    description = '...',
    location = {
        label = 'Pillbox Hill',
        coords = vector2(x, y), -- vector2, not vector3
    },
    time = 900,                 -- seconds the call stays on the board
    notificationTime = 20,
    sound = true,
    fields = { { icon = 'droplet', label = 'Water supply', value = 'Hydranted' } },
    blip = {
        type = 'radius', radius = 60.0, randomCoords = false,
        sprite = 436, color = 1, size = 0.9, shortRange = false, label = 'Structure Fire',
    },
}
```

**Notes:**

- `AddDispatch` is a global inside lb-tablet's escrowed Lua; only the export is callable.
- `location.coords` is a **vector2**. Passing a vector3 is the most likely mistake here.
- Our wrapper is `bridge/dispatch/init.lua`. Nothing in `server/modules/` sees this shape.

---

## mi_fire_rescue — civilian victims

**Role:** ambient civilians flee, injure, and become rescuable at fire scenes. Firefighter
carry, EMS handoff, hospital admission.

**Depends on us for:** `GetAllFires()` — called on **both** client and server.

**Verified:** `[custom]/mi_fire_rescue/client/main.lua:596-598` and
`[custom]/mi_fire_rescue/server/main.lua`. It reads the resource name from
`Config.SmartFiresResource`, so migration is a one-line config change once our export
matches.

**Required return shape** — an array of rows:

```lua
{
    id, coords, incidentId, sourceIncidentId,
    type,            -- 'outdoors' | 'indoors'
    active,          -- boolean
    live,            -- boolean; false once knocked down
    pendingSeed,     -- boolean
    strength, isDead, generation,
}
```

**Migration:** set `Config.SmartFiresResource = 'mi_fire'` in `mi_fire_rescue/config.lua`.
Tracked as `API-003`. Not done yet — the export does not exist.

---

## mi_fire_origins — being retired

**Role:** ambient NPC-origin fire generation, currently against SmartFires.

**Depends on us for:** `CreateFire`, `GetAllFires`, `GetActiveVehicleFires`,
`GetFiresForIncident`, `ProbeInteriorAtCoords`, all server side.

**Verified:** `[custom]/mi_fire_origins/server/main.lua:112, 124, 140, 553, 564, 652, 765`.

`CreateFire(x, y, z, fireType, radius, count, explicitInteriorId, suppressExternalDispatch)`

**Plan:** its behaviour moves into `server/modules/generation/`, and the resource is
retired rather than repointed (`GEN-004`). Worth reading before writing the generation
module — its MLO discovery approach and its distance and staffing gates are sound, and the
reasoning behind them is written up in its README.

---

## illenium-appearance — turnout gear

**Role:** clothing swap when donning and doffing turnout.

**Exports verified** at `[standalone]/illenium-appearance/game/util.lua:392-413`:
`getPedAppearance`, `setPedAppearance`, `setPedComponents`, `setPedComponent`,
`setPedProps`, `setPedProp`.

**Note:** it registers exports with `exports('name', fn)`, so they are called as
`exports['illenium-appearance']:setPedComponents(ped, components)`.

**Important:** appearance is cosmetic only. Fire resistance is read from
`server/core/state.lua`, never from what the player is wearing.

---

## qbx_medical — injury and death

**Role:** decides what happens when a firefighter runs out of health. mi_fire injures; it
never decides that someone is dead.

**Verified** in `[disabled]/qbx_medical`:

| Fact | Where |
|---|---|
| Last stand is decided from `CEventNetworkEntityDamage` | `client/dead.lua:118` |
| It uses `ApplyDamageToPed` on itself for bleed damage | `client/wounding.lua:61` |
| Client exports `IsDead`, `IsLaststand`, `StartLastStand` | `client/main.lua:59`, `client/laststand.lua:94` |
| Death state is on the Qbox player as `metadata.isdead` / `metadata.inlaststand` | `server/main.lua:37` |

**The finding that matters:** `SetEntityHealth` does **not** raise a damage event. A
resource that sets health directly is invisible to qbx_medical -- a firefighter would slide
to zero and die outright with no last stand, no bleeding, and no injury record. `bridge/medical/init.lua`
uses `ApplyDamageToPed` instead, which is what qbx_medical does to itself.

The server reads death state from framework metadata rather than asking the client, because
the client being asked may be the unconscious one.

**Note:** qbx_medical is currently in `[disabled]` and `osp_ambulance` is running. The
bridge prefers qbx_medical, falls back to osp_ambulance, and falls back again to raw health
checks -- so it works either way, and the fallback path is the one running today.

## ox_target, ox_lib, ox_inventory

Standard. `ox_lib` and `ox_target` are hard dependencies in the manifest; `ox_inventory`
is optional and bridged, because gear integrity and SCBA air degrade to "not persisted"
rather than breaking when it is absent.

---

## Reference only — not dependencies

The London Studios fire stack is on this drive and is **reference only**. No code, assets,
config values, or file layout are taken from it.

| Resource | Path |
|---|---|
| SmartFires | `D:/Projects/FiveM/SmartFires` and `[standalone]/[ls]/[tools]/SmartFires` |
| SmartHose | `[standalone]/[ls]/[tools]/SmartHose` |
| Supply-Line | `[standalone]/[ls]/[tools]/Supply-Line` |
| watermonitor, SCBA, FireTools | `[standalone]/[ls]/[tools]/` |

Useful for understanding the shape of the problem — the per-vehicle offset schema in
`SmartHose/config.lua:163-347` and the hydrant prop offsets in `Supply-Line/config.lua:162-167`
show what data a working system needs to carry. What that data should *be* on this server
is a job for our own offset finder.
