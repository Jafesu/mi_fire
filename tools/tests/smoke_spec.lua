--- Smoke reading tests.
---
--- Every assertion here corresponds to a real fireground reading. They are not snapshots of
--- what the code returns -- they are things that are true about smoke, and the code is
--- wrong if it disagrees.
---
--- The two that matter most are the warnings. A flashover reading that never fires is a
--- crew with no notice; one that fires constantly is a crew that learns to ignore it. Both
--- failures are silent in game and obvious here.

return function(t)
    local Smoke = MIFire.Smoke
    local cfg = MIFireSmoke

    local classA = MIFire.FireClass.resolve('A')
    local classB = MIFire.FireClass.resolve('B')
    local gas = MIFire.FireClass.resolve('gas')

    local function attrs(intensity, ventilation, confined, class, fuel)
        return Smoke.attributes({
            intensity = intensity,
            fuelFraction = fuel or 0.5,
            class = class or classA,
            ventilation = ventilation,
            confined = confined ~= false,
        }, cfg)
    end

    -- -----------------------------------------------------------------------

    t.describe('colour reports the stage of heating')

    t.equal(Smoke.stage(10, 1.0, classA), Smoke.Stage.INCIPIENT,
        'a fire just getting going is incipient -- white smoke, moisture driving off')
    t.equal(Smoke.stage(35, 1.0, classA), Smoke.Stage.GROWTH,
        'a growing fire is past that')
    t.equal(Smoke.stage(60, 0.8, classA), Smoke.Stage.PYROLYSIS,
        'a developing fire is pyrolysing -- brown smoke, into the timber')
    t.equal(Smoke.stage(90, 0.3, classA), Smoke.Stage.DEVELOPED,
        'a fully developed fire produces black smoke, which is unburned fuel')

    t.describe('but a clean-burning fuel never looks dirty')

    -- A gas jet at full intensity should not be producing brown structural smoke. It is
    -- burning a clean fuel and there is no timber involved.
    t.ok(Smoke.stage(90, 0.5, gas) ~= Smoke.Stage.PYROLYSIS,
        'a gas fire does not read as pyrolysing however hot it gets')

    t.describe('and colour darkens with stage')

    local incipient = Smoke.colour(Smoke.Stage.INCIPIENT, 0, cfg)
    local developed = Smoke.colour(Smoke.Stage.DEVELOPED, 0, cfg)

    t.ok(incipient.r > developed.r, 'early smoke is far lighter than late smoke')
    t.ok(developed.r < 60, 'developed smoke is genuinely black, not dark grey')

    local pyrolysis = Smoke.colour(Smoke.Stage.PYROLYSIS, 0, cfg)
    t.ok(pyrolysis.r > pyrolysis.b,
        'pyrolysis smoke is brown -- more red than blue -- which is the tell for structural involvement')

    -- -----------------------------------------------------------------------

    t.describe('smoke lightens as it travels')

    -- The reading that locates the seat of a fire across a whole building.
    local atSeat = Smoke.colour(Smoke.Stage.DEVELOPED, 0, cfg)
    local farAway = Smoke.colour(Smoke.Stage.DEVELOPED, cfg.travelToPale, cfg)

    t.ok(farAway.r > atSeat.r,
        'black smoke at the seat comes out grey at the far end, as it cools and filters')

    t.describe('so black at one opening and white at another is one fire')

    local near = Smoke.travel(attrs(90, 'limited', true, classA, 0.3), 2.0, cfg)
    local far = Smoke.travel(attrs(90, 'limited', true, classA, 0.3), 25.0, cfg)

    t.ok(near.colour.r < far.colour.r, 'the darker opening is the one nearer the seat')
    t.ok(near.density > far.density, 'and it is thicker there')
    t.ok(near.velocity > far.velocity, 'and pushing harder')

    -- -----------------------------------------------------------------------

    t.describe('ventilation drives everything')

    local sealed = attrs(60, 'sealed', true)
    local limited = attrs(60, 'limited', true)
    local open = attrs(60, 'open', true)

    t.ok(sealed.density > open.density,
        'a sealed fire burns incompletely and makes far dirtier smoke')
    t.ok(sealed.velocity < limited.velocity,
        'and a starved fire does not push -- low velocity is the tell, not high')
    t.ok(open.density < limited.density,
        'while an opened fire burns cleaner')

    t.describe('and turbulence means heat-pushed')

    local hot = attrs(95, 'limited', true, classA, 0.2)
    t.equal(hot.turbulent, true,
        'a hot ventilation-limited fire pushes turbulent smoke -- the compartment has '
        .. 'stopped absorbing heat')

    local cool = attrs(20, 'open', true)
    t.equal(cool.turbulent, false, 'an early fire in an open space does not')

    -- -----------------------------------------------------------------------

    t.describe('flashover: the reading that precedes it')

    local blackFire = attrs(95, 'limited', true, classA, 0.2)
    local flashover = Smoke.flashoverRisk(blackFire, 'limited', true, cfg)

    t.ok(flashover >= cfg.warnAbove,
        'heavy, turbulent, thick, black smoke in a limited compartment warns of flashover')

    t.describe('and the readings that should not')

    t.ok(Smoke.flashoverRisk(attrs(95, 'limited', true, classA, 0.2), 'limited', false, cfg) == 0.0,
        'an outdoor fire never flashes over -- there is no compartment to hold the heat')

    t.ok(Smoke.flashoverRisk(attrs(20, 'limited', true), 'limited', true, cfg) < cfg.warnAbove,
        'an early fire does not warn, however confined')

    t.ok(Smoke.flashoverRisk(attrs(95, 'open', true, classA, 0.2), 'open', true, cfg)
        < flashover,
        'and a well-ventilated compartment is far less likely to flash than a limited one')

    -- -----------------------------------------------------------------------

    t.describe('backdraft: the opposite condition, and the more dangerous one')

    local starved = attrs(50, 'sealed', true, classA, 0.3)
    local backdraft = Smoke.backdraftRisk(starved, 'sealed', true, cfg)

    t.ok(backdraft >= cfg.warnAbove,
        'a sealed compartment with dense dark smoke and low velocity warns of backdraft')

    t.ok(Smoke.isPulsing(backdraft, cfg),
        'and the smoke pulses, which is the most recognisable sign there is')

    t.describe('and it looks calmer than a flashover, which is the trap')

    t.ok(starved.velocity < blackFire.velocity,
        'the dangerous one is the quiet one -- a starved fire is not pushing')

    t.equal(Smoke.backdraftRisk(attrs(60, 'open', true), 'open', true, cfg), 0.0,
        'a well-ventilated fire cannot backdraft -- it already has its air')

    t.equal(Smoke.backdraftRisk(starved, 'sealed', false, cfg), 0.0,
        'and neither can an outdoor one')

    -- -----------------------------------------------------------------------

    t.describe('the two warnings do not both fire at once')

    local sealedRead = Smoke.read(starved, 'sealed', true, cfg)
    local limitedRead = Smoke.read(blackFire, 'limited', true, cfg)

    t.equal(sealedRead.warning, Smoke.Warning.BACKDRAFT,
        'a sealed compartment warns of backdraft')
    t.equal(limitedRead.warning, Smoke.Warning.FLASHOVER,
        'a ventilation-limited one warns of flashover')

    t.describe('and a quiet fire warns of nothing')

    local quiet = Smoke.read(attrs(15, 'open', true), 'open', true, cfg)
    t.equal(quiet.warning, Smoke.Warning.NONE,
        'an early open fire produces no warning, so the warnings stay worth listening to')

    -- -----------------------------------------------------------------------

    t.describe('a size-up describes what is seen, separately from what it means')

    t.ok(type(limitedRead.volume) == 'string', 'volume is described in words')
    t.ok(type(limitedRead.velocity) == 'string', 'so is velocity')
    t.ok(type(limitedRead.density) == 'string', 'and density')
    t.ok(type(limitedRead.colour) == 'string', 'and colour')

    t.equal(limitedRead.velocity, cfg.words.turbulent,
        'turbulent smoke is called turbulent rather than given a speed band, because that '
        .. 'is the observation that matters')

    t.equal(Smoke.read(attrs(95, 'limited', true, classA, 0.2), 'limited', true, cfg).colour,
        'black', 'and developed smoke is described as black')

    -- -----------------------------------------------------------------------

    t.describe('a dirty fuel smokes more than a clean one')

    local liquid = attrs(70, 'open', false, classB)
    local jet = attrs(70, 'open', false, gas)

    t.ok(liquid.volume > jet.volume,
        'a flammable liquid fire produces far more smoke than a gas jet')
    t.ok(liquid.density > jet.density, 'and much thicker smoke')

    -- -----------------------------------------------------------------------

    t.describe('ventilation actions are coherent')

    local vertical = cfg.actions.vertical_vent
    local door = cfg.actions.force_door

    t.equal(vertical.triggersBackdraft, false,
        'venting vertically is the safe answer to a suspected backdraft')
    t.equal(door.triggersBackdraft, true,
        'forcing a door at ground level is not')
    t.ok(vertical.seconds > door.seconds,
        'and it takes longer, so the safe option costs something')

    for name, action in pairs(cfg.actions) do
        t.ok(cfg.ventilation[action.setsVentilation] ~= nil,
            ('the "%s" action sets a ventilation state that exists'):format(name))
    end
end
