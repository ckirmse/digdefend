# Dig Defend — Build Milestones

Source: game design doc, exported to `gdd.txt` in this repo. Live version: https://docs.google.com/document/d/1uSE6rXA2rIwvqYDbySOI4nr2OXErxfMbViEymtUqWaQ/edit (re-export with `curl -sL "https://docs.google.com/document/d/1uSE6rXA2rIwvqYDbySOI4nr2OXErxfMbViEymtUqWaQ/export?format=txt" -o gdd.txt`). Reference projects: `~/md` (dragons) and `~/square` (lights).

Each milestone should be testable and playable before moving to the next. Milestones are numbered `M<n>` in build order within a phase. Phases are roughly sequential, but later polish/meta phases can interleave once core gameplay (Phase 6) is playable.

Rules:
- Never mark a milestone complete or commit code without explicit approval.
- Every gameplay number lives in a `GameData` data-only module (checked into git for this project, unlike the reference games).
- Every clonable asset (rocks, monsters, weapons, tools, posts, defenses) lives in one central `ReplicatedStorage` location.
- Core loop first, art and polish later. A cube enemy is a fine enemy until Phase 9.
- When copying UI or systems from the reference games, restyle to this project's UI standards (fonts, capitalization, centering, sparse exclamation points).

Open design questions (sections of the GDD that are still empty headings, to be filled before their phase begins): Backpack, Boots, Posts, Defenses, Traps, Wall Repair, Camp Level, Wave Cycle, Monsters, Random Events, Adjusting for Player Counts, Revives, Spectate Mode, Menus, Audio.

---

# Upcoming

## Phase 2: Player Lifecycle, Persistence, and Lobby Shell

## Phase 3: Queues and Teleporting

## Phase 4: Mine Generation and Mining

**M15 — Rock definitions and weight kernel**
Global rock table (filler, resource tiers, uranium, bedrock, gate) in GameData. The `weights(center, count, spread)` kernel, `hardness`/`tierBias` resolution, difficulty transform (`effectiveHardness`, `effectiveVeinCount`). Fully unit tested against the tables in the GDD.

**M16 — Mine generator (data only)**
Pure-Lua generator implementing the ordered pipeline: resolve difficulty, resolve chamber inheritance, validate (fatal vs warn, naming parameter and chamber), size grid, fill bedrock, carve chambers with filler, stamp veins with corridor clearance, stamp hand-placed rock, carve corridors, place gates, report. Seeded and reproducible. Unit tests on the worked example from the GDD.

**M17 — Mine replication and client rendering**
Server holds the grid as Lua data, not parts. Send the grid to clients over the message bus in chunks; clients clone rock templates from `ReplicatedStorage/Rocks` and pool/stream blocks around the player. Rock HP tracked server-side by grid position. Measure bandwidth and memory against the 2 GB phone target.

**M18 — Custom tool bar, pick axe, and Mining Mode**
Custom tool bar (more than 3 slots on mobile, stable order, one equipped at a time). Pick axe as default tool. Mining Mode: center reticle, highlighted target rock with name/HP label, hit input for mouse, touch, and gamepad, server-validated hits with damage applied to the grid, crack overlay at 60% and 30%, rock removal broadcast to clients. Hit particles and sounds can be placeholders.

**M19 — Ore drops, backpack, and pickup**
Ore awarded to the breaker up to backpack capacity, overflow dropped as world pickups collected on walk-over. Backpack HUD icon with slot count, red "Backpack full" state, tap to open backpack contents menu. Pop sound on pickup.

**M20 — Refinery**
Proximity prompt refines all raw ore into Iron Bars, Gold Bars, Diamonds (shared camp progress), and Uranium. Balances shown in the gameplay HUD. Placeholder animation now; the suck-in, grind, and fly-to-HUD sequence is a Phase 9 polish item.

**M21 — Mining Supplies Store and mining tools**
3D proximity-prompt store for Pick Axe, Boots, and Backpack upgrades (4 levels each, adjustable) paid in Gold, plus Torch and Dynamite consumables added to the tool bar. Pick axe model and icon change on upgrade. Dynamite destroys a region of rock server-side.

