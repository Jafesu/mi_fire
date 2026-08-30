--- Station bootstrap configuration.
---
--- **Stations themselves are not here.** They live in MySQL, and they are built in game
--- with the placement tool rather than typed into a file. Hand-editing a coordinate for
--- every speaker in every bay of every station is a job nobody finishes.
---
--- What is here: the defaults a new station gets, the tuning that is genuinely global,
--- and the presentation for each kind of placed point.
---
--- See `docs/internal/DATAMODEL.md` for the schema and
--- `docs/guides/station-operations.md` for how to build one.

MIFireStations = {}

--- Admin command that opens the station tool.
MIFireStations.command = 'firestation'

--- What a freshly created station gets before anything is placed.
MIFireStations.defaults = {
    jobs = { 'fireman' },
    enabled = true,

    --- Until a coverage polygon is drawn, a station covers a circle of this radius around
    --- its origin. That makes a new station immediately useful, and the polygon is a
    --- refinement rather than a prerequisite.
    fallbackCoverageRadius = 400.0,
}

-- ---------------------------------------------------------------------------
-- Point kinds
-- ---------------------------------------------------------------------------

--- Every kind of thing the placement tool can put on a station.
---
--- `snapToSurface` means the preview rides the surface you are aiming at and takes its
--- rotation from that surface's normal -- a speaker aimed at a wall mounts flat against
--- it without anyone typing a rotation.
MIFireStations.pointKinds = {

    light = {
        label = 'Alert light',
        icon = 'lightbulb',
        snapToSurface = true,
        --- No prop by default: most stations already have light fixtures modelled, and
        --- this drives a light on that geometry rather than adding a floating object.
        prop = nil,
        light = {
            colour = { r = 255, g = 30, b = 20 },
            range = 9.0,
            intensity = 4.0,
            --- Rotating beacon rather than a steady lamp.
            rotateSpeed = 2.2,
            --- Also flash the room, which reads far better through a bay window.
            bounce = true,
        },
    },

    speaker = {
        label = 'Speaker',
        icon = 'volume-high',
        snapToSurface = true,
        prop = nil,
        audio = {
            --- Metres. Tones carry through a station and stop at the door.
            range = 28.0,
            --- Falloff exponent. Higher is a tighter, more directional source.
            falloff = 1.6,
        },
    },

    panel = {
        label = 'Alerting panel',
        icon = 'sliders',
        snapToSurface = true,
        prop = nil,
        --- ox_target interaction distance.
        targetRadius = 1.2,
    },

    bay_door = {
        label = 'Bay door',
        icon = 'warehouse',
        snapToSurface = false,
        --- Opened on turnout when a door resource is present, cosmetic otherwise.
        openOnTurnout = true,
    },

    apparatus_bay = {
        label = 'Apparatus bay',
        icon = 'truck',
        snapToSurface = false,
        --- Which rig lives here, shown on the station board. Free text, set at placement.
        prop = nil,
    },
}

-- ---------------------------------------------------------------------------
-- Zone kinds
-- ---------------------------------------------------------------------------

MIFireStations.zoneKinds = {
    coverage = {
        label = 'Coverage area',
        --- The response area that decides which station is toned for a call.
        --- A fire station is not a sphere, and pretending it is puts the tones in the
        --- car park.
        defaultHeight = 200.0,
    },
    interior = {
        label = 'Station interior',
        --- Used for "push the call detail to anyone in here".
        defaultHeight = 12.0,
    },
    bay = {
        label = 'Apparatus bay footprint',
        defaultHeight = 8.0,
    },
}

-- ---------------------------------------------------------------------------
-- Alerting
-- ---------------------------------------------------------------------------

MIFireStations.alerting = {
    --- Only the station whose coverage zone contains the call alerts. A global siren for
    --- every call is how people learn to ignore the siren.
    zonedOnly = true,

    --- Tone patterns per dispatch priority. Played over every `speaker` point.
    tones = {
        high   = { pattern = 'alert_high',   repeats = 3, gapMs = 700 },
        medium = { pattern = 'alert_medium', repeats = 2, gapMs = 900 },
        low    = { pattern = 'alert_low',    repeats = 1, gapMs = 0 },
    },

    --- Lights stay up after the tones stop, until the last assigned unit clears.
    lightsFollowCall = true,

    --- Seconds the turnout timer counts. Presentational, but it changes behaviour --
    --- people move when there is a clock.
    turnoutTimerSeconds = 90,

    --- Acknowledging stops the tones. It does not clear the lights.
    acknowledgeSilencesTones = true,

    --- Tones stop on their own after this long even if nobody acknowledges, so an empty
    --- station is not a siren that runs all night.
    maxToneSeconds = 45,
}

return MIFireStations
