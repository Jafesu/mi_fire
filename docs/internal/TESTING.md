# In-game test script

**Round two.** Everything that passed cleanly in round one has been removed — the record of
what passed is in [DEVLOG.md](DEVLOG.md) session 019, not here. What is left is the work:
seven fixes that need confirming, and the checks nobody has ever been able to run.

Ordered by what invalidates what. A failure in section 1 makes sections 2 and 3 meaningless,
so work down rather than picking.

Set `Config.debug = true` in `config/config.lua` before starting, and watch F8.

> **If a truck shows no gear or SCBA options, run `/fire gear` stood next to it.** It prints
> ox_target's state, your job, whether the vehicle counts as apparatus, and every option
> evaluated against that truck with the gate that refused it named. Anyone can run it.

---

## 0. Before you start

- [ ] Restart the server after updating. No new migrations this round — still **3** rows.
- [ ] Confirm the HUD appears **bottom right**, clear of the minimap.
- [ ] Keybinds unchanged: **J** SCBA valve, **K** PASS panic, **X** stop-drop-roll.

---

## 1. The HUD

Everything below depends on this, because the HUD is now the only readout for air, gear
condition and heat — the screen effects that used to hint at them are gone.

- [ ] With no gear, no bottle and no fire, the HUD shows **nothing at all**. Rows appear only
      when they have something to say.
- [ ] Take an SCBA set. An **AIR** row appears reading `10:00 · CLOSED`.
- [ ] Press **J**. The `CLOSED` disappears and the clock starts running.
- [ ] Let it pass a third remaining — the row goes **amber** at the same moment the low-air
      alarm sounds, and **red** at 10%.
- [ ] Stand in a fire in turnout. A **GEAR** row appears once the coat is below full and
      falls as you stay in. *This is the one that was broken: wear was tracked server-side
      and never sent to you, so the row could not have appeared and neither could the repair
      options.*
- [ ] Stand *near* a fire. A **HEAT** row climbs and falls back when you retreat.

---

## 2. Screen effects are gone

Your call, and this is now intended behaviour rather than a gap.

- [ ] Stand near a fire until **HEAT** is high. **The screen must not change at all** — no
      wash-out, no distortion, no colour shift.
- [ ] Past 75% you get **one** notification about your gear soaking up more than it can shed.
      Once, not repeatedly, and not again until you have cooled off properly.
- [ ] Stand in smoke with **no SCBA**. You take damage with **no screen change and no
      coughing**.

If any of that still distorts, something is reading `MIFireGear.exposure.visuals` wrong —
every flag in it is `false`.

---

## 3. SCBA from a clothing menu

The fix with the widest blast radius: SCBA was never given the treatment turnout gear got in
ADR 0004, so a visible harness counted for nothing.

- [ ] Put an SCBA set on through the **clothing menu**, not the truck.
- [ ] It is recognised: you are told how much air you have, and the **AIR** row appears.
- [ ] Press **J**. The valve opens and air starts draining.
- [ ] Stand in smoke. Damage stops **completely** while the valve is open.
- [ ] Take the set off through the clothing menu. The AIR row disappears.
- [ ] Put it back on. Air **resumes where it left off** — it must not refill.
- [ ] Now go to a truck and **Refill air bottle**. *That* refills it.

Then confirm the rig route still works:

- [ ] **Take an SCBA set** at a truck, and **Rack SCBA set** to return it.

---

## 4. Air is ten minutes now

- [ ] With the valve open, **sprint** around and watch the AIR row. It should drain visibly
      faster than standing still. *You could not check this before — there was no gauge.*
- [ ] Warnings still land in order: half a bottle, low air, critical.
- [ ] Let it run out. The valve shuts itself, you are told, and smoke starts hurting again.
- [ ] Does ten minutes feel right for a working fire? Say if it is still too long.

---

## 5. Catching fire is survivable now

Two separate natives were applying the engine's own fire damage over the top of this
resource's model: `StartEntityFire` on the burning player, and `StartScriptFire` under every
fire node. Both are gone. **The node one is confirmed fixed** — timings are back to the
model's numbers.

- [x] Full turnout in a fire lasts about a minute rather than seven seconds, and ignition
      takes ~46 seconds rather than two.
- [x] Stand in a fire in turnout until you ignite (~46 seconds).
- [x] Hold **X**. It completes. *Confirmed, but "just barely" — that is now fixed twice
      over: heat is no longer double-charged, and rolling itself cuts the damage to 40%.*

**The roll is a real action now, not a progress bar.**

