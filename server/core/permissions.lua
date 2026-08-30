--- Permissions.
---
--- Checks live at the service boundary, once. A transport -- a command, an export, a
--- callback -- calls the service, and the service checks. Four copies of a permission
--- check is four places to get it wrong.

MIFire = MIFire or {}

local Permissions = {}

--- Is this player an mi_fire admin?
---
--- Source 0 is the server console, which is always allowed. That is how the console
--- commands in `server/modules/admin/` work without an ACE grant.
---@param source integer
---@return boolean
function Permissions.isAdmin(source)
    if not source or source == 0 then return true end
    return IsPlayerAceAllowed(source, Config.adminAce) == true
end

--- Admin check with a reason, for transports that want to tell the caller why.
---@param source integer
---@return boolean allowed
---@return string|nil reason
function Permissions.requireAdmin(source)
    if Permissions.isAdmin(source) then return true end
    return false, ('missing ACE permission %s'):format(Config.adminAce)
end

--- Firefighter check that admins pass regardless of job.
---
--- Testing a hose line should not require clocking on as a firefighter first, but a
--- real firefighter still has to be one.
---@param source integer
---@return boolean allowed
---@return string|nil reason
function Permissions.requireFirefighter(source)
    if Permissions.isAdmin(source) then return true end
    if MIFire.Framework.isFirefighter(source) then return true end

    local jobName, onDuty = MIFire.Framework.getJob(source)
    if jobName and Config.fireJobs[jobName] and Config.requireOnDuty and not onDuty then
        return false, 'you are not on duty'
    end
    return false, 'you are not a firefighter'
end

---@param source integer
---@return boolean allowed
---@return string|nil reason
function Permissions.requireEms(source)
    if Permissions.isAdmin(source) then return true end
    if MIFire.Framework.isEms(source) then return true end
    return false, 'you are not EMS'
end

--- Distance gate. Every interaction the client claims to be doing at a position is
--- re-checked here against where the server thinks the player is.
---
--- The client is not trusted about where it is standing; this is what stops a modified
--- client charging a line across the map.
---@param source integer
---@param coords vector3|table
---@param maxDistance number
---@return boolean
function Permissions.isNear(source, coords, maxDistance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local x = coords.x or coords[1]
    local y = coords.y or coords[2]
    local z = coords.z or coords[3]

    local distSq = MIFire.Util.distance3dSq(playerCoords.x, playerCoords.y, playerCoords.z, x, y, z)
    return distSq <= (maxDistance * maxDistance)
end

MIFire.Permissions = Permissions

return Permissions
