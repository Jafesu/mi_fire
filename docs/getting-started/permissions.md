# Permissions

## Admin

Every admin command is gated on one ACE permission:

```cfg
add_ace group.admin mi_fire.admin allow
```

Change the permission name with `Config.adminAce` if your server uses a different scheme.

The server console is always allowed, so fire commands work from the console without
granting anything.

Admins also bypass the firefighter job check. That is deliberate: testing a hose line
should not require clocking on first.

## Firefighters

Not an ACE permission. Firefighters are identified by job, through whatever framework you
run.

```lua
-- config/config.lua
Config.fireJobs = {
    fireman = true,
    fire = true,
    firefighter = true,
    lsfd = true,
}

Config.requireOnDuty = true
```

`requireOnDuty` means holding the job is not enough; the player has to be clocked on. Set
it to `false` if your server does not use a duty system.

## EMS

Same idea, for victim handoff at fire scenes.

```lua
Config.emsJobs = {
    ambulance = true,
    ems = true,
    doctor = true,
}
```

## No framework

If mi_fire cannot find Qbox or ESX, it runs standalone. Everyone is a civilian, and only
admins can use fire equipment. That is enough to test the resource on a bare server, and
not enough to run it in production.
