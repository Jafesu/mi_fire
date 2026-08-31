# Working the pump

A description of how the pump model behaves, written for someone who has actually run a panel.
There is no code in it. If something below is wrong, it is wrong in the game, and we would
rather hear it now than ship it.

---

## What we are trying to do

The aim is that a pump operator's real knowledge is the thing that works. Not a skill bar, not
a minigame — the actual arithmetic. If you know that 200 ft of 1¾″ flowing 150 gpm costs about
70 psi of friction, that number should be the number, and doing the sum in your head should
put water on the fire.

The rule we set ourselves early: **the published figures are not tuning values.** Friction loss
coefficients, nozzle pressures, the pump curve — those are taken from the fire service
literature and are not adjusted to make the game feel better. Anything we *do* tune lives
somewhere else and is labelled as a game decision.

So the honest question this document is asking is: **are the numbers right, and is the shape of
the job right?**

---

## The chain

Every line is solved the same way:

> **Pump discharge pressure = nozzle pressure + friction loss + elevation + appliances**

The operator works the throttle, which is one number for the whole pump, and pulls the gate on
each discharge. Everything between the panel and the tip then takes its share, and what is left
is what does the work.

Crucially, **the nozzle operator does not choose a flow.** They open the bail. What comes out
is whatever survives the trip. A crew that wants more water has to ask for more pressure, and
an operator who does not give it has a crew standing in a fire with a soft line.

### Friction loss

`FL = C × (Q/100)² × (L/100)`

| Hose | Coefficient |
|---|---|
| ¾″ booster | 1100 |
| 1″ booster | 150 |
| 1½″ | 24 |
| **1¾″** | **15.5** |
| 2″ | 8 |
| **2½″** | **2** |
| 3″ (2½″ couplings) | 0.8 |
| 4″ | 0.2 |
| 5″ | 0.08 |

The square is doing the work. Doubling the flow quadruples the loss, which is why a crew that
opens up on a long stretch suddenly has nothing.

### Nozzle pressures

| Nozzle | Pressure |
|---|---|
| Smooth bore handline | 50 psi |
| Smooth bore master stream | 80 psi |
| Fog | 100 psi |
| Low-pressure fog | 75 psi |

Smooth bore flow is `Q = 29.7 × d² × √NP` — so a 15/16″ tip at 50 psi is about 185 gpm and
nobody has to set anything. Fog nozzles are rated for a flow at a pressure and fall off either
side of it.

### Elevation

**0.434 psi per foot** — the weight of a foot of water.

We deliberately did *not* use the ½ psi per foot rule of thumb. The approximation exists for an
operator working it out under pressure; the model a player is being taught against should be
the real figure. **Tell us if that is the wrong call** — there is an argument that a game
should teach the shortcut people actually use.

### Appliances

Nothing below 350 gpm, 10 psi at or above it, 25 psi for a master stream device.

---

## The pump curve

NFPA 1901, and it is a real limit rather than a soft one:

| Net pressure | Capacity |
|---|---|
| 150 psi | 100% of rating |
| 200 psi | 70% |
| 250 psi | 50% |

So a 1500 gpm pump asked for 1500 gpm at 200 psi is being asked for something it cannot do.
When demand exceeds what the pump can make, **every line loses flow proportionally** — opening
a second discharge takes water off the first.

That last behaviour is the one we most want checked. It is the single most important thing for
a nozzle crew to feel, and it is the reason a governor exists at all.

---

## What the operator actually does

1. Stop the rig, put the pump in gear.
2. A crew pulls a line and couples it, or takes a preconnect that is already coupled.
3. They stretch it **dry** — charged hose is about three times the weight — and get into
   position.
4. They call for water.
5. The operator charges the line, **opens its gate**, and works the throttle.
6. Water arrives at the tip at whatever is left after the trip.

A charged line with a shut gate flows nothing, and a pump in gear at idle makes about 40 psi —
so forgetting the throttle gives a soft line rather than a dead one. Both are deliberate and
both are steps people forget.

There is **one throttle for the whole pump**, because there is one pump. Raising it raises the
pressure on every open outlet, which is exactly why opening a second line takes water off the
first, and why a governor is a thing that exists.

---

## What a crew feels

A line is described in words rather than shown a small number, because "42 psi" means nothing
mid-attack and "soft" means everything:

| Nozzle pressure | We call it |
|---|---|
| Nothing | no water |
| Under ⅓ rated | **soft** — no reach, no penetration, and it puts no water on the fire |
| ⅓ to ¾ rated | low |
| Around rated | good |
| Over 1⅓ rated | over-pressured |

