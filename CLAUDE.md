# Dig Defend — Claude Working Guide

## What this game is

Dig Defend is a Roblox game (Luau). Groups of 1 to 6 players fly by helicopter from the Apocalyptic Mining Co. lobby to a camp, mine ore from a generated mine by day, refine it into Gold, Iron, Diamonds, and Uranium, and defend the camp's Refinery from monster waves by night. Reaching the uranium target calls a rescue helicopter; boarding it wins the run. Cash earned in runs buys permanent weapons, posts, and defenses in the lobby.

The game has two places:
- **Lobby** (place id 133996405589098): the start place. Spawn zone, helicopter pads (queues), store, loadout. Third-person camera.
- **Gameplay** (place id 72646464251078): reached only by group teleport from a helicopter pad. Camp, mine, waves. First-person camera.

Game design doc: `gdd.txt` (export of the Google Doc linked in `milestones.md`)
Build milestones: `milestones.md`
Reference games (copy patterns and standards, never ship their code directly): `~/square` (Lucky Squares, "lights", primary reference) and `~/md` (Fuse Dragons, "dragons").

## How we build

We work milestone by milestone from `milestones.md`. Each milestone must be **testable and playable** before starting the next.

Workflow per milestone:
1. Read the milestone description together and agree on the full scope.
2. Implement, then run/test in Roblox Studio via Rojo sync.
3. All unit tests must stay green and `scripts/analyze.sh` must stay clean.
4. **Wait for explicit confirmation from the user that the milestone is complete before marking it done in `milestones.md` or making a git commit.** When the user says "close it out", that is the go-ahead: move the milestone (with ✅) to the end of the Done section in `milestones.md` and commit.

The user jots dated notes directly into `milestones.md` while work is in progress. If `git status` shows such edits, include them in the next commit without asking.

While the project is young, ask before adopting anything from the reference projects that seems contradictory, a bad idea, or inapplicable here.

## Project structure

```
src/
  shared/            -> ReplicatedStorage/Shared          (both places)
  server/            -> ServerScriptService/Server        (both places)
  client/            -> StarterPlayer/StarterPlayerScripts/Client   (both places)
  lobby/
    server/          -> ServerScriptService/Lobby         (lobby only)
    client/          -> StarterPlayerScripts/Lobby        (lobby only)
  gameplay/
    server/          -> ServerScriptService/Gameplay      (gameplay only)
    client/          -> StarterPlayerScripts/Gameplay     (gameplay only)
Packages/            -> ReplicatedStorage/Packages        (Wally output, committed)
```

| Project file | Place | Rojo port |
|---|---|---|
| `lobby.project.json` | Lobby | 34872 |
| `gameplay.project.json` | Gameplay | 34873 |
| `analysis.project.json` | none; mounts everything for `rojo sourcemap` / luau-lsp | — |

Each place project pins `servePlaceIds`, so the Rojo plugin refuses to sync a project into the wrong place. `scripts/serve.sh lobby|gameplay` starts a server; both can run at once.

Toolchain: **Foreman** (tool versions, `foreman.toml`), **Rojo** (Studio sync), **Wally** (packages), **luau-lsp** (static analysis via `scripts/analyze.sh`).

Common code decides which place it is in with `Constants.getPlaceKind()`. Code that exists only for one place lives in that place's folders, never behind a place check in common code.

### Path aliases
Use `@game/ReplicatedStorage/Shared/...` for shared imports from server or client code. Never use relative `../` paths across the server/client boundary. Modules inside `src/shared` require their siblings by instance path (`require(script.Parent.Enums)`) because jest-runtime cannot resolve the string alias; everything else uses `@game`. The alias resolves through the gitignored `game/` tree, which `scripts/analyze.sh` regenerates from `src/shared` and `src/server/GameData` (`scripts/regen_shared_stubs.py`). Rerun it after adding modules or `export type`s there.

## Key architectural decisions

Most of these are implemented in later milestones; the milestone number is noted so the intent is fixed now.

### GameData
Every gameplay number lives in a **GameData** data-only ModuleScript **checked into git** (unlike the reference games, where GameData was Studio-only). They live in `src/server/GameData`, mounted at `ServerScriptService/GameData` in both places, in subfolders by domain (`Control/` for tuning tables; later `Rocks/`, `Waves/`, `Store/`, `Pads/`). Rules:
- Each module exports **raw data only** (a plain table, no logic).
- Constants are `SCREAMING_SNAKE_CASE`.
- Require with the `@game` alias into a variable with a `Data` suffix: `local DifficultyData = require("@game/ServerScriptService/GameData/Control/Difficulty")`.
- Enum-valued fields require shared `Enums` at the top and use real references, never raw numbers.
- New tunable constants go in GameData, not `Constants.luau`.
- The client never requires GameData. Whatever the client needs is replicated by the server through the SplendidGames folders or the message bus.
- `scripts/analyze.sh` regenerates the LSP stubs for GameData along with the shared ones.

### Central asset location
Every clonable asset (rocks, monsters, weapons, tools, posts, defenses) lives in one central `ReplicatedStorage` location. Templates are cloned in one place in code, never ad hoc.

