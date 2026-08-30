--- Permissions.
---
--- Checks live at the service boundary, once. A transport -- a command, an export, a
--- callback -- calls the service, and the service checks. Four copies of a permission
--- check is four places to get it wrong.
---
--- Two independent routes to admin access, because they answer different questions:
--- ACE answers "is this a server administrator", job and grade answers "is this the fire
--- chief". Job grade is runtime state and cannot be expressed as an ACE, which is why the
--- commands are registered unrestricted and gated here rather than by FiveM.

MIFire = MIFire or {}

local Permissions = {}

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

--- Grant the mi_fire ACEs to the configured principals.
---
--- This is what makes the commands work with no `server.cfg` edit: `group.admin` already
--- exists on any Qbox server, so granting it `mi_fire.admin` here means anyone who can run
--- Qbox's own admin commands can run these too.
local function grantPrincipals()
    local perms = Config.permissions
    if type(perms) ~= 'table' then return end
    if type(perms.principals) ~= 'table' or type(perms.aces) ~= 'table' then return end

    for _, principal in ipairs(perms.principals) do
        for _, ace in ipairs(perms.aces) do
            -- Skip `command.*` aces: ox_lib owns those, and granting one here would let a
            -- principal run a command this resource never registered.
            if not ace:find('^command%.') and not IsPrincipalAceAllowed(principal, ace) then
                lib.addAce(principal, ace)
                MIFire.Util.debug('permissions', 'granted %s to %s', ace, principal)
            end
        end
    end
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end
    grantPrincipals()
end)

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------

--- Does this player hold any of the configured admin ACEs?
---@param source integer
---@return boolean
---@return string|nil ace The one that matched.
function Permissions.hasAdminAce(source)
    local aces = Config.permissions and Config.permissions.aces
    if type(aces) ~= 'table' then return false end

    for _, ace in ipairs(aces) do
        if IsPlayerAceAllowed(source, ace) then return true, ace end
    end

    return false
end

--- Does this player hold a job and grade that grants access?
---@param source integer
---@return boolean
---@return string|nil detail Job and grade that matched, or why it did not.
function Permissions.hasJobAccess(source)
    local jobs = Config.permissions and Config.permissions.jobs
    if type(jobs) ~= 'table' then return false end

    local jobName, onDuty, grade = MIFire.Framework.getJob(source)
    if not jobName then return false, 'no job' end

    local required = jobs[jobName]
    if not required then return false, ('%s is not a permitted job'):format(jobName) end

    if grade < required then
        return false, ('%s grade %d is below the required %d'):format(jobName, grade, required)
    end

    if Config.permissions.jobsRequireOnDuty and not onDuty then
        return false, ('%s grade %d, but not on duty'):format(jobName, grade)
    end

    return true, ('%s grade %d'):format(jobName, grade)
end

--- Is this player an mi_fire admin, by either route?
---
--- Source 0 is the server console, which is always allowed -- that is how the console can
--- run these commands without an ACE grant.
---@param source integer
---@param subcommand string|nil Checked against `jobCommands` for job-based access.
---@return boolean
function Permissions.isAdmin(source, subcommand)
    if not source or source == 0 then return true end

    if Permissions.hasAdminAce(source) then return true end

    if Permissions.hasJobAccess(source) then
        local allowed = Config.permissions.jobCommands

        -- No list means job access reaches everything.
        if type(allowed) ~= 'table' or not subcommand then return true end

        for _, name in ipairs(allowed) do
            if name == subcommand then return true end
        end

        return false
    end

    return false
end

--- Admin check with a reason a human can act on.
---
--- The reason matters more than it looks. "Missing ACE permission" tells someone nothing
--- about what to do next; naming both routes and what they currently have does.
---@param source integer
---@param subcommand string|nil
---@return boolean allowed
---@return string|nil reason
function Permissions.requireAdmin(source, subcommand)
    if Permissions.isAdmin(source, subcommand) then return true end

    -- Distinguish "you have job access but not to this subcommand" from "you have nothing",
    -- because they need different fixes.
    if Permissions.hasJobAccess(source) then
        return false, ('your rank cannot use "%s"; ask a server admin'):format(
            tostring(subcommand))
    end

    local _, jobDetail = Permissions.hasJobAccess(source)
    return false, ('not permitted (%s). A server admin can grant access, or your job grade can'):format(
        jobDetail or 'no matching job')
end

--- A full account of why access was or was not granted, for `/fire perms`.
---
--- This exists because "missing ACE permission" is a dead end. Being able to see which
--- ACEs were tested, which principals were granted, and what job grade the caller actually
--- holds turns a permissions problem into something self-diagnosing.
---@param source integer
---@return string[] lines
function Permissions.explain(source)
    local perms = Config.permissions or {}
    local lines = {}

    if source == 0 then
        return { 'server console -- always allowed' }
    end

    local jobName, onDuty, grade = MIFire.Framework.getJob(source)
    lines[#lines + 1] = ('job: %s grade %d, %s'):format(
        jobName or 'none', grade or 0, onDuty and 'on duty' or 'off duty')

    for _, ace in ipairs(perms.aces or {}) do
        lines[#lines + 1] = ('ace %s: %s'):format(ace,
            IsPlayerAceAllowed(source, ace) and 'YES' or 'no')
    end

    local jobOk, jobDetail = Permissions.hasJobAccess(source)
    lines[#lines + 1] = ('job access: %s (%s)'):format(jobOk and 'YES' or 'no',
        jobDetail or 'no matching job')

    lines[#lines + 1] = ('result: %s'):format(
        Permissions.isAdmin(source) and 'ALLOWED' or 'DENIED')

    if not Permissions.isAdmin(source) then
        lines[#lines + 1] = 'to grant: add_ace group.admin mi_fire.admin allow'
    end

    return lines
end

--- Firefighter check that admins pass regardless of job.
---
--- Testing a hose line should not require clocking on as a firefighter first, but a real
--- firefighter still has to be one.
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
