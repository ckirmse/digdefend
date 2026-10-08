# Balance plan

Status: tuned in the model, 2026-09-28; waves raised after the sixth playtest, 2026-09-29; awaiting a logged playtest. Written after the first playtest pass (commit 63fcb5a) and a research pass on balance methodology, Dome Keeper, and tower defense wave design.

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

- A full Normal run was 10 nights plus the rescue wave until the sixth playtest (2026-09-29) found it too short: **Normal is 15 nights** now, Hard 18, Nightmare 20 (21 was asked for; see the 15-night pass below).
- Night 1 is survivable with a handheld; night 3 is the first that gets a little difficult. Refined after the second playtest (2026-09-28): on Normal, night 2 should damage a wall but not break one, night 3 should come close, night 4 should breach. Hard and Nightmare breach on night 3.
- The machine-gun post is the yardstick for player damage; its overheat is the main limit.
- From the third playtest (2026-09-28): players should hold about 10 Gold by the end of night 1 and afford one mining or post upgrade a day; Iron and uranium felt abundant (three towers by night 1, uranium found by its hum); twice the pockets; towers capped at 12 per camp.
- For the fourth playtest (2026-09-28): every camp-level gate removed for testing. On 2026-10-06 (M33) Camp Level, Crystal, and the in-run Diamond were removed from the game and the code in full; the lobby currency is now called Diamonds. The rows below that mention them are history.
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
| Waves DC Normal | 18 / 18 / 12% | 22 / 16 / 8% (24 / 12 / 10% until the sixth playtest, 24 / 16 / 8% for a day after) | the sixth playtest (2026-09-29) found the waves too soft while mining felt right, and asked for 15 nights: a bigger increment makes nights 2 to 5 harder (night 3 takes 99% of a wall, nights 4 and 5 breach) while less compounding keeps night 15 holdable (margin 2.0, final wave 1.4), since a solo crew's power plateaus at the tower cap and the last pick by night 13 |
| Spawn window and group gap (`WAVE_SPAWN_LENGTH_SEC`, `MAX_TIME_BETWEEN_GROUPS_SEC`) | 60 s, 10 s | 90 s, 30 s | the eighth playtest (2026-09-29, solo Normal, lost on night 8): two groups 10 s apart were one wave and the Refinery fell while the gunner was still on the first; a two-group night is now 0 and 30 s and a night's HP has 150 s instead of 120 s to be shot, which lifts every margin about a quarter with the wall progression unchanged |
| Group minimum (`MIN_GROUP_DIFFICULTY`) | 40 | 80 | doubled the same day: nights 2 to 5 now arrive as one group, and a single big group is what reaches and breaks a wall; night 10 is five groups instead of seven |
| Waves DC Hard | 14 / 5 / 15%, own unlock list | 28 / 33 / 3%, Normal's unlocks 2 nights earlier | above Normal through night 15; night 2 breaks a wall; holds its day-18 final wave (1.10); provisional until Normal feels right |
| Waves DC Nightmare | 18 / 6 / 18%, own unlock list | 34 / 42 / 2%, Normal's unlocks 4 nights earlier | above Hard through night 18; breaches night 1; its day-20 final wave is a hair short (0.99) and no curve above Hard's holds a day-21 one, so Nightmare is 20 nights and provisional |
| Waves Frostbite | 10 / 4 / 12% everywhere | Deadman's Canyon's three curves | placeholder until authored; excluded from the audit |
| Enemy HP by crew | 1.0 to 1.5 | 1.0 everywhere | one crew lever, the wave budget |
| Wave budget by crew | 1.0, 1.5, 2.0, 2.5, 3.0, 3.5 | 1.0, 1.6, 2.1, 2.4, 2.6, 2.8 | shared cap plateaus a crew's towers; set so the biggest crew still holds Nightmare's final wave, which leaves crews more margin than solo on Normal |
| Uranium target by crew | 1.0 to 3.5 | 1.0, 2.0, 3.0, 4.0, 4.5, 5.0 (was 1, 2.5, 4.5, 8, 10, 12 on 2026-09-28) | a crew of four or more strips every zone before the run is out, so its finish is set by the mine's supply whatever the table; linear keeps the worst case (six on Nightmare) inside the deepest zone |
| Uranium target by difficulty | 1.0 / 1.15 / 1.3 | 1.0 / 1.2 / 1.7 | Hard lengthens through the thinner supply alone; a solo Nightmare player who hunts by sound is barely slowed by thinning, so Nightmare needs the target too |
| Vein divisor | 1.0 / 1.2 / 1.4 | 1.0 / 1.1 / 1.05 | Iron is the binding resource; the old scarcity made Hard and Nightmare's final waves unholdable |
| Uranium vein divisor | (exempt) | 1.0 / 1.1 / 1.15 | the harder run's extra nights |
| DC mine iron, zones 1 to 4 | 22 / 22 / 22 / 16 veins | 16 / 16 / 16 / 12 | the third playtest built three towers by night 1; a tower a day, not three |
| DC mine iron, single blocks, 2026-09-29 | 64 / 64 / 64 / 48 / 48 | 192 / 192 / 192 / 144 / 144 | the seventh playtest (solo Normal, lost on night 10) found Iron hard to find: three unupgraded Sentries and four walls in ten days, about 110 Iron spent; `ORE_SELECTIVITY` refitted from 2.5 to 0.8 reproduces that run, and tripling the veins restores the sheet's nine towers by night 10 |
| DC mine gold, zones 1 to 4 | 20 / 22 / 22 / 20 veins | 34 / 34 / 34 / 26 | six Gold in four days; gold now ahead of iron near the entrance |
| DC mine uranium, solo target 40 (the designer kept the counter at 40; a 130 pass the same day read as too much) | 6 / 9 / 9 / 111 | 7 / 8 / 9 / 14 / 362 in five zones (3 / 4 / 6 / 20 / 400 for an hour the same day) | it hums, so it is found fast; the designer wants the counter to climb steadily rather than in bunches, so each zone holds a little more than the last and a solo player gains about three a day, 40 on day 14; the new zone 5 (40 blocks deep, hardness 5, the deepest stone) is a big crew's supply and covers the Nightmare six-player worst case after thinning (340 against 348). Uranium centres were held within pick reach of the floor, so a zone held about depth x reach x width of it and 1,500 in a 28-deep zone hung the generator on its last veins; the generator now gives up a vein after 200 tries and warns, and since later the same day uranium sits at any height (the floor rule predated the jet pack) |
| DC mine pockets | 2 / 3 / 4 / 5 | 4 / 6 / 8 / 10 | twice the open spaces to discover |
| DC mine crystal | 36 / 36 / 72 / 108 | 0 in every zone | removed from the spawns by the designer (2026-09-29) while the camp-level gates are open for testing; Diamonds have no sink until the gates return |
| Ore vein size | 1 to 7 blocks (radius 0 to 1), crystal 7 | single blocks, with four times the iron and gold veins and six times the crystal | one seven-block Gold II vein was a whole day of Gold; more, smaller finds |
| Entrance clearance | 0 | 4 blocks | no ore visible from the entrance before the first swing |
| Ore tier depth floors | none (a zone rolls its tier mix, anywhere in the zone) | tier 2 from 14 blocks in, tier 3 from 44, tier 4 from 68; within a zone, tiers above its bias sit in the back half | a Gold II vein a few blocks in let a player buy three upgrades on day 1; ore now climbs with the depth |
| Camp-level gates | mining rungs 3 to 5, post levels 2 to 4, capstone, fortification tiers | none (for testing) | a run whose first crystal was out of reach locked every Gold sink; originals kept. On 2026-09-29 the designer removed Camp Level from the game outright for now (too complicated for a round): gates open, crystal 0 in every zone, billboard gone, Refinery at level 1 HP; the code stays dormant |
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
| Tower build and upgrade prices, 2026-10-06 | 20, 10/20/40/80 (Sentry) and up | 60, 30/60/120/240 (Sentry) and up, every kind tripled | the second M34 run (solo Normal, won day 14): nights 4 to 9 did no wall damage, a day's Iron bought a Sentry and most of its upgrades, the cap was full of maxed towers by night 10; a maxed Sentry is now about three days of Iron |
| Titan I / II HP and points, 2026-10-06 | 2500 / 5000 at 75 / 150 | 4000 / 8000 at 90 / 180 | the night 11 Titan died to the towers before reaching a wall; points up a fifth, HP up three fifths, so it still comes with an escort |
| Final wave multiplier | 1.5 | 1.25 | holdable on the target day with that day's towers under the 12 cap |

