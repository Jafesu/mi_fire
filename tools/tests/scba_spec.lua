--- SCBA and turnout tests.
---
--- The distinction worth protecting: **wearing a set is not breathing from it.** Only an
--- active valve with air left protects, and only an active valve burns air. Getting that
--- wrong makes SCBA either useless or a free pass, and it is one boolean either way.

return function(t)
    local State = MIFire.State
    local Turnout = MIFire.Turnout
    local Appearance = MIFire.Appearance

    local PLAYER = 1

    -- Everything is gated on being a firefighter, so make this one.
    local realGetJob = MIFire.Framework.getJob
    MIFire.Framework.getJob = function() return 'fireman', true, 4 end

    local function reset()
        State.clearGear(PLAYER)
        State.clearScba(PLAYER)
    end

    reset()

    -- -----------------------------------------------------------------------

    t.describe('appearance slots resolve correctly')

    -- The bug this catches: a helmet is a prop, not a component. They go through
    -- different natives with different key names, and a helmet listed as a component
    -- silently does nothing at all.
    local kind, id = Appearance.resolveSlot('hat')
    t.equal(kind, 'prop', 'a helmet is a prop')
    t.equal(id, 0, 'on prop slot 0')

    kind, id = Appearance.resolveSlot('torso2')
    t.equal(kind, 'component', 'a jacket is a component')
    t.equal(id, 11, 'on component 11')

    kind, id = Appearance.resolveSlot('t-shirt')
    t.equal(kind, 'component', 'the SCBA harness slot is a component')
    t.equal(id, 8, 'on component 8, independent of the jacket on 11')

    t.equal(Appearance.resolveSlot('trousers'), nil,
        'a slot name that is not real resolves to nothing rather than guessing')

    t.describe('and split into the two shapes illenium wants')

    local components, props, unknown = Appearance.split({
        hat = 251, torso2 = 692, arms = 179, nonsense = 5,
    })

    t.equal(#props, 1, 'the helmet went to props')
    t.equal(props[1].prop_id, 0, 'with prop_id, not component_id')
    t.equal(props[1].drawable, 251, 'and the right drawable')
    t.equal(#components, 2, 'the jacket and gloves went to components')
    t.equal(#unknown, 1, 'and the invented slot is reported rather than dropped silently')

    local withTexture = Appearance.split({ torso2 = { drawable = 692, texture = 3 } })
    t.equal(withTexture[1].texture, 3, 'an explicit texture is honoured')

    local plain = Appearance.split({ torso2 = 692 })
    t.equal(plain[1].texture, 0, 'and a bare number defaults to texture 0')

    -- -----------------------------------------------------------------------

    t.describe('the turnout tier carries a real appearance')

    local structural = MIFireGear.tiers.structural
    t.ok(type(structural.appearance) == 'table', 'structural turnout has an appearance set')
    t.ok(structural.appearance.male and structural.appearance.female,
        'for both sexes, so nobody is left in civilian clothes')

    t.describe('every appearance slot in every gear tier is a real slot')

    -- The bug this catches is silent and total. `Appearance.split` sorts a slot into components,
    -- props, or `unknown`, and unknown slots are dropped -- so a misspelled name means that
    -- piece of gear simply never goes on, with no error and nothing missing from the config to
    -- look at. `bags` instead of `bag` was exactly this: a firefighter kept their civilian
    -- backpack on over the turnout coat, and every other slot worked, so nothing looked wrong.
    --
    -- Checked across every tier and both sexes, because the tiers are hand-authored and get
    -- copied between each other.
    for tierName, tier in pairs(MIFireGear.tiers) do
        for sex, set in pairs(tier.appearance or {}) do
            for slot in pairs(set) do
                t.ok(Appearance.resolveSlot(slot) ~= nil,
                    ('%s/%s: "%s" is a slot the appearance bridge knows')
                        :format(tierName, sex, slot))
            end
        end
    end

    -- -----------------------------------------------------------------------

    local turnoutComponents, turnoutProps = Appearance.split(structural.appearance.male)
    t.ok(#turnoutProps >= 1, 'including a helmet on the prop slot')
    t.ok(#turnoutComponents >= 3, 'and several clothing components')

    -- -----------------------------------------------------------------------

    t.describe('wearing a set is not breathing from it')

    reset()
    t.equal(State.hasAir(PLAYER), false, 'someone with no set is not protected')

    local ok = Turnout.donScba(PLAYER, { fromRack = true })
    t.equal(ok, true, 'a rack hands out a set')

    local scba = State.getScba(PLAYER)
    t.equal(scba.worn, true, 'which is now worn')
    t.equal(scba.active, false, 'with the valve shut')
    t.equal(scba.air, MIFireScba.air.capacitySeconds, 'and a full bottle')

    t.equal(State.hasAir(PLAYER), false,
        'but a shut valve protects from nothing -- this is the distinction that matters')

    Turnout.setScbaActive(PLAYER, true)
    t.equal(State.hasAir(PLAYER), true, 'opening the valve is what protects')

    Turnout.setScbaActive(PLAYER, false)
    t.equal(State.hasAir(PLAYER), false, 'and shutting it stops')

    t.describe('an empty bottle protects from nothing')

    scba.air = 0.0
    scba.active = true
    t.equal(State.hasAir(PLAYER), false,
        'an open valve on an empty bottle is not protection')

    local emptyOk, emptyWhy = Turnout.setScbaActive(PLAYER, true)
    scba.active = false
    emptyOk, emptyWhy = Turnout.setScbaActive(PLAYER, true)
    t.equal(emptyOk, false, 'and the valve will not open on an empty bottle')
    t.ok(emptyWhy and emptyWhy:find('empty') ~= nil, 'saying so')

    -- -----------------------------------------------------------------------

    t.describe('turnout and SCBA are independent')

    reset()
    Turnout.don(PLAYER, 'structural')
    t.equal(State.getGear(PLAYER).tier, 'structural', 'turnout goes on')
    t.equal(State.getScba(PLAYER).worn, false, 'without pulling an SCBA set with it')

    Turnout.donScba(PLAYER, { fromRack = true })
    t.equal(State.getGear(PLAYER).tier, 'structural', 'and SCBA does not disturb the turnout')
    t.equal(State.getScba(PLAYER).worn, true, 'while being worn itself')

    Turnout.doff(PLAYER)
    t.equal(State.getGear(PLAYER).tier, MIFireGear.defaultTier, 'doffing turnout removes it')
    t.equal(State.getScba(PLAYER).worn, true,
        'and leaves the SCBA on -- they sit on different slots and are different decisions')

    reset()
    Turnout.donScba(PLAYER, { fromRack = true })
    t.equal(State.getGear(PLAYER).tier, MIFireGear.defaultTier,
        'SCBA without turnout is legal: you breathe, but you burn')

    -- -----------------------------------------------------------------------

    t.describe('protection follows the clothing')

    reset()
    t.equal(State.getGearTier(PLAYER).fireResist, MIFireGear.tiers.none.fireResist,
        'someone wearing nothing has no resistance')

    -- ADR 0004. The route does not matter: what is on the ped decides the tier, so a
    -- firefighter who got dressed at a station locker is protected exactly as much as one
    -- who took the gear off a truck.
    local worn = {}
    for slot, value in pairs(MIFireGear.tiers.structural.appearance.male) do
        worn[slot] = type(value) == 'table' and value.drawable or value
    end

    t.equal(MIFire.GearMatch.identify(worn, MIFireGear.tiers, 'male'), 'structural',
        'a full set of turnout is recognised whatever put it there')

    Turnout.don(PLAYER, 'structural')
    t.equal(State.getGearTier(PLAYER).fireResist, MIFireGear.tiers.structural.fireResist,
        'and the tier carries its rated protection')

    t.describe('but immunity is still impossible')

    -- The half of ADR 0001 that 0004 did not touch.
    for name, tier in pairs(MIFireGear.tiers) do
        t.ok(tier.fireResist < 1.0,
            ('the %s tier still grants resistance rather than immunity'):format(name))
    end

    -- -----------------------------------------------------------------------

    t.describe('refusals')

    reset()
    local noSet, noSetWhy = Turnout.setScbaActive(PLAYER, true)
    t.equal(noSet, false, 'you cannot open a valve on a set you are not wearing')
    t.ok(noSetWhy ~= nil, 'with a reason')

    local noDoff, noDoffWhy = Turnout.doff(PLAYER)
    t.equal(noDoff, false, 'or doff gear you do not have on')
    t.ok(noDoffWhy ~= nil, 'with a reason')

    Turnout.don(PLAYER, 'structural')
    local again, againWhy = Turnout.don(PLAYER, 'structural')
    t.equal(again, false, 'or don the same tier twice')
    t.ok(againWhy ~= nil, 'with a reason')

    local unknownTier, unknownWhy = Turnout.don(PLAYER, 'not_a_tier')
    t.equal(unknownTier, false, 'an unknown tier is refused')
    t.ok(unknownWhy and unknownWhy:find('unknown') ~= nil, 'by name')

    -- -----------------------------------------------------------------------

    t.describe('air configuration is sane')

    t.ok(MIFireScba.air.capacitySeconds > 0, 'a bottle holds something')
    t.ok(MIFireScba.air.exertion.sprinting > MIFireScba.air.exertion.idle,
        'sprinting burns air faster than standing still')
    t.ok(MIFireScba.air.exertion.running > MIFireScba.air.exertion.walking,
        'and running faster than walking -- work drives consumption, not time')
    t.ok(MIFireScba.air.criticalAt < MIFireScba.air.lowAirAt,
        'the critical threshold is below the low-air one')
    t.ok(MIFireScba.air.lowAirAt < MIFireScba.air.warnAt,
        'which is below the first courtesy warning')

    -- A rated 30-minute bottle should give far less under work. That gap is the point.
    local workingSeconds = MIFireScba.air.capacitySeconds / MIFireScba.air.exertion.running
    t.ok(workingSeconds < MIFireScba.air.capacitySeconds * 0.6,
        'a bottle under work lasts well under its rated duration')

    t.describe('both SCBA appearance states exist and differ')

    t.ok(MIFireScba.appearance.inactive.male, 'there is an inactive set')
    t.ok(MIFireScba.appearance.active.male, 'and an active one')
    t.ok(MIFireScba.appearance.inactive.male['t-shirt']
        ~= MIFireScba.appearance.active.male['t-shirt'],
        'and they are different, or the mask would never visibly go on')

    -- -----------------------------------------------------------------------

    reset()
    MIFire.Framework.getJob = realGetJob
end