- [ ] Hold **X**. You should visibly **drop** — a short ragdoll, not a snap to the floor.
- [ ] You should then be **on the ground turning over**, not standing still.
- [ ] You get up when it finishes.
- [ ] It should no longer feel marginal. Rolling without backing out of the flame first now
      leaves roughly 36 seconds against a 3 second roll.
- [ ] **The flames should look right** while you burn. They are a particle on your spine now,
      not the engine effect. If nothing is drawn, check F8 for a `burn particle` warning.
- [ ] Getting clear of the flame first should still be **noticeably** better than rolling
      inside it.
- [ ] Cancel the roll partway. You should stand up, still alight, and be able to start again.
- [ ] Second player: target you while you are alight and **Put them out**. Faster than
      rolling. *Never tested.*

---

## 6. Turnout repair and replacement

Both options were unreachable until now, so none of this has ever run.

**Default mode is `persist`.**

- [ ] Burn a set to roughly half — watch the GEAR row to know when.
- [ ] Third-eye the truck. **Draw a fresh set** appears.
- [ ] Draw one. GEAR goes back to full.
- [ ] Burn a set below 15%. It is **condemned** — repair must be refused, telling you to
      replace it instead.
- [ ] Set `MIFireGear.integrity.persist.repairAtApparatus = true`, restart, and use
      **Service turnout gear**. It should take longer the worse the set is.
- [ ] Repair the same set three times. Each repair restores slightly less than the last, so
      patching forever is not viable.

**Then prove the other two models actually differ.**

- [ ] `MIFireGear.integrity.mode = 'regenerate'`, restart. Burn a set, then step out.
- [ ] Nothing for the first minute. Then it climbs back on its own.
- [ ] Duck out for five seconds and back in — it must **not** have recovered. The delay is
      the whole mechanic.
- [ ] `mode = 'session'`, restart. Damage lasts the shift and resets when gear next goes on.

---

## 7. PASS runs on its own battery

Your observation was right and the behaviour changed to match: a PASS is not powered by
cylinder pressure, so an empty bottle must not switch it off.

- [ ] Open the valve, then **close it**. Stand still. It should **still** alarm — that is
      correct, not a glitch.
- [ ] Take the set off entirely. Now it should not alarm.
- [ ] **Get downed while wearing an armed set.** It must alarm on its own **during last
      stand**, not only after you die. *This is the fix — your bottle had usually emptied by
      the time you went down, which silently disarmed the device.*
- [ ] Let a bottle run empty, then stand still. Still alarms.

**Never tested, needs a second player.**

- [ ] Second player tries to reset your PASS while you are still down — **it must refuse**.
- [ ] Can they hear yours from ~45 m, and does it pan as they turn?
- [ ] Does a full alarm notify every on-duty firefighter with a blip?

---

## 8. Class B smoke reads like Class B

Colour was driven only by how developed the fire was, with no input from the fuel — so a
flammable-liquid fire smoked white while it was still small.

- [ ] `/fire start B` — **black and thick from the first second**, obviously unlike A.
- [ ] `/fire here` alongside it for comparison. A should be visibly paler.
- [ ] `/fire start gas` and `/fire start D` — the palest of the set.
- [ ] `/fire start vehicle` — close to B.
- [ ] `/fire sizeup` on the B fire should describe it as dark and thick in words, matching
      what you are looking at.

**Never tested.**

- [ ] As a grade 0/1 firefighter, `/fire sizeup` gives only the observation. At grade 2+ you
      also get the interpretation.

---

## 9. Teardown, with the new particle

Only worth re-running because burning is now a particle we start rather than an engine
effect, and an orphaned one would survive the restart.

- [ ] `restart mi_fire` **twice** while a fire is burning, **you are alight**, gear is on and
      SCBA is active.
- [ ] Confirm fires still **light the scene at night**. The light is drawn directly now
      rather than coming from the script fire that was removed — if a night fire is a flat
      orange smudge, that is the regression to report.
- [ ] No flames left on your ped, no orphaned particles, no stuck timecycle, no lingering
      sound, no leftover blips, no frozen HUD row.
- [ ] `/fire list` after restart — empty.

---

## What is still unproven after all this

Not a checklist — a list of what nobody has been able to test yet, so it does not get
mistaken for working.

| Area | Why |
|---|---|
| Ambient fire generation | Never observed running on its own clock |
| Dispatch to lb-tablet | Never seen land on a board |
| Districts and AOP | Needs a soak test, not an observation |
| Anything needing two players | Backup slots, RIT, hearing a PASS at range |
| Gear surviving a disconnect | Known gap, `TURN-003` |