| Monster point costs (Bombers repriced 10/20/30 on 2026-09-29: a tier 1 wall is 300 HP, so three Bomber I or one Bomber III break one, and at HP points a night bought them for a few percent of its budget) | HP-ish: Runner 6/12/18, Bomber 12/24/36, Flyer 25/50/75, Launcher 50, Titan 100/200 | HP / 50 x speed / 10 x ability: Runner 5/11/16, Bomber 6/12/18, Flyer 16/32/47, Launcher 36, Titan 75/150 | a budget's HP is predictable (17 to 50 HP a point instead of 8 to 50); abilities are gated by unlock night, as the genre does |
| Zombie damage by tier | 10 / 10 / 10 | 10 / 15 / 20 | tiers climb |
| Machine-gun post | 12 damage, 3 s of fire before overheating (60 DPS sustained) | 15 damage, 4 s (85 DPS); back to 12 damage on 2026-09-29 (69 DPS sustained, 120 while firing) after the seventh playtest found every enemy too easy, still above the rifle's 55 | a post is a stationary, exposed commitment; it must out-shoot the rifle's 55 |
| Rocket post | 150 damage every 6 s | 200 | 33 DPS to one target, about a hundred into a group |

Post upgrades (four levels of damage and of fire rate; 15 / 30 / 60 / 120 Gold each until 2026-09-29, then 15 / 90 / 270 / 800, a cheap first rung and then the pick axe's ladder, after the seventh playtest maxed three attributes by day 7 (a dearer first rung pushed the model's first breach to night 3); camp-level gated) are in the model: a player puts 30% of their Gold into them, and by night 10 a solo post is about 2.5x its base. The rifle is unchanged. Frostbite Pass's mine also took Deadman's Canyon's ore counts, so the placeholder map is at least the same game.

## Where the model says we are

Deadman's Canyon, model output on 2026-09-28 (the simulator pass, with backpack trips in the model); the Normal solo row is from the 15-night pass of 2026-09-29, the others are stale until Hard and Nightmare are retuned. "Reached" is the day the uranium target is refined; slack is the crew's DPS over what the night needs to be cleared within the spawn window plus 60 s; final is the same against the rescue wave a call on the target day would bring; the wall columns are the leak's expected damage to the most-hit wall segment as a share of its HP.

