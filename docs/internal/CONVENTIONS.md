# Conventions

How code here is written. Most of these exist because breaking them causes a specific
class of bug, not because of taste.

---

## 1. Architecture

### 1.1 Transports are thin

A command, an export, a net event, and an NUI callback are four doors into the same room.
Put the logic in the room.

```lua
-- Wrong: logic in the transport
RegisterNetEvent('mi_fire:server:chargeLine', function(lineId)
    local line = Lines[lineId]
    if not line then return end
    if GetJob(source) ~= 'fireman' then return end
    line.charged = true
    TriggerClientEvent('mi_fire:client:lineCharged', -1, lineId)
end)

-- Right: the transport is one line
RegisterNetEvent('mi_fire:server:chargeLine', function(lineId)
    Hose.charge(source, lineId)
end)
```

Four copies of a permission check is four places to get it wrong.

### 1.2 Permission checks live at the service boundary, once

`Hose.charge` checks. Everything calling it inherits the check. Not in the transport, not
in the UI, not in both.

### 1.3 The server owns truth

A client may say "I am aiming a nozzle here". It may not say "this fire is out". Anything
a client asserts about world state is a request, validated server side against where the
server thinks that player is — see `MIFire.Permissions.isNear`.

### 1.4 Nothing framework-specific outside `bridge/`

`qbx_core`, `QBX.`, `ESX.` appearing in `server/modules/`, `client/modules/`, or `shared/`
is a defect. Add a method to the framework interface instead.

### 1.5 Nothing hardcoded that is configurable

| Never hardcode | Comes from |
|---|---|
| Job names | `Config.fireJobs`, `Config.emsJobs` |
| Command names | `Config.commands` |
| District names | `MIFireZones.districts` |
| Dispatch recipients | `Config.Dispatch.recipients` and run cards |
| Fire behaviour | `MIFireClasses` |
| Agent effectiveness | `MIFireAgents.matrix` |
| Gear numbers | `MIFireGear.tiers` |

A literal `'fireman'` in module code is a bug.

### 1.6 Clean up what you create

Ropes, props, PTFX loops, blips, and target zones survive a resource stop. Register them
with the trackers in `client/main.lua`. The "restart twice" verification step exists
because the second restart is where a leak shows.

---

## 2. Lua

- Lua 5.4 in game (`lua54 'yes'`). But **`shared/` must parse under 5.1**, because the
  test runner uses whatever interpreter is available. No `//`, no bitwise operators, no
  `goto` in shared code.
- `ox_lib` is a hard dependency. Use `lib.callback`, `lib.addCommand`, `lib.addKeybind`,
  `lib.zones`, `lib.points`, `lib.progressBar`.
- `local` everything. A stray global in a shared script is visible to every resource.
- One module per directory under `server/modules/<name>/`, with `init.lua` exposing the
  service table and registering transports.
- Annotate with LuaLS types (`---@param`, `---@return`, `---@class`). The pump panel and
  the export surface both benefit, and it costs a line.

### Naming

- Files and directories: `snake_case`.
- Functions and locals: `camelCase`.
- Config globals and classes: `PascalCase`.
- Events: `mi_fire:server:verbNoun` and `mi_fire:client:verbNoun`.
- Exports: `PascalCase`, matching what the consumer expects.

### Comments

Explain the *why*, and the fireground reasoning where there is any. A comment that
restates the code is noise; a comment saying "water on a Class D fire dissociates into
hydrogen and oxygen, which is why this is negative" is the reason the next person does not
"fix" it.

---

## 3. Numbers

- Real fire service constants live in `shared/hydraulics.lua` and are **not tuning values**.
  Changing a friction-loss coefficient makes the resource lie to a pump operator who knows
  the real number. Tune `config/`.
- Anything shown to a player is rounded at the presentation layer, never in the model.
  `MIFire.Util.round` exists for this.
- Distances are compared squared inside loops. `MIFire.Util.distance3dSq`.

---

## 4. Configuration

- One file per system, in `config/`. Each gets a matching page in `docs/configuration/`.
- Every option carries a comment saying what it does and what changing it costs.
- Validate at boot in `server/main.lua`. Refuse to start on an invalid config rather than
  half-working — a resource that boots into a broken state is harder to debug than one
  that says why it will not.

---

## 5. Tests

- `shared/` is testable and tested. Everything there is pure.
- Tests assert against known-correct answers, not against current behaviour. A test that
  records what the code does today is worth nothing tomorrow.
- Run `lua tools/run_tests.lua` before every commit. Never commit a red suite.