**M22 — Camp Level and chamber gates**
Diamonds fill the Camp Level bar on the Refinery. Reaching a level opens that chamber's gate blocks with a visible and audible moment, and unlocks the next tier of mining and post upgrades. Definition of what each camp level unlocks lives in GameData. Needs the empty "Camp Level" GDD section filled first.

## Phase 5: Camp, Defense, and Placement

**M23 — Camp structures with HP**
Deadman's Canyon placeholder camp: segmented walls, 6 posts, gate, Refinery, Mining Store, Defense Store, Helicopter Pad. Walls and gate have HP, can be repaired and upgraded with Iron. Refinery HP with destroyed-state hook for the loss condition. Gate opens during day and closes at night.

**M24 — Weapons**
Default Rifle tool with Weapon Mode, first-person aiming, server-validated hits on damageable targets. Weapon definitions in GameData so loadout weapons plug in later.

**M25 — Defensive Posts**
Claim a post (one per player), spawn the post weapon from the loadout, mount and fire it, unmount. Post upgrades bought with Gold. Needs the empty "Posts" GDD section filled first.

**M26 — Placement Area, traps, and defenses**
Placement Area bounds, placement tool bar appearing inside it, ghost preview with green/red validity, place on tap. Traps bought with Iron at the Defense Store and consumed on placement; Defensive Units drawn from loadout and paid for on placement. Needs the empty "Defenses" and "Traps" GDD sections filled first.

**M27 — Defensive unit and trap behavior**
Automated targeting and firing for defensive units, trigger behavior for traps (slow, corral, damage). Simple placeholder models.

## Phase 6: Enemies and the Core Loop

**M28 — Day/night cycle and run state machine**
Run state: `Day` (5 minutes) to `Night` (spawning over 90 seconds, lasting until all enemies dead) to next `Day`. Day counter, clock HUD, gate auto open/close. Run ends on Refinery destroyed or all players dead.

**M29 — Enemy framework**
Enemies as server Lua state rendered through shadows on the client, not full server models. Navigation to the camp, wall/gate/refinery attacking, targeting players, HP and death. Cube enemies are fine. Needs the empty "Monsters" GDD section filled first.

**M30 — Wave data and difficulty scaling**
Per-map, per-difficulty wave composition in GameData. Enemy HP/damage multipliers by difficulty. Wave progression escalating each night. Needs the empty "Wave Cycle" section filled first.

**M31 — Win condition and rescue helicopter**
Uranium target per map/difficulty. Reaching it enables calling the rescue helicopter; final climactic wave spawns as it arrives; boarding the helicopter wins the run. Completion recorded in PlayerData (only if the player had completed the prerequisite themselves) to unlock maps and difficulties in the Create Party menu.

**M32 — Death, revives, and spectate**
Player death handling, revive mechanic, spectate mode for dead players, all-dead loss. Needs the empty "Revives" and "Spectate Mode" sections filled first.

**M33 — Player-count scaling and return to lobby**
Wave and resource adjustments for 1 to 6 players. Run-end summary screen with Cash milestones earned, then teleport back to the lobby. Needs the "Adjusting for Different Player Counts" section filled first.

**M34 — First full playtest pass**
Play Deadman's Canyon Normal solo and with a group, start to finish. Fix blockers, tune the first-pass numbers. This is the "core game is playable" gate.

## Phase 7: Meta Progression and Lobby Economy

**M35 — Store config and Store Menu**
Single `StoreConfig` GameData file driving Featured, Weapons, Posts, Placements, and Currency sections. Three-panel Store Menu with vertical scrolling inventory, item panel, and buy flow for Cash and Robux. Insufficient Cash routes to the smallest sufficient currency pack. Owned non-repeatable items hidden.

**M36 — 3D Store**
Showcase models in `Workspace.Store.Items` with `StoreItem` attributes and proximity prompts that open the purchase flow or the store menu section.