| Difficulty | Crew | Target night | Reached | Slack at target | Final wave | Wall night 1 / 2 / 3 / 4 | First breach |
|---|---|---|---|---|---|---|---|
| Normal | 1 | 15 | 14 | 2.00 | 1.39 | 58% / 67% / 99% / 285% | night 4 |
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

## The 15-night pass (2026-09-29)

The sixth playtest (solo Normal, the log read from the Output: pick 2 and backpack 2 on day 2, pick 3 on day 3, backpack 3 and five post upgrades on day 4, every night to 4 beaten with no wall lost) found mining right and the waves too soft, and 10 nights too short. Changes, all scanned in the model before touching data: the group minimum doubled to 80, the run is 15 / 18 / 20 nights, the curves flattened late (see the table), the mine gained a fifth zone so a solo run keeps counting uranium through day 14 instead of flooding on day 12 when it reaches the old zone 4, the target stays 40 with the veins thinned to match (crystal removed from every zone), and the crew uranium table is linear. The audit's remaining misses are the crew pacing item below, Nightmare's solo final wave at 0.99, and Nightmare's solo uranium landing on day 16 (zone 5 floods it too; Nightmare needs its own thinning or a later zone once Normal is confirmed).

## The eighth playtest (2026-09-29, solo Normal, lost on night 8)

Read from the Output. Economy on pace or ahead: four Sentries by day 3 (the iron fix took), fortifications to tier 2 on day 4, pick 4 on day 7, backpack 4 on day 8, nine post rungs by day 7 at the new prices. Walls: wall 4 fell on nights 2, 4, 6 and 8, wall 3 on nights 6 and 8, a Sentry to Bombers on night 3, the Refinery on night 8 to a two-group wave (109 and 120 points, ten seconds apart, Brute II and Zombie III in both). No tower was added or upgraded after day 3; every later Iron went to fortifications and repairs, so the tower plan the sheet assumes (five by night 8) was three. Changes: the spawn window and group gap above; the stuck-monster slide and the post tool lock (bugs found the same run). Open: walls 3 and 4 fall every other night from night 2, so the leak lands on the same segments, and the sheet spreads it over three; the model does not see that the Refinery sits behind those two.

## The third M34 run (2026-10-07, solo Normal, lost on the final wave, day 13)

The first run on the day-1 economy decided that day (gold-only band 16, zone 1 gold 230 in 24 radius-1 rooms, pick 30 / 100, backpack 40 / 80, boots 40 / 70, rooms never touching) and the first logged by the run report end to end. Three nights were forced early with the dev tool (7, 8, 11), and the run was paused for breaks, so those days' mining lines read low.

| Day | Gold refined | Trips | Iron refined | Bought | Night | Walls lost | Refinery dmg |
|---|---|---|---|---|---|---|---|
| 1 | 72 | 5 (45 s) | 0 | pick 2, backpack 2 | 23 s | 0 | 0 |
| 2 | 117 | 4 | 63 | compass, backpack 3; 5 walls | 22 s | 0 | 0 |
| 3 | 141 | 4 | 15 | pick 3; 7 walls, Sentry | 23 s | 0 | 0 |
| 4 | 123 | 2 | 141 | Geiger; walls, Sentry, 3 Goo Pits | 43 s | 0 | 0 |
| 5 | 185 | 3 | 186 | pick 4 (270); 2 Sentries, 2 upgrades | 39 s | 0 | 0 |
| 6 | 111 | 2 | 153 | boots 3, post Damage 2 | 42 s | 0 | 100 |
| 7 (forced) | 167 | 2 | 102 | backpack 4 and 5 (900), jet pack, boots 4; fortifications to tier 3 | 29 s | 1 | 0 |
| 8 (forced) | 1,465 | 5 | 555 | Geiger 2, pick 5 (800), Sentry, 3 tower upgrades, 3 post rungs | 64 s | 0 | 695 |
| 9 | 1,017 | 1 | 183 | boots 5 (540), 2 walls, 2 upgrades | 48 s | 1 | 0 |
| 10 | 1,063 | 1 | 132 | four post rungs at 270 | 80 s | 3 + gate | 2,600 |
| 11 (forced) | 576 | 1 | 108 | two post rungs at 800 | 61 s | 0 | 0 |
| 12 | 1,912 | 2 | 48 | post rung 800, torches; rescue called | 70 s | 2 | 0 |
| 13 | 576 | 1 | 48 | final wave (781 points, 5 groups): the Refinery fell | | | lost |

Totals: 7,525 gold, 1,734 iron (888 on 32 placements and 7 upgrades, 295 on 8,810 HP of repairs), uranium 40 on day 13, 248 kills, 155 Diamonds.

What it says:

