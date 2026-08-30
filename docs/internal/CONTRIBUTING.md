# Contributing

How work happens in this repo. Read this before writing code.

---

## Start of session

1. Read [BUILD.md](BUILD.md) — what this is, the module map, where things live.
2. Read [CONVENTIONS.md](CONVENTIONS.md) — how code here is written. Not negotiable.
3. Open [TASKS.md](TASKS.md). Pick the task you were asked for, or the next `todo` whose
   dependencies are all `done`. Set it to `in-progress` **before** you start.
4. Skim the last three entries in [DEVLOG.md](DEVLOG.md) — what the previous sessions did
   and what they left open.
5. If your work touches another resource, read its row in [INTEGRATIONS.md](INTEGRATIONS.md)
   first. Those rows carry verified `file:line` facts. Re-verify anything you are about to
   depend on — other resources get updated.

## End of session

1. Update the task status in [TASKS.md](TASKS.md) (`review`, `done`, or back to `blocked`
   with a reason).
2. **Append** an entry to [DEVLOG.md](DEVLOG.md) using the template at the top of that file.
   Never edit or delete an earlier entry.
3. If you added or changed an export, event, or callback, add its row to
   [CONTRACTS.md](CONTRACTS.md) **in the same commit**. A contract change without a docs
   change is a bug.
4. If you shipped a user-facing feature, write or update its guide in `docs/guides/`.
   A feature is not done until someone who was not in the session can use it from the
   documentation alone.
5. If you made a decision a future session could reverse by accident, write an ADR in
   [adr/](adr/). Number it sequentially and link it from the log entry.
6. Run the tests. Commit. Push.

---

## Hard rules

- **Nothing grants immunity to fire.** No gear tier may have `fireResist >= 1.0`.
  `server/main.lua` refuses to boot if one does, and a test asserts it. This is a design
  invariant, not a balance preference.
- **Protection is read from server state, never from clothing.** A player wearing a
  turnout skin has a look, not resistance. See `bridge/appearance/illenium.lua`.
- **Every world interaction is `ox_target`.** No drawtext prompts, no proximity keypress
  loops, no `IsControlJustPressed` polling to interact with anything. Keybinds exist only
  for controls held during an action already in progress, and go through `lib.addKeybind`.
- **No business logic in a transport.** Commands, exports, events, and NUI callbacks are
  thin wrappers over a service function in `server/modules/<name>/`.
- **Permission checks live at the service boundary, once.** Not in the transport, not in
  the UI, not in both.
- **Nothing framework-specific outside `bridge/`.** If you type `qbx_core`, `QBX.`, or
  `ESX.` in a module, that is a defect. Add a bridge method.
- **Nothing hardcoded that is configurable.** Job names, command names, district names,
  dispatch recipients, fire behaviour, gear numbers — all config. A literal `'fireman'`
  in module code is a bug.
- **The server owns all truth.** Clients render and request. A client never asserts that a
  fire is out, a tank is full, or a line is charged.
- **Clean up what you create.** Ropes, props, PTFX, blips, and target zones do not remove
  themselves on resource stop. Register them with the trackers in `client/main.lua`.

---

## Running the tests

From the resource root:

```sh
lua tools/run_tests.lua
```

Any Lua 5.1 through 5.4 interpreter works — the tested code deliberately avoids version
specific syntax so it runs outside FiveM. On this machine the interpreter is at
`C:\Program Files (x86)\Lua\5.1\lua.exe`, which is not on `PATH` by default.

The suite exits non-zero on failure. It covers `shared/hydraulics.lua` against hand-worked
fireground problems with known answers, and asserts the gear-immunity invariant above.

If you change a hydraulics formula and a test fails, the code is wrong until someone shows
the arithmetic says otherwise. These are not snapshots.

## Verifying in game

- `ensure mi_fire` with **zero errors and zero warnings**.
- Then `restart mi_fire` **twice**. The second restart is where leaked ropes, props,
  threads, and target zones become obvious.
- Record what you actually ran in the log entry. "Qbox clean, ESX not tested" is a useful
  entry. "works" is not.

---

## Commits

Conventional commits, lower case, scoped to the system:

```
feat(pump): governor holds PDP across discharge changes
fix(hose): release crew slots when a player disconnects mid-line
docs(guides): pump operations walkthrough
refactor(bridge): fold duty checks into the framework interface
test(hydraulics): friction loss for parallel supply lines
```

Scopes in use: `fire`, `hose`, `pump`, `water`, `ladders`, `scba`, `hazmat`, `rescue`,
`station`, `zones`, `turnout`, `bridge`, `admin`, `docs`, `test`, `build`.

Commit at the end of every session, and push. Never commit a broken test suite.
