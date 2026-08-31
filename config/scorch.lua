--- What a fire leaves behind.
---
--- A fire that vanishes the moment it goes out never happened. Scorch marks are what make an
--- incident something that occurred to a *place*: a crew arriving late can read where the
--- seat was, an investigator has somewhere to stand, and a building carries its history until
--- someone does something about it.
---
--- Marks are server-owned like everything else here. Clients draw them; the server decides
--- which exist, so two firefighters standing in the same doorway see the same burn pattern.
---
--- **A caution about decal IDs.** Every other visual asset in this resource is pinned to a
--- name verified in something already running -- the particle pairs came out of a working
--- fire resource, the roll animation out of qbx_medical. There is no `AddDecal` call anywhere
--- on this machine to check against, so the type IDs below are the one set of visual
--- constants that has **not** been verified that way.
---
--- `AddDecal` returns 0 for a type that does not exist and prints nothing, which is the same
--- silent failure that made an invented particle name look like broken rendering for a whole
--- session. So two things guard it: the client warns loudly when a decal comes back 0, and
--- **`/fire decals` lays out every candidate in a numbered row in front of you** so the right
--- one gets chosen by looking at it rather than by trusting this comment.

MIFireScorch = {}

--- Master switch.
MIFireScorch.enabled = true

--- How a mark is drawn.
---
---   `marker`  A flat dark disc laid on the ground, drawn per frame. Works everywhere,
---             because it uses the same mechanism every checkpoint and objective marker in
---             the game uses. Costs a draw call per visible mark.
---
---   `decal`   A real projected decal. Cheaper, conforms to whatever it lands on, and is
---             what you actually want -- **if your build renders them**.
---
--- Default is `marker`, on evidence rather than preference. On the build this was developed
--- against, `AddDecal` accepts five type IDs (1010, 1015, 1017, 1020, 1030), returns real
--- non-zero handles for all of them, and draws nothing at all -- tested at four metres
--- across in flat white at full opacity with a marker overhead, indoors and out. Something
--- upstream of this resource is eating them.
---
--- The decal path is kept because it is the better mechanism where it works, and
--- `/fire decals sweep` will tell you within a minute whether yours is such a build.
MIFireScorch.renderer = 'marker'

--- Decal type used for a burn mark, when `renderer` is `decal`.
---
--- Confirm with `/fire decals` before trusting it. If burn marks do not appear, this is the
--- first thing to change and the command exists to tell you what to change it to.
MIFireScorch.decal = 1010

--- Candidates offered by `/fire decals`, laid out left to right so you can pick by eye.
--- Widened or trimmed freely; the command reads this list.
--- The five this build reported as accepted when swept. Anything not in this list was
--- refused outright by the native, so there is no point offering it.
MIFireScorch.decalCandidates = { 1010, 1015, 1017, 1020, 1030 }

--- Colour scale. 1.0 treats the colour values below as the 0-1 coefficients their parameter
--- names claim; 255.0 treats them as bytes, which a good deal of working code in the wild
--- assumes. "/fire decals" reports which convention this build accepted -- set this to match
--- rather than guessing, because the wrong one draws something invisible rather than nothing,
--- which is harder to tell apart from a bad type ID than it sounds.
MIFireScorch.colourScale = 1.0

--- How large a mark a node leaves.
---
--- Scaled by how hard and how long the node burned, so a knockdown in the first thirty
--- seconds leaves a scuff and a fire that ate its fuel leaves a floor.
MIFireScorch.size = {
    minimum = 1.2,
    maximum = 5.5,
    --- Seconds of burning at which a node reaches `maximum`.
    fullSizeAfterSeconds = 120.0,
}

--- Colour multipliers, 0-1, for the `decal` renderer. Left dark and desaturated: a scorch is
--- absence of colour rather than a colour of its own, and tinting it warm reads as paint.
MIFireScorch.colour = { r = 0.16, g = 0.15, b = 0.14, alpha = 0.85 }

--- The `marker` renderer, 0-255.
---
--- Near-black at moderate alpha. A marker is a flat unlit disc, so anything above about 140
--- alpha stops reading as scorching and starts reading as a hole in the floor -- which is the
--- main risk with this mechanism and the first thing to turn down if it looks wrong.
MIFireScorch.markerColour = { r = 20, g = 18, b = 16, alpha = 115 }

--- Height of the disc, and how far above the ground it sits. Low enough to lie flat, high
--- enough not to z-fight with the surface it is on.
MIFireScorch.markerHeight = 0.04
MIFireScorch.markerLift = 0.03

--- How long a mark lasts if nobody cleans it.
---
--- Deliberately long. The point of the feature is that a fireground stays marked, and a
--- twenty-minute decal is a decoration rather than a record. Set `0` for marks that only ever
--- disappear when someone removes them.
MIFireScorch.lifetimeMinutes = 180.0

--- Cleaning them up, before the timeout.
---
--- Both models run together, on purpose: marks age out on their own so an unattended server
--- does not silently accumulate thousands of them, and a crew can clear a scene properly
--- rather than leaving it looking burnt for three hours.
MIFireScorch.cleanup = {
    enabled = true,

    --- Seconds of work per mark. Scaled by the size of the mark, so a scuff is quick and a
    --- fully developed floor is a job.
    seconds = 12.0,

    --- Interaction radius on the mark.
    radius = 2.5,

    --- Restricted to the fire department. Washing down a scene is the job, and leaving it
    --- open to anyone means marks get tidied away by passers-by before a crew arrives.
    requiresFirefighter = true,

    label = 'Wash down the scene',

    --- An item consumed per clean, or nil for none. `nil` by default because requiring a
    --- consumable to tidy scenery is the kind of friction that stops it being done at all.
    item = nil,
}

--- Beyond this from the camera, a client does not draw a mark. Decals are cheap but not
--- free, and a busy fireground can leave a lot of them.
MIFireScorch.drawDistance = 90.0

--- Most marks a single client will draw at once, nearest first. A hard ceiling, because a
--- long session on a busy server should degrade into "the closest marks are drawn" rather
--- than into a frame rate problem.
MIFireScorch.maximumRendered = 60

--- Most marks the server will hold. The oldest is dropped when this is exceeded, so a server
--- nobody ever cleans up on stays bounded.
MIFireScorch.maximumStored = 400
