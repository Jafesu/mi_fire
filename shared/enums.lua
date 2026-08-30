--- Shared vocabulary.
---
--- Every string that crosses a boundary -- client to server, server to NUI, resource to
--- resource -- comes from here. A literal like `'structural'` typed into a module is a
--- typo waiting to happen that no test will catch.

MIFire = MIFire or {}

local Enums = {}

--- Fire classification. These follow the real classes because the whole point of having
--- more than one fire type is that the correct agent differs. See `config/agents.lua`
--- for the effectiveness matrix and `config/fire_classes.lua` for behaviour.
Enums.FireClass = {
    A        = 'A',         -- ordinary combustibles: wood, paper, cloth
    B        = 'B',         -- flammable liquids and gases in a pool
    C        = 'C',         -- energized electrical equipment
    D        = 'D',         -- combustible metals
    K        = 'K',         -- cooking oils and fats
    GAS      = 'gas',       -- pressurized fuel gas, still feeding
    WILDLAND = 'wildland',  -- vegetation, wind-driven
    VEHICLE  = 'vehicle',   -- mixed fuel load, including EV packs
}

--- Extinguishing agents.
Enums.Agent = {
    WATER      = 'water',
    FOAM       = 'foam',        -- AFFF
    DRY_CHEM   = 'dry_chem',    -- ABC / BC powder
    CO2        = 'co2',
    WET_CHEM   = 'wet_chem',    -- Class K
    DRY_POWDER = 'dry_powder',  -- Class D, not the same as dry chem
}

--- What a node is doing right now.
Enums.NodeState = {
    IGNITING     = 'igniting',      -- spawned, not yet at working intensity
    GROWING      = 'growing',
    STEADY       = 'steady',        -- fuel-limited or ventilation-limited
    KNOCKED_DOWN = 'knocked_down',  -- intensity suppressed, fuel remains, can reflash
    OVERHAULED   = 'overhauled',    -- fuel consumed or soaked; will not reflash
    OUT          = 'out',
}

--- Incident lifecycle.
Enums.IncidentState = {
    ACTIVE      = 'active',
    CONTAINED   = 'contained',   -- no longer spreading, still burning
    UNDER_CONTROL = 'under_control',
    OUT         = 'out',
    CLOSED      = 'closed',
}

--- Where an incident came from. Used for dispatch wording and for statistics, and to
--- let admins filter generated calls out of a report.
Enums.IncidentOrigin = {
    AMBIENT  = 'ambient',    -- the generation module, on its own clock
    ADMIN    = 'admin',      -- a command
    EXPORT   = 'export',     -- another resource
    VEHICLE  = 'vehicle',    -- a crash or engine failure
    PLAYER   = 'player',     -- arson, explosion, molotov
    SCENARIO = 'scenario',
}

--- Protection channels. The exposure model runs each independently.
Enums.Exposure = {
    FLAME = 'flame',
    HEAT  = 'heat',
    SMOKE = 'smoke',
    CHEM  = 'chem',
}

--- PASS device phases. See `config/scba.lua` for the timings.
Enums.PassPhase = {
    IDLE      = 'idle',
    SENSING   = 'sensing',
    PRE_ALARM = 'pre_alarm',
    FULL      = 'full',
}

--- Hose line roles. A line is one of these; the crew slot system keys off it.
Enums.LineRole = {
    ATTACK  = 'attack',
    SUPPLY  = 'supply',
    RELAY   = 'relay',
    MASTER  = 'master',
}

--- Connection point types on an apparatus or prop. Authored by `/fireoffset`.
Enums.PortType = {
    DISCHARGE = 'discharge',
    INTAKE    = 'intake',
    HOSE_BED  = 'hose_bed',
    DECK_GUN  = 'deck_gun',
    LADDER    = 'ladder_rack',
    GEAR      = 'gear_compartment',
    TOOL      = 'tool_compartment',
    HYDRANT   = 'hydrant',
}

--- District fuel character. Drives what generates where and how it spreads.
Enums.DistrictKind = {
    HIGH_RISE   = 'high_rise',
    COMMERCIAL  = 'commercial',
    RESIDENTIAL = 'residential',
    INDUSTRIAL  = 'industrial',
    RURAL       = 'rural',
    WILDLAND    = 'wildland',
}

--- Dispatch priority, matching what lb-tablet accepts.
Enums.Priority = {
    HIGH   = 'high',
    MEDIUM = 'medium',
    LOW    = 'low',
}

MIFire.Enums = Enums

return Enums