### Player lifecycle (M6)
`Enums.PlayerLifecycle`: `LOADING` → `READY` → `LEAVING` → `GONE`, held in a single authoritative table. **No system may act on a player that is not `READY`** (except the lifecycle manager itself).

### PlayerData (M6)
`PlayerData` is the **sole owner** of all persistent player state and the only code path that reads from or writes to ProfileStore. Managers implement business logic; PlayerData is the record of truth. `Validate` runs on every load.

### Client data: SplendidGames (M7)
The server creates a `SplendidGames` ScreenGui (`ResetOnSpawn = false`) in each player's `PlayerGui` with three folders: `GameMetadata` (global config), `AllPlayers` (public state per Ready player), `CurrentPlayer` (full private state). `CurrentPlayer` **appearing** is the client's ready signal. Clients read these through `ClientDataManager` (typed accessors and listeners); no polling, no RemoteEvents for data the folders already expose. This makes a client's entire state inspectable by a human in the Explorer.

### Networking: single RemoteEvent (M4)
Exactly **one** RemoteEvent, created in code by the server at startup, never authored in Studio. First argument is the event name (a constant from shared `NetEventNames.luau`), second is the payload table. Both sides dispatch by name from a handler table and **loudly log any unhandled name**. Client→server names start with `Try`, server→client names start with `Notify`. `NetManager` owns the receive pipeline: Ready check → known handler → `Validate.isTableShape` against the handler's shape → dispatch. Managers expose `getNetHandlers()`; `GameController` assembles them into one table so the full protocol is visible in one place.

### Server state lives in Lua, not instances
Roblox replicates every server instance to clients at high cost with no throttle, so the server keeps a **minimal instance footprint**. World state is held in server-side Lua tables and validated there. For entities that need a world position, use the **shadow system**: one small invisible anchored Part per logical entity carrying attributes; clients watch the attributes and build all visuals locally (see `~/md/ghost_shadow.md` and `~/square/src/client/ClientShadowManager.luau`). The mine grid is Lua data sent to clients over the message bus, never parts on the server (M17). Enemies are server Lua state rendered through shadows (M29).

### Reset-player dev tool contract (M5)
Any new per-player state must be covered by the reset-player-state dev tool, which must leave a player indistinguishable from a brand-new one.

