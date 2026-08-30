--- Gear integrity tests.
---
--- Three models a server can choose between, and the thing worth protecting is that each
--- one is coherent on its own terms — a forgiving server should never strand someone
--- without a coat, and a realistic one should never quietly heal damage behind their back.

return function(t)
    local Integrity = MIFire.Integrity
    local capacity = 240.0

    --- A config in a given mode, without disturbing the shipped one.
    local function withMode(mode, overrides)
        local cfg = MIFire.Util.merge(MIFireGear.integrity, overrides or {})
        cfg.mode = mode
        return cfg
    end

    -- -----------------------------------------------------------------------

    t.describe('regenerate: gear recovers once you are clear')

    local regen = withMode(Integrity.Mode.REGENERATE)
    local delay = regen.regenerate.delaySeconds

    t.equal(Integrity.recover(100, capacity, delay - 5, 2.0, regen), 100,
        'ducking out briefly does not start recovery -- the delay is the mechanic')

    t.ok(Integrity.recover(100, capacity, delay + 5, 2.0, regen) > 100,
        'staying clear past the delay does')

    t.equal(Integrity.recover(capacity, capacity, 9999, 2.0, regen), capacity,
        'and a healthy set does not recover past full')

    t.describe('and stops at the configured ceiling')

    local partial = withMode(Integrity.Mode.REGENERATE, { regenerate = { recoverTo = 0.6 } })
    local recovered = 0.0
    for _ = 1, 500 do
        recovered = Integrity.recover(recovered, capacity, 9999, 1.0, partial)
    end

    t.ok(recovered <= capacity * 0.6 + 0.01,
        'a ceiling below full means gear still degrades across a shift on this mode')

    -- -----------------------------------------------------------------------

    t.describe('persist: damage stays until someone deals with it')

    local persist = withMode(Integrity.Mode.PERSIST)

    t.equal(Integrity.recover(100, capacity, 99999, 60.0, persist), 100,
        'a persistent set never heals on its own, however long you wait')

    t.describe('session: gear is fresh each time it goes on')

    local session = withMode(Integrity.Mode.SESSION)
    t.equal(Integrity.recover(100, capacity, 99999, 60.0, session), 100,
        'the session model does not recover in place either -- it resets on re-don')

    -- -----------------------------------------------------------------------

    t.describe('condemned gear cannot be repaired')

    local condemnedAt = persist.persist.condemnedBelow

    t.equal(Integrity.isCondemned(capacity * (condemnedAt + 0.1), capacity, persist), false,
        'a damaged set above the threshold is still serviceable')
    t.equal(Integrity.isCondemned(capacity * (condemnedAt - 0.05), capacity, persist), true,
        'below it, the set is condemned')

    local ok, why = Integrity.canRepair(capacity * (condemnedAt - 0.05), capacity, persist)
    t.equal(ok, false, 'and repair is refused')
    t.ok(why and why:find('replac') ~= nil, 'telling you to replace it instead')

    t.describe('and neither can a healthy one')

    local healthyOk, healthyWhy = Integrity.canRepair(capacity, capacity, persist)
    t.equal(healthyOk, false, 'there is nothing to repair on a good set')
    t.ok(healthyWhy ~= nil, 'with a reason')

    t.describe('nor can anything on the regenerate model')

    local regenOk, regenWhy = Integrity.canRepair(100, capacity, regen)
    t.equal(regenOk, false, 'repair is meaningless when gear heals itself')
    t.ok(regenWhy and regenWhy:find('own') ~= nil, 'and says so rather than silently failing')

    -- -----------------------------------------------------------------------

    t.describe('repair takes longer the worse it is')

    local light = Integrity.repairSeconds(capacity * 0.8, capacity, persist)
    local heavy = Integrity.repairSeconds(capacity * 0.2, capacity, persist)

    t.ok(heavy > light,
        'a nearly-condemned coat is a job; a scorched one is quick')
    t.ok(light > 0, 'and neither is instant')

    -- -----------------------------------------------------------------------

    t.describe('repaired gear does not come back as new')

    local first = Integrity.afterRepair(capacity, 1, persist)
    local third = Integrity.afterRepair(capacity, 3, persist)

    t.ok(first <= capacity, 'the first repair does not exceed the original ceiling')
    t.ok(third < first,
        'and each repair costs a little more of it, so a set is eventually replaced '
        .. 'rather than patched forever')

    t.ok(Integrity.afterRepair(capacity, 50, persist) > 0,
        'but the ceiling has a floor, so gear never repairs to nothing')

    t.describe('unless the server turns that off')

    local lossless = withMode(Integrity.Mode.PERSIST, { persist = { ceilingLossPerRepair = 0.0 } })
    t.near(Integrity.afterRepair(capacity, 5, lossless), capacity, 0.01,
        'with no ceiling loss, repair restores to full every time')

    -- -----------------------------------------------------------------------

    t.describe('condition is described in words, not percentages')

    t.equal(Integrity.condition(capacity, capacity, persist), 'serviceable',
        'a full set is serviceable')
    t.equal(Integrity.condition(capacity * 0.75, capacity, persist), 'showing wear',
        'a used one is showing wear')
    t.equal(Integrity.condition(capacity * 0.4, capacity, persist), 'damaged',
        'a battered one is damaged')
    t.equal(Integrity.condition(capacity * 0.05, capacity, persist), 'condemned',
        'and one past saving is condemned')

    t.describe('and a tier with no integrity pool reports honestly')

    local none, fraction = Integrity.condition(0, 0, persist)
    t.equal(none, 'none', 'a station uniform has no condition to report')
    t.equal(fraction, 0.0, 'and no fraction')

    -- -----------------------------------------------------------------------

    t.describe('the shipped configuration is coherent')

    local shipped = MIFireGear.integrity

    t.ok(shipped.mode == Integrity.Mode.REGENERATE
        or shipped.mode == Integrity.Mode.PERSIST
        or shipped.mode == Integrity.Mode.SESSION,
        'the configured mode is one that exists')

    t.ok(shipped.persist.condemnedBelow > 0 and shipped.persist.condemnedBelow < 1,
        'the condemned threshold is a fraction')

    t.ok(shipped.persist.replaceSeconds < shipped.persist.repairSeconds,
        'drawing a fresh set is faster than servicing the one you have, which is why '
        .. 'anyone would ever repair rather than replace')

    t.ok(shipped.regenerate.delaySeconds > 0,
        'recovery has a delay, or backing out for a moment would reset a coat')
end
