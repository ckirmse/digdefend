# Dig Defend: how balance is set up

A reference for the balance designer, written 2026-10-26 from the committed GameData (commit 1b1796a). Every number below is copied from the file named beside it; every formula is quoted as coded. Read `docs/project-overview-for-balance.md` first for the project's shape and the working rules, and `docs/balance-plan.md` for the history of why the numbers are what they are. Where a file's comment disagrees with its value, the value wins; the known cases are listed at the end.

One block in the mine is 4 studs. A player walks 16 studs per second at boots level 1.

---

## 1. The shape of the system

**The loop.** A run is a sequence of days and nights. By day the crew mines; ore refines 1:1 into Gold, Iron, and Uranium at the Refinery. Gold buys mining upgrades (pick, backpack, boots, jet pack, Geiger, compass). Iron buys everything defensive (towers, traps, walls, post rungs, weapon rungs, gadget rungs). Uranium buys nothing: it is the win condition. By night a wave of monsters walks from the spawns to the camp; the Refinery is every monster's first target. When the refined Uranium reaches the target, the radio calls a helicopter; a final wave arrives, the helicopter lands, and anyone aboard wins. Diamonds, the lobby currency, are paid for nights survived and for the rescue.

**The levers, and the rule for each.**

| Lever | Lives in | Rule |
|---|---|---|
| Difficulty (Normal, Hard, Nightmare) | wave generator settings per map, uranium target multiplier, vein divisors | **Parameters, never a stat multiplier.** Harder means more points per night, earlier unlocks, more uranium to find; monster HP and damage never change. |
| Crew size (1 to 6) | `Control/PartyScaling` | Sampled at dawn, only ever decreases. Scales the wave budget and the per-group minimum (so a crew gets the solo group count, each group bigger), the uranium target, the ore yield per rock, and the fortification price. Monster HP multiplier exists but is 1.0 at every crew size. |
| Time | `Control/RunCycle` | A 320 s day; a night ends when the last wave monster dies. |
| The mine | `Mines/<Map>`, `Rocks/*` | A fixed grid, identical at every crew size and difficulty except vein counts. Depth is the gate: rock HP triples a tier, the pick triples a level. |
| Monsters | `Monsters/Roster` | Each kind has a point price. The wave spends points. |
| Player power | `Weapons/*`, `Posts/*`, `Defenses/*`, `Gadgets/*`, `Classes/Roster` | Upgrade ladders bought with Iron during the run; a class is a kit plus a mining-speed debuff. |
| Targets | `Control/Balance` | What the run should feel like: Normal ends on night 15, the first wall breaks on night 4, 20 Gold by the end of night 1. The audit checks GameData against these at every server start. |

**Design decisions that constrain tuning** (from the files and `docs/balance-plan.md`):
- The Refinery stays 1:1.
- No push-your-luck term; nights are open-ended (end when the wave is dead).
- Every class swings alike on damage; no class sets mining power. The class debuff is `MINING_SPEED`, set from each class's combat output over the Recruit.
- A buff that touches only one class's own kit belongs in that kit's GameData, not in the class table.
- The Machine Gun post is the yardstick for player damage.
- Headshots are the Railgun's alone.
- Gadget upgrades go only to a gadget that must keep pace with the waves or the mine (Auto Turret, Remote Charge).
- Every ore vein is a single block. No ore within the gold-only band at the entrance.
- The tower cap is shared by the crew.
- Normal is tuned first; Hard and Nightmare are provisional.

---

## 2. The run's clock, difficulty, and crew scaling

### Day and night: `Control/RunCycle.luau`

| Key | Value | Meaning |
|---|---|---|
| `PRE_DAY_SEC` | 10 | hold before day 1 |
| `DAY_SEC` | 320 | 300 plus a 20 s sunset since 2026-09-29 |
| `DUSK_START_SEC` / `DUSK_STEP_SEC` / `DUSK_MAX_SEC` | 60 / 5 / 90 | dusk on day 1, growth per day, cap |
| `NIGHT_PLACEHOLDER_SEC` | 0 | 0 means only the monsters end a night |

`duskSec(day) = min(60 + 5 * (day - 1), 90)`: 60, 65, 70, ... 90 from day 7.

### Difficulty: `Control/Difficulty.luau`

| Key | NORMAL | HARD | NIGHTMARE | Read by |
|---|---|---|---|---|
| `DIFFICULTY_VALUE` | 1.0 | 1.4 | 1.9 | mine hardness shift (which is 0) and the audit; the waves never read it |
| `URANIUM_TARGET_MULTIPLIER` | 1.0 | 1.2 | 1.7 | rescue target |
| `VEIN_DIVISOR` (iron, gold) | 1.0 | 1.1 | 1.05 | mine generation |
| `URANIUM_VEIN_DIVISOR` | 1.0 | 1.1 | 1.15 | mine generation |
| `HARDNESS_SHIFT` | 0.0 | 0.0 | 0.0 | rock is identical on every difficulty |

```
effectiveVeinCount = floor(baseCount / divisor + 0.5)
uraniumTarget      = mineSoloTarget * URANIUM_TARGET_MULTIPLIER[difficulty] * URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT[crew], rounded to 5
```

The waves' difficulty is the per-difficulty `GENERATOR` table in each map's wave file (section 7). Decision 2026-09-28: Hard lengthens its run only through thinner uranium; Nightmare also needs a bigger target, because a solo player hunting humming uranium is barely slowed by thinning while thinning further starves a big crew.

### Crew: `Control/PartyScaling.luau`

| Crew | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| `ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT` | 1.0 | 1.15 | 1.3 | 1.45 | 1.6 | 1.75 |
| `URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT` | 1.0 | 2.0 | 3.0 | 4.0 | 4.5 | 5.0 |
| `WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT` | 1.0 | 1.6 | 2.1 | 2.4 | 2.6 | 2.8 |
| `ENEMY_HP_MULTIPLIER_BY_PLAYER_COUNT` | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 |

The scaling count is `min(clamp(liveReadyPlayers, 1, 6), previousCount)`, sampled at each dawn (`RunCycleRules.sampleScalingCount`); a player leaving shrinks it at once, a night already under way keeps its wave. The wave multiplier also scales the fortification tier price (section 11) and the tower cap is shared (`ceil(12 / crew)` per player). Monster HP is `floor(MAX_HP * hpMultiplier + 0.5)`; with the table at 1.0 it is the roster value. Decision 2026-09-28: the HP table was set to 1 everywhere so crew size never compounds through stats (four players had met 3.25x solo HP).

---

## 3. The mine and the rocks

### How a mine is generated (`Mines/<Map>.luau`, `shared/MineGenerator.luau`, `shared/RockRules.luau`)

A mine is one open volume in a bedrock shell, entered by a short tunnel. It is sliced along its depth into **zones**; each zone inherits any field it does not set from the one before. A zone spans `height` rows above the entrance floor line and `floorDrop` rows below it. Per zone the designer sets:

