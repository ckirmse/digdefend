# Dig Defend: project overview for the balance designer

Written 2026-10-26 for a second designer (and their Claude) joining to work on balance. It explains how the project is set up, where the tunable numbers live, how to test a change, and the rules for working alongside the main build without stepping on it. Read `CLAUDE.md` after this for the full working guide; read `docs/balance.md` for what the numbers currently are and how they combine.

## The game in one paragraph

Dig Defend is a Roblox game written in Luau. Groups of 1 to 6 players fly by helicopter from a lobby to a camp. By day they mine ore from a generated mine and refine it at the camp's Refinery into Gold, Iron, and Uranium. By night monster waves attack the camp; the crew defends the Refinery with handheld weapons, mounted post weapons, towers, traps, walls, and class gadgets. Reaching the Uranium target calls a rescue helicopter; boarding it wins the run. Diamonds earned in runs are the lobby currency (characters, slots). The design source of truth is `gdd.txt`, an export of the Google Doc.

Two Roblox places:

| Place | What it is | Place id | Rojo port |
|---|---|---|---|
| Lobby | Spawn zone, helicopter pads, store, character menus | 133996405589098 | 34872 |
| Gameplay | Camp, mine, waves, the run | 72646464251078 | 34873 |

Balance work lives almost entirely in the Gameplay place.

## Toolchain

- **Foreman** pins tool versions (`foreman.toml`): Rojo 7.7.1, Wally 0.3.2, luau-lsp 1.69.0. Run `foreman install` once.
- **Rojo** syncs the `src/` tree into Roblox Studio. `scripts/serve.sh lobby` and `scripts/serve.sh gameplay` start one server each; the Rojo plugin in Studio connects to the matching port. Each project file pins its place id, so a project cannot be synced into the wrong place.
- **Wally** installs packages into the committed `Packages/` and `DevPackages/`. You should never need to run it. If you do, stop every Rojo server first (Rojo 7.7 crashes when a watched folder vanishes).
- **luau-lsp** does static analysis: `scripts/analyze.sh`. It prints thousands of ignored colon-method diagnostics by project decision; filter to the files you touched and read those lines, never trust the total.
- **Roblox Studio MCP**: Claude drives Studio (running scripts in the Command Bar, reading the Output, starting Play) through an MCP server configured in `.mcp.json`. The path in that file points at a specific Studio version folder; when Studio updates it breaks with "Connection closed" and the hash must be fixed.
- **Places are not in git.** `.rbxl` files are gitignored. Each Studio place lives on Roblox; the build scripts under `scripts/studio/` recreate authored content (GUIs, templates) when needed.

## Repository layout

```
src/
  shared/            -> ReplicatedStorage/Shared       both places: enums, pure rules, codecs
  server/            -> ServerScriptService/Server     both places: common managers
  server/GameData/   -> ServerScriptService/GameData   ALL TUNABLE NUMBERS (see below)
  client/            -> StarterPlayerScripts/Client    both places: client managers
  lobby/{server,client}                                lobby only
  gameplay/{server,client}                             gameplay only
  tests/shared/*.spec.luau                             jest-roblox unit tests
Packages/, DevPackages/                                Wally output, committed
scripts/             analyze.sh, serve.sh, studio/ (replayable Studio scripts)
docs/                this file, balance.md, balance-plan.md (the running balance log)
gdd.txt              the design doc export
milestones.md        the build log, worked milestone by milestone
```

### How the code is organised

- **Managers** are singletons, one per system (`MiningManager`, `WaveManager`, `PostManager`, ...). `GameController` (common) and each place's `main.server` wire them together. Server state is held in Lua tables, never in Roblox instances, so the server keeps a tiny instance footprint.
- **Pure rules modules** in `src/shared` (`WaveRules`, `RockRules`, `PostRules`, `WeaponRules`, `ClassRules`, `BalanceModel`, and so on) hold every formula. They have no side effects and are unit tested. A manager reads GameData, calls a rules function, and applies the result.
- **GameData** in `src/server/GameData` holds the numbers the rules consume. Data only, no logic.
- **Enums** live in `src/shared/Enums.luau`. GameData refers to kinds (monster kinds, rock kinds, difficulties) by enum reference, never raw numbers.
- **Networking** is one RemoteEvent plus one unreliable snapshot stream. Clients never read GameData; the server publishes what they need as attributes on replicated folders.
- **Client** modules mirror server names with a `Client` prefix.

This split is what makes balance work safe to do in parallel: changing a number in GameData touches no logic, and the tests and the audit tell you at once if a shape or a target broke.

## Where the numbers live

Everything tunable is under `src/server/GameData`, grouped by domain. 63 modules:

