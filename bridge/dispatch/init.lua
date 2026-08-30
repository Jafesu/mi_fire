--- Dispatch bridge.
---
--- One job: turn an incident into whatever the configured dispatch resource expects,
--- and never let that shape leak back into the modules. `server/modules/` calls
--- `Dispatch.send(incident)` and gets a boolean.
---
--- The lb-tablet payload shape here was read off a working integration
--- (`mi_gunrunner/server/shipments.lua`), not guessed from documentation.

MIFire = MIFire or {}

local Dispatch = {}
local lastSentAt = 0

-- ---------------------------------------------------------------------------
-- Providers
-- ---------------------------------------------------------------------------

local providers = {}

--- lb-tablet. The `AddDispatch` export takes a single table.
providers['lb-tablet'] = function(payload)
    local resource = Config.Dispatch.resource or 'lb-tablet'

    if GetResourceState(resource) ~= 'started' then
        return false, 'RESOURCE_STOPPED'
    end

    local ok, result = pcall(function()
        return exports[resource]:AddDispatch(payload)
    end)

    if not ok then return false, tostring(result) end
    return result ~= false, result
end

--- A server owner's own function, from `config/dispatch.lua`.
providers['custom'] = function(payload)
    if type(Config.CustomDispatch) ~= 'function' then
        return false, 'NO_CUSTOM_HANDLER'
    end

    local ok, result = pcall(Config.CustomDispatch, payload)
    if not ok then return false, tostring(result) end
    return result ~= false, result
end

--- Explicitly no dispatch. Not an error -- some servers run calls over the radio.
providers['none'] = function(_payload)
    return true, 'DISPATCH_DISABLED'
end

-- ---------------------------------------------------------------------------
-- Payload construction
-- ---------------------------------------------------------------------------

--- Merge the class-specific dispatch presentation over the default.
---@param fireClass string
---@return table
local function callSettings(fireClass)
    local defaults = Config.DispatchCalls.default or {}
    local specific = Config.DispatchCalls[fireClass]
    if not specific then return MIFire.Util.deepCopy(defaults) end
    return MIFire.Util.merge(defaults, specific)
end

--- Build the lb-tablet-shaped payload for an incident.
---
--- Recipients come from the run card where one applies, falling back to the configured
--- jobs. That is what keeps `'fireman'` from being hardcoded in module code.
---@param incident table
---@return table
function Dispatch.buildPayload(incident)
    local settings = callSettings(incident.class)
    local coords = incident.coords or { x = 0.0, y = 0.0, z = 0.0 }

    local fields = {}

    if incident.districtLabel then
        fields[#fields + 1] = { icon = 'location-dot', label = 'District', value = incident.districtLabel }
    end

    if incident.assignment and #incident.assignment > 0 then
        fields[#fields + 1] = {
            icon = 'truck', label = 'Assignment', value = table.concat(incident.assignment, ', '),
        }
    end

    -- Whether there is water nearby genuinely changes how a crew responds, so it goes
    -- on the call rather than being something they find out on arrival.
    if incident.hydrantDensity ~= nil then
        fields[#fields + 1] = {
            icon = 'droplet',
            label = 'Water supply',
            value = incident.hydrantDensity <= 0.3 and 'Limited -- shuttle or draft' or 'Hydranted',
        }
    end

    if incident.floor and incident.floor > 1 then
        fields[#fields + 1] = { icon = 'building', label = 'Floor', value = tostring(incident.floor) }
    end

    local payload = {
        priority = settings.priority or 'medium',
        code = settings.code or '',
        title = settings.title or 'Fire',
        description = incident.description or settings.title or 'Reported fire',
        location = {
            label = incident.locationLabel or incident.districtLabel or 'Unknown',
            coords = vector2(coords.x + 0.0, coords.y + 0.0),
        },
        time = settings.duration or 900,
        notificationTime = settings.notificationTime or 20,
        sound = settings.sound ~= false,
        fields = #fields > 0 and fields or nil,
        blip = settings.blip and {
            type = 'radius',
            radius = settings.blip.radius or 60.0,
            randomCoords = incident.exactLocationUnknown == true,
            sprite = settings.blip.sprite or 436,
            color = settings.blip.color or 1,
            size = settings.blip.size or 0.9,
            shortRange = false,
            label = settings.title or 'Fire',
        } or nil,
    }

    local recipients = Config.Dispatch.recipients or {}
    local mdts = incident.mdts or recipients.mdts or {}
    local jobs = incident.jobs or recipients.jobs or {}

    if #mdts > 0 then
        payload.mdts = mdts
    elseif #jobs == 1 then
        payload.job = jobs[1]
    elseif #jobs > 1 then
        payload.job = jobs
    end

    return payload
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

--- Raise a dispatch for an incident.
---@param incident table
---@return boolean sent
---@return string|nil reason Why not, when `sent` is false.
function Dispatch.send(incident)
    if not incident then return false, 'NO_INCIDENT' end

    if incident.suppressDispatch then
        return false, 'SUPPRESSED'
    end

    if Config.Dispatch.suppressForAdmin and incident.origin == MIFire.Enums.IncidentOrigin.ADMIN then
        return false, 'SUPPRESSED_ADMIN'
    end

    -- Rate limit. A propagation bug should not become fifty board entries.
    local now = os.time()
    local gap = Config.Dispatch.minSecondsBetweenCalls or 0
    if gap > 0 and (now - lastSentAt) < gap then
        MIFire.Util.debug('dispatch', 'rate limited, %ds since last call', now - lastSentAt)
        return false, 'RATE_LIMITED'
    end

    local provider = providers[Config.Dispatch.provider]
    if not provider then
        MIFire.Util.warn('unknown dispatch provider %s', tostring(Config.Dispatch.provider))
        return false, 'UNKNOWN_PROVIDER'
    end

    local payload = Dispatch.buildPayload(incident)
    local ok, result = provider(payload)

    if ok then
        lastSentAt = now
        MIFire.Util.debug('dispatch', 'sent %s for incident %s', payload.title, tostring(incident.id))
    else
        MIFire.Util.debug('dispatch', 'not sent for incident %s: %s', tostring(incident.id), tostring(result))
    end

    return ok, ok and nil or tostring(result)
end

--- Whether dispatch is actually reachable right now. Surfaced by `/fire info` so a
--- silent board is diagnosable instead of mysterious.
---@return boolean available
---@return string detail
function Dispatch.status()
    local providerName = Config.Dispatch.provider

    if providerName == 'none' then
        return true, 'disabled by config'
    end

    if providerName == 'custom' then
        return type(Config.CustomDispatch) == 'function', 'custom handler'
    end

    local resource = Config.Dispatch.resource or providerName
    local state = GetResourceState(resource)
    return state == 'started', ('%s is %s'):format(resource, state)
end

MIFire.Dispatch = Dispatch

return Dispatch
