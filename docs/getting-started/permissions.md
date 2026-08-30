# Permissions

## The short version

**If you run Qbox, the fire commands already work for your admins.** mi_fire grants itself
to `group.admin` and `group.god` at boot, which is the same group Qbox gates its own admin
commands on. No `server.cfg` edit needed.

If `/fire` refuses you, run:

```
/fire perms
```

It reports every permission it checked, what you actually hold, and the exact line to add
if you need one. That command is deliberately available to everyone — the person who
cannot use the commands is exactly who needs to see why.

---

## Two ways in

They answer different questions, and they work independently.

| Route | Answers | Who it is for |
|---|---|---|
| **ACE** | Is this a server administrator? | Staff testing or cleaning up |
| **Job and grade** | Is this the fire chief? | Officers running drills in character |

A server admin does not need to clock on as a firefighter to test a scene. A fire chief
does not need server admin to run a drill. Neither route requires the other.

## ACE access

```lua
-- config/config.lua
Config.permissions = {
    aces = { 'mi_fire.admin', 'command.fire' },
    principals = { 'group.admin', 'group.god' },
}
```

`principals` is the convenient part: at boot, mi_fire grants its ACE to each of those
groups. Since `group.admin` already exists on any Qbox server, your admins get access with
no configuration.

To turn that off and require an explicit grant instead, empty the list and add your own:

```cfg
add_ace group.admin mi_fire.admin allow
```

Any single ACE in `aces` is enough. `command.fire` is there because that is the ACE ox_lib
would use if you ever restricted the command yourself.

## Job and grade access

```lua
Config.permissions = {
    jobs = {
        fireman = 4,        -- grade 4 and above
    },
    jobsRequireOnDuty = false,
}
```

A player whose job is listed and whose grade is at or above the number gets access. Grades
come from your framework, so `4` means whatever grade 4 is on your server — check your job
definitions rather than guessing.

`jobsRequireOnDuty` is separate from `Config.requireOnDuty` on purpose. The default is
`false`, so an off-duty chief can still stop a runaway fire. Set it to `true` if you want
rank to only count while clocked on.

### Limiting what rank unlocks

```lua
    jobCommands = {
        'here', 'start', 'at', 'stop', 'stopall', 'list', 'info', 'agent', 'classes', 'perms',
    },
```

Only these subcommands are reachable through *job* access. ACE admins always get
everything.

The default withholds `wind`, which changes weather for the whole server rather than for
one incident. Set `jobCommands = nil` to give job holders the full set.

## What refusals look like

mi_fire tries to tell you which of the two routes failed, because they need different
fixes:

| Message | Means |
|---|---|
| `not permitted (no matching job)` | Neither route. You need an ACE or a listed job. |
| `not permitted (fireman grade 2 is below the required 4)` | Right job, not senior enough. |
| `your rank cannot use "wind"` | Job access works, but not for that subcommand. |

All of them are followed by a nudge to run `/fire perms`.

## Firefighters and EMS

Separate from admin access, and not ACE-based. These gate ordinary gameplay — turnout gear,
hose lines, the pump panel — rather than commands.

```lua
Config.fireJobs = { fireman = true, fire = true, firefighter = true, lsfd = true }
Config.emsJobs  = { ambulance = true, ems = true, doctor = true }
Config.requireOnDuty = true
```

If your fire job is not in `fireJobs`, nothing in mi_fire will work for your firefighters.
That is the most common installation mistake.

Admins bypass the firefighter check, so staff can test equipment without clocking on.

## No framework

If mi_fire cannot find Qbox or ESX, it runs standalone. Job access is unavailable because
there are no jobs, so ACE is the only route. That is enough to test on a bare server and
not enough to run one.
