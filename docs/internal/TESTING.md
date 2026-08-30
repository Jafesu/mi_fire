# In-game test script

Everything built so far, in dependency order — a failure early would invalidate what comes
after, so work down rather than picking.

**Nothing below has been tested in game except section 1.** Sections 2 onward are all
unproven.

Set `Config.debug = true` in `config/config.lua` before starting, and watch F8.

---

## 0. Before you start

- [ ] Restart the server. Migration `0003_gear_appearance` must apply.
- [ ] `SELECT * FROM mi_fire_migrations;` — expect **3** rows.
- [ ] Repoint your SCBA item: `server = { export = 'mi_fire.useScba' }`
- [ ] Check keybind conflicts: **J** SCBA valve, **K** PASS panic, **X** stop-drop-roll.
- [ ] `/fire perms` — confirms you have access and shows which route granted it.

---

## 1. Fire engine — *already passed, re-run as a regression*

- [ ] `/fire here` — a fire starts and renders.
- [ ] `/fire agent water` — knocks down, then extinguishes.
- [ ] `/fire start B` then `/fire agent water` — **it gets worse and spreads**.
- [ ] `/fire agent foam` — that one works.
- [ ] `/fire start wildland 5 3` then `/fire wind 90 0.9` — should now spread visibly
      faster than in still air. *This changed since your last test.*
- [ ] `/fire list`, `/fire stopall`.

---

## 2. Turnout gear

The first thing built on top of the engine, and nothing after this works without it.

- [ ] Stand at a fire truck. Third-eye it — **Don turnout gear** appears.
- [ ] Don it. Your appearance changes: helmet, coat, boots, gloves.
- [ ] **The helmet specifically.** It is a prop rather than a component, and the two go
      through different natives — if the coat appears and the helmet does not, that is the
      bug to report.
- [ ] `/fire render` still works — confirms nothing else broke.
- [ ] **Doff turnout gear** — your original clothes come back, not a default skin.
- [ ] Don, disconnect, reconnect. *Known gap: gear state does not survive this yet
      (`TURN-003`). Confirming it is broken is still useful.*

**Then the thing that matters most — note this check has been inverted:**

- [ ] Put on turnout gear through a **clothing menu** instead of the truck.
- [ ] Walk into a fire. You should be **fully protected**, exactly as if you had donned it
      at the apparatus.
- [ ] Do it as a **civilian**, with no fire job. Still protected — the coat is a coat.
- [ ] Wear only the **coat**, no helmet or gloves. You should be protected, but noticeably
      less than in the full set.

That is ADR 0004. Protection follows the clothing, however it got there.

- [ ] Take the coat off mid-fire. Protection should drop within a couple of seconds.
- [ ] Burn a set down, take it off, put it back on. Integrity should **resume where it
      left off**, not reset. Changing clothes does not repair a coat.

---

## 3. SCBA

- [ ] At a truck, third-eye — **Take an SCBA set**. You get one, full.
- [ ] Your appearance changes (harness on your back, mask off).
- [ ] Press **J**. Appearance changes again — mask on.
- [ ] **Use the SCBA item from inventory** instead. Should do the same thing.
      *If nothing happens, the item export is not repointed.*
- [ ] With the valve open, sprint around. Air should drain noticeably faster than standing.
- [ ] Wait for the warnings: half a bottle, then low air, then critical.
- [ ] Let it run out entirely — the valve shuts itself and you are told.
- [ ] Third-eye the truck — **Refill air bottle**.
- [ ] **Rack SCBA set** — it comes off and is refilled.

---

## 4. Exposure — the part that makes all of the above matter

**Wear nothing.**

- [ ] `/fire here`, walk into it. You should go down in about **9 seconds**.
- [ ] Confirm your medical resource sees it properly — last stand or death, *not* a silent
      slide to zero. If you just drop dead with no last stand, the damage is not raising
      events correctly.

**In turnout gear.**

- [ ] Same fire. You should last about **64 seconds**.
- [ ] At roughly **46 seconds** your gear gives out and you can catch fire.
- [ ] Stay in it until you ignite.
- [ ] Hold **X** to stop, drop and roll. It should take about 4 seconds.
- [ ] Get a second player to target you and **Put them out** — should be much faster.

**Heat, without touching the fire.**

- [ ] Stand *near* a fire without entering it. The screen should distort and wash out as
      heat builds.
- [ ] Your stamina should go and sprinting should stop working.
- [ ] Back away — it should fade.

**Smoke.**

- [ ] Stand in smoke with **no SCBA**. Vision darkens, you cough, you take damage.
- [ ] Open your SCBA valve. Damage should stop **completely** and vision should clear.
- [ ] Let the bottle empty while still in smoke — damage resumes.

> The heat and smoke screen effects use stock GTA timecycle modifiers chosen by name and
> **never actually looked at**. They may be ugly or wrong. Say what you see.

---

## 5. PASS device

- [ ] Wearing SCBA with the valve **open**, stand completely still for ~25 seconds.
- [ ] A chirp starts and speeds up.
- [ ] Move — it stops. *This is the phase you are meant to escape.*
- [ ] Stand still again and ignore it for ~12 more seconds. Full alarm.
- [ ] **Move around.** The full alarm should **not** stop. That asymmetry is deliberate.
- [ ] Press **K** with a set on — straight to full alarm, no waiting.
- [ ] `/passreset` — clears it.
- [ ] Get downed while wearing an armed set. It should alarm **on its own**.
- [ ] Have a second player try to reset it while you are still down — **it should refuse**.

**Audio — the least proven thing in the resource.**

- [ ] Do you hear anything at all?
- [ ] Does it get louder as you approach and pan left/right as you turn?
- [ ] Second player: can they hear yours from ~45 m?

> If it is silent, check F8 for a `could not load` line from `sounds.js` **before**
> suspecting the phase machine — the phase logic is tested, the audio is not. The most
> likely failure is the NUI `AudioContext` never resuming.

- [ ] A full alarm should notify every on-duty firefighter with a flashing blip.

---

## 6. Smoke and reading it

- [ ] `/fire here` — is there a visible plume, distinct from the flame?
- [ ] Is it **darker at the base and paler higher up**? That is the travel model.
- [ ] `/fire start B` — a flammable liquid fire should smoke far more heavily and blacker.
- [ ] `/fire start gas` — should barely smoke at all.
- [ ] `/fire sizeup` — reports volume, velocity, density, colour, ventilation.
- [ ] As a low-grade firefighter you get only the observation; at grade 2+ you also get the
      interpretation.

**Ventilation and the two events.**

- [ ] `/fire vent close_up` on an indoor fire — sealed.
- [ ] Wait, then `/fire sizeup`. Smoke should be dense, dark, and **low velocity**, and you
      should be warned about backdraft.
- [ ] Is the plume visibly **pulsing**?
- [ ] `/fire vent force_door` — should have a real chance of setting off a backdraft.
- [ ] Try again on another fire with `/fire vent vertical_vent` **first** — should be safe.
- [ ] On a `limited` indoor fire, let it develop and size it up. Expect a flashover warning,
      then flashover roughly 25 seconds later.
- [ ] `/fire vent vertical_vent` during the warning should buy time.

---

## 7. Teardown

- [ ] `restart mi_fire` **twice** while a fire is burning with gear on and SCBA active.
- [ ] No orphaned particles, no stuck screen effects, no lingering sound, no leftover blips.
- [ ] `/fire list` after restart — empty.

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
