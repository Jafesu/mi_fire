# In-game test script

Everything built so far, in dependency order — a failure early would invalidate what comes
after, so work down rather than picking.

**Nothing below has been tested in game except section 1.** Sections 2 onward are all
unproven.

Set `Config.debug = true` in `config/config.lua` before starting, and watch F8.

---

## 0. Before you start

- [ X ] Restart the server. Migration `0003_gear_appearance` must apply.
- [ X ] `SELECT * FROM mi_fire_migrations;` — expect **3** rows.
- [ X ] Repoint your SCBA item: `server = { export = 'mi_fire.useScba' }`
- [ X ] Check keybind conflicts: **J** SCBA valve, **K** PASS panic, **X** stop-drop-roll.
- [ X ] `/fire perms` — confirms you have access and shows which route granted it.

---

## 1. Fire engine — *already passed, re-run as a regression*

- [ X ] `/fire here` — a fire starts and renders.
- [ X ] `/fire agent water` — knocks down, then extinguishes.
- [ X ] `/fire start B` then `/fire agent water` — **it gets worse and spreads**.
- [ X ] `/fire agent foam` — that one works.
- [ X ] `/fire start wildland 5 3` then `/fire wind 90 0.9` — should now spread visibly
      faster than in still air. *This changed since your last test.*
- [ X ] `/fire list`, `/fire stopall`.

---

## 2. Turnout gear

The first thing built on top of the engine, and nothing after this works without it.

> **If no option appears on the truck, run `/fire gear` while stood next to it.**
>
> Every one of these interactions is five booleans deep — ox_target running, the client
> booted, the vehicle counting as apparatus, the job gate, and the option's own condition —
> and any single false gives the identical symptom of nothing at all. `/fire gear` prints
> all five, evaluates each option against the truck you are stood at, and names the gate
> that refused. It is reachable by anyone, because the person who cannot see the option is
> exactly the person who needs to know why.
>
> The usual answer is the **job gate**: taking equipment off an apparatus is department
> business, so `Don turnout gear`, `Take an SCBA set`, and `Draw a fresh set` need a job in
> `Config.fireJobs` and, by default, being clocked **on duty**. Protection itself is not
> job-gated — only drawing kit off the rig is.

- [ X ] Stand at a fire truck. Third-eye it — **Don turnout gear** appears.
- [ X ] Don it. Your appearance changes: helmet, coat, boots, gloves.
- [ X ] **The helmet specifically.** It is a prop rather than a component, and the two go
      through different natives — if the coat appears and the helmet does not, that is the
      bug to report.
- [ X ] `/fire render` still works — confirms nothing else broke.
- [ X ] **Doff turnout gear** — your original clothes come back, not a default skin.
- [ X ] Don, disconnect, reconnect. *Known gap: gear state does not survive this yet
      (`TURN-003`). Confirming it is broken is still useful.*

**Then the thing that matters most — note this check has been inverted:**

- [ X ] Put on turnout gear through a **clothing menu** instead of the truck.
- [ X ] Walk into a fire. You should be **fully protected**, exactly as if you had donned it
      at the apparatus.
- [ X ] Do it as a **civilian**, with no fire job. Still protected — the coat is a coat.
- [ X ] Wear only the **coat**, no helmet or gloves. You should be protected, but noticeably
      less than in the full set.

That is ADR 0004. Protection follows the clothing, however it got there.

- [ X ] Take the coat off mid-fire. Protection should drop within a couple of seconds.
- [ X ] Burn a set down, take it off, put it back on. Integrity should **resume where it
      left off**, not reset. Changing clothes does not repair a coat.

**Gear condition and repair.** Default mode is `persist`.

> **Fixed since your last run.** The options genuinely could not appear: the exposure module
> degraded integrity server-side but never pushed the new value to the client, so the client
> still believed the coat was full and both options stayed hidden however hard it was worked.
> There is now a **GEAR** row on the HUD showing condition in words, so you can see it fall.

- [ ] Watch the **GEAR** row appear on the HUD once the coat is below full, and fall as you
      stay in the fire.
