# Balance plan

Status: tuned in the model, 2026-09-28; awaiting the logged playtest. Written after the first playtest pass (commit 63fcb5a) and a research pass on balance methodology, Dome Keeper, and tower defense wave design.

## Where the numbers stood before

Facts from a full read of `GameData` and the gameplay managers on 2026-09-28, before any change.

- Normal's Deadman's Canyon generator was 18 / 18 / 12% (start, increment, growth), the designer's tuned curve. Hard (14 / 5 / 15%) and Nightmare (18 / 6 / 18%) predated it and were **easier than Normal on every night**. The GDD and the file header still described 10 / 4 / 12%.
- Crew size was applied to waves twice: the wave budget multiplied (1.0 to 3.5) and every monster's HP multiplied (1.0 to 1.5). Four players faced 3.25x solo enemy HP while fielding 4x free weapon DPS, 4x the tower cap, and about 5.8x solo Iron and Gold income.
- Difficulty entered through four tables that were never reconciled: the generator settings, `VEIN_DIVISOR`, `URANIUM_TARGET_MULTIPLIER`, and `DIFFICULTY_VALUE` (passed to the mine generator, no effect because `HARDNESS_SHIFT` is 0).
- Nights 1 to 3 solo were about 1,000 HP each, cleared by the free rifle and one post with no towers. Iron had no purpose until night 4.
- Late nights outgrew the defense ceiling: five level 5 Sentries gave about 267 DPS for 1,275 Iron; night 12 on Normal was about 17,600 HP with Launchers and Titans that one-shot any tower.
- Sinks were shallow. Every refinery rate was 1:1.
- Nights are open-ended (end when the last monster dies); the sky's 90 s night and the 60 s spawn window are unrelated numbers.

## What the research says

Full source list at the end. The rules adopted:

