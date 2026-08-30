# Reading smoke

*A description of what this system models, written for someone who already knows how fire
behaves. If something below is wrong, it is wrong in the game too — please say so.*

---

## What we are trying to do

Most firefighting in games treats smoke as decoration: a grey particle that means "fire is
here". We are trying to make it the thing it actually is — **the primary source of
information about a fire you cannot see yet**.

The goal is that a crew arriving on scene can look at what is showing and know something
useful before they get off the truck. Not everything. But enough that reading it well is
rewarded and reading it badly costs you.

We have built it around the four attributes, because that is the framework the job actually
uses, and because each one maps onto something we can genuinely render.

---

## The four attributes

### Volume

How much is showing. We drive this off how much fuel is off-gassing — a function of how
developed the fire is and what is burning.

We treat volume as **the least informative attribute on its own**, which we believe is
correct. A large building holds a great deal of smoke without much fire in it. Volume only
means something alongside the other three.

### Velocity

How hard it is leaving, which is really a statement about **pressure inside**.

This is the one we have weighted most heavily, and we would like to know if that is right.
Our model says:

- **Laminar** — smooth, lazy, drifting. The smoke is being pushed by *volume*. The
  compartment is still absorbing heat.
- **Turbulent** — boiling, agitated, angry. The smoke is being pushed by *heat*. The
  compartment has stopped absorbing and is giving it back.

We render these as two genuinely different effects rather than the same one moving faster,
because they do not look alike and the difference is the point.

Turbulent smoke is the single condition that makes our flashover warning fire.

### Density

How thick it is — which is really *how much unburned fuel is suspended in it*.

We treat thick smoke as fuel that has not burned yet and will burn violently the moment it
finds air. Density rises when combustion is incomplete, so a fire with restricted air
produces much dirtier smoke than the same fire with a window open.

### Colour

Colour is doing two jobs at once in our model, and this is the part we are least certain
about.

**First, it reports the stage of heating:**

| What is showing | What we take it to mean |
|---|---|
| White / light grey | Early. Moisture being driven off. |
| Pale yellow | Fuel heating, still early stage. |
| **Brown / tan** | **Unfinished wood off-gassing — the fire is into the structure, not just the contents.** |
| Black | Late stage. Carbon rich, hot, and full of unburned fuel. |

**Second, it reports how far the smoke has travelled.** Smoke lightens as it cools and
filters through a building, losing carbon onto every surface it touches. So in our model the
same fire produces different colours at different openings, and the darker one is nearer the
seat.

That last behaviour is deliberate and it is the thing we most want checked. We think it
means a crew can look at a building showing **black at a ground-floor window and white at
the eaves** and correctly conclude that is one fire, low, not two fires. Is that a
reasonable read?

---

## Ventilation

We model a compartment as being in one of three states, because ventilation changes every
one of the four attributes and we did not want it to be a detail.

### Sealed

Nothing open. The fire consumes the available oxygen and drops back toward smouldering.

- Little visible flame
- Heavy, very dense smoke
- **Low velocity** — a starved fire is not pushing
- Pressure cycling: smoke moving *both ways* through gaps

This is our backdraft condition. We have deliberately made it look calmer than the
flashover condition, because we understand that to be the actual danger — it does not look
like the emergency it is.

### Ventilation-limited

An opening, but not enough. The fire is hot and pressured.

- High velocity, turbulent
- Thick and darkening
- Growing

This is our flashover condition, and it is what we treat as the **default state a structure
fire is found in** — on the grounds that the building was shut when it started. We would
like to know if that default is sensible.

### Open

Adequately ventilated. The fire burns more freely and grows, but the smoke lifts and thins,
and a crew can work under it.

We have modelled this as **more fire but less surprise** — usually the right trade. Is that
how you would put it?

---

## The two events

### Flashover

Our model builds toward it. When volume, velocity, density and colour all agree — heavy,
turbulent, thick, black, in a limited compartment — a clock starts. There is roughly
**25 seconds of warning** before it happens.

That window is deliberate. If reading smoke does not buy time to act, there is no reason to
read it.

We have also made the clock **wind back** if conditions improve, so a crew that cools the
space or vents it properly sees the benefit rather than being on rails.

The reading we treat as the warning is what we understand to be called **black fire** —
high-volume, turbulent, ultra-dense, black smoke that is not yet burning but is about to.

### Backdraft

Our model handles this completely differently, and we think that difference is the important
part.

**Backdraft does not build to a timer.** It waits. A sealed compartment can sit in that
condition indefinitely, and nothing happens — until someone opens it.

Then it is triggered. Specifically:

- **Forcing a door at ground level** sets it off
- **Taking a window** sets it off
- **Cutting the roof** does not

Because venting above the fire lets heat and smoke go straight up rather than drawing fresh
air across the seat.

So the safe play is to vent vertically *first*. We made that take three times as long as
forcing a door, so the correct answer costs something.

---

## What a size-up gives you

A firefighter can size up a fire from a distance and gets told **what is showing**, in the
same terms as above:

> Heavy volume, boiling and turbulent.
> Thick and black.
> Ventilation reads ventilation-limited.

Officers additionally get **what it means**:

> That is heat-pushed. The compartment has stopped absorbing and is giving it back.
> Expect flashover — get a line in place or get out.

We split it that way on purpose. Handing everyone the conclusion would mean nobody ever
learns to read the smoke; handing nobody the conclusion means most players never realise
there is anything to read.

---

## What we deliberately do not model

Being honest about the gaps, because they may matter more than we think.

**No neutral plane.** We do not model the height at which the hot smoke layer meets clear
air, and we do not render smoke banking down or lifting. We understand this is a significant
read — arguably one of the most important for interior crews — and we cannot currently do it
because we do not have the building interiors in a form we can query.

**No smoke pathing.** Smoke does not travel through the building along real paths. It is
produced at the fire and shown rising and drifting. So we cannot represent smoke pushing
from a seam three rooms away from the seat.

**No volumetric fill.** A room does not genuinely fill up. Smoke is rendered as plumes, not
as a volume you move through and lose sight in.

**No condensation or staining.** We do not model smoke staining windows, which we understand
is a backdraft sign in its own right.

**No differentiation by building contents.** A furniture warehouse and an office produce the
same smoke for the same fire class. Fuel type varies by class of fire, not by what is in the
building.

---

## The questions we would most like answered

1. **Is velocity the right thing to weight most heavily?** We have made turbulent-versus-
   laminar the single most consequential read in the system.

2. **Is our colour-plus-travel behaviour right?** Specifically: is "black low, white high,
   therefore one fire near the bottom" a read you would actually make?

3. **Is 25 seconds of flashover warning reasonable?** Too generous, too tight, or is a fixed
   window the wrong shape entirely?

4. **Is "backdraft looks calmer than flashover" the correct instinct to build in?** We have
   made the dangerous one the quiet one.

5. **Is starting structure fires ventilation-limited by default correct?**

6. **Of the things we do not model, which one would you miss most?** If the neutral plane is
   the answer, we would like to know now.

---

## In short

We are not trying to simulate combustion. We are trying to make the *information* real — so
that the smoke coming out of a building tells a crew something true, that reading it well
is rewarded, and that ignoring it occasionally kills you.

If any of the above is wrong, it is wrong in the game, and we would rather fix it than ship
it.