A soft line is treated as genuinely not working, not as working badly. A crew that thinks it
has water and does not is the failure worth naming.

---

## The tank is a clock

An engine carries 1000 gallons. At 150 gpm that is under seven minutes; at 250 it is four. When it
runs dry the line goes soft — there is no alarm, the water simply stops, which is what happens.

That clock is the entire reason anyone lays a supply line rather than parking and fighting the
fire off the tank.

---

## Crew, which is a game decision rather than hydraulics

Pressure and pump capacity decide what a line *can* flow. The people on it decide how much of
that they can hold open.

| Line | Crew |
|---|---|
| Booster reel | 1 |
| 1¾″ | 2 |
| 2½″ | 3 |

Short-handed is never refused — one firefighter can open a 2½″ and find out — but the flow is
capped, the nozzle wanders, and the line can get away from them. The intent is that **a full
crew on a small line beats a short crew on a big one**: two on a 1¾″ flow more than the same
two on a 2½″.

These numbers are ours, not published. **Are they roughly right?**

---

## What we deliberately do not model yet

- **Supply lines, hydrants, relay pumping, drafting.** Everything runs off the tank. The
  percent-drop rule and residual pressure are written and tested but nothing feeds them yet.
- **The governor.** There is no PSI mode holding a setpoint across changes on other discharges.
  The operator sets each outlet by hand.
- **Foam proportioning.** The cells and the agent matrix exist; the eductor does not.
- **Master streams and the deck gun.**
- **Intake pressure**, beyond enough to detect cavitation off the tank.
- **Changing gear, transfer valve, pressure/volume mode.**
- **The transfer valve**, and pressure against volume mode.
- **Engine RPM and temperature**, which are on the panel and behind nothing.

Gates *are* modelled — each discharge is a handle from shut to wide open, and a part-open gate
throttles what passes it. What is ours rather than published is how much: we treat the loss as
growing with the square of how far shut it is, which is the right shape and an invented
coefficient.

---

## The questions we would most like answered

1. **Are the friction loss coefficients the ones you use?** Particularly 1¾″ at 15.5 — we have
   seen 15.5 and 12 and 10 depending on whose manual it is.

2. **Is 0.434 psi/foot right for this, or should we use the ½ psi rule of thumb people actually
   work in?** One is accurate, the other is what a real operator does in their head.

3. ~~**How do you actually set a discharge?**~~ **Answered: you do not type a pressure.** The
   operator works the throttle and pulls the gate handles, and the gauges read what that
   produces. Rebuilt to match — there is one throttle for the whole pump, because there is one
   pump, and each discharge is a handle from shut to wide open. Raising the throttle raises it
   for everybody, which is what makes a second line take water off the first.

   **Still open, and smaller:** we model a part-open gate as a pressure loss growing with the
   square of how far shut it is. The shape is right; the coefficient is ours. How much does a
   half-open gate actually knock off?

4. **What would you pump a 200 ft 1¾″ crosslay with a 15/16″ tip at?** If our model does not
   give roughly your number, our model is wrong.

5. **Is "every line loses proportionally when the pump is over capacity" what actually
   happens?** Or does the nearest/largest discharge win?

6. **Is under ⅓ of rated nozzle pressure the right place to call a line soft?**

7. ~~**Are 750 gallons right?**~~ **Answered: 1000.** Set. The 1500 gpm pump rating is still
   ours rather than measured.

8. ~~**Which gauges do you actually watch?**~~ **Answered: all of them, and they must be
   live.** Every gauge that has a use gets rendered and driven by real state — no decorative
   faces. That decision shapes the whole panel, so the question worth asking instead is:
   **which gauges on these rigs have a use we have not modelled yet?** We currently have
   nothing behind an intake gauge beyond enough to detect cavitation, and nothing at all behind
   a foam or a governor readout.

9. **How does cavitation present to you, and what do you do about it?** We warn the crew on the
   line as well as the operator, on the grounds that they are the ones about to lose water.

10. **Of the things we do not model, which would you miss first?** If the answer is the
    governor, we would like to know before we build the panel around not having one.

---

## In short

We are not trying to simulate a pump. We are trying to make the *arithmetic* real — so that
knowing the job is what makes you good at it, a long stretch genuinely costs you, and a second
line genuinely takes water off the first.

If the numbers are wrong, the lesson is wrong, and we would rather fix that than ship it.
