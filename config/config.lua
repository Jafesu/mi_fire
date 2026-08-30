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

--- ACE permission for every admin command in `server/modules/admin/`.
Config.adminAce = 'mi_fire.admin'

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

--- Distance beyond which a client stops rendering and simulating a node locally.
--- The server keeps simulating; this is purely what a given player is shown.
Config.renderDistance = 200.0

--- Persist active incidents across a resource restart. Useful during development so a
--- restart does not wipe a scene you were testing.
Config.persistIncidents = false

return Config