- [ ] Burn a set to roughly half. Third-eye the truck — **Draw a fresh set** appears.
- [ ] Draw one. Protection back to full.
- [ ] Burn a set below 15% — it is **condemned**. Repair should be refused, telling you to
      replace it.
- [ ] Set `MIFireGear.integrity.persist.repairAtApparatus = true`, restart, and try
      **Service turnout gear**. It should take longer the worse the set is.
- [ ] Repair the same set three times. Each repair should restore slightly less than the
      last, so patching forever is not viable.

**Then switch models and confirm they behave differently.**

- [ ] Set `MIFireGear.integrity.mode = 'regenerate'`, restart.
- [ ] Burn a set, then step out of the fire. Nothing for the first minute.
- [ ] Keep waiting — integrity should climb back on its own.
- [ ] Duck out for five seconds and back in. It should **not** have recovered. The delay is
      the whole mechanic.

---

## 3. SCBA

- [ X ] At a truck, third-eye — **Take an SCBA set**. You get one, full.
- [ ] **Put an SCBA set on through a clothing menu instead.** It should be recognised, the
      HUD should show air, and the valve keybind should work. *This was broken — SCBA was
      never given the ADR 0004 treatment the coat got, so a visible bottle counted for
      nothing.*
- [ ] Take that set off and put it back on. Air should **resume where it left off**, not
      refill. Only a rack refills.
- [ X ] Your appearance changes (harness on your back, mask off).
- [ X ] Press **J**. Appearance changes again — mask on.
- [ X ] **Use the SCBA item from inventory** instead. Should do the same thing.
      *If nothing happens, the item export is not repointed.*
- [ ] With the valve open, sprint around. Watch the **AIR** row on the HUD — it should drain
      noticeably faster than standing still.
- [ X ] Wait for the warnings: half a bottle, then low air, then critical.
- [ ] Let it run out entirely — the valve shuts itself and you are told. *A full bottle is
      now **10 minutes**, not 30.*
- [ X ] Third-eye the truck — **Refill air bottle**.
- [ X ] **Rack SCBA set** — it comes off and is refilled.

---

## 4. Exposure — the part that makes all of the above matter

**Wear nothing.**

- [ X ] `/fire here`, walk into it. You should go down in about **9 seconds**.
- [ x ] Confirm your medical resource sees it properly — last stand or death, *not* a silent
      slide to zero. If you just drop dead with no last stand, the damage is not raising
      events correctly.

**In turnout gear.**

- [ X ] Same fire. You should last about **64 seconds**.
- [ X ] At roughly **46 seconds** your gear gives out and you can catch fire.
- [ X ] Stay in it until you ignite.
> **Fixed.** `StartEntityFire` was setting you alight with GTA's own ped fire, which applies
> its own fast damage on top of ours and ignored the whole gear model — about two seconds of
> life against a four second roll. Flames are now a particle this resource owns, and the
> damage stays in our model, which had always been giving you around eighteen seconds.

- [ ] Hold **X** to stop, drop and roll. It should take about **3 seconds** and you should
      live, provided you start immediately.
- [ ] Try it **while still stood in the fire**. Markedly worse — getting clear first should
      roughly double the window.
- [ ] Get a second player to target you and **Put them out** — should be much faster.

**Heat, without touching the fire.**

> **Removed on your call.** No screen distortion for heat or smoke, and no cough. The
> machinery survives behind `MIFireGear.exposure.visuals`, all flags `false`, for anyone who
> wants it back. What replaced it is the HUD plus one notification.

- [ ] Stand *near* a fire without entering it. **The screen should not change at all.**
- [ ] A **HEAT** row should appear on the HUD and climb.
- [ ] Past 75% you should get one notification telling you your gear is soaking up more than
      it can shed. Once, not repeatedly.
- [ X ] Your stamina should go and sprinting should stop working.
- [ X ] Back away — it should fade.

**Smoke.**

- [ ] Stand in smoke with **no SCBA**. You take damage, with **no screen change and no
      cough**.
- [ X ] Open your SCBA valve. Damage should stop **completely** and vision should clear.
- [ X ] Let the bottle empty while still in smoke — damage resumes.

> The screen effects are off by default and this is now the intended behaviour, not a gap.
> The reasoning is in `config/gear.lua` under `visuals`.

---

## 5. PASS device