### Studio authoring
Studio-only content (ScreenGuis, world templates, placeholder geometry) is authored by Claude through the Roblox Studio MCP tools, never handed to the user as a checklist. After every playtest, read the Studio console output; the game can look fine while spamming errors. After Studio is reopened, verify Rojo sync is fresh (check a script's `.Source` for a recent edit) before trusting a playtest.

### Attributes and Tags
All instance attribute names live in `Attributes.luau`; all CollectionService tags in `Tags.luau`. Never raw strings.

## Coding standards

### Module pattern
```lua
local Foo = {}
Foo.__index = Foo

function Foo:someMethod()
end

function Foo.new(...)
	local self = setmetatable({}, Foo)
	return self
end

return Foo
```
- Methods always use **colon syntax**, never `function Foo.method(self: Foo, ...)`. The new Luau solver does not infer `self` well for colon methods; those type errors are ignored by decision. Do not add casts or workarounds for that category; fix every other class of error.
- Methods come first; `Foo.new()` is the **last** function before `return Foo` (`Foo:init` second to last). Other static constructors may stay above.
- New modules use `--!strict` with real type annotations on parameters, returns, and table fields. Prefer `export type` shared via `require` over untyped tables. Do not over-index on the LSP when it copes badly.
- Subclasses alias the parent as `local super = ParentClass` right after the parent's require, and every parent reference uses `super`.
- Managers are singletons constructed at the bottom of the file or wired by `GameController`. `GameController` is the single top-level orchestrator: requires all managers, calls `init()` with dependencies to break circular references, wires `PlayerAdded`/`PlayerRemoving`, assembles the net dispatch table.
- Circular references: declare the dependency as a forward reference (`local itemManager -- prevent circular reference by not initializing here`) and assign it in `init()`. `init()` takes individual named parameters, not a bundled table.
- Client-side modules are prefixed `Client` and mirror server names exactly apart from the prefix (`NetManager` ↔ `ClientNetManager`).

### Enums
All enums live in `src/shared/Enums.luau`. Keys are `SCREAMING_SNAKE_CASE` (including `PlayerLifecycle`, where square used PascalCase), values are integers, and anything user-facing carries a `PublicNames` sub-table. Helpers (`getCount`, `getAllValues`, `isValidValue`, `getName`, `getValueByName`, `getPublicName`) live on the enum module and skip non-number entries, so `PublicNames` is never matched as a value.

### Validate
Every RemoteEvent handler validates its inputs before doing anything. Table payloads are validated against a `*_SHAPE` constant defined near the top of the owning manager.

### Naming
- Full descriptive names, **no abbreviations** (`descendant` not `desc`, `index` not `i` unless a pure counter).
- No underscore-prefixed function names.
- Booleans use a predicate prefix (`isReady`, `hasItem`, `canBuy`). The first return of `pcall` is always `isSuccess`.
- Conditional-action functions end in `IfNeeded`, never start with `maybe`.
- `local` singletons in camelCase, classes in PascalCase.

### Style
- Tabs for indentation.
- All `require()` calls at the top of the file assigned to module-level variables, never inline.
- `if`/`then` always spans multiple lines, even one-line guards.
- Use `continue` rather than early returns in loops.
- Use `+=`, `-=`, `*=`.
- `warn()` for unexpected-but-recoverable situations; `error()` only for truly unrecoverable ones.
- Comments explain *why*, never *what*. No multi-line docstrings.
- **Time:** never `os.time()`, `os.clock()`, or `tick()`; always `workspace:GetServerTimeNow()`, client included.
- **Randomness:** never `math.random`; always the `Random` class (`Random.new()`, `NextNumber`/`NextInteger`/`Shuffle`).
- Use non-deprecated Roblox APIs (for example `IsFriendsWithAsync`); check deprecation before proposing an engine API.
- Prefer `TweenService` over Heartbeat loops for simple animations.
- A closing `)` after `end` goes on its own line, and a function literal argument starts `function` on its own indented line:
  ```lua
  Players.PlayerAdded:Connect(
  	function(player)
  		doSomething(player)
  	end
  )
  ```
- Table literals: one field per line, trailing comma on the last field, no vertical alignment of `=` (exactly one space each side).

### Terminology
- **location** = (x, z) coordinate; **position** = (x, y, z).
- **Backpack** is the mining-capacity item from the GDD (upgrades, HUD icon, contents menu). Roblox's `Backpack` service is never used for inventory or UX.
- **Respawn** happens only through the game's own flows (death and revive rules, teleport failure returning a player to `SpawnZone`). Never call `LoadCharacter` ad hoc from a system or dev tool.
- In-world interactions use **ProximityPrompts** (Refinery, stores, posts) as the GDD specifies.

## UI standards

Defined in M10 and recorded here when decided: font choices, capitalization, centering, layout rules, exclamation points (very rarely). When copying UI from the reference games, restyle to these standards even if the functionality is the same.

## Testing

jest-roblox (jsdotlua Jest via Wally dev-dependencies), run from the Studio command bar in Edit mode through a `TestRunner`; set up in M3. Tests live under `src/tests/`. Every formula and every pure data transform (rock weights, mine generation, wave scaling) must have unit tests.

## Not adopted from the reference projects

Listed so the choice is visible; revisit if it turns out wrong.
- **Studio-only GameData and the `redump-gamedata` skill** (square): GameData is in git here, so there is nothing to dump.
- **"SurfaceGui buttons, never ProximityPrompts"** (square): this GDD uses proximity prompts.
- **"Nothing is named backpack"** and **"characters never respawn"** (square): adapted, see Terminology.
- **`Types.luau` generator and interface-style class types** (md): square's `typeof(setmetatable(...))` style is used instead.
- **Studio-authored RemoteEvents, one per message** (md): one code-created RemoteEvent instead.
- **Committed `.rbxl` place file** (md): places live on Roblox; `.rbxl` files are gitignored.
- **TopBarPlus** (md): not needed yet.
- **`BigNumber`** (square): this game's numbers stay well inside double precision. `utils.abbreviateNumber` stops at trillions.
- **Object/Item hierarchy** (`BaseObject` → `Object` → `Item` with `ObjectType`/`ObjectDataStore`, both games): see the recommendation below.

## Object/item system recommendation (M2)

The reference system has two halves. The definition half (`ObjectType` = raw data + template + validation hooks, `ObjectDataStore` = name → type registry) and the instance half (`Object` = owner, generated id, cloned template; `Item` = a persistent player-owned `Object` with rarity/level/traits, inventory placement and slots, and `getSaveData`/`loadSaveData` into PlayerData).

Decision: **do not port `Item` or the persistence half. Port the definition/registry half later, renamed, when M25 needs it.**
- Persistent state here is flat: Cash, a set of owned unlock names, a loadout of names, completion flags, level. Nothing is instanced, rolled, or slot-tracked, so `Item` would carry no information.
- In-run entities are short-lived. Rocks are grid data (M17), enemies are server Lua state with shadows (M29). Only placed defenses, traps (M26/M27), and claimed posts (M25) look like `Object`: a definition, a shadow part, a position, HP.
- At M25/M26 introduce `EntityType` + `EntityTypeRegistry` (the `ObjectType`/`ObjectDataStore` pattern, definitions from GameData, templates from the central `ReplicatedStorage` asset folder) and an `Entity` base (id, definition, one shadow part, `destroy`) without `userId` baked in. Definitions declare a `dataTableShape` validated by `Validate.isTableShape`, and registration is two-pass (data at load, then `validateInstances`/`processInstances` once Studio assets exist) so content errors name the offending file at startup. One registry serves everything GameData-defined: weapons, posts, defenses, enemies, rocks, store items. md's `ItemMover` motion strategies are a candidate for enemy movement at M29.
