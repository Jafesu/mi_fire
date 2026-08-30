--- Recognising gear from what someone is wearing.
---
--- Protection follows the **clothing**, not the route by which it was put on. A firefighter
--- who got dressed at a station locker, through an outfit menu, or from a job clock-in is
--- wearing turnout gear, and it protects them exactly as much as if they had taken it off
--- the truck. Anything else is a system telling a player that the coat on their back is not
--- really a coat.
---
--- Two rules make that safe and correct:
---
---   **Match on drawable, never texture.** Texture carries the name tape and rank, which
---   are per-character (`mi_fire_gear_appearance`). Matching on it would mean a firefighter
---   with their own markings is not recognised as wearing the gear at all.
---
---   **A signature slot must match.** Some pieces are weak evidence -- `pants = 11` is
---   "no separate trousers" and half the outfits on a server use it. The coat is the
---   garment that says turnout gear; the rest add to coverage once the coat is there.
---
--- Pure. No natives, so what counts as wearing gear can be checked without getting dressed.

MIFire = MIFire or {}

local GearMatch = {}

--- Does a worn set match a tier?
---
---@param worn table `{ slot = drawable }` as reported by the client.
---@param tier table A tier from `MIFireGear.tiers`.
---@param sex string|nil 'male' or 'female'; defaults to male.
---@return boolean matched Signature slots all present.
---@return number coverage 0-1, how much of the full set is on.
---@return string[] missing Slots that did not match, for diagnostics.
function GearMatch.matchTier(worn, tier, sex)
    if type(worn) ~= 'table' or type(tier) ~= 'table' then return false, 0.0, {} end

    local appearance = tier.appearance
    if type(appearance) ~= 'table' then return false, 0.0, {} end

    local set = appearance[sex or 'male'] or appearance.male
    if type(set) ~= 'table' then return false, 0.0, {} end

    local signature = tier.signature or {}
    local total, matched, missing = 0, 0, {}

    for slot, expected in pairs(set) do
        local wanted = type(expected) == 'table' and expected.drawable or expected
        wanted = tonumber(wanted)

        -- A drawable of -1 means "leave this slot alone", so it is not evidence either way.
        if wanted and wanted >= 0 then
            total = total + 1

            if tonumber(worn[slot]) == wanted then
                matched = matched + 1
            else
                missing[#missing + 1] = slot
            end
        end
    end

    if total == 0 then return false, 0.0, missing end

    -- Every signature slot has to match, or this is not the gear however much else lines up.
    for i = 1, #signature do
        local slot = signature[i]
        local expected = set[slot]
        local wanted = type(expected) == 'table' and expected.drawable or expected

        if tonumber(worn[slot]) ~= tonumber(wanted) then
            return false, 0.0, missing
        end
    end

    return true, matched / total, missing
end

--- Which tier is this person wearing?
---
--- Best match wins, ranked by coverage then by protection -- so someone in a full set of
--- turnout is not identified as the hazmat tier because two slots happened to coincide.
---
---@param worn table `{ slot = drawable }`
---@param tiers table `MIFireGear.tiers`
---@param sex string|nil
---@return string|nil tierName Nil when nothing matches.
---@return number coverage 0-1
---@return string[] missing
function GearMatch.identify(worn, tiers, sex)
    local bestName, bestCoverage, bestMissing, bestScore = nil, 0.0, {}, -1

    for name, tier in pairs(tiers or {}) do
        -- The default tier is the absence of gear; it has nothing to match against.
        if tier.appearance then
            local matched, coverage, missing = GearMatch.matchTier(worn, tier, sex)

            if matched then
                -- Coverage first, then how protective the tier is. A full set beats a
                -- partial one, and between two equal matches the real gear wins.
                local score = coverage * 100 + (tonumber(tier.fireResist) or 0)

                if score > bestScore then
                    bestName, bestCoverage, bestMissing, bestScore = name, coverage, missing, score
                end
            end
        end
    end

    return bestName, bestCoverage, bestMissing
end

--- How much of a tier's rated protection partial coverage actually gives.
---
--- Wearing the coat without the helmet is not the same as wearing the set, and it should
--- not protect like it. Scales between `coverage.minimum` at signature-only and full at a
--- complete set -- so the missing hood is a real decision rather than a cosmetic one.
---
---@param coverage number 0-1
---@param config table `MIFireGear.coverage`
---@return number multiplier
function GearMatch.protectionMultiplier(coverage, config)
    if not config or config.partialCounts == false then
        return coverage >= 1.0 and 1.0 or 0.0
    end

    local floor = tonumber(config.minimum) or 0.5
    coverage = math.max(0.0, math.min(1.0, tonumber(coverage) or 0.0))

    return floor + (1.0 - floor) * coverage
end

MIFire.GearMatch = GearMatch

return GearMatch