**M37 — Loadout Menu**
Owned/unowned/equipped states, equip/unequip/buy actions, slot replacement rules, five-slot loadout display. Loadout carried into the gameplay place via PlayerData.

**M38 — Cash milestones**
In-run milestone table awarding Cash. (Player level, XP, the level-10 bonus loadout slot, and level-gated pads were removed from the design on 2026-09-10; pads gate on completions only.)

**M39 — Daily Rewards**
Daily Rewards Menu ported from lights with configurable day count and rewards, restyled to this project's UI standards.

**M40 — Dev products and Robux purchase handling**
`ProcessReceipt` for currency packs and Robux store items, idempotent granting, purchase logging.

## Phase 8: Second Map and Content Breadth

**M41 — Map system**
Map selection from join data drives camp layout, mine config, and wave data. Camp structure placement authored per map.

**M42 — Frostbite Pass**
Second camp with more exposure and its own mine and wave data. Weather placeholder.

**M43 — Difficulty tiers for both maps**
Hard and Nightmare tuning for both maps. Map and difficulty unlock chain verified end to end.

**M44 — Launch content**
Full launch roster of weapons, post weapons, defensive units, traps, and mining tool tiers with data and placeholder models.

**M45 — Random events**
Mid-run random events framework and a first few events. Needs the empty "Random Events" section filled first.

## Phase 9: Art, Audio, and Feel

**M46 — Rock, mining, and refinery feel**
Final rock textures, crack overlays, hit particles, ore pop, refinery suck-in/grind/fly-to-HUD sequence with balance bar shake.

**M47 — Enemies, weapons, and camp art**
Replace placeholder enemy, weapon, post, defense, trap, and structure models with final assets from the central asset location.

**M48 — Lobby art and helicopters**
Lobby environment, helicopter models and takeoff animation, 3D store showcases, loading screen art.

**M49 — Audio**
Sound effects across mining, combat, UI, and camp; ambient and music per place; volume options. Needs the empty "Audio" section filled first.

**M50 — UI polish pass**
Every menu checked against the UI standards from M10. Mobile layout verification on small screens.

## Phase 10: Performance, Stability, and Launch Prep

**M51 — Low-end device performance**
Profile on a 2 GB phone and low bandwidth. Tune streaming radius, rock pooling, enemy shadow update rates, and message sizes.

**M52 — Robustness**
Teleport failure paths, mid-run disconnects and rejoins, server shutdown handling, data save flush under load, error reporting.

**M53 — Analytics and telemetry**
Run funnel events (queue, run start, day reached, win/loss, purchases) for post-launch balancing.

**M54 — Balance pass and soft launch**
Full balance pass on both maps and three difficulties using playtest and telemetry data. Launch checklist: place permissions, group gating, dev products live, event area sign in place.

---

# Done

**M1 — Toolchain and two-place project** ✅
Finished 2026-09-10. Foreman/Rojo/Wally/luau-lsp toolchain mirroring `~/square`. Two Rojo projects (`lobby.project.json` on port 34872, `gameplay.project.json` on port 34873, each pinned to its place id) sharing `src/shared`, `src/server`, `src/client`, with per-place `src/lobby` and `src/gameplay` folders. `analysis.project.json` feeds `scripts/analyze.sh`. Both places synced into Studio and played with boot lines and no errors. `.gitignore`, `README.md`, and `CLAUDE.md` seeded; non-adopted reference standards listed at the bottom of `CLAUDE.md`.

**M2 — Core shared libraries and coding standards** ✅
Finished 2026-09-10. Ported `Enums` (with GDD-seeded enums), `utils`, `Validate`, `Tags`, `Attributes`, `NetEventNames`, and an extended `Constants`, all generic and `--!strict`. GameData lives in `src/server/GameData` (server-only, in git), seeded with `Control/Difficulty`; LSP stubs cover it. Conventions and the object/item recommendation (skip `Item`, port the definition registry at M25 as `EntityType`) are in `CLAUDE.md`. Flagged: GDD says both "Brutal" and "Nightmare" for the top difficulty.