- **Day 1 landed where the day-1 design put it.** 72 gold from 5 full packs is the ceiling the pack sets (15 ore a trip), and it bought the pick and the backpack with 2 left: the "excellent day buys both" case. The 95th-percentile question is still open because every log is the designer's.
- **Gold runs away from day 8.** Backpack 4 and 5 bought the same day (day 7) took trips from 4 a day to 1 and gold from about 150 a day to 1,000 to 1,900. Everything Gold buys was maxed by day 12 (pick 5, backpack 5, boots 5, four post rungs at 800). Pick Axe 6 (2,400) was never bought. The late Gold sink is still missing or too cheap; the run ended holding 369 then 125.
- **Iron is the binding constraint all run.** Iron held closed at 0 to 8 on nine of thirteen days. From night 9 the Launchers and Flyer IIs shred the line: night 9 took 2,305 wall HP and a wall, night 10 took 3,295, three walls, the gate, and 2,600 Refinery HP in one night at tier 3 (4,000). Repairs cost 108 Iron on day 11 alone. The sheet's "walls hold once towers come online" never happened: placements were destroyed every night from 7 on (Placement destroyed lines), so the Iron went to rebuilding the same Sentries and Goo Pits.
- **The final wave lost the run.** The rescue was called on day 13 at 40 uranium, two days ahead of the day-15 target, and the final wave (781 points, five groups 8 s apart, Titan and Brute III in night 12 already) broke Wall3 and the Refinery before the helicopter landed and boarded (60 s landing plus the boarding window). With the second M34 run won on day 14 and this one lost on day 13, the final wave's scale and the landing time are the first things to look at, before any mining number.
- **Uranium pacing is right.** 40 on day 13 against a day-15 target with three forced nights is on the curve the 2026-09-29 pass asked for (about three a day, no jumps).

Changes made from it the same day: gold and iron yields both to 3 / 9 / 27 / 81 / 243 a rock (gold was quadrupling, iron doubling), flyer damage halved (50 / 100 / 150), Brute HP 600 / 1,200 / 1,800, the Titans' reach 15 studs, and a 30 s breather between the radio call and the final wave (the Rescue Wait state with its countdown). The sheet after: 33 misses (29 before), with solo Normal's uranium landing on day 18 in the model against day 13 in play: the model buys the pick and backpack rungs from gold per pack, so the gold cut slows its advance far more than it slowed the designer, who reached the deep zones on upgrades bought by day 8 either way. The model's advance assumptions are the next thing to refit, from this run's pick and backpack dates (pick 3 day 3, pick 4 day 5, backpack 4 and 5 day 7, pick 5 day 8). Later the same day, for feel only: yields to 2 / 6 / 18 / 54 / 162 with iron and gold counts times 1.5 and resource HP times two thirds, so ore per zone, swings per ore, and every sheet number stay put while finds come half again as often; and a zone 0 starter band (8 blocks, gold only, 90 rocks) so day 1 pays the first pack on any seed.

## The fifth M34 run (2026-10-08, solo Normal, lost on night 7)

The first run on the day-1 aim of 50 Gold (zone 0 gold 60, zone 1 140, clearance 1, zone 0 floor drop 2, pack 16), the first with the extended report, and the first saved as a run record (GameData hash e7aa3403). Two breaks were taken on days 2 and 3 with the pause tool (71 s and 286 s); the day 3 camp time below includes the second, a report bug fixed the same day.

| Day | Gold refined | Trips | Iron refined | Bought | Night | Walls lost | Refinery dmg |
|---|---|---|---|---|---|---|---|
| 1 | 56 | 4 (78 s) | 0 | pick 2 | 31 s | 0 | 0 |
| 2 | 77 | 4 | 34 | backpack 2, four post rungs at 15; 2 walls | 32 s | 0 | 0 |
| 3 | 62 | 2 | 28 | boots 2; 3 walls | 17 s | 0 | 0 |
| 4 | 100 | 3 | 33 | pick 3; 2 walls | 47 s | 1 (Wall3) | 0 |
| 5 | 62 | 4 | 118 | backpack 3; 9 walls | 55 s | 1 (Wall2) | 45 (Flyers) |
| 6 | 234 | 4 | 306 | compass, jet pack 2, boots 3, post Damage 2; 3 Sentries, 6 Goo Pits, 4 walls | 40 s | 0, nine placements lost | 0 |
| 7 | 270 | 4 | 177 | backpack 4; a Sentry, 5 walls, 3 Goo Pits | lost | | destroyed |

Totals: 861 gold, 696 iron (630 on 38 placements, 31 on 875 HP of repairs), uranium 4, 97 kills, 30 Diamonds. Per day about 200 to 270 s in the mine, 70 to 130 s in camp, 36 to 92 s on the post.

What it says:

