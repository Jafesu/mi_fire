--- Districts, area of play, and run cards.
---
--- Three layers that are easy to confuse and important to keep apart:
---
---   District  a named response area with a fuel character. Decides *what* burns here.
---   AOP       the set of districts that are currently live. Decides *where* fires start.
---   Run card  district + call type -> which station is due. Decides *who* gets toned.
---
--- Districts below are starting geometry, not gospel. `/district here` reports which one
--- you are standing in, which is the fastest way to check a boundary you have moved.

MIFireZones = {}

-- ---------------------------------------------------------------------------
-- Districts
-- ---------------------------------------------------------------------------

--- Defaults merged under every district.
MIFireZones.districtBase = {
    kind = 'residential',

    --- Relative likelihood this district is picked when generating an ambient fire.
    --- Weight is per-district, not per-square-metre, so a large rural district does not
    --- drown out downtown just by being big.
    weight = 1.0,

    --- Fire classes that can generate here, as weights. A district that cannot produce
    --- a class simply omits it.
    fireClasses = { A = 1.0 },

    --- Fraction of ambient fires here that start inside a structure.
    indoorChance = 55.0,

    --- Working hydrants are close by. Drives whether a call is a hydrant operation or
    --- a tanker shuttle, and is surfaced to the crew on the dispatch.
    hydrantDensity = 1.0,

    --- Typical building height, used to pick a floor for indoor fires. 1 means ground
    --- floor only, which is most of the map.
    maxFloors = 1,
}

MIFireZones.districts = {

    ---------------------------------------------------------------- Los Santos ------

    pillbox_hill = {
        label = 'Pillbox Hill',
        kind = 'high_rise',
        weight = 1.4,
        shape = { type = 'sphere', coords = { x = 230.0, y = -880.0, z = 30.0 }, radius = 420.0 },
        fireClasses = { A = 1.0, C = 0.5, K = 0.4 },
        indoorChance = 80.0,
        hydrantDensity = 1.6,
        maxFloors = 30,   -- elevation loss becomes a real pump problem here
    },

    vinewood = {
        label = 'Vinewood',
        kind = 'commercial',
        weight = 1.1,
        shape = { type = 'sphere', coords = { x = 300.0, y = 200.0, z = 100.0 }, radius = 500.0 },
        fireClasses = { A = 1.0, C = 0.4, K = 0.6 },
        indoorChance = 70.0,
        hydrantDensity = 1.4,
        maxFloors = 6,
    },

    rockford_hills = {
        label = 'Rockford Hills',
        kind = 'residential',
        weight = 0.9,
        shape = { type = 'sphere', coords = { x = -800.0, y = -200.0, z = 40.0 }, radius = 550.0 },
        fireClasses = { A = 1.0, C = 0.3, K = 0.3 },
        indoorChance = 75.0,
        hydrantDensity = 1.3,
        maxFloors = 3,
    },

    del_perro = {
        label = 'Del Perro & Vespucci',
        kind = 'commercial',
        weight = 1.0,
        shape = { type = 'sphere', coords = { x = -1250.0, y = -1100.0, z = 10.0 }, radius = 600.0 },
        fireClasses = { A = 1.0, K = 0.7, C = 0.3 },
        indoorChance = 70.0,
        hydrantDensity = 1.4,
        maxFloors = 8,
    },

    strawberry = {
        label = 'Strawberry & Davis',
        kind = 'residential',
        weight = 1.2,
        shape = { type = 'sphere', coords = { x = 180.0, y = -1700.0, z = 30.0 }, radius = 550.0 },
        fireClasses = { A = 1.0, vehicle = 0.5, C = 0.3 },
        indoorChance = 60.0,
        hydrantDensity = 1.2,
        maxFloors = 4,
    },

    la_mesa = {
        label = 'La Mesa & Cypress Flats',
        kind = 'industrial',
        weight = 1.1,
        shape = { type = 'sphere', coords = { x = 850.0, y = -1300.0, z = 30.0 }, radius = 600.0 },
        fireClasses = { A = 0.7, B = 1.2, C = 0.6, D = 0.25, gas = 0.4, vehicle = 0.5 },
        indoorChance = 55.0,
        hydrantDensity = 1.0,
        maxFloors = 3,
    },

    port_of_ls = {
        label = 'Port of Los Santos & Elysian Island',
        kind = 'industrial',
        weight = 0.9,
        shape = { type = 'sphere', coords = { x = 300.0, y = -2600.0, z = 6.0 }, radius = 750.0 },
        fireClasses = { B = 1.4, A = 0.5, gas = 0.6, D = 0.3, C = 0.4 },
        indoorChance = 35.0,
        hydrantDensity = 0.7,
        maxFloors = 2,
    },

    lsia = {
        label = 'Los Santos International',
        kind = 'industrial',
        weight = 0.6,
        shape = { type = 'sphere', coords = { x = -1050.0, y = -2700.0, z = 15.0 }, radius = 600.0 },
        fireClasses = { B = 1.5, A = 0.4, vehicle = 0.6, gas = 0.3 },
        indoorChance = 30.0,
        hydrantDensity = 0.9,
        maxFloors = 2,
    },

    ---------------------------------------------------------------- Blaine County --

    sandy_shores = {
        label = 'Sandy Shores',
        kind = 'rural',
        weight = 0.8,
        shape = { type = 'sphere', coords = { x = 1900.0, y = 3700.0, z = 32.0 }, radius = 900.0 },
        fireClasses = { A = 1.0, wildland = 0.8, vehicle = 0.5, B = 0.3 },
        indoorChance = 45.0,
        hydrantDensity = 0.3,   -- tanker shuttle country
        maxFloors = 2,
    },

    grapeseed = {
        label = 'Grapeseed',
        kind = 'rural',
        weight = 0.6,
        shape = { type = 'sphere', coords = { x = 2450.0, y = 4750.0, z = 35.0 }, radius = 800.0 },
        fireClasses = { A = 0.9, wildland = 1.0, vehicle = 0.4 },
        indoorChance = 40.0,
        hydrantDensity = 0.25,
        maxFloors = 2,
    },

    paleto_bay = {
        label = 'Paleto Bay',
        kind = 'rural',
        weight = 0.7,
        shape = { type = 'sphere', coords = { x = -200.0, y = 6350.0, z = 31.0 }, radius = 800.0 },
        fireClasses = { A = 1.0, wildland = 0.7, vehicle = 0.4 },
        indoorChance = 50.0,
        hydrantDensity = 0.5,
        maxFloors = 2,
    },

    mount_chiliad = {
        label = 'Mount Chiliad & Raton Canyon',
        kind = 'wildland',
        weight = 0.9,
        shape = { type = 'sphere', coords = { x = 400.0, y = 5600.0, z = 550.0 }, radius = 1400.0 },
        fireClasses = { wildland = 1.0 },
        indoorChance = 0.0,
        hydrantDensity = 0.0,   -- draft or shuttle, nothing else
        maxFloors = 1,
    },

    grand_senora = {
        label = 'Grand Senora Desert',
        kind = 'wildland',
        weight = 0.7,
        shape = { type = 'sphere', coords = { x = 1400.0, y = 2800.0, z = 60.0 }, radius = 1500.0 },
        fireClasses = { wildland = 1.0, vehicle = 0.3 },
        indoorChance = 0.0,
        hydrantDensity = 0.0,
        maxFloors = 1,
    },

    vinewood_hills = {
        label = 'Vinewood Hills',
        kind = 'wildland',
        weight = 0.8,
        shape = { type = 'sphere', coords = { x = -500.0, y = 700.0, z = 180.0 }, radius = 900.0 },
        fireClasses = { wildland = 0.9, A = 0.7 },
        indoorChance = 30.0,
        hydrantDensity = 0.4,
        maxFloors = 2,
    },
}

