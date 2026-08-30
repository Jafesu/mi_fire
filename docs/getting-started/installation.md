# Installation

## Requirements

**Required.** The resource will not start without these.

| Resource | Why |
|---|---|
| `ox_lib` | Commands, callbacks, zones, progress bars |
| `ox_target` | Every interaction in mi_fire is a target option |

**Optional.** Each degrades gracefully — mi_fire detects what is running and adapts.

| Resource | What you lose without it |
|---|---|
| Qbox or ESX | Job checks. Without a framework, only admins can use fire equipment. |
| `lb-tablet` | Dispatch. Fires still start; nobody gets toned out. |
| `ox_inventory` | Gear damage and SCBA air will not persist between uses. |
| `illenium-appearance` | Turnout gear changes your protection but not your appearance. |

## Install

1. Drop the `mi_fire` folder into your resources directory.

2. Add it to `server.cfg`, **after** its dependencies:

   ```cfg
   ensure ox_lib
   ensure ox_target
   ensure mi_fire
   ```

3. Grant your admins the permission for the fire commands:

   ```cfg
   add_ace group.admin mi_fire.admin allow
   ```

4. Start the server and check the console. mi_fire validates its configuration at boot and
   **refuses to start** if something is wrong, printing exactly what. A clean start prints
   nothing.

## Check it worked

In game, as an admin:

```
/fire here
```

A fire should start at your feet. Then:

```
/fire list
```

It should be listed with an ID. Put it out with `/fire stop <id>`, or `/fire stopall`.

If `/fire` does nothing at all, you are missing the ACE grant from step 3.

## Configure it

Everything is in `config/`. The two files worth looking at first:

- **`config/config.lua`** — your job names. The defaults are `fireman`, `fire`,
  `firefighter`, and `lsfd`. If your server uses something else, add it here or nothing
  will work for your firefighters.
- **`config/zones.lua`** — districts and area of play. The default districts are rough
  spheres over the obvious parts of the map. Walk your response areas with
  `/district here` and adjust them.

Every option in every config file is explained in
[the configuration reference](../configuration/README.md).

## Migrating from another fire resource

mi_fire provides exports under the same names as the resource many servers are coming
from, so add-ons written against it keep working. If you run `mi_fire_rescue`, point it at
mi_fire:

```lua
-- mi_fire_rescue/config.lua
Config.SmartFiresResource = 'mi_fire'
```

Stop the old resource before starting mi_fire. Running both means two systems creating
fires that neither can see, and it will not go well.
