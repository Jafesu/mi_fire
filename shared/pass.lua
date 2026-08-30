--- PASS device phase machine.
---
--- Pure: takes a state and what happened, returns the next state. No natives, no timers,
--- no side effects -- so the phase transitions can be checked outside the game, which
--- matters because they are almost impossible to test by hand. Standing perfectly still
--- for twenty-five seconds to verify a chirp is not a test anyone repeats.
---
--- Modelled on NFPA 1982. Four phases:
---
---   idle       not armed
---   sensing    armed and moving. Silent.
---   pre_alarm  motionless too long. Escalating chirp. **Movement clears it.**
---   full       pre-alarm ignored. Loud, and movement does NOT clear it -- it needs a
---              manual reset on the device.
---
--- That last asymmetry is the whole design. A firefighter who stops to work a nozzle gets
--- a chirp and wiggles it away. One who goes down and is dragged out by a partner is still
--- alarming when they arrive, because the alarm is for the people looking for them, not
--- for the wearer.

MIFire = MIFire or {}

local Pass = {}

Pass.Phase = {
    IDLE = 'idle',
    SENSING = 'sensing',
    PRE_ALARM = 'pre_alarm',
    FULL = 'full',
}

--- A fresh device state.
---@return table
function Pass.newState()
    return {
        phase = Pass.Phase.IDLE,
        motionless = 0.0,   -- seconds without meaningful movement
        inPhase = 0.0,      -- seconds in the current phase
        manual = false,     -- triggered by the wearer rather than by stillness
    }
end

--- Advance a device by `dt` seconds.
---
---@param state table From `Pass.newState`, mutated in place.
---@param dt number Seconds since the last step.
---@param input table
---   armed    boolean  the set is on and the valve open
---   moved    boolean  the wearer moved meaningfully since the last step
---   downed   boolean  ragdolled, unconscious, or dead
---   manual   boolean  the wearer hit the panic button this step
---   reset    boolean  someone pressed reset on the device
---@param config table `MIFireScba.pass`
---@return string phase
---@return boolean changed
function Pass.step(state, dt, input, config)
    local previous = state.phase

    -- Disarming stops everything, including a full alarm. Taking the set off is a
    -- deliberate act by someone who is evidently fine.
    if not input.armed then
        state.phase = Pass.Phase.IDLE
        state.motionless = 0.0
        state.inPhase = 0.0
        state.manual = false
        return state.phase, previous ~= state.phase
    end

    -- Manual activation goes straight to full alarm. This is the "I am trapped and I
    -- know it" button, and it must not be reachable by any amount of waiting.
    if input.manual then
        state.phase = Pass.Phase.FULL
        state.manual = true
        state.inPhase = 0.0
        return state.phase, previous ~= state.phase
    end

    -- Reset only clears a full alarm, and only when the wearer is not still down.
    -- Resetting a device on an unconscious firefighter should not silence it.
    if input.reset and state.phase == Pass.Phase.FULL and not input.downed then
        state.phase = Pass.Phase.SENSING
        state.motionless = 0.0
        state.inPhase = 0.0
        state.manual = false
        return state.phase, previous ~= state.phase
    end

    -- A downed wearer counts as motionless no matter what the position deltas say. This
    -- is the case the device exists for.
    local moving = input.moved and not input.downed

    if moving then
        state.motionless = 0.0
    else
        state.motionless = state.motionless + dt
    end

    if state.phase == Pass.Phase.IDLE then
        state.phase = Pass.Phase.SENSING
        state.motionless = 0.0
    end

    if state.phase == Pass.Phase.SENSING then
        if state.motionless >= config.preAlarmSeconds then
            state.phase = Pass.Phase.PRE_ALARM
            state.inPhase = 0.0
        end

    elseif state.phase == Pass.Phase.PRE_ALARM then
        -- Movement clears the pre-alarm. This is the phase you wiggle out of.
        if moving then
            state.phase = Pass.Phase.SENSING
            state.inPhase = 0.0
        else
            state.inPhase = state.inPhase + dt
            if state.inPhase >= config.fullAlarmSeconds then
                state.phase = Pass.Phase.FULL
                state.inPhase = 0.0
            end
        end

    elseif state.phase == Pass.Phase.FULL then
        -- Movement does **not** clear a full alarm. Someone being dragged to safety is
        -- moving, and their PASS should still be sounding when they arrive.
        state.inPhase = state.inPhase + dt
    end

    if state.phase ~= previous and state.phase ~= Pass.Phase.PRE_ALARM then
        state.inPhase = 0.0
    end

    return state.phase, previous ~= state.phase
end

--- How urgent the pre-alarm chirp should sound, 0 to 1.
---
--- A real PASS pre-alarm escalates in rate and pitch as it approaches full alarm, which
--- is what gives the wearer a reason to move before it goes off properly.
---@param state table
---@param config table
---@return number
function Pass.escalation(state, config)
    if state.phase ~= Pass.Phase.PRE_ALARM then return 0.0 end
    local fraction = state.inPhase / math.max(0.001, config.fullAlarmSeconds)
    return math.min(1.0, math.max(0.0, fraction))
end

--- Should this phase make a noise other people can hear?
---@param phase string
---@return boolean
function Pass.isAudible(phase)
    return phase == Pass.Phase.PRE_ALARM or phase == Pass.Phase.FULL
end

--- How far this phase carries.
---@param phase string
---@param config table
---@return number metres
function Pass.range(phase, config)
    if phase == Pass.Phase.FULL then return config.range.full end
    if phase == Pass.Phase.PRE_ALARM then return config.range.preAlarm end
    return 0.0
end

MIFire.Pass = Pass

return Pass
