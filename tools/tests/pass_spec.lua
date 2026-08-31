--- PASS device phase tests.
---
--- These exist because the transitions are close to untestable by hand. Verifying that a
--- chirp starts at twenty-five seconds means standing perfectly still for twenty-five
--- seconds; verifying that movement clears a pre-alarm but not a full alarm means doing it
--- twice more. Nobody repeats that, so it silently rots.

return function(t)
    local Pass = MIFire.Pass
    local cfg = MIFireScba.pass

    --- Run the machine for `seconds`, one step per second.
    local function run(state, seconds, input)
        local phase
        for _ = 1, seconds do
            phase = Pass.step(state, 1.0, input, cfg)
        end
        return phase
    end

    local ARMED_STILL = { armed = true, moved = false }
    local ARMED_MOVING = { armed = true, moved = true }

    local toFullAlarm = math.floor(cfg.preAlarmSeconds + cfg.fullAlarmSeconds) + 2

    -- -----------------------------------------------------------------------

    t.describe('a device that is not armed does nothing')

    local state = Pass.newState()
    t.equal(state.phase, Pass.Phase.IDLE, 'a fresh device is idle')

    run(state, 120, { armed = false, moved = false })
    t.equal(state.phase, Pass.Phase.IDLE,
        'standing still for two minutes with the valve shut is not an emergency')

    -- -----------------------------------------------------------------------

    t.describe('an armed device senses')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    t.equal(state.phase, Pass.Phase.SENSING, 'arming starts sensing')

    run(state, 120, ARMED_MOVING)
    t.equal(state.phase, Pass.Phase.SENSING,
        'and a firefighter who keeps moving never alarms, however long they work')

    -- -----------------------------------------------------------------------

    t.describe('standing still raises a pre-alarm')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)

    run(state, math.floor(cfg.preAlarmSeconds) - 2, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.SENSING, 'just short of the threshold, still silent')

    run(state, 3, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.PRE_ALARM, 'past it, the chirp starts')

    t.describe('and the chirp escalates')

    local early = Pass.escalation(state, cfg)
    run(state, math.floor(cfg.fullAlarmSeconds / 2), ARMED_STILL)
    local later = Pass.escalation(state, cfg)

    t.ok(later > early, 'escalation climbs while the pre-alarm runs')
    t.ok(later <= 1.0, 'and is bounded at one')

    -- -----------------------------------------------------------------------

    t.describe('movement clears a pre-alarm')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    run(state, math.floor(cfg.preAlarmSeconds) + 1, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.PRE_ALARM, 'chirping')

    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    t.equal(state.phase, Pass.Phase.SENSING,
        'a wiggle clears it -- this is the phase you are meant to be able to escape')
    t.equal(Pass.escalation(state, cfg), 0.0, 'and the escalation resets')

    -- -----------------------------------------------------------------------

    t.describe('ignoring the chirp raises a full alarm')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    run(state, toFullAlarm, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.FULL, 'the full alarm sounds')

    t.describe('and movement does NOT clear a full alarm')

    run(state, 30, ARMED_MOVING)
    t.equal(state.phase, Pass.Phase.FULL,
        'a firefighter being dragged out is still alarming when they arrive, because the '
        .. 'alarm is for the people looking rather than for the wearer')

    -- -----------------------------------------------------------------------

    t.describe('going down alarms on its own')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)

    -- A ragdolled ped slides, so position says "moving". Downed has to override that, or
    -- the device stays silent for exactly the person it exists to find.
    run(state, toFullAlarm, { armed = true, moved = true, downed = true })

    t.equal(state.phase, Pass.Phase.FULL,
        'a downed firefighter alarms even though their body is still moving')

    -- -----------------------------------------------------------------------

    t.describe('the panic button is immediate')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    Pass.step(state, 1.0, { armed = true, moved = true, manual = true }, cfg)

    t.equal(state.phase, Pass.Phase.FULL,
        'manual activation goes straight to full alarm with no waiting')
    t.equal(state.manual, true, 'and is marked as deliberate')

    -- -----------------------------------------------------------------------

    t.describe('reset')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    run(state, toFullAlarm, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.FULL, 'alarming')

    Pass.step(state, 1.0, { armed = true, moved = true, reset = true }, cfg)
    t.equal(state.phase, Pass.Phase.SENSING, 'reset clears it')

    t.describe('but not on someone still down')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    run(state, toFullAlarm, { armed = true, moved = false, downed = true })
    t.equal(state.phase, Pass.Phase.FULL, 'alarming for a downed firefighter')

    Pass.step(state, 1.0, { armed = true, moved = false, downed = true, reset = true }, cfg)
    t.equal(state.phase, Pass.Phase.FULL,
        'resetting a device on someone still unconscious does not silence it')

    -- -----------------------------------------------------------------------

    t.describe('taking the set off stops everything')

    state = Pass.newState()
    Pass.step(state, 1.0, ARMED_MOVING, cfg)
    run(state, toFullAlarm, ARMED_STILL)
    t.equal(state.phase, Pass.Phase.FULL, 'alarming')

    Pass.step(state, 1.0, { armed = false }, cfg)
    t.equal(state.phase, Pass.Phase.IDLE,
        'disarming stops even a full alarm, because taking a set off is a deliberate act '
        .. 'by someone who is evidently fine')

    -- -----------------------------------------------------------------------

    t.describe('audibility and range')

    t.equal(Pass.isAudible(Pass.Phase.IDLE), false, 'an idle device is silent')
    t.equal(Pass.isAudible(Pass.Phase.SENSING), false, 'so is one that is sensing')
    t.equal(Pass.isAudible(Pass.Phase.PRE_ALARM), true, 'a pre-alarm is heard')
    t.equal(Pass.isAudible(Pass.Phase.FULL), true, 'and so is a full alarm')

    t.ok(Pass.range(Pass.Phase.FULL, cfg) > Pass.range(Pass.Phase.PRE_ALARM, cfg),
        'a full alarm carries further than a chirp, which is the point of it')
    t.equal(Pass.range(Pass.Phase.SENSING, cfg), 0.0, 'and a silent phase carries nothing')

    -- -----------------------------------------------------------------------

    t.describe('the configured timings are sane')

    t.ok(cfg.preAlarmSeconds > 0, 'the pre-alarm has a delay')
    t.ok(cfg.fullAlarmSeconds > 0, 'and so does the full alarm')
    t.ok(cfg.preAlarmSeconds > cfg.fullAlarmSeconds,
        'the wait before chirping is longer than the grace after it -- a device that '
        .. 'reached full alarm faster than it started chirping would give no warning')
    t.ok(cfg.movementThreshold > 0,
        'movement needs a threshold, or a standing ped drifting would count as moving')

    -- -----------------------------------------------------------------------

    t.describe('audio is configured to be heard')

    local audio = MIFireScba.audio
    t.ok(type(audio) == 'table', 'there is an audio configuration')
    t.ok(audio.files and audio.files.full,
        'with a full-alarm file, which is what auto mode needs to pick NUI over native')

    -- A missing pre-alarm file is fine and expected: the full sound is played in bursts.
    -- What must not happen is auto mode falling back to native because of it.
    t.ok(audio.burst and audio.burst.burstMs and audio.burst.gapMsAtStart,
        'and burst timings, so one sound file can cover both phases')
    t.ok(audio.burst.gapMsAtFull < audio.burst.gapMsAtStart,
        'with the gap shortening as it escalates, so the chirp speeds up')

    -- -----------------------------------------------------------------------

    t.describe('a downed wearer alarms far sooner')

    -- Reported from play: going down and waiting produced silence for long enough that the
    -- device may as well not have been there. A real PASS genuinely does take its full
    -- thirty-odd seconds -- it cannot tell you are down -- but thirty seconds is most of a
    -- bleed-out timer, so this is a deliberate departure.
    local cfg = MIFireScba.pass

    ---@param downed boolean
    ---@return number seconds until full alarm
    local function secondsToFullAlarm(downed)
        local state = Pass.newState()
        local elapsed = 0.0

        while elapsed < 300 do
            Pass.step(state, 0.5, { armed = true, moved = false, downed = downed }, cfg)
            elapsed = elapsed + 0.5
            if state.phase == Pass.Phase.FULL then return elapsed end
        end

        return elapsed
    end

    local standing = secondsToFullAlarm(false)
    local down = secondsToFullAlarm(true)

    t.ok(down < standing,
        ('a downed firefighter alarms sooner than one merely standing still (%.0fs vs %.0fs)')
            :format(down, standing))

    t.ok(down <= 20,
        'and soon enough to be worth having -- a mayday nobody hears for half a minute is '
        .. 'not a mayday')

    t.ok(standing >= cfg.preAlarmSeconds,
        'while standing still still takes the full realistic time')

    t.describe('and the shortcut is configurable away')

    local realistic = MIFire.Util.merge(cfg, {
        downed = { preAlarmSeconds = cfg.preAlarmSeconds, fullAlarmSeconds = cfg.fullAlarmSeconds },
    })

    local state = Pass.newState()
    local elapsed = 0.0
    while elapsed < 300 and state.phase ~= Pass.Phase.FULL do
        Pass.step(state, 0.5, { armed = true, moved = false, downed = true }, realistic)
        elapsed = elapsed + 0.5
    end

    t.ok(elapsed >= cfg.preAlarmSeconds,
        'a server that wants the accurate behaviour can have it back')
end
