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

> **This resource is still in development.** The fire engine is not built yet, so there
> is nothing to *see* on a first boot — no commands, no fires. What a clean start proves
> is that the resource loads, the configuration is valid, and the database schema applied.
> That is worth confirming before the rest is built on top of it.

Watch the server console as it starts. A healthy boot is **silent** — mi_fire only prints
when something is wrong or when `Config.debug` is on.

Turn on `Config.debug = true` in `config/config.lua` for the first boot and you should see
one line naming the framework, dispatch, and database it found:

```
[mi_fire:boot] framework=qbx dispatch=lb-tablet is started database=ready
```

Then confirm the schema applied. mi_fire creates its tables on first boot and records
what it ran:

```sql
SELECT * FROM mi_fire_migrations;
```

Two rows, `0001_stations` and `0002_sprinklers`. If the table does not exist, the database
was unreachable — see the warning in the console for which.

Finally, `restart mi_fire` **twice**. The second restart is where leaked handles show up,
and catching that now is far cheaper than catching it once there is a fireground to leak.

### If something is wrong

mi_fire validates its configuration at boot and **refuses to start** on a bad one, listing
every problem rather than failing at the first:

```
[mi_fire] configuration problems found:
  - gear tier "structural" has fireResist 1.00; nothing may grant immunity to fire
  - AOP default names unknown district "downtown"
[mi_fire] refusing to start with an invalid configuration
```

Those messages name the file and key to fix. A resource that boots into a half-working
state is harder to debug than one that says why it will not.

Warnings are different from errors — these are informational, and mi_fire keeps running:

| Warning | Meaning |
|---|---|
| `dispatch unavailable` | Fires will still start; nobody gets toned out. |
| `oxmysql is not started` / `database is unreachable` | Station and sprinkler features are off. Everything else is fine. |
| `ox_target is not started` | No interactions will be available. Fix this one. |

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
