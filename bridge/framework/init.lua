--- Framework bridge.
---
--- Nothing outside this directory may reference `qbx_core`, `QBX`, `ESX`, or any other
--- framework by name. Modules ask `Framework.getJob(source)` and do not know or care
--- what answers.
---
--- The cost of breaking that rule is not theoretical: framework-specific calls scattered
--- through feature code is how a resource ends up working on exactly one server.

MIFire = MIFire or {}

local Framework = {
    name = 'unknown',
    ---@type table
    impl = nil,
}

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

--- Adapters, in priority order. The first one whose resource is running wins.
local adapters = {
    {
        name = 'qbx',
        detect = function() return resourceStarted('qbx_core') end,
        build = function()
            local impl = {}

            if IsDuplicityVersion() then
                function impl.getPlayer(source)
                    return exports.qbx_core:GetPlayer(source)
                end

                function impl.getJob(source)
                    local player = exports.qbx_core:GetPlayer(source)
                    if not player then return nil end
                    local job = player.PlayerData and player.PlayerData.job
                    if not job then return nil end
                    return job.name, job.onduty == true, job.grade and job.grade.level or 0
                end

                function impl.getIdentifier(source)
                    local player = exports.qbx_core:GetPlayer(source)
                    return player and player.PlayerData and player.PlayerData.citizenid or nil
                end

                function impl.getPlayersWithJob(jobName)
                    local out = {}
                    local players = exports.qbx_core:GetQBPlayers()
                    for src, player in pairs(players or {}) do
                        local job = player.PlayerData and player.PlayerData.job
                        if job and job.name == jobName then
                            out[#out + 1] = { source = tonumber(src), onDuty = job.onduty == true }
                        end
                    end
                    return out
                end
            else
                function impl.getPlayerData()
                    return exports.qbx_core:GetPlayerData()
                end

                function impl.getJob()
                    local data = exports.qbx_core:GetPlayerData()
                    local job = data and data.job
                    if not job then return nil end
                    return job.name, job.onduty == true, job.grade and job.grade.level or 0
                end
            end

            return impl
        end,
    },

    {
        name = 'esx',
        detect = function() return resourceStarted('es_extended') end,
        build = function()
            local ESX = exports.es_extended:getSharedObject()
            local impl = {}

            if IsDuplicityVersion() then
                function impl.getPlayer(source)
                    return ESX.GetPlayerFromId(source)
                end

                function impl.getJob(source)
                    local player = ESX.GetPlayerFromId(source)
                    if not player or not player.job then return nil end
                    -- ESX has no duty concept of its own; treat holding the job as on duty
                    -- unless a server has added one.
                    return player.job.name, true, player.job.grade or 0
                end

                function impl.getIdentifier(source)
                    local player = ESX.GetPlayerFromId(source)
                    return player and player.identifier or nil
                end

                function impl.getPlayersWithJob(jobName)
                    local out = {}
                    for _, src in ipairs(ESX.GetPlayers()) do
                        local player = ESX.GetPlayerFromId(src)
                        if player and player.job and player.job.name == jobName then
                            out[#out + 1] = { source = src, onDuty = true }
                        end
                    end
                    return out
                end
            else
                function impl.getPlayerData()
                    return ESX.GetPlayerData()
                end

                function impl.getJob()
                    local data = ESX.GetPlayerData()
                    if not data or not data.job then return nil end
                    return data.job.name, true, data.job.grade or 0
                end
            end

            return impl
        end,
    },

    {
        name = 'standalone',
        detect = function() return true end,
        build = function()
            -- No framework. Everyone is a civilian unless ACE says otherwise, which
            -- keeps the resource startable for testing on a bare server.
            local impl = {}

            if IsDuplicityVersion() then
                function impl.getPlayer(source) return { source = source } end
                function impl.getJob(_source) return nil, false, 0 end
                function impl.getIdentifier(source) return ('src:%s'):format(source) end
                function impl.getPlayersWithJob(_jobName) return {} end
            else
                function impl.getPlayerData() return {} end
                function impl.getJob() return nil, false, 0 end
            end

            return impl
        end,
    },
}

local function resolve()
    for i = 1, #adapters do
        local adapter = adapters[i]
        local ok, detected = pcall(adapter.detect)
        if ok and detected then
            local built, impl = pcall(adapter.build)
            if built then
                Framework.name = adapter.name
                Framework.impl = impl
                return
            end
            print(('[mi_fire] framework adapter %s matched but failed to build: %s')
                :format(adapter.name, impl))
        end
    end
end

resolve()

-- ---------------------------------------------------------------------------
-- Public interface
-- ---------------------------------------------------------------------------

--- Job name, duty state, and grade for a player.
--- Server: pass a source. Client: pass nothing.
---@param source integer|nil
---@return string|nil jobName
---@return boolean onDuty
---@return integer grade
function Framework.getJob(source)
    if not Framework.impl then return nil, false, 0 end
    local name, onDuty, grade = Framework.impl.getJob(source)
    return name, onDuty == true, grade or 0
end

--- Is this player a firefighter, per `Config.fireJobs` and `Config.requireOnDuty`?
---@param source integer|nil
---@return boolean
function Framework.isFirefighter(source)
    local name, onDuty = Framework.getJob(source)
    if not name or not Config.fireJobs[name] then return false end
    if Config.requireOnDuty and not onDuty then return false end
    return true
end

--- Is this player EMS?
---@param source integer|nil
---@return boolean
function Framework.isEms(source)
    local name, onDuty = Framework.getJob(source)
    if not name or not Config.emsJobs[name] then return false end
    if Config.requireOnDuty and not onDuty then return false end
    return true
end

---@param source integer
---@return string|nil
function Framework.getIdentifier(source)
    if not Framework.impl or not Framework.impl.getIdentifier then return nil end
    return Framework.impl.getIdentifier(source)
end

--- Every firefighter currently on duty. Used by staffing gates and the accountability
--- board.
---@return table[] { source, onDuty }
function Framework.getOnDutyFirefighters()
    if not Framework.impl or not Framework.impl.getPlayersWithJob then return {} end

    local seen, out = {}, {}
    for jobName in pairs(Config.fireJobs) do
        for _, entry in ipairs(Framework.impl.getPlayersWithJob(jobName)) do
            if not seen[entry.source] and (entry.onDuty or not Config.requireOnDuty) then
                seen[entry.source] = true
                out[#out + 1] = entry
            end
        end
    end

    return out
end

MIFire.Framework = Framework

return Framework