- `hardness` (1 to 5): the centre of a triangular kernel over the five Stone tiers; it decides the filler rock.
- `tierBias` (1 to 5): the same kernel over the five ore tiers; it splits the zone's vein count across tiers.
- `iron`, `gold`, `uranium`, `uranium2`, `uranium3`: vein counts. Every vein is one block, so a count is a rock count. The three uranium fields are Uranium 1 / 2 / 3 (1 / 3 / 6 ore), placed directly with no tierBias split; each is inherited on its own, so every zone writes all three.
- `pockets`: pre-carved 4x4 rooms, three rows tall (36 cells), never touching each other or the entrance.

Kernel: `weight[i] = max(0, 1 - |i - center| / SPREAD)`, normalised; at `SPREAD` 1.2 a whole-number centre gives 75% own tier and 12.5% to each neighbour. Vein counts split by largest remainder. Placement rules: gold and uranium are kept `veinEntranceClearance` blocks from the tunnel; iron is kept out of the `goldOnlyEntranceRadius` band (uranium was too until 2026-10-27, which put all of zone 1's on block 20); each iron and gold tier has a global depth floor `TIER_MIN_DEPTH_BLOCKS = { 0, 14, 44, 68, 97 }` (`Rocks/Weights.luau`); within a zone, iron and gold tiers above `round(tierBias)` may only centre in the back half and tiers below it in the front half; uranium spreads over its whole zone (the half-zone split held it to the front half of zones 2 to 5 until 2026-10-27) and may sit at any height. The generator refuses a mine whose thinned uranium total is under the worst-case target (six players on Nightmare).

### Deadman's Canyon: `Mines/DeadmansCanyon.luau`

Solo `uraniumTarget` **35** (40 before 2026-10-23). `goldOnlyEntranceRadius` 16, `veinEntranceClearance` 1, width 24, pocket radius 2.

| Zone | depth (blocks) | rows | hardness | tierBias | iron | gold | uranium (U1 / U2 / U3) | pockets | starts at block |
|---|---|---|---|---|---|---|---|---|---|
| 0 (starter band) | 8 | 7 | 1.0 | 1.0 | 0 | 78 | 0 / 0 / 0 | 1 | 1 |
| 1 | 12 | 10 | 1.0 | 1.0 | 60 | 140 | 3 / 0 / 0 | 3 | 9 |
| 2 | 24 | 12 | 2.0 | 2.0 | 400 | 255 | 9 / 0 / 0 | 5 | 21 |
| 3 | 24 | 18 | 3.0 | 3.0 | 250 | 234 | 9 / 9 / 0 | 9 | 45 |
| 4 | 28 | 24 | 4.0 | 4.0 | 280 | 180 | 0 / 36 / 0 | 13 | 69 |
| 5 (abyss) | 40 | 26 | 5.0 | 5.0 | 280 | 180 | 0 / 27 / 27 | 15 | 97 |

Totals: 136 blocks deep; 1,270 iron rocks, 1,067 gold rocks, 120 uranium rocks for 399 ore. The uranium rocks follow a power curve (2026-10-27): 2.5 / 7.5 / 15 / 30 / 45% of the rocks in zones 1 to 5, about 1 / 2 / 9 / 27 / 61% of the ore. Ore by the end of each zone on Normal / Hard / Nightmare: 3 / 12 / 48 / 156 / 399, 3 / 11 / 43 / 142 / 367, 3 / 11 / 43 / 136 / 343, so a solo crew reaches its target (35 / 40 / 60) in zone 3 on Normal and Hard and zone 4 on Nightmare (the designer accepted zone 3 over the 2026-09-29 rule of zone 4). Worst case: 35 x 1.7 x 5.0 = 297.5, rounded to 300, against 343 thinned on Nightmare. `BalanceAudit` previews with a party multiplier of 1, so only the generator (and `MineGenerator.spec`'s shipped-mines test) checks this floor.

Frostbite Pass (`Mines/FrostbitePass.luau`) is a placeholder copy with `uraniumTarget` 40, zone 1 iron 0, slightly lower iron counts, and the same uranium; it is excluded from the audit. Its worst case is 340 against the same 343, 3 ore to spare.

Decision history in the file: 2026-09-28 single-block veins and tier depth floors (a Gold II vein near the mouth bought three upgrades on day 1); 2026-09-29 zone 5 for the 15-night run, uranium at any height, about three uranium a day solo; 2026-10-07 the 16-block gold-only band and the starter zone; 2026-10-08 pockets as rooms, zone 0 and 1 gold cut for a 50-Gold day 1; 2026-10-11 iron up about 12% in zones 2 to 5 when rungs moved to Iron; 2026-10-23 target 35, zone 0 gold +30%, zone 1 iron 60; 2026-10-26 three uranium tiers; 2026-10-27 the uranium power curve at 120 rocks, uranium over whole zones and out of the gold-only band.

### Rocks: `Rocks/RockDefinitions.luau`

Rock HP triples a tier to match the pick, which triples a level. Iron and Gold yield the same ladder. Uranium is 1 ore at 100 HP: a hunt, not a number. **No rock requires a pick level**: any pick digs any rock; the gate is the swing count.

| Rock | HP | Yield (ore) | Swings at pick 1 / 2 / 3 / 4 / 5 / 6 |
|---|---|---|---|
| STONE_1 .. STONE_5 (filler) | 10 / 30 / 90 / 270 / 810 | none | 2 / 1 / 1 / 1 / 1 / 1 up to 162 / 54 / 18 / 6 / 3 / 1 |
| IRON_1 .. IRON_5 | 10 / 30 / 90 / 270 / 810 | 2 / 6 / 18 / 54 / 162 | same as Stone |
| GOLD_1 .. GOLD_5 | 14 / 40 / 120 / 360 / 1080 | 2 / 6 / 18 / 54 / 162 | 3 / 1 / 1 / 1 / 1 / 1 up to 216 / 72 / 24 / 8 / 3 / 1 |
| URANIUM | 100 | 1 | 20 / 7 / 3 / 1 / 1 / 1 |
| BEDROCK | indestructible | | |

Ore per HP: Iron 0.2 at every tier, Gold about 0.15, Uranium 0.01. Ore awarded on a break: `floor(baseYield * ORE_YIELD_MULTIPLIER[crew] + 0.5)` for Iron and Gold (times the class `ORE_YIELD`, Prospector 1.2); Uranium is never multiplied. Overflow past the backpack drops as a pickup (120 s life).

### Lurkers: `Monsters/Lurkers.luau`

A fixed number of pockets from zone index 3 down each hold a sleeping Cave Spider that wakes when a block on its wall is cleared. `lurkerCount(crew) = clamp(10 + 2 * (crew - 1), 0, 20)`: 10 to 20. They are never in a wave and never hold a night.

---

## 4. Mining tools and the Gold economy

Every upgrade is a ladder bought with Gold at the Mining Supplies store (`Store/MiningSupplies.luau` holds the prices, `Mining/<Tool>.luau` the effect). Level 1 is free; the first rungs are cheap on purpose (decided 2026-10-07: day 1 should feel good; tune later rungs, not day 1). Pick and backpack triple per level at about triple the price ("the mine is a simulator", 2026-09-28).

**A swing** (`MiningManager`, `MiningRules`): reach `12 + 6` studs; server cooldown `0.35 / MINING_SPEED` s; client interval `0.45 / MINING_SPEED` s (published per player); damage `DAMAGE_BY_LEVEL[pickLevel]` flat (the `MINING_POWER` modifier is 1 for every class). No per-rock multiplier. Crack stages at 60% and 30% HP.

| Pick level | Damage | Price (Gold) | Cumulative | DPS at 0.45 s |
|---|---|---|---|---|
| 1 | 5 | 0 | 0 | 11 |
| 2 | 15 | 25 | 25 | 33 |
| 3 | 45 | 100 | 125 | 100 |
| 4 | 135 | 270 | 395 | 300 |
| 5 | 400 | 800 | 1,195 | 889 |
| 6 | 1200 | 2400 | 3,595 | 2,667 |

| Backpack level | Capacity (ore) | Price | Cumulative |
|---|---|---|---|
| 1 | 16 | 0 | 0 |
| 2 | 45 | 35 | 35 |
| 3 | 135 | 80 | 115 |
| 4 | 400 | 225 | 340 |
| 5 | 1200 | 675 | 1,015 |

| Boots level | Walk speed | Price | Cumulative |
|---|---|---|---|
| 1 | 16 | 0 | 0 |
| 2 | 20 | 35 | 35 |
| 3 | 24 | 70 | 105 |
| 4 | 28 | 180 | 285 |
| 5 | 32 | 540 | 825 |

| Jet pack level | Fuel (s) | Climb (studs, 12/s) | Price | Cumulative |
|---|---|---|---|---|
| 1 | 1.5 | 18 | 0 | 0 |
| 2 | 2.5 | 30 | 35 | 35 |
| 3 | 3.5 | 42 | 120 | 155 |
| 4 | 4.5 | 54 | 360 | 515 |
| 5 | 5.5 | 66 | 1080 | 1,595 |

Fuel refills at 0.5 s per second anywhere; a dry tank locks until full. `maxFuel = 1.5 + 1.0 * (level - 1)`.

| Geiger Counter | Range (studs) | Price | Cumulative |
|---|---|---|---|
| none | 0 | | |
| own it | 20 | 90 | 90 |
| 3 | 30 | 270 | 360 |
| 4 | 40 | 800 | 1,160 |

Compass 30 Gold once. Torches 5 Gold for 4. Dynamite is no longer sold (the Demolitionist's gadget since 2026-10-20). Class walk speed is `WALK_SPEED_BY_LEVEL * MOVE_SPEED * stimBoost`; class backpack is `floor(capacity * BACKPACK_CAPACITY + 0.5)`.

---

## 5. Refinery, the target, Diamonds, rescue, and health

### Refinery: `Refinery/Refinery.luau`, `shared/RefineryRules.luau`

Standing within 14 studs of the Refinery refines the backpack automatically: 1 ore to 1 bar for all three resources, over a 4 s grind (2 s before 2026-10-09). The uranium target is `roundTo5(mineSoloTarget * crewMultiplier * difficultyMultiplier)`:

| Crew | Normal | Hard | Nightmare |
|---|---|---|---|
| 1 | 35 | 40 | 60 |
| 2 | 70 | 85 | 120 |
| 3 | 105 | 125 | 180 |
| 4 | 140 | 170 | 240 |
| 5 | 160 | 190 | 270 |
| 6 | 175 | 210 | 300 |

### Diamonds: `Run/DiamondTaps.luau`

Paid to every player at the dawn after the night, saved at once. Nights 1 / 3 / 5 / 8 / 10 / 12 / 15 pay 5 / 10 / 15 / 25 / 40 / 60 / 100 (255 by night 15). Rescue pays 150 / 300 / 500 by difficulty. There are **no per-kill rewards** of any resource anywhere in GameData. Starting Diamonds 0 (`Control/Player.luau`). The file's header calls every amount a placeholder until the lobby economy is set.

### Rescue: `Run/Rescue.luau`

Radio call, then a 30 s breather (`FINAL_WAVE_DELAY_SEC`, added 2026-10-07 after a run lost on the final wave), then the run enters RESCUE: the final wave spawns (section 7.5), the helicopter lands 60 s later (`RESCUE_FLIGHT_SEC`), and leaves when everyone living is aboard or 30 s after landing with someone aboard. Anyone aboard wins. `FINAL_WAVE_MULTIPLIER` 1.25 (1.5 before 2026-09-28).

### Health and revives: `Run/Revives.luau`

Health 100 (`MAX_HEALTH` modifier set by no class), only monsters lower it, nothing regenerates; the Stim Shot's heal is the one in-run heal. Self Revive window 60 s, wipe window 60 s, revive invulnerability 5 s. Revive prices are Robux products read from Roblox, not GameData. A solo player only ever gets their own Revive.

---

## 6. Monsters: `Monsters/Roster.luau`

Each kind has a point price, `DIFFICULTY_VALUE`, which the wave budget spends. Pricing rule (2026-09-28): `points ≈ (MAX_HP / 50) * (SPEED / 10) * abilityFactor`, with factor 2 for Bombers, 1.5 for Flyers, Launchers, and Titans. Abilities are gated by unlock night rather than price.

Targeting: the Refinery is always first, then the kind's `TARGET_PRIORITIES` in order; a monster notices targets within `max(DETECTION_RANGE, ATTACK_RANGE)` plus half its width and walks to the highest-priority one; a candidate that **draws** (Decoy, Auto Turret within 30 studs, Flare within 30) beats a plain one of the same type. It attacks every `ATTACK_INTERVAL_SEC` (default 1.5). A blast radius hurts the listed types too. Bombers die on their first attack. The Refinery is "under attack" while any monster is within 20 studs of it.

| Kind | Points | HP | Damage | Speed | Interval s | Type | Ranges detect / attack / blast | Priorities after Refinery | Notes |
|---|---|---|---|---|---|---|---|---|---|
| ZOMBIE_1 / 2 / 3 | 2 / 4 / 6 | 100 / 200 / 300 | 10 / 15 / 20 | 10 | 1.5 | melee | 20 / 5 / 0 | PLAYERS | |
| RUNNER_1 / 2 / 3 | 5 / 11 / 16 | 120 / 240 / 360 | 15 / 30 / 45 | 22 | 1.5 | melee | 20 / 5 / 0 | WALLS, PLAYERS | |
| BRUTE_1 / 2 / 3 | 10 / 20 / 30 | 600 / 1200 / 1800 | 40 / 80 / 120 | 10 | 1.5 | melee | 20 / 5 (10 for 2 and 3) / 0 | WALLS, PLAYERS | |
| LAUNCHER_1 | 60 | 2500 | 200 | 10 | 3 | ranged | 20 / 200 / 20 | WALLS | blast hurts walls, traps, towers; siege piece |
| BOMBER_1 / 2 / 3 | 10 / 20 / 30 | 100 / 200 / 300 | 100 / 200 / 300 | 15 | 1.5 | melee | 20 / 10 / 20 | TOWERS, TRAPS, WALLS | dies on attack; blast hurts walls, traps, towers, players |
| FLYER_1 / 2 / 3 | 16 / 32 / 47 | 350 / 700 / 1050 | 50 / 100 / 150 | 15 | 2 | ranged, air at 36 studs | 20 / 50 / 5 | (Refinery only) | blast hurts players |
| TITAN_1 / 2 | 90 / 180 | 4000 / 8000 | 500 / 1000 | 5 | 2.5 | melee | 20 / 15 / 0 | TOWERS, TRAPS, WALLS | |
| CAVE_SPIDER (lurker) | 3 | 120 | 20 | 9 | 3 | melee, crawls | 40 / 5 / 0 | PLAYERS | never in a wave |

DPS per body: Zombie 6.7 / 10 / 13.3; Runner 10 / 20 / 30; Brute 26.7 / 53.3 / 80; Launcher 66.7 per blast target; Bomber 100 / 200 / 300 once; Flyer 25 / 50 / 75; Titan 200 / 400.

Engine values that matter for balance (`Monsters/Behavior.luau`): `TICK_RATE_HZ` 10; `BARRIER_COST_CELLS` 60 (a detour under 60 cells beats breaking a wall); `MIN_PASSABLE_GAP_CELLS` 2 (narrower gaps are closed, so monsters break the wall instead); projectile speed 60; `MAX_ALIVE` 500.

Decision history: 2026-09-29 Bombers priced for their blast (three Bomber I or one Bomber III break a tier-1 wall); 2026-10-01 Launcher 2500 HP at 60 points; 2026-10-06 Titans 4000 / 8000 at 90 / 180; 2026-10-08 Flyer attack range 50 (was 100), Cave Spider slowed to 9 and 20 damage every 3 s.

**Status effects** (`shared/StatusRules.luau`): slows never stack, the strongest wins; a stun is a full slow; a knockdown is a stun plus a pose; a burn re-applied keeps the higher rate and the later end. All durations and rates come from the applying item's GameData.

---

## 7. Waves: how a night is built

Files: `Waves/DeadmansCanyon.luau`, `Waves/FrostbitePass.luau` (an identical copy), `Waves/Generation.luau`; rules `shared/WaveRules.luau`, `shared/WaveGenerator.luau`; driver `MonsterWaveManager:buildWave`.

### 7.1 The steps

1. `crew` is the dawn sample; `crewMultiplier = WAVE_DIFFICULTY_MULTIPLIER[crew]`; `waveMultiplier = crewMultiplier * scale` where `scale` is 1 except the final wave's 1.25.
2. If the map has an authored wave for this night (`WAVES` list), its counts are scaled by `waveMultiplier`. **Both maps have `WAVES = {}` today, so every night is generated.**
3. Otherwise `WaveGenerator.generate` runs with the map's `GENERATOR[difficulty]` settings and the shared `Generation` tuning.

### 7.2 The generator, as coded

```
nightIndex   = night - 1
target       = (STARTING_DIFFICULTY + DIFFICULTY_INCREASE_PER_WAVE * nightIndex) * (1 + GROWTH_PER_WAVE) ^ nightIndex * waveMultiplier
unlocked     = kinds with WAVE_UNLOCKED <= night, cheapest first
minGroup     = (MIN_GROUP_DIFFICULTY + MIN_GROUP_DIFFICULTY_PER_NIGHT * nightIndex) * crewMultiplier    -- crew only, not the final-wave scale
groupCount   = max(1, floor(target / minGroup))
group share  = target * weight / sumWeights, weight drawn in [0.5, 1.5]; a share under minGroup is raised at the biggest group's expense
fill         = per group, random unlocked kinds that fit the remaining budget (plus carry-over) until nothing fits
land         = add random fitting kinds while total < target - RANGE; remove cheapest while total > target + RANGE
order        = groups ascending by points, biggest last
timing       = group i at (i-1)/(n-1) * (90 * 0.85) s plus jitter in [-4, 4], first at 0, each capped at previous + maxGap
maxGap       = max(MIN_TIME_BETWEEN_GROUPS_SEC, MAX_TIME_BETWEEN_GROUPS_SEC - GROUP_GAP_SHRINK_SEC_PER_NIGHT * nightIndex)
```

At runtime, when the field is empty and the next group is still waiting, every remaining group moves up so the next spawns now. Monsters scatter over a 15-stud disc round a random spawn part, never the previous group's when there is a choice.

### 7.3 Map values (identical on both maps)

| Key | Value |
|---|---|
| `MIN_GROUP_DIFFICULTY` | 80 |
| `MIN_GROUP_DIFFICULTY_PER_NIGHT` | 5 |
| `WAVE_SPAWN_LENGTH_SEC` | 90 |
| `MAX_TIME_BETWEEN_GROUPS_SEC` | 30 |
| `GROUP_GAP_SHRINK_SEC_PER_NIGHT` | 2 |
| `MIN_TIME_BETWEEN_GROUPS_SEC` | 8 |
| `SPAWN_RADIUS_STUDS` | 15 |
| `Generation`: `GROUP_WEIGHT_MIN` / `MAX`, `LAST_GROUP_WINDOW_SHARE`, `SPAWN_TIME_JITTER_SEC` | 0.5 / 1.5, 0.85, 4 |

### 7.4 Per-difficulty settings and unlock nights

| Setting | NORMAL | HARD | NIGHTMARE |
|---|---|---|---|
| `STARTING_DIFFICULTY` | 22 | 28 | 34 |
| `DIFFICULTY_INCREASE_PER_WAVE` | 16 | 33 | 42 |
| `GROWTH_PER_WAVE` | 0.08 | 0.03 | 0.02 |
| `WAVE_DIFFICULTY_RANGE` | 4 | 4 | 5 |
| Tuned run length | 15 nights | 18 | 20 to 21 |

Unlock night (`WAVE_UNLOCKED`); Hard is Normal two nights earlier, Nightmare four, floored at 1:

| Kind | NORMAL | HARD | NIGHTMARE |
|---|---|---|---|
| ZOMBIE_1 | 1 | 1 | 1 |
| RUNNER_1 | 2 | 1 | 1 |
| BOMBER_1 | 3 | 1 | 1 |
| ZOMBIE_2, BRUTE_1 | 4 | 2 | 1 |
| FLYER_1 | 5 | 3 | 1 |
| RUNNER_2 | 6 | 4 | 2 |
| BOMBER_2 | 7 | 5 | 3 |
| ZOMBIE_3, BRUTE_2 | 8 | 6 | 4 |
| LAUNCHER_1 | 9 | 7 | 5 |
| FLYER_2 | 10 | 8 | 6 |
| TITAN_1, RUNNER_3 | 11 | 9 | 7 |
| BOMBER_3, BRUTE_3 | 12 | 10 | 8 |
| FLYER_3 | 15 | 13 | 11 |
| TITAN_2 | 20 | 18 | 16 |

Solo target points by night (computed from the formula; groups = `floor(target / minGroup)`, min 1):

| Night | NORMAL (points / groups) | HARD | NIGHTMARE | minGroup | max gap s |
|---|---|---|---|---|---|
| 1 | 22 / 1 | 28 / 1 | 34 / 1 | 80 | 30 |
| 2 | 41 / 1 | 63 / 1 | 78 / 1 | 85 | 28 |
| 3 | 63 / 1 | 100 / 1 | 123 / 1 | 90 | 26 |
| 4 | 88 / 1 | 139 / 1 | 170 / 1 | 95 | 24 |
| 5 | 117 / 1 | 180 / 1 | 219 / 2 | 100 | 22 |
| 6 | 150 / 1 | 224 / 2 | 269 / 2 | 105 | 20 |
| 8 | 230 / 1 | 319 / 2 | 377 / 3 | 115 | 16 |
| 10 | 332 / 2 | 424 / 3 | 492 / 3 | 125 | 12 |
| 12 | 462 / 3 | 541 / 4 | 617 / 4 | 135 | 8 |
| 15 | 723 / 4 | 741 / 4 | 821 / 5 | 150 | 8 |
| 18 | 1,090 / 6 | 974 / 5 | 1,047 / 6 | 165 | 8 |
| 21 | | 1,243 / 6 | 1,299 / 7 | 180 | 8 |

A crew of N multiplies both the target and minGroup by `WAVE_DIFFICULTY_MULTIPLIER[N]`, so the group count matches solo and each group is that much bigger.

### 7.5 The final wave

`finalWaveNight(day) = day + 1`, target scaled by `crewMultiplier * 1.25`, minGroup by `crewMultiplier` alone, so the extra budget tends to add a group rather than enlarge them. Example: solo Normal, radio called on day 10: night 11's 393 x 1.25 = 491 points, minGroup 130, 3 groups.

Decision history: 2026-09-24 linear increment compounded by a small growth, one knob for group count, no one-kind rule; 2026-09-29 Normal start 22, group minimum 80, 15 / 18 / 21 nights, 90 s window and 30 s gap cap after the eighth playtest; 2026-10-01 minimum climbs 5 a night and the gap cap shrinks 2 s a night to 8 s so late groups overlap (ninth playtest: from night 7 every group died before the next arrived).

---

## 8. Handheld weapons: `Weapons/Handheld.luau`, `Weapons/Upgrades.luau`

Hitscan with a magazine and unlimited reserve. A `SCOPE` block zooms; a `CONE` block hits everything in the cone every tick and stacks a burn; a `SECONDARY` block is a grenade on its own cooldown. Class `HANDHELD_DAMAGE` multiplies every shot (Ranger 1.3, Hauler 0.7).

| Weapon | Damage | Interval s | Range | Magazine | Reload s | Burst DPS | Sustained DPS | Special |
|---|---|---|---|---|---|---|---|---|
| RIFLE (default, lever action) | 60 | 0.6 | 300 | 5 | 2.5 | 100 | 54.5 | |
| PISTOL | 22 | 0.3 | 120 | 8 | 1.2 | 73 | 48.9 | |
| SNIPER | 220 | 1.4 | 600 | 4 | 3 | 157 | 102 | scope FOV 13 |
| FLAMETHROWER | 5 per tick | 0.1 | 22 | 60 ticks (6 s) | 3 | 50 plus burn | | cone 24 deg; burn 8/s for 3 s per tick |
| ASSAULT_RIFLE | 18 | 0.1 | 250 | 30 | 1.6 | 180 | 117 | grenade: 120 dmg, 10 splash, 8 s cooldown, 200 range |

Sustained DPS = `damage * magazine / (magazine * interval + reload)`. Headshots: `HEADSHOT_MULTIPLIER` 1 for every hand weapon (none).

Upgrade ladder (Weapons Table, Iron, three attributes, four rungs each): prices 10 / 40 / 120 / 300; DAMAGE +25% per rung (2.0x at 4), AMMO +20% (rounded to whole rounds), RANGE +20%. Full ladder 470 Iron per attribute. Interval, reload, cone, and grenade numbers are not upgradable.

---

## 9. Post weapons: `Posts/PostWeapons.luau`, `shared/PostRules.luau`

A post is a free claimed turret with no magazine; its pace is the fire interval, a per-shot reload, or a heat budget. Each kind has exactly four upgrade rows bought at the Post & Gadget Upgrades table for 10 / 40 / 120 / 300 Iron. `PostRules.statsFor` rebuilds the stats from the base and the levels; `PostManager` then applies the class `POST_DAMAGE` (set by no class).

| Attribute | Per level | Effect |
|---|---|---|
| DAMAGE | 0.25 | damage x (1 + 0.25 L) |
| FIRE_RATE | 0.2 | interval, reload, charge time / (1 + 0.2 L) |
| TURN_SPEED | 0.5 | turn x (1 + 0.5 L) |
| RANGE | 0.2 | range, chain jump, pull radius x (1 + 0.2 L) |
| COOLDOWN | 1/6 | cool time x max(1 - L/6, 0.05): subtractive, the same half second per rung |
| HEADSHOT | 0.25 | multiplier + 0.25 L (additive) |
| IMPACT_RADIUS | 0.2 | splash and pool radius x (1 + 0.2 L) |
| FIRE_DAMAGE | 0.25 | damage and pool burn x (1 + 0.25 L) |
| FIRE_LENGTH | 0.25 | pool and burn seconds x (1 + 0.25 L) |
| LOCK_COUNT | 1 | +1 lock per level |
| DURATION | 0.25 | knockdown seconds x (1 + 0.25 L) |

Heat: `heatPerShot = heldSec / FULL_SEC`; a gap over `max(1.5 * interval, 0.25)` s counts as rest and cools at `1 / COOL_SEC` per second; overheated at 1, fires again at 0. Sustained heat DPS = `damage / interval * FULL / (FULL + COOL)`. Charge (Railgun): damage share is the square of the charge reached.

| Kind | Class | Damage | Interval or reload s | Turn | Range | Rows | Mechanic and sustained DPS |
|---|---|---|---|---|---|---|---|
| MACHINE_GUN (default, the yardstick) | Recruit | 12 | 0.1 | 22 | 350 | DAMAGE, FIRE_RATE, TURN_SPEED, COOLDOWN | heat 4 s full / 3 s cool: 120 firing, 69 sustained |
| MINI_GUN | Gunner | 11.25 | 0.06 | 16 | 350 | same as MG | heat 6 / 4, fixed 1 s spin-up: 187.5 firing, about 102 sustained (the Gunner's old +25% post damage folded into the base, 2026-10-20) |
| RAIL_GUN | Sniper | 260 | 0.5 | 10 | 600 | DAMAGE, FIRE_RATE, TURN_SPEED, HEADSHOT | charge 4 s, fires on release, pierces 2 bodies, headshot 3x (780 full charge) |
| ROCKET_LAUNCHER | Pyro | 200 | 6 | 12 | 500 | DAMAGE, FIRE_RATE, TURN_SPEED, RANGE | rocket at 120, splash 12: 33 single, about 100 into a group |
| MORTAR (TNT Launcher) | Demolitionist | 100 | 5 | 20 | 260 | IMPACT_RADIUS, FIRE_DAMAGE, TURN_SPEED, FIRE_LENGTH | lobbed at 60 deg, splash 8; pool radius 10 for 6 s burning 18/s for 3 s |
| AA_LAUNCHER (Missile Launcher) | Air Defense | 280 | 3 | 20 | 400 | DAMAGE, IMPACT_RADIUS, LOCK_COUNT, TURN_SPEED | homing, splash 5; lock 0.75 s each, 2 locks (+1 per level to 6), ground locks at 60% damage, dumb fire 50% |
| MACHINE_GUN_AUTOMATED | Ranger | 6 | 0.1 | 30 | 200 | same as MG | unmanned, aims itself; heat 3 / 4: 60 firing, about 26 sustained |
| DRILL_GUN (Fault Line Drill) | Prospector | 100 | 4 | 30 | 220 | DURATION, DAMAGE, FIRE_RATE, TURN_SPEED | gravity projectile; where it lands a 100 x 10 stud crack races out at 110 studs/s, hits every body standing on it and knocks it down 2.5 s |
| MINE_LAYER | Engineer (unbuilt) | 110 | 2 | 16 | 180 | DAMAGE, FIRE_RATE, TURN_SPEED, RANGE | lobbed proximity mines, 12 armed max, 4 stud trigger, fizzle at dawn |
| TESLA_ARC | Electrician (post launch) | 9 | 0.2 | 20 | 160 | DAMAGE, FIRE_RATE, TURN_SPEED, RANGE | chains to 3 more bodies within 12 studs: 45 per body |
| SAW_GUN | Hauler (unbuilt) | 70 | 1.5 | 14 | 220 | DAMAGE, FIRE_RATE, TURN_SPEED, RANGE | piercing blade, every body once |
| MAGNET_GUN | Medic (post launch) | 0 | 6 | 18 | 250 | DAMAGE, FIRE_RATE, TURN_SPEED, RANGE | pulls every monster within 18 studs of the landing to it for 3 s |

Decision history: MG 15 to 12 (2026-09-29, "every enemy felt easy"); Minigun a 6 s / 1 s spin burst weapon (2026-10-19); Railgun 4 s proportional-squared charge, Headshot row replaces Range (2026-10-19); Mortar 100 damage and 18 burn (designer 2026-10-23); Missile Launcher 280 so the first Damage rung drops a 350 HP Flyer (2026-10-21); Drill Gun 100 / 4 s (designer 2026-10-23).

---

## 10. Towers, traps, and placement: `Defenses/*`

Built in Build Mode at the Defense Table on the Defensive Zone grid (4-stud cells; cells within 2 of a wall, post, or gate are reserved). Towers have five levels; `UPGRADE_PRICE_IRON_BY_LEVEL[N]` is the price of level N+1. Traps are never upgraded. Selling returns half of everything spent. Range is measured from the footprint edge (`reach = RANGE + 8` for a 4x4 tower). A level upgrade keeps the HP share. `MAX_ACTIVE_TOWERS_CAMP` 12, shared: each player may hold `ceil(12 / crew)`. Class `DEFENSE_COST` scales prices (set by no class).

**SENTRY_GUN** (default; Recruit, Gunner, Ranger, Engineer). Build 50 (60 before 2026-10-23). Upgrades 30 / 60 / 120 / 240.

| Lvl | Damage | Interval | DPS | Range | HP |
|---|---|---|---|---|---|
| 1 | 12 | 0.5 | 24 | 40 | 150 |
| 2 | 16 | 0.45 | 36 | 44 | 180 |
| 3 | 20 | 0.4 | 50 | 48 | 220 |
| 4 | 26 | 0.35 | 74 | 52 | 270 |
| 5 | 32 | 0.3 | 107 | 60 | 330 |

**FLAMETHROWER** (Pyro, Demolitionist; 60 deg cone, 0.2 s ticks for a flame, then 1.5 s rest). Build 90. Upgrades 45 / 75 / 150 / 300.

| Lvl | Damage per tick | Flame s | Range | HP | Cycle-average DPS |
|---|---|---|---|---|---|
| 1 | 6 | 2 | 18 | 180 | 17 |
| 2 | 8 | 2.4 | 20 | 220 | 25 |
| 3 | 10 | 2.8 | 22 | 270 | 33 |
| 4 | 12 | 3.2 | 24 | 330 | 41 |
| 5 | 16 | 4 | 28 | 400 | 58 |

**AA_TURRET** (Missile Turret; Air Defense; ground and air, prefers air). Build 105. Upgrades 45 / 75 / 150 / 300.

| Lvl | Damage | Interval | DPS | Range | HP |
|---|---|---|---|---|---|
| 1 | 20 | 0.4 | 50 | 70 | 150 |
| 2 | 26 | 0.36 | 72 | 76 | 180 |
| 3 | 32 | 0.32 | 100 | 82 | 220 |
| 4 | 40 | 0.28 | 143 | 90 | 270 |
| 5 | 50 | 0.24 | 208 | 100 | 330 |

**FROST_TOWER** (Hauler, Medic; cone, no damage, strongest slow wins). Build 90. Upgrades 45 / 75 / 150 / 300. Slow share 0.3 / 0.35 / 0.4 / 0.5 / 0.6 for 2 / 2.5 / 3 / 3.5 / 4 s; range 24 to 42; HP 200 to 420.

**TESLA_COIL** (Electrician; chain, 0.4 s stun each). Build 120. Upgrades 45 / 105 / 210 / 420. Damage 24 / 30 / 38 / 48 / 60 every 1.2 / 1.1 / 1.0 / 0.9 / 0.8 s to 1 + chain (1 / 2 / 2 / 3 / 4) bodies within 14 studs; range 30 to 45; HP 170 to 350.

**SNIPER_TOWER** (Sniper). Build 135. Upgrades 45 / 105 / 210 / 420. Damage 80 / 100 / 124 / 156 / 200 every 2.5 / 2.3 / 2.1 / 1.9 / 1.7 s (32 to 118 DPS); range 120 to 175; HP 200 to 420.

**DRILL_RIG** (Prospector; no attack, zero DPS in the model, counts against the cap). Build 90. Upgrades 45 / 75 / 150 / 300. Yield 4 / 5 / 6 / 8 / 10 ore per minute into a stock capped at 20 / 26 / 32 / 40 / 50, split 70% iron ore / 30% gold ore, collected into the backpack within 12 studs; HP 200 to 420.

**Traps** (Iron, consumable, air units never touch one):

| Trap | Iron | HP | Cells | Effect |
|---|---|---|---|---|
| WALL | 10 (12 before 2026-10-23) | 300 | 4x2 | barrier, repairable |
| SPIKE_TRAP | 15 | 120 | 4x4 | 25 damage to everything on it, up 1 s, recharge 3 s |
| GOO_PIT | 10 | 100 | 4x2 | slow 0.5 for 1.5 s after leaving |
| LAND_MINE | 20 | 60 | 2x2 | 120 damage within 10 studs, once |
| BEAR_TRAP | 8 | 80 | 2x2 | 40 damage and a full stop for 3 s to one crosser, once |
| DECOY | 18 | 400 | 2x2 | draws attacks within 30 studs |

Decision history: every tower's damage doubled 2026-09-30 (towers by night 4 shot less than the rifle; target: towers about half the defense early, about 60% at cap against a maxed post); all prices tripled 2026-10-06 (a run won on day 14 with maxed towers by night 10); cap shared out among the crew 2026-09-28.

---

## 11. Camp structures: `Camp/Structures.luau`, `shared/StructureRules.luau`

Walls, the gate, and the Refinery share one fortification tier, raised at the Walls Table by donations into a shared pool. Repair is a Hammer swing: the tier's chunk of HP for the tier's chunk of Iron (1 Iron per 10 HP at every tier). Rubble is rebuilt swing by swing and stands again only at full.

| Structure | Tier 1 HP | Tier 2 | Tier 3 |
|---|---|---|---|
| WALL | 300 | 600 | 1200 |
| GATE | 450 | 900 | 1800 |
| REFINERY | 1000 | 2000 | 4000 |

| Tier reached | Solo Iron (`FORTIFICATION_UPGRADE_IRON_TO_TIER`) | Donation per press | Repair chunk HP / Iron |
|---|---|---|---|
| 1 | 0 | 10 | 30 / 1 |
| 2 | 150 | 20 | 60 / 2 |
| 3 | 400 | 40 | 120 / 4 |

`scaledUpgradeCost = ceil(cost * WAVE_DIFFICULTY_MULTIPLIER[crew] / donation) * donation`: four players pay 360 then 960. Class `REPAIR_SPEED` scales chunk HP and `REPAIR_COST` chunk Iron (Medic 2.0 / 0.5). Hammer interval 0.45 s, reach 17.

Decision history: walls and gate +50% (2026-09-25); Refinery joined the tier (2026-09-29); repair chunk tripled to 30 / 60 / 120 (2026-10-06, repairs ate every Iron from day 10); donation doubles per tier (2026-10-08).

---

## 12. Gadgets: `Gadgets/*.luau`, `Mining/Dynamite.luau`

A class's gadget is a tool slot (the Binoculars are fused with the Railgun post instead). Only the Auto Turret and the Remote Charge have upgrade ladders (one level per player per run, at the Post & Gadget Upgrades table, 30 / 60 / 120 / 240 Iron).

| Gadget | Class | Numbers |
|---|---|---|
| AUTO_TURRET | Gunner | free, one standing; a player target to monsters (draw 30 studs); lost until dawn when destroyed. Levels 1 to 5: damage 8 / 10 / 13 / 17 / 22 every 0.25 / 0.23 / 0.21 / 0.19 / 0.17 s (32 to 129 DPS), range 90 to 120, HP 100 to 210 |
| BINOCULARS | Sniper | tag one monster for 10 s: every hit on it x1.3 (through the damage-taken multiplier, so towers and turrets honour it); 10 s cooldown; range 600 |
| REMOTE_CHARGE | Pyro | a planted mine detonated from anywhere; 15 s cooldown after. Levels: damage 150 / 170 / 195 / 225 / 260, burst radius 14 to 22, pool 6 to 10 s at 0.7 x radius burning 12/s |
| STIM_SHOT | Ranger | heal up to 50% of max, speed x1.3 and invulnerable for 20 s; one use per day |
| FLARE | Air Defense | fired from the Flare Gun; burns 12 s, draws every monster within 30 studs; 45 s cooldown; no upgrades (designer 2026-10-21) |
| ORE_SCANNER | Prospector | reveals every ore block within 30 studs to the crew; 300 s cooldown |
| DYNAMITE | Demolitionist | one stick, the next 90 s after a throw; 3 s fuse; clears a 3x3x3 block cube (ore drops); 120 damage to monsters within 10 studs |

Unbuilt: BUILD_TABLET (Engineer), STORM_ROD (Electrician), ORE_CART (Hauler), MEDKIT (Medic).

---

## 13. Classes: `Classes/Roster.luau`, `shared/ClassRules.luau`

A class is a fixed kit (exactly one weapon, post, tower, gadget) and a table of `Enums.ClassModifier` scales, 1.0 when absent. The place a stat is computed asks `CharacterManager:getModifier`; nothing checks the class by name. The Recruit is the free baseline every class must beat on solo Normal. Decision 2026-10-22/23: every class swings alike on damage; price modifiers were tried for a day and dropped; the debuff is `MINING_SPEED`, "about 2% of pace per 10% of combat over the Recruit".

| Class | Status | Weapon | Post | Tower | Gadget | MINING_SPEED | Other |
|---|---|---|---|---|---|---|---|
| RECRUIT | built, default | PISTOL | MACHINE_GUN | SENTRY_GUN | none | 1.0 | |
| GUNNER | built | RIFLE | MINI_GUN | SENTRY_GUN | AUTO_TURRET | 0.75 | |
| SNIPER | built | PISTOL | RAIL_GUN | SNIPER_TOWER | BINOCULARS | 0.85 | LARGE_MONSTER_DAMAGE 1.5 (applied nowhere) |
| PYRO | built | FLAMETHROWER | ROCKET_LAUNCHER | FLAMETHROWER | REMOTE_CHARGE | 0.9 | |
| AIR_DEFENSE | built | RIFLE | AA_LAUNCHER | AA_TURRET | FLARE | 0.8 | |
| RANGER | built | ASSAULT_RIFLE | MACHINE_GUN_AUTOMATED | SENTRY_GUN | STIM_SHOT | 0.7 | HANDHELD_DAMAGE 1.3, MOVE_SPEED 1.1 |
| PROSPECTOR | built | PISTOL | DRILL_GUN | DRILL_RIG | ORE_SCANNER | 1.2 | ORE_YIELD 1.2 |
| DEMOLITIONIST | built | PISTOL | MORTAR | FLAMETHROWER | DYNAMITE | 1.1 | |
| ENGINEER | UNBUILT | RIFLE | MINE_LAYER | SENTRY_GUN (stand-in) | BUILD_TABLET | 1.0 | |
| HAULER | UNBUILT | PISTOL | SAW_GUN | FROST_TOWER (stand-in) | ORE_CART | 1.0 | BACKPACK_CAPACITY 1.5, HANDHELD_DAMAGE 0.7 |
| ELECTRICIAN | UNBUILT, POST_LAUNCH | RIFLE | TESLA_ARC | TESLA_COIL | STORM_ROD | 1.0 | |
| MEDIC | UNBUILT, POST_LAUNCH | PISTOL | MAGNET_GUN | FROST_TOWER (stand-in) | MEDKIT | 1.0 | REPAIR_SPEED 2.0, REPAIR_COST 0.5 |

Where each modifier is applied:

| Modifier | Applied in | Stat |
|---|---|---|
| MINING_SPEED | `MiningManager` | hit cooldown `0.35 / mod`, swing interval `0.45 / mod`: Ranger 0.64 s, Gunner 0.6, Air Defense 0.56, Sniper 0.53, Pyro 0.5, Recruit 0.45, Demolitionist 0.41, Prospector 0.375 |
| HANDHELD_DAMAGE | `WeaponManager` | every shot, cone tick, grenade |
| MOVE_SPEED | `BootsManager` | walk speed |
| BACKPACK_CAPACITY | `BackpackManager` | capacity |
| ORE_YIELD | `MiningManager` | ore per break, after crew scaling |
| REPAIR_SPEED, REPAIR_COST | `StructureManager`, `PlacementManager` | Hammer chunk HP and Iron |
| MINING_POWER, POST_DAMAGE, DEFENSE_COST, MINING_UPGRADE_COST, MAX_HEALTH | plumbed | set by no class; a value in the roster shows and charges at once |
| LARGE_MONSTER_DAMAGE | nowhere | the Sniper's 1.5 is data only |

### Characters: stars and progression

Stars (1 to 5, `BONUS_PER_STAR` 0.05, `Characters/Stars.luau`) are stored and shown but **applied to no stat yet** (planned for M56). Skill slots open at 5 / 15 / 50 nights survived (`Characters/Progression.luau`). Characters have no level or XP. Skills (`Characters/Skills.luau`) are a catalogue with rarities and no gameplay effect yet.

---

## 14. The balance model and the audit

`shared/BalanceModel.luau` (pure) simulates a run night by night from GameData alone; `Control/Balance.luau` holds the targets and the assumptions; `gameplay/server/BalanceAudit.luau` maps GameData into the model and checks the result. It runs at every gameplay server start (the last startup line in the Output is any missed target), from the Monsters dev panel ("Balance sheet (Output)"), and in Edit mode through `scripts/studio/balance_sheet.luau`.

**Each day** the crew swings for `DAY_SEC - DAY_OVERHEAD_SEC` less backpack trips (each a walk from the tunnel front to the Refinery and back at the boots' speed, plus the 4 s grind). HP mined becomes ore at the zone's ore-per-HP times a selectivity per resource (uranium hunted 10x, gold 2x, iron 0.8x). Gold is split pick 50% / backpack 30% / boots 15% and buys rungs one at a time; Iron pays each player's post rungs (25%) first, then 80% of the rest buys towers greedily by DPS per Iron up to the cap. **Each night** the wave budget times the expected HP per point over the unlocked kinds is the wave HP; required DPS is wave HP over the spawn window plus 60 s; available is crew x free-weapon DPS x uptime plus tower DPS x coverage; slack is their ratio. The leak is what survives the 20 s walk to the wall, spread over 3 segments, as a share of a tier-1 wall. It also reports the final-wave slack a rescue called that day would face.

Targets (`Control/Balance.luau`): `TARGET_NIGHTS` 15 / 18 / 20; `BREACH_NIGHT` 4 / 2 / 2 (Hard and Nightmare bring Runners, Bombers, and Brutes on night 2); `MAX_WALL_DAMAGE_SHARE` 1.5; `GOLD_BY_NIGHT_1` 20; tolerances 1 night solo, 2 crew; audited crews 1, 4, 6; audited map Deadman's Canyon; crews within 2 nights of solo.

Assumptions (`Balance.ASSUMPTIONS`): `DAY_OVERHEAD_SEC` 60 (run reports read 85 to 110), `REFINERY_TO_ENTRANCE_STUDS` 64, `ORE_SELECTIVITY` 0.8, `GOLD_SELECTIVITY` 2.0 (reports read about 2.5), `URANIUM_SELECTIVITY` 10, `ZONE_ADVANCE_SHARE` 0.15 (the least known), `TOWER_COVERAGE` 0.6, `WEAPON_UPTIME` 0.5, `CLEAR_SLACK_SEC` 60, `DEFENSE_IRON_SHARE` 0.8, `POST_IRON_SHARE` 0.25, Gold shares 0.5 / 0.3 / 0.15, `POST_EFFECTIVENESS` 0.6, `WALL_WALK_SEC` 20, `WALL_SEGMENTS_HIT` 3, `TOWER_NEEDED_SLACK` 1.75, `CREW_ADVANCE_EXPONENT` 0.6.

Rule from the file: the targets are the designer's answers; the assumptions are the model's guesses, corrected from the run reports, never from the data they are checked against.

Known limits (from `docs/balance-plan.md`): the model measures a night as one lump against total DPS, so it cannot see the per-moment plateau the ninth playtest showed (every group dead before the next arrived); it does not see siege range (the Launcher); it ignores overflow ore, the jet pack, dynamite, torches, death, the Refinery's own HP, traps, class mining speeds, and the Geiger Counter. As of 2026-10-01 the sheet reported 24 misses, mostly Hard and Nightmare nights already failing.

---

## 15. Comments that disagree with their values

Found while writing this; the values are current, the comments are stale. Fix the comment when you next touch the file.

- `Rocks/RockDefinitions.luau` header: "Gold quadruples and Iron doubles a tier"; both are 2 / 6 / 18 / 54 / 162 since 2026-10-07.
- `Mining/JetPack.luau` header: "42 studs at level 5" was computed with 0.5 s per level; it is 66 studs at the current 1.0.
- `Store/MiningSupplies.luau` header: "3 / 10 / 30 / 87 ore per rock" is the old ladder.
- `Control/Difficulty.luau` header: hardness clamps to 1 to 4; the filler order has 5 tiers.
- `shared/GadgetRules.luau` header names the Grounding Net and Storm Rod as upgradable; only the Auto Turret and Remote Charge have ladders.
- `docs/balance-plan.md` "Assumptions to calibrate" lists `MINING_SHARE_OF_DAY`, which the trip model replaced with `DAY_OVERHEAD_SEC`.
- `Waves/*` comments say Nightmare is tuned to 21 nights; `Control/Balance.TARGET_NIGHTS` holds 20 (21 was unholdable).

---

## 16. Where to go next

- The history, with every playtest's findings and the open items: `docs/balance-plan.md`.
- The design intent in the designer's words: `gdd.txt`.
- The calibration source: the run report in the Output at every dawn, and `scripts/studio/pull_run_records.luau` for the saved records.
- Open items recorded on 2026-10-01: pull Iron back (veins 192 to about 128 per zone, since outpaced by the 2026-10-11 increases), teach the model the group split, Hard and Nightmare pacing, crews (a crew of four or more strips every zone), a late Gold sink, Frostbite Pass's own mine and waves.