| Folder | Contents |
|---|---|
| `Control/` | `Difficulty`, `PartyScaling` (crew scaling), `RunCycle` (day and night lengths), `Balance` (the audit's targets and the model's assumptions), `Player`, `Network`, `Telemetry` |
| `Monsters/` | `Roster` (every monster kind's stats), `Behavior` (engine and targeting tuning), `Lurkers` |
| `Waves/` | `DeadmansCanyon`, `FrostbitePass` (authored waves and the generator's per-difficulty settings), `Generation`, `Registry` |
| `Mines/` | `DeadmansCanyon`, `FrostbitePass` (zones, depth, ore distribution), `Generation`, `Registry`, `Streaming` |
| `Rocks/` | `RockDefinitions` (HP, yields, pick level), `Weights` |
| `Mining/` | `PickAxe`, `Backpack`, `Boots`, `Torch`, `JetPack`, `GeigerCounter`, `Compass`, `Clearance`, `Dynamite` (tool upgrade ladders) |
| `Store/` | `MiningSupplies` (what the mining store sells) |
| `Refinery/` | `Refinery` (ore to bar rates, refine time, the uranium target) |
| `Weapons/` | `Handheld` (every hand weapon), `Upgrades` (the weapon ladder) |
| `Posts/` | `PostWeapons` (every mounted post weapon and its upgrade rows) |
| `Defenses/` | `Towers`, `Traps`, `Placement` (caps, repair), `Table` (the Defense Table) |
| `Camp/` | `Structures` (walls, gate, Refinery HP per tier, fortification prices) |
| `Gadgets/` | one file per class gadget |
| `Classes/` | `Roster` (every class's kit and modifiers) |
| `Characters/` | `Stars`, `Progression`, `Rank`, `Rerolls`, `Skills`, `Slots`, `Hats` (lobby progression; stars do not yet affect stats) |
| `Run/` | `Rescue`, `Revives`, `DiamondTaps`, `GiveCurrency`, `Arrival`, `StudioDefaults` |
| `Pads/` | `Party` (lobby queue) |

Conventions inside a GameData file:
- Constants are `SCREAMING_SNAKE_CASE`; the file returns one plain table.
- Enum-valued keys use the enum (`[Enums.Difficulty.NORMAL] = 15`).
- Comments record **why** a number is what it is, usually with a date and the playtest that set it. Keep that habit: when you change a number, update or add the comment with the date and the reason. The history of decisions is in those comments, in `docs/balance-plan.md`, and in `milestones.md`.
- Several files are checked by unit tests or by startup validation (wave shapes, roster fields, class kits). A malformed entry fails the tests or warns at server start with the file named.

## The formulas (read, do not edit)

The curves that turn GameData into outcomes live in `src/shared`. The ones a balance designer will want to read:

| Module | What it computes |
|---|---|
| `WaveRules`, `WaveGenerator` | how a night's wave is built from the authored list or generated from points, crew scaling, group timing |
| `MonsterRules` | targeting, attack resolution |
| `RockRules`, `MineGenerator` | rock HP by tier, ore placement by zone and depth |
| `MiningRules`, `BackpackRules` | swing interval, mining power, capacity |
| `RefineryRules` | ore to bars, the uranium target by crew and difficulty |
| `WeaponRules`, `PostRules`, `TowerRules`, `TrapRules` | damage per level, headshots, upgrade stats |
| `StructureRules`, `PlacementRules` | wall HP, repair chunks, caps |
| `ClassRules` | class modifiers and how they scale a stat |
| `BalanceModel` | the night-by-night simulation of income against threat |

Changing a formula is a code change: it needs the unit tests updated and it can collide with feature work in the same file. Ask for it rather than making it (see the working rules below). Everything you can express as a constant belongs in GameData instead.

## How to test a balance change

In order of cost:

1. **Unit tests** (seconds, no Play). From the Studio Command Bar in Edit mode, with Rojo synced:
   ```lua
   task.spawn(function() loadstring(game.ServerScriptService.Tests.TestRunner.Source)():run() end) return "running"
   ```
   Read the Output. Specs live in `src/tests/shared`.

2. **The balance sheet** (seconds, no Play). `scripts/studio/balance_sheet.luau` loads `BalanceAudit` and prints the model's night-by-night sheet (income, threat, leak, breach night, target night) for the maps, difficulties, and crew sizes listed in its `SHEETS` table, plus every missed target from `GameData/Control/Balance`. Run it in the Edit datamodel through the Studio MCP after the GameData edit has synced. `BalanceAudit:buildInput(map, difficulty, crew, nights)` plus `BalanceModel.simulate` lets you override wave settings or zones in memory to scan candidates before touching data. The same audit runs at every gameplay server start and warns for every missed target, so a broken target is the last startup line in the Output. Only `AUDITED_MAPS` (Deadman's Canyon) is held to targets.

3. **A playtest**. Play the gameplay place. The dev panel (RightShift, admins only) can spawn monsters, skip to sunset, set the active class, print the sheet for the current run, run the monster stress test, and more. At every dawn and at the run's end the **run report** prints a per-day, per-player table to the Output (Refinery payouts, spend, kills, damage by structure and monster kind, swings by rock kind, deepest block, where players stood). Read it; it is the calibration source for the model's assumptions.

4. **Run records.** Every run is also saved to a DataStore with no player identity, stamped with the place version and a fingerprint of every GameData table. `scripts/studio/pull_run_records.luau` prints the newest runs and per-day averages, filterable by map, difficulty, data fingerprint, and whether dev commands were used. This is how a batch of tester runs reads as one table against the sheet.

Caveats learned the hard way:
- Studio Play sessions in the lobby and gameplay places share one player profile. Stop the lobby's Play before playing the gameplay place or the gameplay player is kicked.
- The Studio MCP thread cannot `require()` modules directly; the Studio scripts use a substitute require. Never substitute-require a gameplay manager that pulls in `GameController` from the Edit datamodel; it leaves a stray RemoteEvent that silently breaks the next Play session.
- After Studio reopens, confirm Rojo sync is fresh before trusting a playtest.
- A playtest can look fine while the Output spams errors. Always read the Output.

## Working alongside the main build

The main build (the owner and their Claude) commits to `main` daily, currently on the class passes (M64 and M65 in `milestones.md`). Feature work adds GameData constantly without anyone asking for it: a new gadget is a new `Gadgets/<Name>` file plus a kit entry in `Classes/Roster`; a new post is a block in `Posts/PostWeapons`; a new tower a block in `Defenses/Towers`. So "balance edits GameData, features edit code" is not a clean wall. The practical rules:

1. **Stay inside `src/server/GameData` and `docs/`.** Numbers go in GameData. Notes, logs, and proposals go in `docs/balance-plan.md` or a new file under `docs/`. If a change needs a formula, a new dev command, a new run-report column, or a new GameData field that the code must read, write it up as a request and send it to the owner; do not edit `src/shared`, any manager, `DevTools`, or `RunReportManager`.
2. **Do not touch the rows of a class whose pass is in flight.** The owner names the classes being built each week. Their `Classes/Roster` rows, their gadget files, and their post and tower blocks are off limits until the pass closes. Classes listed in the roster's `UNBUILT_KINDS` and `POST_LAUNCH_KINDS` are not tunable yet. Everything else in GameData is yours.
3. **Branch and pull-request.** Work on a branch, commit often, open a pull request against `main`. The main build stays on `main`. Number-only branches rebase cleanly almost every time; where two people changed the same entry (one added a field, one changed a number) the conflict is a few lines and resolved by hand.
4. **One Rojo and one Studio per person.** Two Rojo sessions syncing the same place fight. Use your own checkout, your own `scripts/serve.sh gameplay`, and your own copy of the gameplay place (a local save or a separate test place), never the shared live place while someone else is synced to it.
5. **Do not edit `gdd.txt` or `milestones.md` directly.** Both are edited at every main-build commit and will conflict. Put GDD changes you want in your pull request description or in your docs file; the owner carries them into the GDD and the Google Doc.
6. **Every number change carries its reason.** Update the comment beside the constant with the date and the playtest or model result that motivated it. Future sessions, yours and ours, read those comments as the history.
7. **Before a pull request:** unit tests green, the balance sheet run and its misses listed in the description (the audit's targets are themselves tunable in `Control/Balance`, so say if you moved a target rather than met it), `scripts/analyze.sh` clean on your files.

## Project rules that apply to balance data

From `CLAUDE.md`, the ones you will meet:

- GameData exports raw data only, no logic, no functions.
- Difficulty is parameters, never a stat multiplier: a harder tier changes which monsters come, when, and how many, through its own settings, not by scaling monster stats. (The crew's enemy HP multiplier from `PartyScaling` is the one multiplier, and it scales with crew size, not difficulty.)
- Every class swings alike on damage and no class sets mining power; class differences are kit plus `MINING_SPEED` and a small set of modifiers in `Enums.ClassModifier`. A buff that touches only one class's own kit belongs in that kit's GameData, not in the class table.
- Headshots are the Railgun's alone; a GameData default of 1 means no headshot.
- Gadget upgrades go only to a gadget that must keep pace with the waves or the mine.
- Resources show as icons, never words, in any UI copy you propose.
- Time is `workspace:GetServerTimeNow()`, randomness is the `Random` class; relevant only if a request of yours turns into code.

## Where to read the history

- `docs/balance-plan.md`: the running balance log since 2026-09-28, with the designer's targets, every playtest's findings, what changed and why, open items, and the playtest protocol. Start here.
- `GameData/Control/Balance.luau`: the audit's targets and the model's assumptions, each commented.
- `milestones.md`: the build log; the Done section records each pass with dates.
- The dated comments inside every GameData file.
