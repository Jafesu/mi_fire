# Apparatus

The fleet mi_fire is built for, and what the vehicle files tell us about each rig.

**Re-verify before depending on a row.** These were read from `.meta` files on 2026-08-30 and
vehicle packs get replaced.

---

## The fleet

### 2026 fire truck pack

`[assets]/[vehicles]/2026firetrucks` — the primary fleet. Six Pierce-style apparatus.

| Model | Role | Panel family | Physical panel |
|---|---|---|---|
| `EengineHT` | Engine / pumper | `engine` | `Pump_Panelengine` |
| `EPUCHT` | PUC pumper | `puc` | `Pump_PanelPUC` |
| `EladderLT` | Aerial ladder | `ladder` | `Pump_Panelladdder` *(sic)* |
| `EtowerLT` | Tower ladder | `tower` | `Pump_Paneltower` |
| `EtankerHT` | Tanker / tender | `tanker` | — |
| `ERescueHT` | Heavy rescue | `rescue` | — |

The pack ships **four modelled pump panels**, which is why panel families are a fact about the
trucks rather than a taxonomy we invented. See [adr/0003](adr/0003-panels-are-data-not-code.md).

### Outside that pack

| Model | Role | Panel family | Source |
|---|---|---|---|
| `brushtruck` | Brush / wildland | `brush` | `[assets]/[vehicles]/firerescue` |

Other fire apparatus exist on the drive (`engine1`, `mtlengine`, `FIREONE`, `rearmount`,
`midmount`, `tiller`, `containerwatertank`) but are not the primary fleet.

**`alamolhp` is not a fire rig.** It is a police Alamo from a law-enforcement pack
(`FLAG_LAW_ENFORCEMENT`, alongside `lhpstanier` and `dnscoutlhp`). It was briefly mistaken for a
brush truck on the strength of its name; it has no place in the apparatus config.

---

## Panel photographs

`docs/Reference/PumpPanels/` holds photographs of the real in-game panels, captured
2026-08-30. **Phase 4 layouts are authored against these**, not invented — which is the whole
reason that phase was gated on them existing.

| File | Rig |
|---|---|
| `EengineHT-PumpPanel.png` | Engine |
| `EpucHT-PumpPanel.png` | PUC |
| `EladderLT-PumpPanel.png` | Aerial |
| `EtowerLT-PumpPanel.png` | Tower |
| `EtankerHT-PumpPanel.png` | Tanker |
| `EnforcerENG-PumpPanel.png` | Enforcer engine |
| `engine1-PumpPanel-Controls.png` | engine1, controls |
| `engine1-PumpPanel-Left Hookups.png` | engine1, left side connections |
| `engine1-PumpPanel-Right Hookups.png` | engine1, right side connections |

Two rigs appear here that the earlier survey did not list: **`EnforcerENG`** and **`engine1`**.
Both are in service, both now have profiles in `config/apparatus.lua`, and both carry
conventional engine figures that should be corrected against the real rigs.

The `engine1` set is the most useful of the nine for Phase 3 as well as Phase 4: the two
hookup photographs show where the discharges and intakes physically are, which is exactly what
`/fireoffset` has to reproduce as port offsets.

There is no `ERescueHT` panel photograph, consistent with it carrying little or no pump.

### What the `EengineHT` panel establishes

Read off `EengineHT-PumpPanel.png`. The label text is below legible resolution, so this is
what the **layout** shows rather than what the plates say — the names come later, from the rig.

| Reading | Consequence |
|---|---|
| Master intake and master discharge gauges, top left | Two compound gauges, the reference pair every other reading hangs off |
| **Eight** individual discharge gauges | The rig has eight discharges. Three are authored so far. |
| Gauges are **colour-coded** — orange, green, blue, yellow, white, red, light blue, purple | Standard Pierce practice: each outlet carries a matching coloured tag. **This is how to name the ports** — match the tag at the outlet to the gauge colour, and the panel and the truck agree by construction. |
| Water level **and** foam level gauges | Confirms the foam system. `foamGallons = 30` stands. |
| Two large chrome outlets with handwheels, on the panel face | Panel-mounted discharges, almost certainly 2.5 inch |
| Large steamer intake, bottom left | The main intake. Big enough to be LDH, 4 or 5 inch. |
| Colour-coded valve handwheels, bottom row | Match a subset of the gauge colours |
| Throttle and what appears to be a pressure governor, right | Confirms `governor` for the Phase 4 `engine` family |