**M3 — Test suite runnable from Studio** ✅
Finished 2026-09-10. jest-roblox 3.10.0 via Wally dev-dependencies, committed in `DevPackages/`. `src/tests/TestRunner.luau` (square's Edit-mode workarounds) and `src/tests/shared/*.spec.luau` are mounted at `ServerScriptService/Tests` in both places and in `analysis.project.json`. Four specs (`utils`, `Validate`, `Enums`, `Constants`), 56 tests, green from the Studio Command Bar; Claude runs them through the Studio MCP and reads the Output. Run line documented in `CLAUDE.md` and `README.md`.

**M4 — Single RemoteEvent message bus** ✅
Finished 2026-09-10. `NetManager` creates the one `RemoteEvent` in code and runs the receive pipeline (rate limit → Ready check → known name → `Validate.isTableShape` → pcall handler) with throttled rejection warnings; per-player `TokenBucket` (unit tested) tuned by `GameData/Control/Network`. `ClientNetManager` mirrors it with loud unhandled-name warnings. `GameController` assembles handlers from `getNetHandlers()` owners. Feedback channel kept inside the one-RemoteEvent rule: `PlayerFeedbackManager:give()` sends `NotifyPlayerFeedback`; `ClientPlayerFeedbackManager` also owns the `GivePlayerFeedbackLocal` BindableEvent and prints until the M9 ScreenGui listens. Verified in Play: good/bad/unknown messages in both directions. Analyzer now reports only colon-method self-inference errors (ignored by decision); consider filtering that class in `scripts/analyze.sh`.

**M5 — Dev tools and group-gated access** ✅
Finished 2026-09-10. Iris 2.5.1 via Wally (`Packages/`, committed). Server `DevTools` handles `TryDevTool` against the `DevToolCommands` allowlist and re-checks admin per message; admin = rank ≥ 254 in group 571203718 (group-page roles, not Creator Hub collaborators), stamped as the `IsAdmin` Player attribute. `ClientDevTools` Iris panel (RightShift / triple-tap) with Players, Icon Framing, test feedback, and confirm-gated reset. Reset contract mechanism (`PLAYER_READY_SEQUENCE` / `PLAYER_TEARDOWN_SEQUENCE` in `GameController`) established, empty until M6. Icon capture pipeline ported with Windows replacements: `docs/icon-capture.md`, `scripts/capture_studio_window.ps1` (PrintWindow), `scripts/process_icon.sh` (ImageMagick 7, installed via winget). Verified in Play: non-admin refused; admin path handled valid/unknown/bad-args/reset commands. 8 suites / 75 tests. Lesson: stop `rojo serve` before `wally install` (Rojo 7.7 crashes).

**M6 — Player lifecycle and PlayerData** ✅
Finished 2026-09-10. ProfileStore vendored in `ServerLibs/` (mounted `Server/Libs`, excluded from analysis). `GameController.playerDatas` is the single lifecycle table (LOADING → READY → LEAVING → GONE); `getPlayerData` returns nil unless READY and fences NetManager and DevTools. `PlayerData` owns the live record and profile; the save shape, defaults, and repair rules are the pure shared `PlayerSaveSchema` (cash, ownedUnlocks set, loadout by `Enums.LoadoutSlot` name with WEAPON/POST/DEFENSE_1..3, completions keyed by `CompletionKeys` "MAP/DIFFICULTY", dailyReward, sessionMeta). XP/level dropped from the design. Tuning in `GameData/Control/Player` (store `DigDefendPlayerData_v1`, starting Cash 0, 30 s load timeout). Reset dev tool now wipes the save and overwrites the live profile; `setCash` dev command added. Verified against the real DataStore (Studio API access enabled): Cash survived a rejoin, sessions and playtime accumulate, reset wrote defaults; 3-client Test-tab stress run saved all three fake players on leave with no session locks left and no errors. 10 suites / 89 tests.

**M7 — Client data folders** ✅
Finished 2026-09-10. `SplendidReplicationManager` builds the `SplendidGames` ScreenGui at Ready (first entry of the ready sequence): `GameMetadata` (ServerStartTime, SchemaVersion, PlaceKind), `AllPlayers` (UserId, DisplayName, IsReady per Ready player; balances and flags private by decision), `CurrentPlayer` (Cash, IsAdmin, five loadout slot attributes, daily reward progress, `OwnedUnlocks` and `Completions` marker folders). Attribute sets come from shared `PlayerPublicSchema` (unit tested). `replicate*` methods are the only write path after a PlayerData mutation; reset rewrites the tree in place. `ClientDataManager` (awaitReady, typed reads, attribute/marker/AllPlayers listeners) gates `main.client`; dev tools read IsAdmin and the Players window from the tree. Verified: live Cash listener, reset in place, and a 3-client Test-tab run where every client's AllPlayers showed all three entries with only public fields and dropped a leaving player. 11 suites / 94 tests.

**M8 — Lobby map skeleton and spawn** ✅
Finished 2026-09-10. Studio-authored (via MCP) Workspace folders `SpawnZone` (platform, four SpawnLocations, sign), `HelicopterPads` (six `Pad<n>` models with `PadIndex` attribute, `JoinCollision`, `ExitSpawn`, `HelicopterSpawn`, `CameraPositionPart`, `GuiPart.PadGui`; the designer rebuilt Pad1's slab as a `Pad` model and authored the four-label `PadGui`, then pads 2–6 were cloned from it), `Store` (shell + empty `Items`), `EventArea` (fenced, "Coming Soon" sign), `HoldingArea` (sealed room at y=-120 with six `Spawns`). `ReplicatedStorage.GameAssets` created with a placeholder `Helicopter` template (`PlayerSpawns` x6). Third-person camera via StarterPlayer. Lobby-only `LobbyMapManager` (`src/lobby/server`, started by the lobby `main.server`) validates the whole tree at startup and warns per missing piece; names in `Constants`. Decisions recorded on M11 (pad config in GameData, `PadIndex` only on the model) and M12 (billboard colors). Place published by the designer.

**M11 — Party config and pad state** ✅
Finished 2026-09-11 (built out of order, before M9/M10, because the pad redesign landed first; nothing in it depends on them). Redesigned 2026-09-11 (see `docs/helicopter-pad-party-spec.md` and the GDD "Helicopter Pads – Party Creation/Teleports" section): pads are no longer pre-assigned to a map and difficulty. All six pads are identical; the first player onto an idle pad becomes the host and configures map, difficulty, party size, and Public/Friends Only visibility (Dead Rails' Create Party flow, no join-by-code). Pad models stay as built in M8 (`PadIndex` attribute, `HelicopterSpawn`, `CameraPositionPart`, `GuiPart.PadGui`, `JoinCollision`, `ExitSpawn`; helicopter template in `GameAssets` with `PlayerSpawns`). `GameData/Pads/Party` holds `CREATION_TIMEOUT`, `BOARDING_TIMEOUT`, `CAPACITY_TIME`, `MAX_PARTY_SIZE`, `DEFAULT_MAX_PLAYERS`, `DEFAULT_VISIBILITY`, and the ordered map and difficulty lists with requirements as `Enums.Map` / `Enums.Difficulty` references, validated at startup (unique ids, requirements resolve, timeouts positive, defaults in range). `Enums.PadState` (`IDLE`, `CONFIGURING`, `BOARDING`, `DEPARTING`) and `Enums.PartyVisibility` (`PUBLIC`, `FRIENDS_ONLY`). Server `PartyManager` owns one Lua party record per pad (state, host, settings, ordered member list, timer end time) and replicates state, host, map, difficulty, max players, visibility, member count, and departure server-time as attributes on the pad model. The pad billboard (`GuiPart.PadGui`, re-authored for the four states: "Open", "Setting up…", configuration + count + friends-only icon + countdown, "Departing") renders from those attributes; countdowns are computed client-side from the replicated end time, never ticked over the network. Pure unlock and validation rules unit tested. The `Timer` label was added to every `PadGui` in Studio (PlayerCount shrunk to make room); `LobbyMapManager` requires all five labels. Playtested by driving pad attributes by hand; all four billboard states verified.

**M9 — Arrival loading screen and feedback text** ✅
Finished 2026-09-11. Lucky Squares pattern: `src/first/loading.client.luau` (ReplicatedFirst, no requires) shows the Studio-authored `Loading` ScreenGui on frame one and removes the default screen; `ClientLoadingScreenManager` takes over via the `LoadingHandoff` attribute, fills the bar in stages from `main.client` (save, world, assets via `PreloadAsync` on `GameAssets`, systems), shows retry/slow-connection captions from `LoadStatus`, holds a minimum visible time, and tweens off. `PlayerFeedback` ScreenGui (`FeedbackBox.Message`) driven by `ClientPlayerFeedbackManager`; a newer message replaces the current one. Both GUIs are built by `scripts/studio/build_*.luau`, which must be replayed in the gameplay place when it is first opened (M14). Title image is a text placeholder until art exists; colours and fonts provisional until M10. Layout standard (scale + aspect/size/text-size constraints, offset only for hairlines) decided here and recorded in CLAUDE.md; both GUIs rebuilt to it. GUI standard (goal: identical intended appearance on every device type) recorded in CLAUDE.md; Device Emulator pass deferred to M10 when all three screens are restyled together.

**M10 — Lobby HUD** ✅
Finished 2026-09-11. `HUD` ScreenGui (built by `scripts/studio/build_hud_gui.luau`): `CashWallet` (tap opens the store currency tab at M35), `LoadoutStrip` with five slot frames carrying the `LoadoutSlot` attribute, `MenuButtons` (Store, Loadout, Daily Rewards; "Coming soon" feedback until their menus exist). Lobby `ClientHudManager` flashes Cash green/red with the `CoinsAdded`/`SaleSuccess` sounds before updating, renders slots from the loadout attributes, and slides all three groups off screen on overlay begin. Common `ClientOverlayManager` (Lucky Squares: one overlay, blur, click-catching backdrop, frozen character, FOV nudge, deferred while loading) and `ClientSoundManager` (plays designer-authored `AudioPlayer`s under `SoundService.Sfx`/`Music`; names in shared `SoundNames`; warns once for empty assets). Shared `UiStyle` (Poppins Bold ALL CAPS titles, Montserrat body, palette, timings, text bounds) recorded in CLAUDE.md; Loading and PlayerFeedback rebuilt to it. Dev tools gained "Toggle test menu (overlay)" as the stand-in menu until M35. Sound asset ids are empty until the designer can upload; source files in `audio/`. SoundService structure must be mirrored in the gameplay place (M14). Designer confirmed the look and the Device Emulator pass on 2026-09-11. Still owed: sound asset ids once the designer has upload permission (source files stay in `audio/` as the archive of record).

**M12 — Host, configure, join, and leave** ✅
Finished 2026-09-11. Touching `JoinCollision` on an idle pad seats the toucher in the pad's helicopter (cloned from `GameAssets` at startup, one per pad), moves the camera to `CameraPositionPart`, and opens the `CreateParty` menu (map and difficulty carousels with locks and requirement text, players stepper, Friends Only toggle, "Cancelling in N seconds", Create disabled while locked, Cancel). `TryCreateParty` carries the whole selection, validated against the host's completions server-side; on success the pad boards, the boarding timer starts (20 s, decided 2026-09-11), and the `Queue` menu opens in host mode (Launch) or member mode (Exit). Join checks, full-party timer clamp (never rises), host promotion, seat-leave and disconnect handling are in `PartyManager`; pure rules and the config codec in `PartyRules` (unit tested). Place managers register net handlers and teardown through `GameController:registerPlaceManager`; the party config reaches clients as one JSON attribute on `GameMetadata`. Party menus hide the pad billboards and lock jumping; the seat is left only via Exit or Cancel. The rotor (`Rotar.Rotar`, blades welded) spins client-side while Boarding or Departing (`ClientHelicopterManager`). Launch is stubbed until M13 (timer expiry or Launch press empties the pad). Studio fixes found in playtest: `JoinCollision` parts were unanchored and fell out of the world at Play (now anchored, validator warns), `CameraPositionPart`s faced away from the helicopter, helicopter seats are real `Seat`s kept `Disabled` so the engine never auto-seats a passer-by. Multi-player paths (join checks, friends-only, promotion) are implemented but were only exercised solo.

**M13 — Launch and teleport** ✅
Finished 2026-09-11. Launch on host Launch press, boarding timeout, or capacity countdown (a party of one fills at Create and launches after `CAPACITY_TIME_SEC`). `PartyManager:runLaunch`: Departing, `TAKEOFF_SEC` wait, members unseated and moved to random `HoldingArea.Spawns`, `ReserveServer` + one `TeleportAsync` with the member list (the deprecated party call is not used), retried `TELEPORT_RETRY_COUNT` times; final failure respawns each member in `SpawnZone` with "Teleport failed" and restores their menu and camera; stragglers after `TELEPORT_SETTLE_SEC` get the same; the launched helicopter is renamed `DepartedHelicopter` (destroyed after its lifetime) and a fresh one cloned, pad to Idle. Join data (`PartyRules.buildJoinData`) carries map, difficulty, actual player count, host, pad index, and member ids; the gameplay place's `ArrivalGateManager` kicks arrivals that are not listed (warn-only in Studio). Client (`ClientHelicopterManager`, every client): departed helicopter climbs 100 studs then cruises 1000 studs along its facing and is removed; rotor resolved lazily against streaming and the helicopter template set to Atomic streaming after inconsistent spins. Party members see the Queue menu fade while the camera stays on the pad, then after 2 s the `Loading` ScreenGui in departure mode ("Flying to <map>...", reused for now, may change). Gameplay place synced with Rojo for the first time and published; the designer confirmed a live lobby-to-gameplay teleport. Studio-only verification covered the failure path (Studio teleports always 403).

**M14 — Gameplay place arrival** ✅
Finished 2026-09-11. Gameplay `RunManager` records the first valid join data as the run (map, difficulty, player count, host, member ids) and replicates map/difficulty/count/host as `GameMetadata` attributes; `ArrivalManager` (replaces the M13 gate) kicks arrivals not in the party (warn-only in Studio), places characters on the designer's `Camp.HelicopterPad.Spawns` parts 1-6 in arrival order, spawns the camp helicopter at `HelicopterSpawn` with the rotor turning, and flies it off 3 s after every expected member is Ready (or 45 s after the first arrival); tuning in `GameData/Run/Arrival`. `GameplayMapManager` validates the camp tree. Helicopters became one system for both places: common server `HelicopterManager` clones, tags (`Tags.HELICOPTER`), and sets `Enums.HelicopterPhase`; common `ClientHelicopterManager` animates every tagged model; the lobby maps pad states to phases. `GameController:registerPlaceManager` now also admits `onPlayerReady`; `DevTools:registerPlaceCommand` and `ClientDevTools:addMenuSection` let places add commands, used by the gameplay "Return to lobby" dev tool (`RunDevTools` / `ClientRunDevTools`) for round trips. Dev windows free the mouse (first person locks it). First person via `StarterPlayer.CameraMode` (in `gameplay.project.json` and set in Studio). The departure screen is handed to `TeleportService:SetTeleportGui` and the ReplicatedFirst bootstrap keeps the arriving copy, so no Roblox loading screen shows and the bar (empty during the flight) fills once on arrival. Gameplay place: Loading and PlayerFeedback GUIs replayed, SoundService `Sfx`/`Music` mirrored, published. Designer confirmed the live round trip: launch, arrive on spawn 1 in first person, helicopter leaves, return to lobby.
