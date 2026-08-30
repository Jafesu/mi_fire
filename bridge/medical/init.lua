--- Medical bridge.
---
--- mi_fire injures. What happens when someone runs out of health is the medical resource's
--- decision, not ours -- so this file answers two questions and nothing else: *is this
--- player down*, and *how do I hurt them in a way the medical resource will notice*.
---
--- Targets **qbx_medical**, with graceful fallbacks. It is currently in `[disabled]` on
--- this server, so the fallback path is the one that runs today and it has to work.
---
--- The important finding behind this file: `SetEntityHealth` does **not** raise a damage
--- event. qbx_medical decides last stand from `CEventNetworkEntityDamage`
--- (`client/dead.lua:118`), so health set directly is invisible to it -- a firefighter
--- would slide to zero and simply die with no last stand, no bleeding, and no injury
--- record. `ApplyDamageToPed` raises the event properly, and is what qbx_medical uses on
--- itself for bleed damage (`client/wounding.lua:61`).

MIFire = MIFire or {}

local Medical = { resource = nil }

--- Resources we know how to talk to, in preference order.
local KNOWN = { 'qbx_medical', 'osp_ambulance' }

local function detect()
    if Medical.resource ~= nil then return Medical.resource end

    for _, name in ipairs(KNOWN) do
        if GetResourceState(name) == 'started' then
            Medical.resource = name
            return name
        end
    end

    Medical.resource = false
    return false
end

-- ---------------------------------------------------------------------------
-- Is this player out of the fight?
-- ---------------------------------------------------------------------------

if IsDuplicityVersion() then

    --- Server side, from framework metadata.
    ---
    --- qbx_medical writes `isdead` and `inlaststand` onto the Qbox player
    --- (`server/main.lua:37`), so the server can answer without asking the client --
    --- which matters, because the client being asked may be the one that is unconscious.
    ---@param source integer
    ---@return boolean down
    ---@return string|nil reason 'dead' | 'laststand'
    function Medical.isDown(source)
        local player = exports.qbx_core and exports.qbx_core:GetPlayer(source)
        local metadata = player and player.PlayerData and player.PlayerData.metadata

        if metadata then
            if metadata.isdead then return true, 'dead' end
            if metadata.inlaststand then return true, 'laststand' end
            return false
        end

        -- No framework metadata to read. Fall back to health, remembering that a GTA
        -- player ped is dead at 100 rather than 0.
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false end

        if IsPedDeadOrDying(ped, true) then return true, 'dead' end
        return GetEntityHealth(ped) <= 101, 'laststand'
    end

else

    --- Client side, from the medical resource itself when it is running.
    ---@return boolean down
    ---@return string|nil reason
    function Medical.isDown()
        local resource = detect()

        if resource == 'qbx_medical' then
            local ok, dead = pcall(function() return exports.qbx_medical:IsDead() end)
            if ok and dead then return true, 'dead' end

            local okStand, stand = pcall(function() return exports.qbx_medical:IsLaststand() end)
            if okStand and stand then return true, 'laststand' end

            return false
        end

        if IsPedDeadOrDying(cache.ped, true) then return true, 'dead' end
        return GetEntityHealth(cache.ped) <= 101, 'laststand'
    end

    -- -----------------------------------------------------------------------
    -- Hurting someone in a way the medical resource notices
    -- -----------------------------------------------------------------------

    --- Sub-point damage carried between calls.
    ---
    --- `ApplyDamageToPed` takes whole numbers. Smoke at low density does well under one
    --- point per tick, and flooring each call would round it to nothing forever -- so the
    --- remainder is banked rather than discarded.
    local pending = 0.0

    --- Apply exposure damage.
    ---@param amount number May be fractional.
    ---@return boolean applied
    function Medical.damage(amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return false end

        -- Never beat someone who is already down. Damage past that point does nothing a
        -- medical resource can act on and produces a stream of pointless events.
        if Medical.isDown() then
            pending = 0.0
            return false
        end

        pending = pending + amount
        if pending < 1.0 then return false end

        local whole = math.floor(pending)
        pending = pending - whole

        ApplyDamageToPed(cache.ped, whole, false)
        return true
    end

    --- How much health there is left to lose.
    ---
    --- A GTA player ped reads 200 at full and is dead at 100, so the usable pool is 100
    --- points rather than 200. Assuming 200 doubles every survival estimate, which is
    --- exactly the mistake the balance figures were making until it was checked.
    ---@return number
    function Medical.usableHealth()
        return math.max(0, GetEntityHealth(cache.ped) - 100)
    end
end

--- Which medical resource was found, for diagnostics.
---@return string|nil
function Medical.detected()
    local resource = detect()
    return resource or nil
end

MIFire.Medical = Medical

return Medical