> **Your observation was right, and the behaviour is now deliberate.** A PASS runs on its
> own battery, not on cylinder pressure. Tying `armed` to the valve meant an empty bottle
> silently switched the device off at the exact moment its wearer needed it — which is also
> why it did not alarm during last stand. It now latches on when the valve is first opened
> and stays armed until the set comes off.

- [ X ] Wearing SCBA with the valve **open**, stand completely still for ~25 seconds.
- [ ] Close the valve and stand still again. It should **still** alarm. That is correct.
- [ ] Take the set off entirely. Now it should not.
- [ X ] A chirp starts and speeds up.
- [ X ] Move — it stops. *This is the phase you are meant to escape.*
- [ X ] Stand still again and ignore it for ~12 more seconds. Full alarm.
- [ X ] **Move around.** The full alarm should **not** stop. That asymmetry is deliberate.
- [ X ] Press **K** with a set on — straight to full alarm, no waiting.
- [ X ] `/passreset` — clears it.
- [ ] Get downed while wearing an armed set. It should alarm **on its own**, during last
      stand and not only after it. *Same root cause as above: the bottle had usually emptied
      by the time you went down, which disarmed the device.*
- [ ] Have a second player try to reset it while you are still down — **it should refuse**.

**Audio — the least proven thing in the resource.**

- [ X ] Do you hear anything at all?
- [ X ] Does it get louder as you approach and pan left/right as you turn?
- [ ] Second player: can they hear yours from ~45 m?

> If it is silent, check F8 for a `could not load` line from `sounds.js` **before**
> suspecting the phase machine — the phase logic is tested, the audio is not. The most
> likely failure is the NUI `AudioContext` never resuming.

- [ ] A full alarm should notify every on-duty firefighter with a flashing blip.

---

## 6. Smoke and reading it

- [ X ] `/fire here` — is there a visible plume, distinct from the flame?
- [ X ] Is it **darker at the base and paler higher up**? That is the travel model.
> **Fixed.** Smoke colour was driven only by fire *stage*, with no input from the fuel — so
> a flammable-liquid fire smoked white while it was still small. Backwards: sooting is a
> property of the fuel, not the temperature, which is why a diesel pool is black from the
> first second. Each class now carries a `sootiness`.

- [ ] `/fire start B` — should now be **black and thick from the start**, visibly unlike A.
- [ ] `/fire start D` and `/fire start gas` — should be the palest of the set.
- [ X ] `/fire start gas` — should barely smoke at all. 
- [ X ] `/fire sizeup` — reports volume, velocity, density, colour, ventilation.
- [ ] As a low-grade firefighter you get only the observation; at grade 2+ you also get the
      interpretation.

**Ventilation and the two events.**

- [ X ] `/fire vent close_up` on an indoor fire — sealed.
- [ X ] Wait, then `/fire sizeup`. Smoke should be dense, dark, and **low velocity**, and you
      should be warned about backdraft.
- [ X ] Is the plume visibly **pulsing**?
- [ X ] `/fire vent force_door` — should have a real chance of setting off a backdraft.
- [ X ] Try again on another fire with `/fire vent vertical_vent` **first** — should be safe.
- [ X ] On a `limited` indoor fire, let it develop and size it up. Expect a flashover warning,
      then flashover roughly 25 seconds later.
- [ X ] `/fire vent vertical_vent` during the warning should buy time.

---

## 7. Teardown

- [ X ] `restart mi_fire` **twice** while a fire is burning with gear on and SCBA active.
- [ X ] No orphaned particles, no stuck screen effects, no lingering sound, no leftover blips.
- [ X ] `/fire list` after restart — empty.

---

## Known gaps — do not report these

- Gear state does not survive a disconnect (`TURN-003`).
- Only `structural` turnout has an appearance. Other tiers change protection, not looks.
- `isApparatus` accepts **any emergency vehicle**, so police cars offer turnout gear. Fixed
  in Phase 2 when `config/apparatus.lua` lands.
- No accountability board.
- `mobility` is configured per tier and applied nowhere — heavy gear does not slow you.
- Smoke renders one plume per incident, not per node.
- Ventilation is commands, not `ox_target` on real doors and windows.
