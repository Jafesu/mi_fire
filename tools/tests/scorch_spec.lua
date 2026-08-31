--- Burn marks.
---
--- The sizing curve is the whole of what is worth testing here: it decides whether a scene
--- carries information or is just decorated. Everything else is transport.

return function(t)
    local Scorch = MIFire.Scorch
    local size = MIFireScorch.size

    t.describe('a mark is sized by what actually happened')

    local scuff = Scorch.size(10, 100, size)
    local floor = Scorch.size(300, 100, size)

    t.ok(floor > scuff,
        'a fire that burned for five minutes leaves more than one knocked down in ten seconds')

    t.ok(scuff >= size.minimum, 'even a brief flare-up leaves something')
    t.ok(floor <= size.maximum, 'and nothing exceeds the configured maximum')

    t.describe('time matters more than peak intensity')

    -- A brief flare-up at full intensity is still brief, and it should not mark a floor the
    -- way a long steady burn does. Without this every scene reads the same.
    local briefHot = Scorch.size(10, 100, size)
    local longCool = Scorch.size(300, 40, size)

    t.ok(longCool > briefHot,
        'a long moderate fire marks more than a short fierce one')

    t.describe('and a fire that never really got going barely marks')

    t.near(Scorch.size(0, 0, size), size.minimum, 0.01,
        'nothing burned, nothing much to see')

    -- -----------------------------------------------------------------------

    t.describe('cleaning up scales with the mess')

    local quick = Scorch.cleanSeconds(size.minimum, MIFireScorch.cleanup, size)
    local slow = Scorch.cleanSeconds(size.maximum, MIFireScorch.cleanup, size)

    t.ok(slow > quick, 'a scorched floor is a job; a scuff is not')
    t.ok(quick > 0, 'and neither is instant')

    -- -----------------------------------------------------------------------

    t.describe('marks age out, and fade as they go')

    local now = 1000000
    local lifetime = MIFireScorch.lifetimeMinutes * 60

    t.equal(Scorch.expired(now, now, MIFireScorch), false, 'a fresh mark has not expired')
    t.equal(Scorch.expired(now - lifetime - 1, now, MIFireScorch), true,
        'one past its lifetime has')

    t.ok(Scorch.fade(now, now, MIFireScorch) < 0.01, 'a fresh mark is not faded')
    t.ok(Scorch.fade(now - lifetime * 0.5, now, MIFireScorch) > 0.4,
        'a half-aged one is visibly lighter')

    t.describe('and a lifetime of zero means they never age out on their own')

    local forever = MIFire.Util.merge(MIFireScorch, { lifetimeMinutes = 0 })

    t.equal(Scorch.expired(now - 999999, now, forever), false,
        'nothing ages out when the server has asked for permanent marks')
    t.equal(Scorch.fade(now - 999999, now, forever), 0.0,
        'and they do not fade either -- a mark that must be cleaned should stay legible')

    -- -----------------------------------------------------------------------

    t.describe('the shipped configuration is coherent')

    t.ok(MIFireScorch.size.minimum < MIFireScorch.size.maximum,
        'the size range is a range')
    t.ok(MIFireScorch.maximumRendered <= MIFireScorch.maximumStored,
        'a client never has to draw more than the server can hold')
    t.ok(#MIFireScorch.decalCandidates > 0,
        'there are candidates for "/fire decals" to lay out, since the decal type is the '
        .. 'one visual constant here that could not be verified against anything on disk')

    -- -----------------------------------------------------------------------

    t.describe('the renderer is one that exists')

    -- `decal` is the better mechanism and does not work on every build: on the one this was
    -- developed against, AddDecal accepts five type IDs, hands back real non-zero handles for
    -- all of them, and draws nothing. So the default is the mechanism that cannot quietly
    -- fail, and this asserts nobody has typo'd it into a third value that silently draws
    -- neither.
    t.ok(MIFireScorch.renderer == 'marker' or MIFireScorch.renderer == 'decal',
        'renderer is "marker" or "decal"')

    t.describe('and the marker is dark enough to read as scorching')

    local marker = MIFireScorch.markerColour

    t.ok(marker.r < 60 and marker.g < 60 and marker.b < 60,
        'a scorch is the absence of colour, not a colour of its own')

    t.ok(marker.alpha > 0 and marker.alpha < 200,
        'and it is not opaque -- a flat unlit disc at full alpha reads as a hole in the '
        .. 'floor rather than as a burn')

    t.ok((MIFireScorch.markerHeight or 0) > 0 and (MIFireScorch.markerHeight or 0) < 0.5,
        'the disc lies flat rather than standing up as a cylinder')
end
