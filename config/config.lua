--- Core configuration.
---
--- Feature-specific tuning lives in its own file next to this one. This is for things
--- that do not belong to any single system.
---
--- Every file in `config/` is documented option by option in `docs/configuration/`.

Config = {}

--- Verbose logging on both server and client consoles. Safe to leave on while tuning;
--- it is read live, so toggling it does not need a restart.
Config.debug = false

--- Jobs treated as firefighters. Anything gated on being a firefighter -- turnout,
--- hose lines, the pump panel, admin-exempt targets -- checks against this.
Config.fireJobs = {
    fireman = true,
    fire = true,
    firefighter = true,
    lsfd = true,
}

--- Jobs treated as EMS, for victim handoff.
Config.emsJobs = {
    ambulance = true,
    ems = true,
    doctor = true,
}

--- Require the player to be clocked on duty, not merely to hold the job.
Config.requireOnDuty = true

--- Does protective equipment only work for firefighters?
---
--- **No, by default.** Turnout gear is a coat, not a permission. If a civilian gets hold of
--- a set, it protects them exactly as much as it protects anyone else, because that is what
--- the coat does. The same goes for SCBA: a bottle of air works for whoever is breathing it.
---
--- The line is drawn somewhere more sensible instead -- **taking equipment off an
--- apparatus or a station rack** is still department business and stays job-gated. Getting
--- hold of the gear is the gate; using it is not.
---
--- Set true if you would rather protection was a job perk.
Config.gearRequiresJob = false

--- Who can use the admin commands in `server/modules/admin/`.
---
--- Two independent routes in, because they answer different questions. ACE answers "is this
--- person a server administrator"; job and grade answers "is this person the fire chief".
--- A chief running a drill should not need to be handed server admin, and a server admin
--- testing a scene should not need to clock on as a firefighter.
Config.permissions = {
    --- ACE objects that grant full access. Any one is enough.
    aces = {
        'mi_fire.admin',
        'command.fire',
    },

    --- Principals granted the mi_fire ACE automatically at boot, so no `server.cfg` edit is
    --- needed. `group.admin` is how Qbox gates its own admin commands
    --- (`qbx_core/server/commands.lua`), so anyone who can run those can run these.
    ---
    --- Set to an empty table to require an explicit grant instead:
    ---     add_ace group.admin mi_fire.admin allow
    principals = {
        'group.admin',
        'group.god',
    },

    --- Job name to minimum grade level. A grade at or above the number gets access.
    --- This is why the commands are not ACE-restricted at the FiveM level: a job grade is
    --- runtime state and cannot be expressed as an ACE.
    jobs = {
        fireman = 4,
    },

    --- Whether job-based access also requires being clocked on. Independent of
    --- `Config.requireOnDuty`, since an off-duty chief may still need to stop a runaway fire.
    jobsRequireOnDuty = false,

    --- Subcommands reachable through *job* access. ACE admins always get everything.
    --- Set to nil to give job holders the full command set.
    ---
    --- The default withholds nothing destructive so much as nothing surprising: a chief can
    --- run the whole fireground, but `wind` changes weather for the entire server.
    jobCommands = {
        'here', 'start', 'at', 'stop', 'stopall', 'list', 'info', 'agent', 'classes', 'perms', 'render', 'sizeup', 'vent',
    },
}

--- Command names. Nothing user-facing is hardcoded in module code.
Config.commands = {
    fire = 'fire',            -- /fire start|stop|stopall|list|info|here|at
    aop = 'aop',              -- /aop set|add|remove|list|auto|clear
    district = 'district',    -- /district list|info|here
    offsetFinder = 'fireoffset',
}

--- How often the server advances fire simulation. Lower is smoother and more expensive.
--- Node counts scale with this, so measure before lowering it on a busy server.
Config.tickMs = 1000

--- Hard ceilings. These exist to stop a runaway generation bug from taking a server
--- down, and they are deliberately not generous.
Config.limits = {
    maxIncidents = 8,
    maxNodesPerIncident = 40,
    maxNodesTotal = 200,
    maxHoseLinesPerVehicle = 6,
}

--- Uniforms
--- Distance beyond which a client stops rendering and simulating a node locally.
--- The server keeps simulating; this is purely what a given player is shown.
Config.renderDistance = 200.0

--- Persist active incidents across a resource restart. Useful during development so a
--- restart does not wipe a scene you were testing.
Config.persistIncidents = false

return Config
