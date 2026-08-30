# Configuration

All configuration is in `config/`. One file per system. Every option carries a comment in
the file itself saying what it does — this reference explains the ones where the *why*
matters more than the *what*.

Changes need a resource restart unless noted otherwise.

## The files

| File | Covers |
|---|---|
| `config.lua` | Jobs, commands, tick rate, limits |
| `dispatch.lua` | Dispatch provider and how calls are presented |
| `zones.lua` | Districts, area of play, run cards |
| `fire_classes.lua` | How each class of fire behaves |
| `agents.lua` | What puts each class out, and what makes it worse |
| `gear.lua` | Turnout, proximity, and hazmat protection |

Files for later phases — `hose.lua`, `apparatus.lua`, `hydrants.lua`, `ladders.lua`,
`stations.lua`, `scba.lua`, `hazmat.lua`, `rescue.lua` — are documented as they ship.

---

## The options that matter most

### Your job names

In `config.lua`:

```lua
Config.fireJobs = { fireman = true, fire = true, firefighter = true, lsfd = true }
```

If your fire job is not in this table, nothing in mi_fire will work for your firefighters.
This is the single most common installation mistake.

`Config.requireOnDuty` means holding the job is not enough — the player has to be clocked
on. Set it to `false` if your server has no duty system.

### Who can run the fire commands

Two independent routes, in `config.lua`. ACE answers "is this a server administrator"; job
and grade answers "is this the fire chief".

```lua
Config.permissions = {
    aces       = { 'mi_fire.admin', 'command.fire' },
    principals = { 'group.admin', 'group.god' },
    jobs       = { fireman = 4 },
}
```

`principals` is granted at boot, so **Qbox admins work with no `server.cfg` edit**. Job
grade cannot be an ACE -- it is runtime state -- which is why the commands are gated in the
resource rather than by FiveM, and why a refused player gets told why instead of "unknown
command".

Full detail in [Permissions](../getting-started/permissions.md). If it refuses someone,
`/fire perms` explains exactly why.

### How busy the server feels

In `zones.lua`. Area of play is the strongest knob you have. It decides *where* ambient
fires can start, which on a small server is the difference between a department that feels
busy and one that spends every call driving to Paleto.

```lua
MIFireZones.aop.mode = 'auto'
```

| Mode | Behaviour |
|---|---|
| `'auto'` | Districts go live where players actually are. Recommended. |
| `'manual'` | Only what an admin sets with `/aop`. |
| `'all'` | The whole map is live. Only sensible on a large, well-staffed server. |

In auto mode, `activateAtPlayers` is how many players make a district live, and
`holdSeconds` is how long it stays live after they leave. That hold exists so a district
does not flicker off every time a crew crosses a boundary — lower it too far and you will
watch generation thrash.

`minimumDistanceFromPlayers` is worth respecting. A call the crew watched appear is not a
call.

### District character

Each district declares what burns there. This is what stops every call being the same
call:

```lua
la_mesa = {
    kind = 'industrial',
    fireClasses = { A = 0.7, B = 1.2, C = 0.6, D = 0.25, gas = 0.4, vehicle = 0.5 },
    hydrantDensity = 1.0,
    maxFloors = 3,
}
```

Set `hydrantDensity` honestly. Below `0.3`, mi_fire tells the responding crew on the
dispatch that they are looking at a shuttle or a draft rather than a hydrant, and that
changes how they respond before they leave the station.

`maxFloors` matters more than it looks. In a high-rise district, elevation loss becomes a
real pump problem — five psi per floor adds up, and a crew on the twentieth floor needs a
hundred psi they would not need at ground level.

### Difficulty

To make fires harder, raise `growthPerSecond` and `resistance` in `fire_classes.lua`, or
lower the master knock-down rate in `agents.lua`:

```lua
MIFireAgents.suppression.intensityPerSecondAtReferenceFlow = 9.0
```

Lower that and every fire takes longer to put out.

**Do not** make things easier by removing negative effectiveness from the agent matrix.
Water on a Class D fire is `-1.0` on purpose, and water into hot cooking oil is `-0.8`. If
players are being caught out by those, that is the system working. Point them at
[Firefighting basics](../guides/firefighting-basics.md) instead.

### Protection

In `gear.lua`:

```lua
structural = {
    fireResist = 0.75,
    integrity = 100,
    degradeRate = 2.0,
    ignitionThreshold = 0.20,
}
```

| Option | What it does |
|---|---|
| `fireResist` | Fraction of flame damage removed. **Must stay below 1.0.** |
| `heatResist` | Fraction of radiant heat build-up removed. |
| `integrity` | Durability pool spent while standing in flame. |
| `degradeRate` | Integrity lost per second of contact at full fire intensity. |
| `ignitionThreshold` | Integrity fraction below which the wearer can catch fire. |

The resource **refuses to boot** if any tier has `fireResist` at 1.0 or above, because
nothing may grant immunity to fire. If you want a more forgiving fireground, raise
`integrity` — that gives crews longer inside without ever making them invulnerable.

Note there is no smoke field anywhere in this file. Smoke is stopped by SCBA and nothing
else, by design. Turnout gear will not help a firefighter who is breathing.

### Dispatch

In `dispatch.lua`:

```lua
Config.Dispatch = {
    provider = 'lb-tablet',
    resource = 'lb-tablet',
    recipients = { jobs = { 'fireman' }, mdts = {} },
}
```

`provider` is `'lb-tablet'`, `'custom'`, or `'none'`. `'none'` is a legitimate choice if
your server runs calls over the radio.

For anything else, set `provider = 'custom'` and write `Config.CustomDispatch`. It
receives the built payload and returns true on success — no code changes needed elsewhere.

`minSecondsBetweenCalls` is a rate limit. It exists so that a misconfigured generation
setting produces one confusing call rather than fifty.
