# SCBA and air

Smoke will kill you, and your turnout gear will not help. SCBA is the only thing that
stops it — and only while the valve is open and there is air in the bottle.

## The two states

This is the distinction that catches people out.

| State | What it looks like | Air used | Protection |
|---|---|---|---|
| **On your back** | Set worn, mask off | None | **None** |
| **Breathing** | Mask sealed, valve open | Yes | Smoke cannot touch you |

Wearing a set is not the same as being protected. A firefighter who walks into a smoke-
filled room with the set on their back and the mask hanging is in exactly as much trouble
as one wearing nothing.

## Getting a set

Three ways, and they all end with the same thing on your back:

1. **At the apparatus** — target any fire rig and choose **Take an SCBA set**. The rig
   hands you a full bottle.
2. **At a station rack** — same interaction, at a fixed rack.
3. **From your inventory** — use an SCBA item you are already carrying.

The item *is* the bottle. Its air level travels with it, so a set you carry between rigs
keeps whatever pressure it had. That is also why racking a set refills it: putting it back
is how it gets recharged.

## Using it

Press **J** (or `/scba`) to open and close the valve.

Opening it seals the mask and starts the clock. Closing it stops using air — worth doing
the moment you are out of the smoke, because the bottle is smaller than it sounds.

## How long a bottle lasts

The rating on the cylinder is not the working duration. A thirty-minute bottle gives about
thirty minutes **standing still**. Working, it gives far less:

| What you are doing | Air used |
|---|---|
| Standing | Normal |
| Walking | A third faster |
| Running | Twice as fast |
| Sprinting | Three times as fast |
| Carrying a line or a casualty | Nearly twice as fast |

Heavy smoke makes you breathe harder even through the mask.

So: **a sprint down a hallway costs you three times what walking it does.** Air management
is a skill, and the firefighter who paces themselves comes out with a reserve.

## The warnings

You are told three times, and they get less polite:

- **Half a bottle** — a courtesy. You are fine, but start thinking about the way out.
- **Low air** — begin your exit *now*. Not after this room.
- **Critical** — you should already be moving toward air.

When it runs out, the valve shuts on its own and you are breathing smoke again. Nothing
stops you working; it just starts hurting.

## Refilling

Target an apparatus and choose **Refill air bottle**, or rack the set and take another.
Racking is faster if there is a spare, which is the reason to carry one.

## The PASS device

Built into the harness. It arms itself when you open the air valve, and it is listening for
one thing: whether you have stopped moving.

| Phase | When | What you hear |
|---|---|---|
| **Sensing** | Armed and moving | Nothing |
| **Pre-alarm** | About 25 seconds motionless | Chirping, speeding up |
| **Full alarm** | 12 seconds of chirping ignored | Loud, and it carries |

**The chirp is the one you can escape.** Move, and it stops. That is deliberate — a
firefighter working a nozzle from one spot will set it off eventually, and a wiggle clears
it.

**The full alarm is not.** Once it goes off, moving does *not* silence it. It has to be
reset on the device, and it will not reset on someone who is still down. That is the whole
point: if you are being dragged out unconscious, your PASS should still be screaming when
you reach the door, because the alarm is for the people looking for you.

Going down triggers it on its own. You do not have to press anything, which matters because
the situations it exists for are the ones where you cannot.

### The panic button

Press **K** to go straight to full alarm. No waiting, no chirp. The "I am trapped and I know
it" button.

### Answering one

A full alarm is a **mayday**. Every on-duty firefighter is told and gets a flashing blip,
wherever they are on the map.

Finding them is by ear. The alarm carries about 45 metres and pans across your headphones as
you turn, so sweep your view and walk toward where it gets louder.

To silence it once you have them, target them and choose **Reset PASS alarm**, or use
`/passreset` on your own. It will refuse while they are still unconscious.

## Turnout gear is a separate decision

SCBA and turnout are independent. You can wear either, both, or neither, and each protects
against a different thing:

| | Flame | Radiant heat | Smoke |
|---|---|---|---|
| Turnout gear | Reduced | Reduced | **No help at all** |
| SCBA (breathing) | No help | No help | **Stopped completely** |

Turnout without SCBA means you survive the flame and choke. SCBA without turnout means you
breathe fine while you burn. Both are legal, and both are mistakes.

**No combination makes you fireproof.** Turnout reduces flame damage and degrades while it
does it. Stand in fire long enough and you burn through the gear and catch light, whatever
you are wearing.

### Roughly how long you have

Standing still in a fully developed fire:

| What you are wearing | Gear gives out | You go down |
|---|---|---|
| Station uniform | immediately | ~9 seconds |
| Wildland brush gear | ~13s | ~20 seconds |
| Structural turnout | ~46s | ~64 seconds |
| Proximity gear | ~60s | ~76 seconds |

Those are worst cases — a fire you are standing *in*, at full intensity, without moving.
Working near one rather than in it, or in a fire that is not fully developed, gives you a
great deal longer.

**The middle column is the one to watch.** Once your gear gives out you are still alive, and
now you can catch fire. In turnout that leaves about eighteen seconds of being flammable before
it kills you: enough to get out, and enough not to.

**The middle column is the one to watch.** Once your gear gives out you are still alive, and
now you can catch fire. In turnout that leaves about eighteen seconds of being flammable before
it kills you: enough to get out, and enough not to.

Smoke without a mask takes about a minute to put you down at full density. Slower than
fire, and it does not stop.

### Catching fire

Your gear wears down while you are in flame, and worn gear protects less. Once it is far
enough gone, you can catch light.

If you do: **hold X** to stop, drop and roll. It takes a few seconds and longer in a hazmat
suit, because you cannot roll properly in one.

Faster: a partner with a charged line. They target you and put you out in about a second
and a half. That is the point of having a partner.

### Heat, before it gets that far

You do not need to be in the fire to be in trouble. Radiant heat builds up as you work near
one, and the screen distorts and washes out as it climbs. Past a point your stamina goes and
you stop being able to sprint.

Back off and it fades. That is the system telling you to rotate out, and it is the same
thing a real crew is watching for.
