--- Target bridge.
---
--- Every world interaction in this resource goes through here. There are no drawtext
--- prompts, no proximity keypress loops, and no `IsControlJustPressed` polling for
--- interacting with anything -- if a player does it to a truck, a hydrant, a hose, a
--- ladder, a victim, or a station panel, it is a target option.
---
--- Keybinds exist only for controls held *during* an action already in progress
--- (nozzle pattern, pump throttle), and those go through `lib.addKeybind`, not a loop.

MIFire = MIFire or {}

local Target = { available = false }

local registered = {
    models = {},
    entities = {},
    zones = {},
    globalVehicle = {},
    globalPed = {},
    globalPlayer = {},
}

local function ensure()
    if Target.available then return true end
    Target.available = GetResourceState('ox_target') == 'started'
    if not Target.available then
        MIFire.Util.warn('ox_target is not started; no interactions will be available')
    end
    return Target.available
end

-- ---------------------------------------------------------------------------
-- Shared option decoration
-- ---------------------------------------------------------------------------

--- Wrap an option so every interaction inherits the same gates without each caller
--- remembering to add them. `canInteract` composes rather than overwrites.
---@param option table
---@return table
local function decorate(option)
    local userCanInteract = option.canInteract
    local requiresFirefighter = option.requiresFirefighter
    local requiresEms = option.requiresEms

    option.canInteract = function(entity, distance, coords, name, bone)
        if requiresFirefighter and not MIFire.Framework.isFirefighter() then return false end
        if requiresEms and not MIFire.Framework.isEms() then return false end
        if userCanInteract then
            return userCanInteract(entity, distance, coords, name, bone) == true
        end
        return true
    end

    option.requiresFirefighter = nil
    option.requiresEms = nil

    -- ox_target wants `icon` as a Font Awesome name; default to something sane so a
    -- missing icon does not render as a blank box.
    option.icon = option.icon or 'fire'

    return option
end

---@param options table[]
---@return table[]
local function decorateAll(options)
    local out = {}
    for i = 1, #options do out[i] = decorate(options[i]) end
    return out
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

--- Options on every entity of a set of models -- hydrant props, for example.
---@param models table Array of model names or hashes.
---@param options table[]
function Target.addModel(models, options)
    if not ensure() then return end
    local decorated = decorateAll(options)
    exports.ox_target:addModel(models, decorated)
    registered.models[#registered.models + 1] = { models = models, options = decorated }
end

--- Options on one specific entity -- a hose coupling, a placed ladder.
---@param entity integer
---@param options table[]
function Target.addEntity(entity, options)
    if not ensure() then return end
    exports.ox_target:addLocalEntity(entity, decorateAll(options))
    registered.entities[#registered.entities + 1] = entity
end

---@param entity integer
function Target.removeEntity(entity)
    if not Target.available then return end
    exports.ox_target:removeLocalEntity(entity)
    for i = #registered.entities, 1, -1 do
        if registered.entities[i] == entity then table.remove(registered.entities, i) end
    end
end

--- Options on every vehicle, filtered by `canInteract`. This is how apparatus options
--- attach without needing to know which vehicles exist -- the filter runs per vehicle
--- against `config/apparatus.lua`.
---@param options table[]
---@return integer id
function Target.addGlobalVehicle(options)
    if not ensure() then return 0 end
    local decorated = decorateAll(options)
    local id = exports.ox_target:addGlobalVehicle(decorated)
    registered.globalVehicle[#registered.globalVehicle + 1] = id
    return id
end

--- Options on every **NPC** ped.
---
--- Not on players. ox_target keeps those apart, and registering here for something meant to
--- appear on a colleague produces an option that silently never fires -- which is exactly what
--- happened to "Back up this line".
---@param options table[]
---@return integer id
function Target.addGlobalPed(options)
    if not ensure() then return 0 end
    local decorated = decorateAll(options)
    local id = exports.ox_target:addGlobalPed(decorated)
    registered.globalPed[#registered.globalPed + 1] = id
    return id
end

--- Options on every **player** ped, including your own.
---
--- The separate registration is the whole reason this function exists rather than callers
--- reaching for `addGlobalPed` and wondering why nothing appears on a firefighter.
---@param options table[]
---@return integer id
function Target.addGlobalPlayer(options)
    if not ensure() then return 0 end
    local decorated = decorateAll(options)
    local id = exports.ox_target:addGlobalPlayer(decorated)
    registered.globalPlayer[#registered.globalPlayer + 1] = id
    return id
end

--- A sphere at a fixed point -- a station panel, a hospital intake.
---@param coords vector3
---@param radius number
---@param options table[]
---@return integer id
function Target.addSphere(coords, radius, options)
    if not ensure() then return 0 end
    local id = exports.ox_target:addSphereZone({
        coords = coords,
        radius = radius,
        options = decorateAll(options),
    })
    registered.zones[#registered.zones + 1] = id
    return id
end

--- A box, for apparatus connection points where a sphere is the wrong shape.
---@param params table { coords, size, rotation, options }
---@return integer id
function Target.addBox(params)
    if not ensure() then return 0 end
    params.options = decorateAll(params.options or {})
    local id = exports.ox_target:addBoxZone(params)
    registered.zones[#registered.zones + 1] = id
    return id
end

---@param id integer
function Target.removeZone(id)
    if not Target.available or not id or id == 0 then return end
    exports.ox_target:removeZone(id)
end

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------

--- Remove everything this resource registered.
---
--- Called on resource stop. Without this, a restart leaves orphaned zones behind and
--- the second restart leaves twice as many -- which is exactly the leak the plan's
--- "restart twice" verification step is designed to catch.
function Target.removeAll()
    if not Target.available then return end

    for i = 1, #registered.zones do
        pcall(function() exports.ox_target:removeZone(registered.zones[i]) end)
    end

    for i = 1, #registered.entities do
        pcall(function() exports.ox_target:removeLocalEntity(registered.entities[i]) end)
    end

    for i = 1, #registered.globalVehicle do
        pcall(function() exports.ox_target:removeGlobalVehicle(registered.globalVehicle[i]) end)
    end

    for i = 1, #registered.globalPed do
        pcall(function() exports.ox_target:removeGlobalPed(registered.globalPed[i]) end)
    end

    for i = 1, #registered.globalPlayer do
        pcall(function() exports.ox_target:removeGlobalPlayer(registered.globalPlayer[i]) end)
    end

    registered = {
        models = {}, entities = {}, zones = {},
        globalVehicle = {}, globalPed = {}, globalPlayer = {},
    }
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Target.removeAll()
end)

MIFire.Target = Target

return Target
