--- ox_inventory item definitions for mi_fire.
---
--- This file is **not loaded**. It returns the definitions so it stays valid Lua and gets
--- checked by the parse gate; copy the entries you want into `ox_inventory/data/items.lua`.
---
--- Everything here is optional. Without ox_inventory, SCBA is still available from
--- apparatus and station racks and turnout still works. What is lost is carrying a bottle
--- away from the rig and having gear wear persist between shifts.

return {

    --- If you already have an SCBA item, you do **not** need this block. Repoint the
    --- export you already have and keep everything else:
    ---
    ---     ['scba'] = {
    ---         label = 'SCBA',
    ---         weight = 220,
    ---         server = {
    ---             export = 'mi_fire.useScba',   -- was your old handler
    ---         },
    ---     },
    ---
    --- One string. Using the item toggles the set on and off; the air valve is a separate
    --- keybind, so using the item never accidentally starts burning air.
    ['scba'] = {
        label = 'SCBA',
        weight = 11000,          -- a real set with a full cylinder is about 11 kg
        stack = false,           -- each set is its own thing, with its own pressure
        close = true,
        description = 'Self-contained breathing apparatus. Use to put it on or take it off.',
        server = {
            export = 'mi_fire.useScba',
        },
    },

    --- Turnout gear as a possession. Optional even with ox_inventory, since donning works
    --- from an apparatus rack without holding anything.
    ---
    --- **Name tapes and rank markings are not stored here.** Those are per-character and
    --- live in `mi_fire_gear_appearance`, because they belong to the firefighter rather
    --- than to the coat -- gear issued from a rack has no item at all, and a coat handed
    --- to someone else must not carry the previous owner's name across.
    --- See `exports.mi_fire:SetGearAppearance`.
    ---
    --- What *is* stored here is wear: `integrity` in metadata, so a set that took a
    --- beating stays beaten until it is repaired or replaced.
    ['turnout_structural'] = {
        label = 'Structural Turnout Gear',
        weight = 13000,
        stack = false,
        close = true,
        description = 'Coat, trousers, boots, gloves and helmet. Reduces flame damage. Does not stop smoke.',
    },

    ['turnout_wildland'] = {
        label = 'Wildland Brush Gear',
        weight = 4000,
        stack = false,
        close = true,
        description = 'Lighter and cooler than structural. Correct for brush, dangerous inside.',
    },

    ['turnout_proximity'] = {
        label = 'Proximity Gear',
        weight = 16000,
        stack = false,
        close = true,
        description = 'Aluminized, for radiant heat off a fuel fire. Heavy and slow to work in.',
    },

    ['scba_bottle'] = {
        label = 'Spare Air Cylinder',
        weight = 7000,
        stack = false,
        close = true,
        description = 'A charged spare. Swap it at a rack.',
    },
}
