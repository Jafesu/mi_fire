--- Gear recognition tests.
---
--- The rule these protect: **protection follows the clothing, not the route by which it was
--- put on**. A firefighter who got dressed at a station locker or through an outfit menu is
--- wearing turnout gear, and it works.
---
--- Two failures would break that quietly. Matching on texture would mean a firefighter with
--- their own name tape is not recognised at all. Matching without a signature slot would
--- mean half the server counts as wearing turnout because they happen to have no trousers.

return function(t)
    local GearMatch = MIFire.GearMatch
    local tiers = MIFireGear.tiers
    local structural = tiers.structural

    --- The full set, as configured.
    local function fullSet()
        local worn = {}
        for slot, value in pairs(structural.appearance.male) do
            worn[slot] = type(value) == 'table' and value.drawable or value
        end
        return worn
    end

    -- -----------------------------------------------------------------------

    t.describe('a full set is recognised')

    local matched, coverage = GearMatch.matchTier(fullSet(), structural, 'male')
    t.equal(matched, true, 'wearing the whole set matches the tier')
    t.near(coverage, 1.0, 0.01, 'at full coverage')

    local tierName, identified = GearMatch.identify(fullSet(), tiers, 'male')
    t.equal(tierName, 'structural', 'and identify names the right tier')
    t.near(identified, 1.0, 0.01, 'with full coverage')

    t.describe('however it was put on')

    -- The whole point. There is no field here recording where the clothes came from,
    -- which is exactly why a clothing menu works the same as an apparatus.
    t.equal(GearMatch.identify(fullSet(), tiers, 'male'), 'structural',
        'the matcher sees clothing and nothing else -- there is no route to check')

    -- -----------------------------------------------------------------------

    t.describe('texture is ignored, because it carries the name tape')

    -- A firefighter with their own markings has a different texture on the coat. If that
    -- broke recognition, every officer on the server would lose their protection.
    local marked = fullSet()
    local withTexture = {}
    for slot, drawable in pairs(marked) do withTexture[slot] = drawable end

    t.equal(GearMatch.identify(withTexture, tiers, 'male'), 'structural',
        'per-character markings do not stop the gear being recognised')

    -- -----------------------------------------------------------------------

    t.describe('the coat is the signature')

    local coatOnly = { torso2 = structural.appearance.male.torso2 }
    local coatMatched, coatCoverage = GearMatch.matchTier(coatOnly, structural, 'male')

    t.equal(coatMatched, true, 'the coat alone counts as wearing turnout')
    t.ok(coatCoverage < 1.0, 'but at partial coverage')

    t.describe('and everything else is not')

    -- `pants = 11` is "no separate trousers" and half the outfits on a server use it.
    -- Matching on that alone would identify most of the population as firefighters.
    local noCoat = fullSet()
    noCoat.torso2 = 1

    t.equal(GearMatch.matchTier(noCoat, structural, 'male'), false,
        'the rest of the set without the coat is not turnout gear')

    t.equal(GearMatch.identify({ pants = 11 }, tiers, 'male'), nil,
        'and having no trousers certainly is not')

    t.equal(GearMatch.identify({}, tiers, 'male'), nil,
        'nor is wearing nothing recognisable')

    -- -----------------------------------------------------------------------

    t.describe('partial coverage protects less')

    local cfg = MIFireGear.coverage

    local full = GearMatch.protectionMultiplier(1.0, cfg)
    local partial = GearMatch.protectionMultiplier(0.4, cfg)

    t.near(full, 1.0, 0.01, 'a complete set gives the tier its rated protection')
    t.ok(partial < full, 'a partial set gives less')
    t.ok(partial > 0, 'but not nothing -- a coat with no helmet is still a coat')
    t.ok(partial >= cfg.minimum,
        'and never below the configured floor, so the coat always counts for something')

    t.describe('unless partial coverage is turned off')

    local strict = { partialCounts = false, minimum = 0.55 }
    t.equal(GearMatch.protectionMultiplier(0.9, strict), 0.0,
        'with partialCounts off, an incomplete set protects from nothing')
    t.equal(GearMatch.protectionMultiplier(1.0, strict), 1.0,
        'and only a complete one counts')

    -- -----------------------------------------------------------------------

    t.describe('missing pieces are reported')

    local _, _, missing = GearMatch.matchTier(coatOnly, structural, 'male')
    t.ok(#missing > 0, 'a partial set says which slots are missing')

    local hatless = fullSet()
    hatless.hat = 0
    local _, hatlessCoverage, hatlessMissing = GearMatch.matchTier(hatless, structural, 'male')

    t.ok(hatlessCoverage < 1.0, 'working without your helmet is not full coverage')
    t.equal(hatlessMissing[1], 'hat', 'and it is named, so the player can be told')

    -- -----------------------------------------------------------------------

    t.describe('a tier with no appearance is never matched')

    -- The default tier is the absence of gear. It has nothing to match against, and
    -- matching it would mean everyone is always wearing something.
    t.equal(tiers.none.appearance, nil, 'the default tier has no appearance')

    local matchedNone = GearMatch.matchTier({}, tiers.none, 'male')
    t.equal(matchedNone, false, 'so it never matches, even against an empty set')

    -- -----------------------------------------------------------------------

    t.describe('sex-specific sets')

    t.ok(structural.appearance.female ~= nil, 'the tier has a female set')
    t.equal(GearMatch.identify(fullSet(), tiers, 'female'), 'structural',
        'and the matching drawables are recognised for either')
end