-- ---------------------------------------------------------------------------
-- Area of play
-- ---------------------------------------------------------------------------

MIFireZones.aop = {
    --- Districts live at boot when `mode` is 'manual'.
    default = { 'pillbox_hill', 'strawberry', 'la_mesa' },

    --- 'manual'  only what an admin sets with /aop
    --- 'auto'    follows where players actually are
    --- 'all'     the whole map is live; ignores everything below
    mode = 'auto',

    auto = {
        --- A district goes live once this many players are inside it.
        activateAtPlayers = 2,

        --- And stays live for this long after the last one leaves, so a district does
        --- not flicker off the moment a crew drives through a boundary.
        holdSeconds = 900,

        --- Never fewer than this many live districts, so a quiet server still gets calls.
        minimumActive = 1,

        --- Never more than this, so a spread-out server does not generate everywhere.
        maximumActive = 5,

        --- How often the auto mode re-evaluates.
        evaluateSeconds = 60,
    },

    --- Ambient fires never generate closer than this to any player. A call the crew
    --- watched appear is not a call.
    minimumDistanceFromPlayers = 250.0,

    --- Nor closer than this to an existing incident, so scenes stay distinct.
    minimumDistanceFromIncidents = 150.0,
}

-- ---------------------------------------------------------------------------
-- Run cards
-- ---------------------------------------------------------------------------

--- Which station is due for what. `stations` are keys from `config/stations.lua`.
---
--- `default` applies to any district not named here. A district may override the whole
--- card or just one call type.
MIFireZones.runCards = {
    default = {
        first = 'station_1',
        second = 'station_2',
        --- Apparatus each due station is expected to send. Presentational for now --
        --- it appears on the dispatch and on the station board.
        assignment = { 'Engine', 'Truck', 'Battalion' },
        --- A working fire escalates: each level adds the next station in the list.
        alarms = { 'station_2', 'station_3', 'station_4' },
    },

    byDistrict = {
        pillbox_hill = {
            first = 'station_1',
            second = 'station_2',
            assignment = { 'Engine', 'Engine', 'Truck', 'Rescue', 'Battalion' },
        },
        port_of_ls = {
            first = 'station_3',
            assignment = { 'Engine', 'Foam Tender', 'Hazmat', 'Battalion' },
        },
        la_mesa = {
            first = 'station_3',
            assignment = { 'Engine', 'Engine', 'Hazmat', 'Battalion' },
        },
        sandy_shores = {
            first = 'station_7',
            assignment = { 'Engine', 'Tender', 'Brush' },
        },
        paleto_bay = {
            first = 'station_8',
            assignment = { 'Engine', 'Tender', 'Brush' },
        },
        mount_chiliad = {
            first = 'station_8',
            assignment = { 'Brush', 'Brush', 'Tender', 'Battalion' },
        },
        grand_senora = {
            first = 'station_7',
            assignment = { 'Brush', 'Tender' },
        },
    },

    --- Call types that always add a specialist regardless of district.
    byClass = {
        B    = { adds = { 'Foam Tender' } },
        D    = { adds = { 'Hazmat' } },
        gas  = { adds = { 'Hazmat' } },
        wildland = { adds = { 'Brush' } },
    },
}

return MIFireZones
