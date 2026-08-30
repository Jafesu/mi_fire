--- Self-contained breathing apparatus.
---
--- **SCBA is the only defence against smoke, and it is the only thing in mi_fire that
--- grants true immunity to anything.** A sealed mask with air in the bottle stops smoke
--- completely -- and stops nothing else. It does not reduce flame damage, it does not
--- reduce radiant heat, and it ends the moment the bottle does. See ADR 0001.
---
--- Two states, which is what the appearance sets describe:
---
---   **Inactive** -- the set is on the firefighter's back, mask off, air valve shut. No
---   air is used and no protection is given. This is how you arrive.
---
---   **Active** -- mask on, breathing bottle air. Smoke cannot touch you, and the clock
---   is running.
---
--- Air is stored on the item, not on the player, so a bottle carried between rigs keeps
--- its pressure. That is the same pattern `mi_diving` uses for rebreathers.

MIFireScba = {}

--- ox_inventory item. Air lives in its metadata, so each bottle is its own thing.
MIFireScba.item = 'scba'

--- Command and keybind to open and close the air valve. Toggling your own mask is an
--- action on yourself rather than on the world, so it is a keybind rather than an
--- ox_target option -- the ox_target rule is about interacting with things, not with your
--- own equipment.
MIFireScba.toggle = {
    command = 'scba',
    keybind = 'J',
    label = 'Open or close SCBA air',
}

-- ---------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------

--- Slot names follow illenium-appearance's vocabulary. See `bridge/appearance/illenium.lua`.
---
--- These sit on `t-shirt` (component 8), independent of the turnout jacket on `torso2`,
--- so SCBA and turnout can be worn in any combination. That independence is deliberate:
--- SCBA without turnout means you breathe but burn, turnout without SCBA means you
--- survive flame but not smoke, and both are legal states with real consequences.
MIFireScba.appearance = {
    --- On the back, mask off.
    inactive = {
        male   = { ['t-shirt'] = 308 },
        female = { ['t-shirt'] = 308 },
    },

    --- Mask on, breathing.
    active = {
        male   = { ['t-shirt'] = 311 },
        female = { ['t-shirt'] = 311 },
    },
}

-- ---------------------------------------------------------------------------
-- Air
-- ---------------------------------------------------------------------------

MIFireScba.air = {
    --- A full bottle, in seconds of working air. A real 30-minute bottle gives closer to
    --- 15-20 under work, and that gap is the point: rated duration is not working duration.
    capacitySeconds = 1800.0,

    --- Metadata key on the item. Reading and writing the same key as `mi_diving` would be
    --- convenient and wrong -- a dive rebreather is not an SCBA bottle.
    metadataKey = 'air',

    --- Baseline consumption while the mask is on, in air-seconds per real second.
    --- 1.0 means a full bottle lasts its rated duration at rest.
    baseRate = 1.0,

    --- Work drives consumption far more than time does.
    exertion = {
        idle = 1.0,
        walking = 1.3,
        running = 2.1,
        sprinting = 3.2,
        --- Carrying a hose line, a ladder, or a casualty.
        carrying = 1.8,
    },

    --- Heavy smoke makes a firefighter breathe harder even through a mask.
    --- Applied on top of exertion once the exposure model lands.
    smokeMultiplier = 1.25,

    --- Fractions of a full bottle at which the wearer is warned.
    --- A real low-air alarm sounds at one third; the earlier notice is a courtesy.
    warnAt = 0.50,
    lowAirAt = 0.33,
    criticalAt = 0.10,

    --- Refilling at a station or apparatus cascade, in air-seconds per real second.
    refillRate = 300.0,
}

-- ---------------------------------------------------------------------------
-- Where bottles come from
-- ---------------------------------------------------------------------------

--- Racks hand out a bottle and take it back. The item is the bottle, so returning one to
--- a rack is what refills it -- a firefighter cannot hoard a dozen full cylinders in a
--- backpack and never visit a station.
MIFireScba.sources = {
    --- Racks on the apparatus. Offsets are authored with `/fireoffset` in Phase 2; until
    --- then a rack is offered on any configured fire apparatus.
    apparatus = {
        enabled = true,
        --- Port type on the apparatus profile that carries SCBA.
        portType = 'scba_rack',
        --- Until per-vehicle offsets exist, allow the interaction anywhere on the rig.
        fallbackToWholeVehicle = true,
        --- Bottles available per apparatus. nil means unlimited.
        capacity = nil,
        --- Racking a bottle refills it, so a rig is also a cascade.
        refillsOnReturn = true,
    },

    --- Fixed points in a station. These become rows in `mi_fire_station_points` once the
    --- station tool lands (`STN-002`); the list here is the bootstrap for servers that
    --- want a rack before then.
    station = {
        enabled = true,
        pointKind = 'scba_rack',
        refillsOnReturn = true,
        --- Static fallback racks, for use before any station is built in game.
        --- `{ coords = vec3(...), radius = 1.5, label = 'SCBA cascade' }`
        points = {},
    },
}

-- ---------------------------------------------------------------------------
-- PASS device
-- ---------------------------------------------------------------------------

--- Modelled on NFPA 1982. Part of the harness by default.
---
--- Not implemented yet -- these are the numbers `SCBA-005` will use. Written down now
--- because they are the reason the device is worth having, and because a later session
--- guessing them would get the phases wrong.
MIFireScba.pass = {
    enabled = true,

    --- Arms automatically when the air valve is opened.
    armOnActivate = true,

    --- Seconds motionless before the escalating pre-alarm chirp starts.
    preAlarmSeconds = 25.0,

    --- Further seconds of pre-alarm before full alarm. Movement clears the pre-alarm;
    --- it does not clear a full alarm, which needs a manual reset on the device.
    fullAlarmSeconds = 12.0,

    --- Movement below this counts as motionless. A firefighter working a nozzle from one
    --- spot should not be alarming, but one who has stopped moving entirely should.
    movementThreshold = 0.15,

    --- Downed, ragdolled, or unconscious counts as motionless regardless of the above.
    --- This is the whole point of the device: a firefighter who goes down alarms on their
    --- own, without having to press anything.
    alarmWhenDowned = true,

    range = { preAlarm = 15.0, full = 45.0 },
}

return MIFireScba