- **Day 1 landed on the aim.** 56 Gold against 50, from 26 gold rocks broken (the band measurement predicted about 25). The pick was bought on day 1 and the backpack on day 2: "the pick on day 1 and the backpack nearly", as designed.
- **The wall progression is on the designer's curve for the first time.** Nights 1 to 3 touched nothing, night 4 (88 points, the first Brute) took Wall3 and dented two more, night 5 took Wall2. The targets say night 2 dents, night 3 comes close, night 4 breaches; nights 2 and 3 are still a little soft, and the designer said the run felt good.
- **Night 7 was lost to Flyers with the alarm silent.** The Refinery alarm polled for a monster within 20 studs of the box, and a Flyer shells from 100 studs, so the siren never sounded while two Flyers took the Refinery apart. Fixed the same day: a monster's hit on the Refinery now holds the alarm on for 5 s (`REFINERY_ATTACK_HOLD_SEC`), whatever the distance, and the Flyers' attack range is 50 (they hovered over the wall line at 100, hard to see and shoot; now they must come in over the camp).
- **Night 6 was the first tower night.** Nine placements fell (three Goo Pits, a Sentry, five walls) with no structure damage: the new line shows where the Iron went and why day 7's 177 Iron bought the same things again.
- **Iron was binding until day 5 and then flooded.** Iron held closed at 0 to 11 on days 1 to 5, then 306 refined on day 6 and 177 on day 7 once the tunnel reached the first iron zone (block 45, the generator's zone 4). Towers only appeared on day 6, which is later than the sheet's "a tower a day".
- **Uranium is far behind.** 4 by day 7 against the curve's "about three a day" (about 20): only 24 swings at uranium all run and no Geiger Counter bought, so this was a choice, not a supply problem, but it says the counter does not pull a player who is busy with walls. Worth watching on the next run before touching the counts.
- **The model's day assumptions read off the report:** mining share of the day about 0.6 (the model says 0.55), camp overhead about 90 to 110 s (the model says 60), gold selectivity about 2.5 times its share on day 1 (the model says 2.0). To be refitted once a full run is in the store.

## The sixth M34 run (2026-10-08, solo Normal, won on day 16)

The first full run on the numbers of the fifth (day-1 aim 50, Flyer range 50, the hit-driven Refinery alarm), played straight through with no breaks and no dev commands, and the first complete run record in the store (GameData hash 8b618193, 17.7 KB).

| Day | Gold | Trips | Iron | Uranium (total) | Bought | Night | Walls lost | Refinery dmg |
|---|---|---|---|---|---|---|---|---|
| 1 | 70 | 5 | 4 | 2 (2) | pick 2, backpack 2 | 24 s | 0 | 0 |
| 2 | 86 | 4 | 80 | 1 (3) | boots 2, three post rungs; 7 placements | 28 s | 0 | 0 |
| 3 | 78 | 3 | 54 | 2 (5) | 4 placements | 15 s | 0 | 0 |
| 4 | 56 | 3 | 78 | 1 (6) | pick 3; 7 placements | 36 s | 0 | 0 |
| 5 | 162 | 5 | 219 | 0 (6) | backpack 3, boots 3; 6 placements | 46 s | 0 (Wall2 240) | 150 (Flyer) |
| 6 | 176 | 3 | 225 | 4 (10) | Geiger, fortifications to tier 2 | 32 s | 0 | 0 |
| 7 | 366 | 3 | 302 | 2 (12) | backpack 4, compass, two post rungs; 7 upgrades | 21 s | 0 | 0 |
| 8 | 178 | 2 | 264 | 3 (15) | 4 placements | 30 s | 0 | 0 |
| 9 | 234 | 2 | 280 | 3 (18) | pick 4, jet pack 2; 7 upgrades | 55 s | 3 (Launchers 1,800) | 0 |
| 10 | 386 | 2 | 414 | 0 (18) | two post rungs; 3 upgrades, 2,040 HP repaired | 46 s | 1 (Launchers 1,000) | 0 |
| 11 | 990 | 2 | 288 | 0 (18) | backpack 5 (675); 14 placements | 64 s | 0, nine placements lost | 0 |
| 12 | 288 | 1 | 270 | 2 (20) | pick 5 (800); 10 placements | 233 s | 2 (Brutes 2,460) | 960 |
| 13 | 540 | 1 | 558 | 4 (24) | fortifications to tier 3, two post rungs at 270; 2,460 HP repaired | 60 s | 0 | 0 |
| 14 | 612 | 1 | 587 | 1 (25) | Geiger 2, torches, dynamite, a post rung; 11 placements, 9 upgrades | 53 s | 0 | 0 |
| 15 | 396 | 1 | 222 | 4 (29) | jet pack 3, a post rung | 67 s | 2 (Launchers 2,760) | 0 |
| 16 | 504 | 1 | 288 | 11 (40) | nothing; 3,200 HP repaired; rescue called | final wave | 3 and the gate | boarded |

Totals: 5,122 gold, 4,133 iron (3,067 on 77 placements and 27 upgrades, 332 on 9,930 HP of repairs), 40 uranium on day 16, 387 kills, 405 Diamonds, no deaths. Per day about 200 to 250 s in the mine, 60 to 130 s in camp, 30 to 80 s on the post. The final wave (1,190 points, seven groups 8 s apart, two Titans) took Wall1, Wall2, Wall4, and the gate but the helicopter landed and the player boarded; the Refinery fell after the win.

What it says:

- **The run is winnable solo on these numbers**, one day after the day-15 target, with the rescue wait and the 60 s landing holding against a 1,190-point final wave. Against the third run (lost on day 13 to a 781-point final wave) the differences are the halved Flyer damage, the 30 s breather, and the alarm.
- **Day 1 and the gear ladder are on pace.** 70 Gold (five full packs of 16, above the 50 aim because this seed's corridor was rich), pick and backpack on day 1, pick 3 on day 4, 4 on day 9, 5 on day 12; backpack 5 on day 11; boots 3 on day 5 and never further. Every Gold sink was bought by day 15 and the run ended holding 679: the late Gold sink is still missing, as the third run found.
- **The early nights are soft.** Nights 1 to 4 took no wall damage at all (the targets say night 2 dents, night 3 nearly breaks, night 4 breaches); night 5 was the first dent (a Brute, 240) and the first Flyer hit on the Refinery (150, survived with the alarm working). The first breach was night 9, and it was the Launchers: every wall lost on nights 9, 10, 13, 14, and 15 was Launcher fire (1,800 / 1,000 / 600 / 800 / 2,760). The designer called the run good, so the early softness is a feel decision to confirm, not a bug; the Launcher as the one wall-breaker from night 9 is the shape to look at.
- **Night 12 ran 233 s, 217 s after the last group arrived**, against 30 to 67 s every other night: Brute III and Brute II took the gate, 600 off Wall2, and 960 off the Refinery. Something held that night open (a Brute stuck, or out of the player's reach) long after the fight; the next such night should be watched in play.
- **Iron turns on at day 5 and is never short again from day 12.** Held at 0 to 31 through day 11 while every Iron went straight into placements (77 built, 27 upgraded), then 148 and 94 held on days 12 and 13 and 184 at the end. Towers started on day 2 this time (seven placements) because the seed's zone 3 iron was reachable early.
- **Uranium pacing is right**, with the Geiger Counter bought on day 6: 2 to 4 a day through day 15 and 11 on day 16 once the tunnel reached block 100 (the generator's zone 6, the data's zone 5), landing 40 one day past the target. The fifth run's 4 by day 7 was the choice not to hunt it.
- **Fortifications:** tier 2 on day 6 (15 donations), tier 3 on day 13 (5 on day 10 plus 35); the report's purchase list now collapses a run of the same purchase into one entry with a count.
- **The designer's verdict (2026-10-08): close to perfect for them, and they are an above-average player.** So the soft early nights and the late Gold surplus are read as the margin an average player will use up, not as slack to remove: a tester is expected to breach earlier, buy the ladder later, and reach the deep zones later. Nothing is retuned from this run. The numbers stay as they are until tester records are in the store, and the comparison to make then is a tester's day-by-day against this run's.
- **The model's assumptions, read off sixteen days:** mining share of the day about 0.62 (model 0.55), camp overhead about 85 s (model 60), post time 30 to 80 s a night, gold selectivity about 2.5 early (model 2.0), trips falling from 5 a day to 1 from day 12 as the pack reaches 1,200. These are the refit inputs; the refit is the next step.

## Crew scaling of the mine (discussed 2026-10-07, undecided)

The designer wants crew scaling to keep the solo balance, so solo is what gets tuned and crews inherit it. Today the grid is identical for every crew and ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT (1.0 to 1.75) pays more ore per rock: that leaves day 1 alone (a pack pays 15 whatever the yield) but a crew of four shares one mine's supply, so zone 1 empties in a quarter of the time and nothing tuned solo holds. The designer prefers more resource rocks over more ore per rock. Three approaches were compared:

1. **Rock count scaling** (vein counts times a crew table, yield 1.0): per-player supply over the run matches solo, but density rises, so each player finds ore faster and delivers more packs a day (digging is about half a trip, so a crew of four runs about 1.6x solo early). Cheap, keeps the footprint, needs the multiplier set below the crew size by hand.
2. **Width scaling** (zone width times the crew, density unchanged, yield 1.0, uranium counts scaling with the width, target table linear): each player is in a solo-sized mine side by side, so everything carries across exactly. Costs: the hill must hold the widest mine (96 wide solo, 384 for four, 576 for six studs; a sublinear table of 1 / 1.8 / 2.5 / 3.1 / 3.6 / 4.0 keeps the shape), a one-time client rebuild of about half a second for six, and about 200 KB per client at run start. Drawing, the server, and digging are unchanged at any size.
3. **Leave yield scaling** until a crew can play; the one thing it affects, how fast a crew empties the mine, cannot be judged without one.

Decision deferred to the group playtest. The designer also feels the mine is close to balanced solo and reads as too much stone, but does not want density touched now.

Scanned in the model the same day (BalanceAudit:buildInput with the yield at 1.0 and every zone's ore times a rock multiplier; Normal, Deadman's Canyon, per player), against solo's gold per player 477 / 1,760 / 3,894 at nights 5 / 10 / 15, iron 239 / 1,149, uranium on night 18, slack 2.7 / 4.0:

| Crew | Today (yield) | Rocks x1.0 | Rocks x1.5 | Rocks x2.0 | Rocks linear |
|---|---|---|---|---|---|
| 2 | gold 534 / 1,949, uranium 16 | 358 / 1,172, 18 | 811 / 3,005, 13 | 1,007 / 4,430, 12 | same as x2 |
| 3 | 570 / 2,236, 14 | 332 / 1,083, 19 | 583 / 2,383, 14 | 887 / 3,538, 13 | 1,472 / 9,073, 10 |
| 4 | 768 / 2,774, 13 | 318 / 995, 19 | 530 / 2,225, 14 | 817 / 3,283, 12 | 2,955 / 15,717, 9 |
| 5 | 809 / 2,935, 12 | 306 / 898, 19 | 494 / 1,884, 14 | 767 / 3,097, 12 | 3,289 / 17,443, 7 |
| 6 | 854 / 3,134, 12 | 270 / 799, 19 | 468 / 1,619, 15 | 730 / 2,977, 12 | 3,519 / 19,800, 7 |

Reading: a linear rock count makes a crew five to ten times richer per head than solo in the model, because a crew strips a zone rather than tunnelling (CREW_ADVANCE_EXPONENT 0.6) and denser rock pays for every swing. No scaling at all (x1.0) leaves crews poorer than solo and lands uranium late. The multiplier that keeps each player on solo's curve is about 1.5 for two to four players and 1.5 to 2.0 for five and six, which is also about where today's yield table sits (1.15 to 1.75). So the two approaches land in the same place in the model; the rock-count version is preferred by the designer because it keeps ore per rock honest and the frontier on solo's pace. Candidate table: 1.0 / 1.5 / 1.5 / 1.5 / 1.7 / 2.0, to be checked on the first crew run (the model's crew advance exponent is a guess). The nights are easier for crews at every setting (slack 5 to 12 against solo's 3 to 4), which is the wave multiplier and the posts, not the ore.


## Open items

1. **Gold visibility.** The third playtest broke about two gold rocks to twenty iron in a mine that holds gold at 60% of iron near the floor. Check the gold rock template reads as ore at mining distance before trusting the Gold numbers.
2. **Crew pacing on Hard and Nightmare.** A crew of four or more strips the mine, so its uranium is capped by the thinned supply, not paced by it; any target inside that cap is reached about day 10 to 11 whatever the difficulty, and a target near the cap is brittle. Levers tried: thinner uranium (helps solo, barely moves crews), a bigger supply (crews find a share of what is left, so more supply is found faster). Candidates not yet tried: a per-difficulty crew table for the uranium target, or a slower crew advance on harder rock (the GDD's hardness knob, off by decision). Decide after the logged playtest.
3. **The run report dev tool** (built 2026-10-06, M34: `RunReportManager` with the pure `RunReportRules`): at each dawn the server Output gets the day just closed, per player Iron / Gold / Uranium refined, Refinery trips and the average seconds between them, towers built and upgraded with the Iron spent, Hammer repairs (HP and Iron), kills, damage given, Diamonds earned, and for the night its length, kills, wall damage, walls lost, and Refinery damage; the whole run with totals prints at the run's end, and "Print the run report" on the Run dev panel prints everything so far. Its purpose is to calibrate the `ASSUMPTIONS`, above all `ZONE_ADVANCE_SHARE`, `DAY_OVERHEAD_SEC`, `ORE_SELECTIVITY`, and `URANIUM_SELECTIVITY`; the first M34 playtests are its first data. Extended 2026-10-08 so those assumptions can be read off instead of guessed: a second line per player with where they stood (seconds in the mine, manning a post, or in camp, sampled every 2 s from the server), pick axe swings and breaks by kind (stone, gold, iron, uranium), the deepest block hit and its zone, deaths, revives, damage taken, and every named purchase in order (store items, post claims and rungs, weapon rungs, fortifications, gifts; repairs and the Defense Table keep their columns); and a night line under the header with the wave's group count, the generator's target, how long the field took to clear after the last group arrived, placements lost, and damage by structure and by monster kind, biggest first. The monster kind now travels with every hit (`MonsterManager:hurt`, projectiles included) into `damageStructure`, `damagePlacement`, and `damagePlayer`. The same day the mine report at run start gained each zone's real rock density (one in N diggable blocks per resource), after the zone 0 gold rate was worked out by hand at twice its true value: a zone is its height plus its floor drop, and the entrance clearance box had kept every vein out of the first seven blocks of the corridor (clearance 4 to 1, zone 0 floor drop 5 to 2).
4. **Run records** (built 2026-10-08, M34: `RunRecordManager` with the pure `RunRecordRules` and `DataHash`, tuning in `GameData/Control/Telemetry`, the reader `scripts/studio/pull_run_records.luau`). At every dawn and at the run's end the report's rows are saved as one entry per run in the `DigDefendRunRecords_v1` DataStore, so testers' runs can be pulled and averaged beside the designer's. Checked before building, against Roblox's rules and limits: the record names nobody (players are crew slots 1 to 6 by first appearance; no UserId, no username, no chat, nothing from the profile), so it holds no personal data under Roblox's privacy policy or GDPR and a right-to-erasure request has nothing to find; the only identity-adjacent fields are a flag that an admin was in the crew (to separate the designer's runs) and whether it was a Studio session. Size: a one-day solo run is 881 bytes and a 20-day crew of six is about 150 KB against the 4 MB a key allows, with a 1 MB cap in the data that refuses a record rather than writing it; one `SetAsync` per dawn (about every six minutes) and one at the end, against a budget of 60 writes a minute plus 10 per player, so the budget is never close; the key (`run_<start unix>_<8 of the job id, or random in Studio>`) is about 23 of the 50 characters allowed; `ListKeysAsync` and `GetAsync` on the reader side are within their own budgets for tens of runs. Each record is stamped with `game.PlaceVersion` and an FNV-1a fingerprint of every GameData table, so the reader can refuse to average runs from different tuning, and with the count of dev commands used, so a run with forced nights is visible. Decided the same day: this is the one DataStore writer besides `PlayerData`, a separate write-only store that never touches a player's save. Open: the GameData hash changes on any tuning edit, so a sample is only as big as the runs since the last change; whether that is too strict is for the first batch of tester runs to show.
5. **Crews lean on posts.** A crew never breaches a wall in the model and keeps a margin of 4 or more on Normal's target night. With six posts and Gold to spare, a crew's manned posts carry it to night 8 or later before a tower is needed on Normal, and its margin at the target night is well above solo's. The wave table could go higher on Normal alone if a per-difficulty crew table is ever wanted; today one table serves all three.
6. **Sinks.** Nothing new was added; the model treats 80% of Iron as tower spend. The fortification pool scales with the crew's wave multiplier since 2026-09-29 (150 / 400 solo, 1.6x for two up to 2.8x for six), and repair swings double their HP and Iron with the fortification tier (10 / 20 / 40 HP for 1 / 2 / 4 Iron, halved from 2 / 4 / 8 the same day, then tripled to 30 / 60 / 120 HP on 2026-10-06 after the first M34 run spent 204 to 210 Iron a day on repairs from day 12 because the eighth playtest spent every Iron after day 3 on rebuilding two walls a night) so a tier 3 wall is not two minutes of hammering; repair cost does not scale with the crew, since a crew brings more hammers and the swing is already the limit. The Refinery's HP follows the fortification tier too since 2026-09-29 (1,000 / 2,000 / 4,000, doubling like the walls; it followed the Camp Level before, which is out of the game), so the pool is now the one purchase that toughens everything the monsters can attack. Tower kinds were not balanced against each other (Flamethrower and Sniper are about half a Sentry's DPS per Iron on paper; range, cone, slow, and stun are unpriced).
7. **Frostbite Pass** is a copy of Deadman's Canyon's numbers and is excluded from the audit (`AUDITED_MAPS`) until authored.
8. **Records to update at close-out**: `gdd.txt` sections Difficulty, Party scaling, Wave Cycle (final wave), Defenses (camp cap), Randomized Mine Creation section 7 (uranium divisor) and the Deadman's Canyon example; `milestones.md`'s stale wall HP, repair, and uranium notes; the M29 header comment in `Waves/DeadmansCanyon` was rewritten.

## Assumptions to calibrate

All in `GameData/Control/Balance.ASSUMPTIONS`, with what set each: `MINING_SHARE_OF_DAY` 0.55 (guess); `ORE_SELECTIVITY` 1.5 (guess); `URANIUM_SELECTIVITY` 2.0 (guess, it hums); `ZONE_ADVANCE_SHARE` 0.15 (guess, tunnelling); `CREW_ADVANCE_EXPONENT` 0.6 (guess); `TOWER_COVERAGE` 0.6 (guess); `WEAPON_UPTIME` 0.5 and `POST_EFFECTIVENESS` 0.6 (together they put the second playtest's night 2 breach and night 1 hold where they were seen); `ORE_SELECTIVITY` 0.8 (refitted to the seventh playtest's Iron on 2026-09-29; was 2.5), `GOLD_SELECTIVITY` 2.0, `URANIUM_SELECTIVITY` 10, `DAY_OVERHEAD_SEC` 60 (40 until the day grew to 320 s on 2026-09-29; the extra sunset is for defenses, not mining) (the last three fitted jointly to the fifth playtest's log: about 370 Gold by the end of day 3, 35 Iron by day 2, 40 uranium by day 4, pick 3 on day 3); `WALL_WALK_SEC` 20 (map estimate); `WALL_SEGMENTS_HIT` 3 (second playtest's night 3); `CLEAR_SLACK_SEC` 60; `DEFENSE_IRON_SHARE` 0.8; (`DAY_OVERHEAD_SEC` was 75 before the fit); `REFINERY_TO_ENTRANCE_STUDS` 64 (measured on the map); Gold shares pick axe 0.4, backpack 0.25, boots 0.1, post 0.25; `TOWER_NEEDED_SLACK` 1.75 (now informational).

Not modelled: overflow ore dropped on the ground, the jet pack, dynamite, torches, player death, the Refinery's own HP, trap purchases, and the walk to a post at dusk.

## Playtest protocol

Three logged runs: solo Normal, four-player Normal, solo Hard. Compare the run report to the sheet, correct the assumptions where the report disagrees, retune, and only then close.

## Sources

Methodology: Schreiber, Game Balance Concepts levels 2, 3, 6, 7, 8, 10 (gamebalanceconcepts.wordpress.com); Dan Cook, Value Chains (lostgarden.com/2021/12/12/value-chains); Adams and Dormans, Machinations (gamedeveloper.com); The Math of Idle Games (gamedeveloper.com); Deep Rock Galactic difficulty scaling (deeprockgalactic.wiki.gg/wiki/Difficulty_Scaling); Risk of Rain 2 difficulty (riskofrain2.wiki.gg/wiki/Difficulty); Left 4 Dead difficulty; Helldivers 2 patrol scaling (pcgamer.com); 7 Days to Die party gamestage; Vampire Survivors co-op slots.

Dome Keeper: Relic Hunt, Technical Terms, Version History, Modifiers, Multiplayer (domekeeper.wiki.gg); Habermann interview (gamedeveloper.com/business/how-dome-keeper-focuses-on-systems-that-feed-into-one-another); Steam co-op scaling threads; Xbox Wire multiplayer announcement 2026-04-13.

Tower defense: Balance in TD games / Goal Defense (gamedeveloper.com/design/balance-in-td-games); PvZ wave points and budget formula (plantsvszombies.wiki.gg); BTD6 rounds and RBE (bloonswiki.com); Kingdom Rush campaign design (gamedeveloper.com); Sanctum 2 postmortem (gamedeveloper.com); Defender's Quest design (gamedeveloper.com); Tower defense economics (bigarcade.net); Loughran, Tower Defense Proof in Excel; Brian Davis, Balancing Your Game: A Formula-Driven Approach (GDC Europe 2016).
