--- Database access and the migration runner.
---
--- Only runtime data that a server owner *builds* lives in MySQL -- stations and the
--- points and zones that make one up. Tuning stays in `config/`, because tuning is
--- something you edit in a text editor and station geometry is not.
---
--- Migrations are numbered files applied by this runner and recorded in a table. Never
--- hand-run SQL, and never edit a migration that has shipped -- write a new one.

MIFire = MIFire or {}

local DB = {
    available = false,
    ---@type string|nil
    unavailableReason = nil,
}

-- ---------------------------------------------------------------------------
-- Availability
-- ---------------------------------------------------------------------------

--- oxmysql is a hard dependency of the manifest, so its *absence* is not a case this can
--- reach -- the resource would not have started. What this catches is the different and
--- much more common failure: oxmysql present but the database unreachable, credentials
--- wrong, or the connection not up yet at boot.
---
--- In that case mi_fire loses stations and says so once. The fire core has no reason to
--- care whether MySQL is answering.
---@return boolean
local function detect()
    if GetResourceState('oxmysql') ~= 'started' then
        DB.unavailableReason = 'oxmysql is not started'
        return false
    end

    if not MySQL then
        DB.unavailableReason = 'oxmysql is started but MySQL is not in scope'
        return false
    end

    -- Prove the connection rather than trusting the resource state. A started oxmysql
    -- with a bad connection string looks identical to a working one until the first
    -- query fails, which is usually somewhere far less convenient than here.
    local ok, err = pcall(MySQL.scalar.await, 'SELECT 1')
    if not ok then
        DB.unavailableReason = ('database is unreachable: %s'):format(tostring(err))
        return false
    end

    return true
end

--- Is the database usable? Callers that need it check this rather than assuming.
---@return boolean
---@return string|nil reason
function DB.isAvailable()
    return DB.available, DB.unavailableReason
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

--- Every helper returns a safe empty value when the database is absent, so a caller can
--- degrade rather than nil-index. Errors are caught and logged with the query that caused
--- them, because a silent MySQL failure is close to undebuggable.

---@param query string
---@param params table|nil
---@return table rows
function DB.query(query, params)
    if not DB.available then return {} end
    local ok, result = pcall(MySQL.query.await, query, params)
    if not ok then
        MIFire.Util.warn('query failed: %s\n  %s', tostring(result), query)
        return {}
    end
    return result or {}
end

---@param query string
---@param params table|nil
---@return table|nil row
function DB.single(query, params)
    if not DB.available then return nil end
    local ok, result = pcall(MySQL.single.await, query, params)
    if not ok then
        MIFire.Util.warn('single failed: %s\n  %s', tostring(result), query)
        return nil
    end
    return result
end

---@param query string
---@param params table|nil
---@return any
function DB.scalar(query, params)
    if not DB.available then return nil end
    local ok, result = pcall(MySQL.scalar.await, query, params)
    if not ok then
        MIFire.Util.warn('scalar failed: %s\n  %s', tostring(result), query)
        return nil
    end
    return result
end

---@param query string
---@param params table|nil
---@return integer affectedRows
function DB.update(query, params)
    if not DB.available then return 0 end
    local ok, result = pcall(MySQL.update.await, query, params)
    if not ok then
        MIFire.Util.warn('update failed: %s\n  %s', tostring(result), query)
        return 0
    end
    return result or 0
end

---@param query string
---@param params table|nil
---@return integer|nil insertId
function DB.insert(query, params)
    if not DB.available then return nil end
    local ok, result = pcall(MySQL.insert.await, query, params)
    if not ok then
        MIFire.Util.warn('insert failed: %s\n  %s', tostring(result), query)
        return nil
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Migrations
-- ---------------------------------------------------------------------------

--- Files in `install/migrations/`, in the order they must be applied.
---
--- Listed explicitly rather than globbed: FiveM cannot enumerate a resource directory at
--- runtime, and an ordering that depends on filesystem iteration order is an ordering
--- waiting to change under you.
local MIGRATIONS = {
    { version = 1, name = '0001_stations' },
}

local function ensureMigrationTable()
    return DB.update([[
        CREATE TABLE IF NOT EXISTS `mi_fire_migrations` (
            `version`    INT UNSIGNED NOT NULL,
            `name`       VARCHAR(128) NOT NULL,
            `applied_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`version`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]) ~= nil
end

---@return table<integer, boolean>
local function appliedVersions()
    local applied = {}
    for _, row in ipairs(DB.query('SELECT `version` FROM `mi_fire_migrations`')) do
        applied[tonumber(row.version)] = true
    end
    return applied
end

--- Split a migration file into individual statements.
---
--- Naive on purpose: statements are separated by a semicolon at end of line, and the
--- migrations in this repo are written to suit that. A migration needing a procedure or a
--- trigger would need a real parser, and the right answer then is to not write one.
---@param sql string
---@return string[]
local function splitStatements(sql)
    local statements = {}

    -- Strip full-line comments first so a `;` inside one cannot split a statement.
    local cleaned = sql:gsub('%-%-[^\n]*', '')

    for statement in cleaned:gmatch('[^;]+') do
        local trimmed = statement:match('^%s*(.-)%s*$')
        if trimmed ~= '' then
            statements[#statements + 1] = trimmed
        end
    end

    return statements
end

---@param name string
---@return boolean ok
local function applyMigration(name)
    local path = ('install/migrations/%s.sql'):format(name)
    local sql = LoadResourceFile(GetCurrentResourceName(), path)

    if not sql or sql == '' then
        MIFire.Util.warn('migration %s is missing or empty at %s', name, path)
        return false
    end

    for _, statement in ipairs(splitStatements(sql)) do
        local ok, err = pcall(MySQL.update.await, statement)
        if not ok then
            MIFire.Util.warn('migration %s failed: %s\n  %s', name, tostring(err), statement)
            return false
        end
    end

    return true
end

--- Apply every migration that has not run yet.
---
--- Returns false if any migration failed, so the caller can disable the features that
--- depend on the schema rather than letting them fail one query at a time.
---@return boolean ok
---@return integer applied How many ran this boot.
function DB.migrate()
    if not DB.available then return false, 0 end

    if not ensureMigrationTable() then
        MIFire.Util.warn('could not create the migration table; station features are disabled')
        return false, 0
    end

    local applied = appliedVersions()
    local count = 0

    for _, migration in ipairs(MIGRATIONS) do
        if not applied[migration.version] then
            if not applyMigration(migration.name) then
                return false, count
            end

            DB.update('INSERT INTO `mi_fire_migrations` (`version`, `name`) VALUES (?, ?)',
                { migration.version, migration.name })

            count = count + 1
            print(('[mi_fire] applied migration %s'):format(migration.name))
        end
    end

    return true, count
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

--- Called from `server/main.lua` after config validation.
---@return boolean ready
function DB.init()
    DB.available = detect()

    if not DB.available then
        MIFire.Util.warn('%s; station configuration is unavailable and everything else runs normally',
            DB.unavailableReason)
        return false
    end

    local ok, applied = DB.migrate()

    if not ok then
        DB.available = false
        DB.unavailableReason = 'migrations failed'
        return false
    end

    MIFire.Util.debug('db', 'ready, %d migration(s) applied this boot', applied)
    return true
end

MIFire.DB = DB

return DB
