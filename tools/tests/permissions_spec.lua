--- Permission tests.
---
--- Two independent routes to admin access, and the interesting cases are the boundaries:
--- the grade just below the threshold, the job that is not listed, the subcommand a rank
--- cannot reach. Those are the ones that produce a support ticket when they are wrong.
---
--- `IsPlayerAceAllowed` and the framework job lookup are both swapped out here, so the
--- real permission logic runs against controllable inputs.

return function(t)
    local Permissions = MIFire.Permissions

    -- -----------------------------------------------------------------------
    -- Controllable identity
    -- -----------------------------------------------------------------------

    local grantedAces = {}
    local currentJob = { name = nil, onDuty = false, grade = 0 }

    local realAceCheck = IsPlayerAceAllowed
    local realGetJob = MIFire.Framework.getJob

    IsPlayerAceAllowed = function(_source, ace) return grantedAces[ace] == true end
    MIFire.Framework.getJob = function() return currentJob.name, currentJob.onDuty, currentJob.grade end

    local function setAces(...)
        grantedAces = {}
        for _, ace in ipairs({ ... }) do grantedAces[ace] = true end
    end

    local function setJob(name, grade, onDuty)
        currentJob = { name = name, grade = grade or 0, onDuty = onDuty == true }
    end

    -- A source of 1 rather than 0: 0 is the console and always allowed, which would make
    -- every one of these pass for the wrong reason.
    local PLAYER = 1

    local savedPermissions = MIFire.Util.deepCopy(Config.permissions)

    local function usePermissions(overrides)
        Config.permissions = MIFire.Util.merge(savedPermissions, overrides or {})
    end

    usePermissions()

    -- -----------------------------------------------------------------------

    t.describe('the console is always allowed')

    t.equal(Permissions.isAdmin(0), true, 'source 0 is the server console and never refused')

    t.describe('ACE access')

    setAces()
    setJob(nil)
    t.equal(Permissions.isAdmin(PLAYER), false, 'a player with no ace and no job is refused')

    setAces('mi_fire.admin')
    t.equal(Permissions.isAdmin(PLAYER), true, 'the dedicated mi_fire ace grants access')

    setAces('command.fire')
    t.equal(Permissions.isAdmin(PLAYER), true, 'so does the command ace ox_lib would grant')

    setAces('some.other.permission')
    t.equal(Permissions.isAdmin(PLAYER), false, 'an unrelated ace does not')

    setAces('mi_fire.admin')
    local hasAce, which = Permissions.hasAdminAce(PLAYER)
    t.equal(hasAce, true, 'hasAdminAce reports success')
    t.equal(which, 'mi_fire.admin', 'and names the ace that matched, which is what makes it debuggable')

    -- -----------------------------------------------------------------------

    t.describe('job and grade access')

    usePermissions({ jobs = { fireman = 4 }, jobsRequireOnDuty = false })
    setAces()

    setJob('fireman', 4)
    t.equal(Permissions.isAdmin(PLAYER), true, 'a fireman at the required grade gets access')

    setJob('fireman', 9)
    t.equal(Permissions.isAdmin(PLAYER), true, 'and so does one above it')

    setJob('fireman', 3)
    t.equal(Permissions.isAdmin(PLAYER), false, 'one grade below the threshold does not')

    local _, why = Permissions.hasJobAccess(PLAYER)
    t.ok(why and why:find('3') ~= nil, 'and the reason names the grade they actually hold')
    t.ok(why and why:find('4') ~= nil, 'and the grade they needed')

    setJob('police', 10)
    t.equal(Permissions.isAdmin(PLAYER), false, 'a high rank in an unlisted job gets nothing')

    setJob(nil)
    t.equal(Permissions.isAdmin(PLAYER), false, 'and neither does no job at all')

    t.describe('duty requirement')

    usePermissions({ jobs = { fireman = 4 }, jobsRequireOnDuty = true })
    setJob('fireman', 9, false)
    t.equal(Permissions.isAdmin(PLAYER), false, 'with jobsRequireOnDuty, an off-duty chief is refused')

    setJob('fireman', 9, true)
    t.equal(Permissions.isAdmin(PLAYER), true, 'and an on-duty one is not')

    usePermissions({ jobs = { fireman = 4 }, jobsRequireOnDuty = false })
    setJob('fireman', 9, false)
    t.equal(Permissions.isAdmin(PLAYER), true,
        'without it, an off-duty chief can still stop a runaway fire')

    -- -----------------------------------------------------------------------

    t.describe('the two routes are independent')

    usePermissions({ jobs = { fireman = 4 } })
    setAces('mi_fire.admin')
    setJob(nil)
    t.equal(Permissions.isAdmin(PLAYER), true,
        'an admin needs no job -- testing a scene should not require clocking on')

    setAces()
    setJob('fireman', 9)
    t.equal(Permissions.isAdmin(PLAYER), true,
        'and a chief needs no ace -- running a drill should not require server admin')

    -- -----------------------------------------------------------------------

    t.describe('merge replaces lists rather than blending them')

    -- This is here because getting it wrong produced a test failure that looked like a
    -- permissions bug: overriding a five-entry jobCommands list with a one-entry list kept
    -- entries two through five, so a rank that should have been refused was allowed.
    local blended = MIFire.Util.merge(
        { list = { 'a', 'b', 'c' }, hash = { x = 1, y = 2 } },
        { list = { 'z' },           hash = { y = 9 } })

    t.equal(#blended.list, 1, 'an overriding list replaces the original outright')
    t.equal(blended.list[1], 'z', 'with only what the override named')
    t.equal(blended.hash.x, 1, 'while hashes still merge')
    t.equal(blended.hash.y, 9, 'with the override winning on shared keys')

    -- -----------------------------------------------------------------------

    t.describe('job access can be limited to some subcommands')

    usePermissions({ jobs = { fireman = 4 }, jobCommands = { 'list', 'info' } })
    setAces()
    setJob('fireman', 9)

    t.equal(Permissions.isAdmin(PLAYER, 'list'), true, 'a listed subcommand is reachable by job')
    t.equal(Permissions.isAdmin(PLAYER, 'wind'), false, 'an unlisted one is not')

    setAces('mi_fire.admin')
    t.equal(Permissions.isAdmin(PLAYER, 'wind'), true,
        'but an ace admin reaches everything regardless of the list')

    setAces()
    Config.permissions.jobCommands = nil
    t.equal(Permissions.isAdmin(PLAYER, 'wind'), true,
        'and with no list at all, job access reaches everything')

    -- -----------------------------------------------------------------------

    t.describe('refusals explain themselves')

    usePermissions({ jobs = { fireman = 4 }, jobCommands = { 'list' } })
    setAces()
    setJob('fireman', 2)

    local allowed, reason = Permissions.requireAdmin(PLAYER, 'start')
    t.equal(allowed, false, 'an under-ranked firefighter is refused')
    t.ok(type(reason) == 'string' and #reason > 0, 'with a reason rather than a bare false')

    setJob('fireman', 9)
    local rankAllowed, rankReason = Permissions.requireAdmin(PLAYER, 'start')
    t.equal(rankAllowed, false, 'a chief outside the permitted subcommand list is refused')
    t.ok(rankReason and rankReason:find('rank') ~= nil,
        'and told it is their rank, not their identity -- a different fix from having no access')

    t.describe('the diagnostic reports both routes')

    setAces('mi_fire.admin')
    setJob('fireman', 9, true)
    local lines = Permissions.explain(PLAYER)
    local blob = table.concat(lines, '\n')

    t.ok(#lines > 0, 'explain returns something')
    t.ok(blob:find('fireman') ~= nil, 'naming the job held')
    t.ok(blob:find('mi_fire%.admin') ~= nil, 'and every ace it tested')
    t.ok(blob:find('ALLOWED') ~= nil, 'and the verdict')

    setAces()
    setJob(nil)
    blob = table.concat(Permissions.explain(PLAYER), '\n')
    t.ok(blob:find('DENIED') ~= nil, 'a denied player is told so plainly')
    t.ok(blob:find('add_ace') ~= nil,
        'and given the exact server.cfg line to fix it, which is the whole point')

    t.equal(Permissions.explain(0)[1]:find('console') ~= nil, true,
        'the console explains itself too')

    -- -----------------------------------------------------------------------

    t.describe('validation catches a permissions config that grants nothing')

    local broken = MIFire.Util.deepCopy(Config)
    broken.permissions = { aces = {}, jobs = {} }
    t.ok(#MIFire.Validate.configuration(broken, MIFireGear, MIFireZones) > 0,
        'a config with no aces and no jobs is rejected rather than silently locking everyone out')

    local badGrade = MIFire.Util.deepCopy(Config)
    badGrade.permissions.jobs = { fireman = 'chief' }
    t.ok(#MIFire.Validate.configuration(badGrade, MIFireGear, MIFireZones) > 0,
        'a non-numeric grade is rejected')

    local ghostCommand = MIFire.Util.deepCopy(Config)
    ghostCommand.permissions.jobCommands = { 'list', 'not_a_subcommand' }
    t.ok(#MIFire.Validate.configuration(ghostCommand, MIFireGear, MIFireZones) > 0,
        'a jobCommands entry naming no real subcommand is rejected, because it reads as working')

    -- -----------------------------------------------------------------------

    Config.permissions = savedPermissions
    IsPlayerAceAllowed = realAceCheck
    MIFire.Framework.getJob = realGetJob
end