1. **Budget waves, difficulty as parameter rows.** Deep Rock Galactic and Risk of Rain 2 keep tiers monotonic by putting each difficulty in one row of one table and never mixing axes. The audit tests that every night of a harder difficulty is at least the easier one's, up to the easier one's target night.
2. **One axis per lever.** Player count scales monster *count* through the wave budget, difficulty scales the *curve*. Never both count and HP by player count (Serious Sam's compounding trap, Dome Keeper's co-op "player-hostile" complaints).
3. **Sub-linear crew scaling.** Survivors of the crew-scaling wars: DRG (solo = duo, then roughly linear), RoR2 (1 + 0.3 per extra player), Dome Keeper versus (1.0, 1.6, 2.08, 2.39, 2.57, 2.66). Linear per-head scaling failed in Helldivers 2 and Dome Keeper co-op.
4. **Income is linear, so sinks must be repeatable or growing.** Dan Cook's value chains: a trickle source must feed repeatable or exponential sinks, and for a fixed-length game the sum of sources and sinks over the run must match, sinks slightly larger so nothing pools.
5. **Spreadsheet the whole run.** Schreiber: draw the player power curve and the threat curve on one chart, aim for a sawtooth. Goal Defense: a wave's total HP equals seconds under fire times effective DPS with 1.2 to 1.5 slack. Decide target nights per difficulty first, derive the uranium target from modelled income, not the reverse.
6. **Tower economy.** A day's Iron should buy about one new tower or one meaningful upgrade, never both comfortably. Upgrade tiers 1 to 3 cheap side-grades, tiers 4 and 5 commitments that are worse per Iron and justified only by the cap. Range and slows are priced by time on target.
7. **Introduce one kind at a time in an otherwise easy night, then spike it 3 to 5 nights later.** BTD6 and Kingdom Rush both do exactly this.
8. **Push your luck** (Dome Keeper's per-resource wave term): declined by the designer on 2026-09-28, it punishes mining well.
9. **Final wave about 3x** in Dome Keeper (nerfed from 4.5x); ours is 1.35x because the night after the target is already a step up and a crew fights it with that day's defenses.
10. **Travel time, not fight length, is the pacing complaint.**

## The designer's targets (2026-09-28)

- A full Normal run is 75 minutes: 10 nights plus the rescue wave. Hard 90 minutes (12 nights), Nightmare 110 minutes (14 nights).
- Night 1 is survivable with a handheld; night 3 is the first that gets a little difficult. Refined after the second playtest (2026-09-28): on Normal, night 2 should damage a wall but not break one, night 3 should come close, night 4 should breach. Hard and Nightmare breach on night 3.
- The machine-gun post is the yardstick for player damage; its overheat is the main limit.
- From the third playtest (2026-09-28): players should hold about 10 Gold by the end of night 1 and afford one mining or post upgrade a day; Iron and uranium felt abundant (three towers by night 1, uranium found by its hum); twice the pockets; towers capped at 12 per camp.
- For the fourth playtest (2026-09-28): every camp-level gate removed for testing (the originals are recorded in `GameData/Camp/Level` and in memory).
- **The mine is a simulator** (decided 2026-09-28): small numbers first, every upgrade a jump, big numbers by the end. Five levels stay. Each pick axe level triples the last and costs three times as much; backpack the same; rock HP triples a tier so the deep mine is a wall until the pick has been earned; Gold and Diamonds per rock quadruple a tier so the deeper the crew digs the faster they arrive. Only the mining loop ramps (option 1): Iron per rock triples with the rock so the tower budget stays level, and uranium stays one per rock so the rescue counter stays achievable. Night-1 Gold target 20.
- Hard and Nightmare bring Runners, Bombers, and Brutes on night 2, which break a wall whatever the budget, so their breach night is 2 (Normal stays 4).
- The fifth playtest (2026-09-28, solo Normal, won on day 4): pick 2 on day 1, backpack and boots 2 on day 2, pick 3, backpack 3, boots 3 and five post upgrades on day 3 (about 300 Gold that day), 40 uranium by day 4, no wall lost before the final wave. The model was under-reading mining by about 2.5x and uranium by more; its assumptions were refitted to that log. Decision: get Normal right first; Hard and Nightmare lengths are adjustable later.
- A crew game should take the same number of nights as a solo game.
- No push-your-luck term.
- Nights stay open-ended: the night ends when every monster is dead.
- The tower cap is a camp total divided among the living players.
- Hard and Nightmare: the comparable titles' pattern, the same curve started higher with the strong kinds earlier; longer runs through the uranium target.
- The run is lost when everyone is dead or the Refinery falls, rescue called or not.
- From the first playtest: night 4 first felt dangerous; Iron was the resource that felt scarce; the fortification pool did not scale with the crew.
- The refinery stays 1:1.

All of these live in `GameData/Control/Balance` (targets) and are checked by the audit.

## What was built

- **`BalanceModel`** (shared, pure, 32 tests): a run on paper. Every day the crew swings for what is left after a fixed overhead and the backpack trips (each load walks from the tunnel front, which deepens through the run, to the refinery and back at the boots' speed, so the swinging share of the day falls from about 190 s on day 1 to about 110 s by night 10), the HP it chews through becomes ore at the current zone's ore-per-HP (uranium hunted harder, since it hums; gold taken as it comes), the ore refines, Gold is split across pick axe, backpack, boots, and post upgrades, Iron buys the towers with the best DPS per Iron up to the camp cap; every night the generator's budget becomes expected HP from the kinds unlocked and is measured against the crew's free weapons plus its towers. Also the final wave a rescue on each day would bring, and the leak: each spawn group is shot from the moment it appears, whatever survives the walk beats on the wall until it is killed, and that damage is spread over about three segments. The second playtest calibrated it: 13 zombies on night 1 held, 4 zombies and 10 runners on night 2 broke one wall, two groups with bombers on night 3 broke two walls and the gate. Checks: monotonic difficulty, survivable to the target night, final wave holdable, the wall progression (dent, near-break, breach on the chosen nights), uranium refined on the target day, crew parity with solo.
- **`GameData/Control/Balance`**: the targets above and the model's `ASSUMPTIONS` about how people play. The assumptions are the model's guesses, to be corrected from run reports, never from the data they check.
- **`BalanceAudit`** (gameplay server): the only code that knows where the model's numbers come from. Runs every audited map and difficulty at crews of 1, 4, and 6 at gameplay startup and warns per missed target. The Monsters dev panel's "Balance sheet (Output)" prints the full table for the current run and every miss.
- **`scripts/studio/balance_sheet.luau`**: prints the sheet in Edit mode without a Play session, through a substitute require.
- **Camp tower cap** (`TowersData.MAX_ACTIVE_TOWERS_CAMP`, `PlacementRules.towerAllowance`): each player may hold `ceil(camp / crew)`, the crew being the count sampled at dawn, so a leaver's share opens the next morning. The build bar shows the allowance.
- **Uranium's own vein divisor** (`DifficultyData.URANIUM_VEIN_DIVISOR`, `GeneratorConfig.uraniumVeinDivisor`): a harder difficulty thins uranium too. The generator still refuses a mine whose thinned supply is under the worst-case target.

## What changed, and why

| Table | Before | After | Why |
|---|---|---|---|
| Waves DC Normal | 18 / 18 / 12% | 24 / 12 / 10% | with the refitted model: night 1 dents (58%), nights 2 and 3 about half a wall, night 4 breaks one; night 10 margin 2.9, final wave 2.0 |
| Waves DC Hard | 14 / 5 / 15%, own unlock list | 28 / 26 / 6%, Normal's unlocks 2 nights earlier | above Normal through Normal's target night; night 2 breaks a wall; provisional until Normal feels right |
| Waves DC Nightmare | 18 / 6 / 18%, own unlock list | 30 / 26 / 6%, Normal's unlocks 4 nights earlier | above Hard through Hard's target night; night 2 breaks a wall; provisional |
| Waves Frostbite | 10 / 4 / 12% everywhere | Deadman's Canyon's three curves | placeholder until authored; excluded from the audit |
| Enemy HP by crew | 1.0 to 1.5 | 1.0 everywhere | one crew lever, the wave budget |
| Wave budget by crew | 1.0, 1.5, 2.0, 2.5, 3.0, 3.5 | 1.0, 1.6, 2.1, 2.4, 2.6, 2.8 | shared cap plateaus a crew's towers; set so the biggest crew still holds Nightmare's final wave, which leaves crews more margin than solo on Normal |
| Uranium target by crew | 1.0 to 3.5 | 1.0, 2.5, 4.5, 8, 10, 12 | a crew strips every zone it passes and hunts uranium; four players hold eight times solo's uranium by day 10 |
| Uranium target by difficulty | 1.0 / 1.15 / 1.3 | 1.0 / 1.2 / 1.7 | Hard lengthens through the thinner supply alone; a solo Nightmare player who hunts by sound is barely slowed by thinning, so Nightmare needs the target too |
| Vein divisor | 1.0 / 1.2 / 1.4 | 1.0 / 1.1 / 1.05 | Iron is the binding resource; the old scarcity made Hard and Nightmare's final waves unholdable |
| Uranium vein divisor | (exempt) | 1.0 / 1.1 / 1.15 | the harder run's extra nights |
| DC mine iron, zones 1 to 4 | 22 / 22 / 22 / 16 veins | 16 / 16 / 16 / 12 | the third playtest built three towers by night 1; a tower a day, not three |
| DC mine gold, zones 1 to 4 | 20 / 22 / 22 / 20 veins | 34 / 34 / 34 / 26 | six Gold in four days; gold now ahead of iron near the entrance |
| DC mine uranium, solo target 40 (was 30) | 6 / 9 / 9 / 111 | 9 / 14 / 20 / 950 | it hums, so it is found fast; zone 4 is a big crew's supply and covers the Nightmare six-player worst case after thinning |
| DC mine pockets | 2 / 3 / 4 / 5 | 4 / 6 / 8 / 10 | twice the open spaces to discover |
| Ore vein size | 1 to 7 blocks (radius 0 to 1), crystal 7 | single blocks, with four times the iron and gold veins and six times the crystal | one seven-block Gold II vein was a whole day of Gold; more, smaller finds |
| Entrance clearance | 0 | 4 blocks | no ore visible from the entrance before the first swing |
| Ore tier depth floors | none (a zone rolls its tier mix, anywhere in the zone) | tier 2 from 14 blocks in, tier 3 from 44, tier 4 from 68; within a zone, tiers above its bias sit in the back half | a Gold II vein a few blocks in let a player buy three upgrades on day 1; ore now climbs with the depth |
| Camp-level gates | mining rungs 3 to 5, post levels 2 to 4, capstone, fortification tiers | none (for testing) | a run whose first crystal was out of reach locked every Gold sink; originals kept |
| Pick axe damage by level | 5 / 12 / 25 / 50 / 100 | 5 / 15 / 45 / 135 / 400 | each level triples |
| Backpack capacity | 15 / 25 / 40 / 60 / 90 | 15 / 45 / 135 / 400 / 1,200 | each level triples |
| Boots speed | 16 / 18 / 20 / 22 / 24 | 16 / 20 / 24 / 28 / 32 | twice the step |
| Jet pack fuel per level | 0.5 s | 1 s | twice the step |
| Mining upgrade prices | pick 15 / 40 / 100 / 250 and the rest | pick 30 / 90 / 270 / 800, backpack and boots 20 / 60 / 180 / 540, jet pack 40 / 120 / 360 / 1,080 | tripling with the effect; the price is the brake |
| Stone HP by tier | 10 / 20 / 40 / 80 / 160 | 10 / 30 / 90 / 270 / 810 | triples with the pick |
| Ore rock HP by tier | iron 15 / 30 / 60 / 110 and similar | iron 15 / 45 / 135 / 405, gold 20 / 60 / 180 / 540, crystal 30 / 90 / 270 / 810 | triples |
| Gold per rock by tier | 3 / 10 / 30 / 87 | 3 / 12 / 48 / 192 | quadruples a tier; halved back after the fifth playtest bought three upgrades a day |
| Diamonds per rock by tier | 2 / 5 / 14 / 39 | 2 / 8 / 32 / 128 | quadruples |
| Iron per rock by tier | 3 / 10 / 29 / 78 | 3 / 6 / 12 / 24 | doubles a tier, under the rock's HP, so a bigger pick in deeper rock does not flood the tower budget |
| Tower build and upgrade prices | 30, 15/30/60/120 (Sentry) and up | 20, 10/20/40/80 and up | back to two thirds; a day's Iron buys a tower or an upgrade |
| Tower cap | 5 per player | 12 per camp, shared | designer's answer |
| Final wave multiplier | 1.5 | 1.25 | holdable on the target day with that day's towers under the 12 cap |

| Monster point costs | HP-ish: Runner 6/12/18, Bomber 12/24/36, Flyer 25/50/75, Launcher 50, Titan 100/200 | HP / 50 x speed / 10 x ability: Runner 5/11/16, Bomber 6/12/18, Flyer 16/32/47, Launcher 36, Titan 75/150 | a budget's HP is predictable (17 to 50 HP a point instead of 8 to 50); abilities are gated by unlock night, as the genre does |
| Zombie damage by tier | 10 / 10 / 10 | 10 / 15 / 20 | tiers climb |
| Machine-gun post | 12 damage, 3 s of fire before overheating (60 DPS sustained) | 15 damage, 4 s (85 DPS) | a post is a stationary, exposed commitment; it must out-shoot the rifle's 55 |
| Rocket post | 150 damage every 6 s | 200 | 33 DPS to one target, about a hundred into a group |

Post upgrades (four levels of damage and of fire rate for 15 / 30 / 60 / 120 Gold each, camp-level gated) are unchanged but now in the model: a player puts 30% of their Gold into them, and by night 10 a solo post is about 2.5x its base. The rifle is unchanged. Frostbite Pass's mine also took Deadman's Canyon's ore counts, so the placeholder map is at least the same game.

## Where the model says we are

Deadman's Canyon, model output on 2026-09-28 (the simulator pass, with backpack trips in the model). "Reached" is the day the uranium target is refined; slack is the crew's DPS over what the night needs to be cleared within the spawn window plus 60 s; final is the same against the rescue wave a call on the target day would bring; the wall columns are the leak's expected damage to the most-hit wall segment as a share of its HP.

| Difficulty | Crew | Target night | Reached | Slack at target | Final wave | Wall night 1 / 2 / 3 / 4 | First breach |
|---|---|---|---|---|---|---|---|
| Normal | 1 | 10 | 10 | 2.90 | 1.99 | 58% / 47% / 51% / 174% | night 4 |
| Normal | 4 | 10 | 10 | 3.27 | 2.18 | none | never |
| Normal | 6 | 10 | 10 | 4.26 | 2.84 | none | never |
| Hard | 1 | 12 | 12 | 1.83 | 1.30 | 0% / 131% / 343% / 48% | night 2 |
| Hard | 4 | 12 | 11 | 2.82 | 2.00 | none | never |
| Hard | 6 | 12 | 10 | 3.21 | 2.27 | none | never |
| Nightmare | 1 | 14 | 13 | 1.56 | 1.10 | 72% / 203% / 110% / 19% | night 2 |
| Nightmare | 4 | 14 | 11 | 2.11 | 1.49 | none | never |
| Nightmare | 6 | 14 | 10 | 2.35 | 1.66 | none | never |

Solo Normal day 1 in the refitted model: 19 Iron and 39 Gold; 149 Gold by the end of day 3; about 780 Gold a day by day 10; Iron 19 to 95 a day. Pick 2 on day 3, pick 3 on day 6, pick 4 on day 9; uranium 40 on day 10. Crews and the harder tiers are out of date in this table until Normal is confirmed in play; the audit lists them.

After the first breach night the walls hold in the model because towers come online; the leak columns go to 0.

With backpack trips in the model, crews slow down as much as solo players do, and every crew row is on target. The remaining misses are in the audit's startup line. Crews never leak in the model (their posts out-shoot the early nights), so the wall progression is a solo target only.

## Open items

1. **Gold visibility.** The third playtest broke about two gold rocks to twenty iron in a mine that holds gold at 60% of iron near the floor. Check the gold rock template reads as ore at mining distance before trusting the Gold numbers.
2. **Crew pacing on Hard and Nightmare.** A crew of four or more strips the mine, so its uranium is capped by the thinned supply, not paced by it; any target inside that cap is reached about day 10 to 11 whatever the difficulty, and a target near the cap is brittle. Levers tried: thinner uranium (helps solo, barely moves crews), a bigger supply (crews find a share of what is left, so more supply is found faster). Candidates not yet tried: a per-difficulty crew table for the uranium target, or a slower crew advance on harder rock (the GDD's hardness knob, off by decision). Decide after the logged playtest.
3. **The run report dev tool** (Step 1 of the plan, not built yet): at each dawn log Iron / Gold / Diamonds / Uranium refined per player, refinery trips and their length, towers built and upgraded, night clear time, wall and refinery damage; print a table at run end. Its purpose is to calibrate the `ASSUMPTIONS`, above all `ZONE_ADVANCE_SHARE`, `DAY_OVERHEAD_SEC`, `ORE_SELECTIVITY`, and `URANIUM_SELECTIVITY`.
4. **Crews lean on posts.** A crew never breaches a wall in the model and keeps a margin of 4 or more on Normal's target night. With six posts and Gold to spare, a crew's manned posts carry it to night 8 or later before a tower is needed on Normal, and its margin at the target night is well above solo's. The wave table could go higher on Normal alone if a per-difficulty crew table is ever wanted; today one table serves all three.
5. **Sinks.** Nothing new was added; the model treats 80% of Iron as tower spend. The fortification pool still costs the same for one player as for six. Tower kinds were not balanced against each other (Flamethrower and Sniper are about half a Sentry's DPS per Iron on paper; range, cone, slow, and stun are unpriced).
6. **Frostbite Pass** is a copy of Deadman's Canyon's numbers and is excluded from the audit (`AUDITED_MAPS`) until authored.
7. **Records to update at close-out**: `gdd.txt` sections Difficulty, Party scaling, Wave Cycle (final wave), Defenses (camp cap), Randomized Mine Creation section 7 (uranium divisor) and the Deadman's Canyon example; `milestones.md`'s stale wall HP, repair, and uranium notes; the M29 header comment in `Waves/DeadmansCanyon` was rewritten.

## Assumptions to calibrate

All in `GameData/Control/Balance.ASSUMPTIONS`, with what set each: `MINING_SHARE_OF_DAY` 0.55 (guess); `ORE_SELECTIVITY` 1.5 (guess); `URANIUM_SELECTIVITY` 2.0 (guess, it hums); `ZONE_ADVANCE_SHARE` 0.15 (guess, tunnelling); `CREW_ADVANCE_EXPONENT` 0.6 (guess); `TOWER_COVERAGE` 0.6 (guess); `WEAPON_UPTIME` 0.5 and `POST_EFFECTIVENESS` 0.6 (together they put the second playtest's night 2 breach and night 1 hold where they were seen); `ORE_SELECTIVITY` 2.5, `GOLD_SELECTIVITY` 2.0, `URANIUM_SELECTIVITY` 10, `DAY_OVERHEAD_SEC` 40 (all four fitted jointly to the fifth playtest's log: about 370 Gold by the end of day 3, 35 Iron by day 2, 40 uranium by day 4, pick 3 on day 3); `WALL_WALK_SEC` 20 (map estimate); `WALL_SEGMENTS_HIT` 3 (second playtest's night 3); `CLEAR_SLACK_SEC` 60; `DEFENSE_IRON_SHARE` 0.8; (`DAY_OVERHEAD_SEC` was 75 before the fit); `REFINERY_TO_ENTRANCE_STUDS` 64 (measured on the map); Gold shares pick axe 0.4, backpack 0.25, boots 0.1, post 0.25; `TOWER_NEEDED_SLACK` 1.75 (now informational).

Not modelled: overflow ore dropped on the ground, the jet pack, dynamite, torches, player death, the Refinery's own HP, trap purchases, and the walk to a post at dusk.

## Playtest protocol

Three logged runs: solo Normal, four-player Normal, solo Hard. Compare the run report to the sheet, correct the assumptions where the report disagrees, retune, and only then close.

## Sources

Methodology: Schreiber, Game Balance Concepts levels 2, 3, 6, 7, 8, 10 (gamebalanceconcepts.wordpress.com); Dan Cook, Value Chains (lostgarden.com/2021/12/12/value-chains); Adams and Dormans, Machinations (gamedeveloper.com); The Math of Idle Games (gamedeveloper.com); Deep Rock Galactic difficulty scaling (deeprockgalactic.wiki.gg/wiki/Difficulty_Scaling); Risk of Rain 2 difficulty (riskofrain2.wiki.gg/wiki/Difficulty); Left 4 Dead difficulty; Helldivers 2 patrol scaling (pcgamer.com); 7 Days to Die party gamestage; Vampire Survivors co-op slots.

Dome Keeper: Relic Hunt, Technical Terms, Version History, Modifiers, Multiplayer (domekeeper.wiki.gg); Habermann interview (gamedeveloper.com/business/how-dome-keeper-focuses-on-systems-that-feed-into-one-another); Steam co-op scaling threads; Xbox Wire multiplayer announcement 2026-04-13.

Tower defense: Balance in TD games / Goal Defense (gamedeveloper.com/design/balance-in-td-games); PvZ wave points and budget formula (plantsvszombies.wiki.gg); BTD6 rounds and RBE (bloonswiki.com); Kingdom Rush campaign design (gamedeveloper.com); Sanctum 2 postmortem (gamedeveloper.com); Defender's Quest design (gamedeveloper.com); Tower defense economics (bigarcade.net); Loughran, Tower Defense Proof in Excel; Brian Davis, Balancing Your Game: A Formula-Driven Approach (GDC Europe 2016).