**Eight discharges is the number that matters.** A typical engine splits them roughly as two
crosslays, one or two front bumper, two side, two rear — and the rear photograph shows four
fittings on the tailboard, which is consistent. The crosslays are the ones worth finding on
the model: they are the first line off the truck, and Phase 3 has nothing to pull without one.

Colour coding is the cheap way to author the rest. Rather than guessing which gauge belongs to
which outlet, name each port for its tag colour — `discharge_red`, `discharge_green` — and the
Phase 4 panel binds to the same names without anyone having to reconcile two lists.

---

## Bones

**`EengineHT` has no bones at its hookups.** Checked in game on 2026-08-30 with
`/fireoffset` → *Scan this rig*.

This was worth checking rather than assuming, because a bone at a hookup would have made
ports free: nothing to measure, and correct forever even if the model is updated. The pack's
panel mod switching off `misc_p` suggested the author used the conventional `misc_*` slots,
and that turned out to be for the mod geometry rather than for connection points.

So **apparatus ports on this fleet are hand-measured offsets**, and that is not a fallback we
are settling for — it is the only option the models give us. `/fireoffset` still offers the
bone route because other packs do ship useful bones, and the scan costs a minute to rule it
out on a rig nobody has checked.

Re-run the scan if the pack is ever updated. A future version might add them.

---

## Mod slots

The 2026 pack attaches functional-looking geometry to **vehicle mod slots**, which means it can
be toggled at runtime.

Verified in `2026firetrucks/data/EengineHT/carcols.meta`:

| Geometry | Mod type | Bone | Notes |
|---|---|---|---|
| `Pump_Panelengine` | `VMT_HYDRO` | `chassis` | Turns off bone `misc_p` |
| `hydrant_EengineHT` | `VMT_WING_L` | `chassis` | Intake fitting |
| `ladder_engine` | `VMT_PLAQUE` | `chassis` | |
| `bumper_engine` | `VMT_BUMPER_R` | `chassis` | Turns off `bumper_r` |

**What this makes possible:** opening the pump panel NUI can physically deploy the panel on the
truck, and connecting a supply line can make the intake fitting appear. A pump operation that
visibly opens the rig is worth considerably more than the same UI floating in front of a closed
truck.

**The cost:** driving those slots makes mi_fire partly responsible for the vehicle's appearance,
which can fight a customs or tuning resource that writes the same slots. It is opt-in per model
(`deployPanelMod`), and off means the NUI simply opens without the model changing.

Numeric mod indices are **not** recorded here on purpose — they get confirmed in game during
Phase 2 rather than guessed from the type names.

### The brush truck is the opposite case

`brushtruck` ships **no mod kit at all**. Its `carcols.meta` defines no mod models, and the
vehicle uses extras (`FLAG_EXTRAS_STRONG`, `FLAG_HAS_INTERIOR_EXTRAS`) rather than mod slots.

So there is no panel geometry to deploy: `deployPanelMod = false`, and its panel is pure NUI.
That makes it the honest test of the auto-generated fallback — a rig where the model gives us
nothing to work with — which is why the `brush` family is built early despite being last in
priority.

---

## What cannot be read from the files

Both packs ship **`RSC7`-compressed** models. Bone names, extra indices, and connection geometry
are not extractable from disk — confirmed by attempting it.

Everything positional has to be found in game with `/fireoffset` in Phase 2:

- discharge and intake port positions
- pump panel location
- hose bed, ladder rack, gear compartment
- which extras a vehicle has, and what they are

**No offsets can be pre-authored from disk.** A future session that assumes otherwise will waste
its time; this paragraph exists to save it.

---

## Filling in `config/apparatus.lua`

Per model: tank capacity, foam cell, pump rating, maximum discharge pressure, intake count, and
the connection point list. Ports carry a `portId` that the pump panel layout references by name,
so the discharge on the panel is the outlet a crewmate connected a line to.

Pump ratings and tank sizes are a judgement call per rig rather than something the model files
carry. Sensible starting points for the fleet above, to be tuned in play:

| Family | Tank (gal) | Pump (gpm) | Notes |
|---|---|---|---|
| Engine / PUC | 750–1000 | 1500–2000 | The reference pumper |
| Aerial / tower | 300–500 | 1500–2000 | Smaller tank, ladder pipe |
| Tanker | 2500–3000 | 500–750 | Carries water, does not fight with it |
| Brush | 200–400 | 150–250 | Small pump, pump-and-roll |
| Rescue | 0–300 | 0 | Confirm on the model before assuming a pump |
