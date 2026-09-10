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

## Phase 1: Infrastructure and Project Scaffold

**M1 — Toolchain and two-place project**
Foreman/Rojo/Wally/luau-lsp setup mirroring `~/square`. Two Rojo projects (or one project with two place roots) for the Lobby place and the Gameplay place, sharing `src/shared`. Both places sync into Studio and run with an empty baseplate. `.gitignore`, `README.md`, and a `CLAUDE.md` seeded from the reference projects' standards. Flag anything from those standards that seems contradictory or inapplicable here before adopting it.

**M2 — Core shared libraries and coding standards**
Port `utils`, `Validate`, `Constants`, `Enums`, `Tags` from the reference games, stripped of game content. Decide and document: no abbreviations in names, colon methods for object methods, Luau types where the LSP copes, `GameData` module conventions (raw data, `SCREAMING_SNAKE_CASE`, `Data` suffix on requires). Decide whether the dragons/lights object/item system is worth porting given how little persists between runs; write the recommendation down.

**M3 — Test suite runnable from Studio**
Jest (via Wally, as in lights) plus a Studio test runner. A few tests against shared utilities so the pipeline is proven green before any game code exists.

**M4 — Single RemoteEvent message bus**
One `RemoteEvent` for all client/server traffic, dispatched by message name, with loud failure on a missing handler. Copy the lights pattern. Includes the `GivePlayerFeedback` remote and `GivePlayerFeedbackLocal` bindable so the feedback text system has a channel.

**M5 — Dev tools and group-gated access**
Iris dev tool panel, access locked to members of the company group. Reset-player-state dev tool contract established (any new per-player state must be covered by it). Screenshot-to-image-asset capture tool ported from lights if it still applies.

## Phase 2: Player Lifecycle, Persistence, and Lobby Shell

**M6 — Player lifecycle and PlayerData**
`PlayerLifecycle` enum (`Loading`, `Ready`, `Leaving`, `Gone`), single authoritative lifecycle table, ProfileStore-backed `PlayerData` as the sole owner of persistent state (Cash, owned items, loadout, map/difficulty completions, daily reward progress, level). `Validate` on every load. Join/leave stress test.

**M7 — Client data folders**
Server-created `SplendidGames` ScreenGui with `GameMetadata`, `AllPlayers`, `CurrentPlayer` folders; `CurrentPlayer` appearing is the client's ready signal. `ClientDataManager` with typed accessors and listeners. Both places use this.

**M8 — Lobby map skeleton and spawn**
Workspace folders `SpawnZone`, `HelicopterPads`, `Store`, `EventArea`, `HoldingArea` with placeholder geometry. Players spawn in `SpawnZone`, third-person camera. Event Area closed with a "coming soon" sign.

**M9 — Arrival loading screen and feedback text**
Arrival loading screen with title image and progress bar that fills as assets load and data is set up, then tweens off. `PlayerFeedback` ScreenGui listening on the M4 events with timed display.

**M10 — Lobby HUD**
Cash balance display with green/red flash and sounds on change, loadout slot strip (1 weapon, 1 post, 3 defenses, bonus slot at level 10), menu buttons for Store, Loadout, Daily Rewards. HUD hides when a menu opens. Establish the shared UI style (fonts, capitalization, layout rules) here and document it.

## Phase 3: Queues and Teleporting

**M11 — Helicopter pad models and config**
Pad model structure per the GDD (`MapNumber`, `DifficultyNumber`, `MaxPlayers`, `Boarding`, `HelicopterModel.PlayerSpawns`, `HelicopterSpawn`, `CameraPositionPart`, `GuiPart.PadGui`, `JoinCollision`, `ExitSpawn`). Six pads defined in a GameData module with map, difficulty, max players, and unlock requirements. Global `FullTime` and `CapacityTime`.

**M12 — Queue join, leave, and timer**
Touching `JoinCollision` checks requirements, seats the player in the helicopter, moves their camera, shows the Queue Menu with its exit button. Timer logic: starts at `FullTime` on first join, drops to `CapacityTime` when full, resets when empty. Pad billboard shows status, count, and seconds.

**M13 — Departure and teleport**
On timer expiry: status "Departing", helicopter takes off, departure loading screen fades in, characters moved to `HoldingArea` spawns, group teleport to a fresh reserved gameplay server with `playerNumber`, map, and difficulty in join data. Retry handling; failure respawns the player in `SpawnZone` with a "Teleport failed" message. New helicopter cloned and pad reopened. Gameplay server rejects players not in the reserved group.

**M14 — Gameplay place arrival**
Gameplay server reads join data, spawns players on the camp Helicopter Pad, first-person camera locked, initial loading screen that visually matches the departure screen. Solo pad-to-run round trip works end to end.

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
Uranium target per map/difficulty. Reaching it enables calling the rescue helicopter; final climactic wave spawns as it arrives; boarding the helicopter wins the run. Completion recorded in PlayerData to unlock pads.

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

**M38 — Cash milestones and skill level**
In-run milestone table awarding Cash, player level and XP, bonus loadout slot at level 10. Level-gated pads.

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
Hard and Nightmare tuning for both maps. Pad unlock chain verified end to end.

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

(none yet)
