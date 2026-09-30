-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local BalanceModel = require(game:GetService("ReplicatedStorage").Shared.BalanceModel)

-- kinds and resources by number so the spec does not depend on the enums
local ZOMBIE = 1
local FLYER = 2
local LAND = 1
local AIR = 2
local IRON = 1
local GOLD = 2
local CRYSTAL = 3
local URANIUM = 4
local SENTRY = 1
local FLAME = 2
local TESLA = 3

local ATTACK = {
	SINGLE = 1,
	CONE = 2,
	CHAIN = 3,
}

local MONSTERS = {
	[ZOMBIE] = { DIFFICULTY_VALUE = 2, MAX_HP = 100, TRAVERSAL = LAND, DPS = 10 },
	[FLYER] = { DIFFICULTY_VALUE = 25, MAX_HP = 350, TRAVERSAL = AIR, DPS = 50 },
}

local SENTRY_DATA = {
	BUILD_PRICE_IRON = 30,
	UPGRADE_PRICE_IRON_BY_LEVEL = { 15, 30 },
	BEHAVIOR = { ATTACK = ATTACK.SINGLE },
	STATS_BY_LEVEL = {
		{ DAMAGE = 6, FIRE_INTERVAL_SEC = 0.5, MAX_HP = 150 },
		{ DAMAGE = 8, FIRE_INTERVAL_SEC = 0.4, MAX_HP = 180 },
		{ DAMAGE = 10, FIRE_INTERVAL_SEC = 0.4, MAX_HP = 220 },
	},
}
local FLAME_DATA = {
	BUILD_PRICE_IRON = 45,
	UPGRADE_PRICE_IRON_BY_LEVEL = {},
	BEHAVIOR = { ATTACK = ATTACK.CONE, TICK_INTERVAL_SEC = 0.2, REST_SEC = 1.5 },
	STATS_BY_LEVEL = {
		{ DAMAGE = 3, FLAME_SEC = 2, MAX_HP = 180 },
	},
}
local TESLA_DATA = {
	BUILD_PRICE_IRON = 60,
	UPGRADE_PRICE_IRON_BY_LEVEL = {},
	BEHAVIOR = { ATTACK = ATTACK.CHAIN },
	STATS_BY_LEVEL = {
		{ DAMAGE = 12, FIRE_INTERVAL_SEC = 1.2, CHAIN_COUNT = 1, MAX_HP = 170 },
	},
}
local TOWERS = {
	[SENTRY] = SENTRY_DATA,
	[FLAME] = FLAME_DATA,
	[TESLA] = TESLA_DATA,
}

local ASSUMPTIONS = {
	DAY_OVERHEAD_SEC = 0,
	ORE_SELECTIVITY = 1,
	GOLD_SELECTIVITY = 1,
	ZONE_ADVANCE_SHARE = 0.5,
	TOWER_COVERAGE = 1,
	WEAPON_UPTIME = 1,
	CLEAR_SLACK_SEC = 40,
	DEFENSE_IRON_SHARE = 1,
	PICK_AXE_GOLD_SHARE = 1,
	BACKPACK_GOLD_SHARE = 0,
	BOOTS_GOLD_SHARE = 0,
	URANIUM_SELECTIVITY = 1,
	TOWER_NEEDED_SLACK = 1,
	CREW_ADVANCE_EXPONENT = 1,
	POST_GOLD_SHARE = 1,
	POST_EFFECTIVENESS = 1,
	WALL_WALK_SEC = 10,
	WALL_SEGMENTS_HIT = 1,
}

local function settings(overrides)
	local value = {
		STARTING_DIFFICULTY = 10,
		DIFFICULTY_INCREASE_PER_WAVE = 10,
		GROWTH_PER_WAVE = 0,
		WAVE_DIFFICULTY_RANGE = 4,
		AVAILABLE_ENEMIES = {
			{ KIND = ZOMBIE, WAVE_UNLOCKED = 1 },
			{ KIND = FLYER, WAVE_UNLOCKED = 3 },
		},
	}
	for key, override in overrides or {} do
		value[key] = override
	end
	return value
end

-- one day of 100 swings at 10 damage is 1000 HP; zone 1 holds 2000 HP
-- with 200 iron, 100 gold, 40 crystal, 10 uranium; zone 2 is richer
local function input(overrides)
	local value = {
		assumptions = ASSUMPTIONS,
		crew = 1,
		nights = 4,
		daySec = 100,
		hitIntervalSec = 1,
		pickDamageByLevel = { 10, 20 },
		pickPriceByLevel = { 0, 50 },
		pickRequiredCampLevelByLevel = { 1, 2 },
		diamondsRequiredByLevel = { 20 },
		zones = {
			{ ore = { [IRON] = 200, [GOLD] = 100, [CRYSTAL] = 40, [URANIUM] = 10 }, hp = 2000, depthStartBlocks = 0, depthBlocks = 10 },
			{ ore = { [IRON] = 400, [GOLD] = 400, [CRYSTAL] = 80, [URANIUM] = 100 }, hp = 4000, depthStartBlocks = 10, depthBlocks = 10 },
		},
		-- a bottomless backpack and no walk keep the other tests' arithmetic
		backpack = { valueByLevel = { 1000000 }, priceByLevel = { 0 }, requiredCampLevelByLevel = { 1 } },
		boots = { valueByLevel = { 16 }, priceByLevel = { 0 }, requiredCampLevelByLevel = { 1 } },
		refineSec = 0,
		refineryToEntranceStuds = 0,
		blockSizeStuds = 4,
		ironResource = IRON,
		goldResource = GOLD,
		crystalResource = CRYSTAL,
		uraniumResource = URANIUM,
		refineRateByRaw = {},
		oreYieldMultiplier = 1,
		uraniumTarget = 20,
		waveSettings = settings(),
		waveMultiplier = 1,
		enemyHpMultiplier = 1,
		monsterByKind = MONSTERS,
		airTraversal = AIR,
		spawnWindowSec = 60,
		minGroupDifficulty = 40,
		wallHp = 100,
		handheldDps = 10,
		postDps = 0,
		postUpgrades = nil,
		towerKinds = { SENTRY },
		towerByKind = TOWERS,
		towerAttackKinds = ATTACK,
		maxTowers = 5,
		finalWaveMultiplier = 1.5,
	}
	for key, override in overrides or {} do
		value[key] = override
	end
	return value
end

describe(
	"BalanceModel weapons and towers",
	function()
		it(
			"sums a magazine's shots over the shots and the reload",
			function()
				-- 5 shots of 60 over 3 s of firing plus 2.5 s of reload
				expect(BalanceModel.magazineDps(60, 0.6, 5, 2.5)).toBeCloseTo(300 / 5.5, 5)
				expect(BalanceModel.magazineDps(60, 0, 0, 0)).toBe(0)
			end
		)
		it(
			"halves a heat weapon that overheats as long as it cools",
			function()
				expect(BalanceModel.heatDps(12, 0.1, 3, 3)).toBeCloseTo(60, 5)
				expect(BalanceModel.heatDps(12, 0, 3, 3)).toBe(0)
			end
		)
		it(
			"reads single, cone, and chain towers by their shape",
			function()
				expect(BalanceModel.towerDps(SENTRY_DATA, 1, ATTACK)).toBeCloseTo(12, 5)
				expect(BalanceModel.towerDps(SENTRY_DATA, 2, ATTACK)).toBeCloseTo(20, 5)
				-- 15 a second while burning, burning 2 of every 3.5 s
				expect(BalanceModel.towerDps(FLAME_DATA, 1, ATTACK)).toBeCloseTo(15 * 2 / 3.5, 5)
				-- the bolt and one jump
				expect(BalanceModel.towerDps(TESLA_DATA, 1, ATTACK)).toBeCloseTo(20, 5)
				expect(BalanceModel.towerDps(SENTRY_DATA, 9, ATTACK)).toBe(0)
			end
		)
		it(
			"spends Iron on the most DPS per Iron first and stops at the cap",
			function()
				-- a sentry is 12 DPS for 30 (0.4 an Iron); its first upgrade is
				-- +8 for 15 (0.53), so the upgrade comes before a second sentry
				local dps, count, spent = BalanceModel.planTowers(45, { SENTRY }, TOWERS, 5, ATTACK)
				expect(count).toBe(1)
				expect(spent).toBe(45)
				expect(dps).toBeCloseTo(20, 5)
				-- with 60: sentry (30), upgrade (15), then 15 left buys nothing
				dps, count, spent = BalanceModel.planTowers(60, { SENTRY }, TOWERS, 5, ATTACK)
				expect(count).toBe(1)
				expect(spent).toBe(45)
				-- a cap of 1 with plenty of Iron upgrades to the top and stops
				dps, count, spent = BalanceModel.planTowers(1000, { SENTRY }, TOWERS, 1, ATTACK)
				expect(count).toBe(1)
				expect(spent).toBe(75)
				expect(dps).toBeCloseTo(25, 5)
				-- nothing affordable builds nothing
				dps, count, spent = BalanceModel.planTowers(10, { SENTRY }, TOWERS, 5, ATTACK)
				expect(count).toBe(0)
				expect(dps).toBe(0)
			end
		)
		it(
			"weights expected HP per point over the unlocked kinds and reports the flying share",
			function()
				local hpPerPoint, airShare = BalanceModel.expectedHpPerPoint({ ZOMBIE }, MONSTERS, AIR)
				expect(hpPerPoint).toBeCloseTo(50, 5)
				expect(airShare).toBe(0)
				hpPerPoint, airShare = BalanceModel.expectedHpPerPoint({ ZOMBIE, FLYER }, MONSTERS, AIR)
				expect(hpPerPoint).toBeCloseTo((50 + 14) / 2, 5)
				expect(airShare).toBeCloseTo(14 / 64, 5)
				hpPerPoint = BalanceModel.expectedHpPerPoint({}, MONSTERS, AIR)
				expect(hpPerPoint).toBe(0)
			end
		)
	end
)

describe(
	"BalanceModel walls",
	function()
		it(
			"leaks nothing when the walk kills a whole group",
			function()
				-- one group of 600 HP against 100 DPS over a 10 s walk
				expect(BalanceModel.wallHpSeconds(600, 1, 100, 10)).toBe(0)
				expect(BalanceModel.wallHpSeconds(1000, 1, 100, 10)).toBe(0)
				expect(BalanceModel.wallHpSeconds(0, 1, 100, 10)).toBe(0)
			end
		)
		it(
			"sums the survivors' HP-seconds at the wall, group by group",
			function()
				-- one group of 2000 HP: 1000 survive the walk and die over 10 s,
				-- so 1000 x 10 / 2 = 5000 HP-seconds
				expect(BalanceModel.wallHpSeconds(2000, 1, 100, 10)).toBeCloseTo(5000, 3)
				-- the same HP in two groups: 1000 each, nothing survives the walk
				expect(BalanceModel.wallHpSeconds(2000, 2, 100, 10)).toBe(0)
				-- four groups of 2000: four times one
				expect(BalanceModel.wallHpSeconds(8000, 4, 100, 10)).toBeCloseTo(20000, 3)
				expect(BalanceModel.wallHpSeconds(2000, 1, 0, 10)).toBe(math.huge)
			end
		)
		it(
			"rates wall pressure per HP over the walking kinds and reports their share",
			function()
				local dpsPerHp, landShare = BalanceModel.wallPressure({ ZOMBIE }, MONSTERS, AIR)
				expect(dpsPerHp).toBeCloseTo(0.1, 5)
				expect(landShare).toBe(1)
				dpsPerHp, landShare = BalanceModel.wallPressure({ ZOMBIE, FLYER }, MONSTERS, AIR)
				expect(dpsPerHp).toBeCloseTo(0.1, 5)
				expect(landShare).toBeCloseTo(50 / 64, 5)
				expect((BalanceModel.wallPressure({ FLYER }, MONSTERS, AIR))).toBe(0)
			end
		)
		it(
			"records the breach night and checks the dent and near-break nights before it",
			function()
				-- a weak crew: 1 DPS against 500 HP nights, so the wall goes on night 1
				local result = BalanceModel.simulate(input({ nights = 3, handheldDps = 1, wallHp = 100, zones = { { ore = {}, hp = 1000, depthStartBlocks = 0, depthBlocks = 10 } } }))
				expect(result.breachNight).toBe(1)
				expect(result.rows[1].wallDamageShare).toBeGreaterThan(1)
				local failures = BalanceModel.checkWallPressure("Weak", result, 3)
				expect(failures[#failures]).toContain("first breaks a wall on night 1, not night 3")
				local strong = BalanceModel.simulate(input({ nights = 3, handheldDps = 1000 }))
				expect(strong.breachNight).toBe(nil)
				local strongFailures = BalanceModel.checkWallPressure("Strong", strong, 3)
				expect(strongFailures[1]).toContain("night 2 should nearly break a wall")
				expect(strongFailures[2]).toContain("never breaks a wall")
			end
		)
	end
)

describe(
	"BalanceModel shops",
	function()
		it(
			"buys pick axe levels in order, gated by the camp level",
			function()
				local level, spent = BalanceModel.affordablePickLevel(100, { 0, 50, 80 }, { 1, 1, 2 }, 1)
				expect(level).toBe(2)
				expect(spent).toBe(50)
				level, spent = BalanceModel.affordablePickLevel(200, { 0, 50, 80 }, { 1, 1, 2 }, 2)
				expect(level).toBe(3)
				expect(spent).toBe(130)
				level = BalanceModel.affordablePickLevel(49, { 0, 50, 80 }, { 1, 1, 2 }, 5)
				expect(level).toBe(1)
			end
		)
		it(
			"buys post upgrades damage and rate in turn, gated by the camp level",
			function()
				local ladder = { priceByLevel = { 10, 20 }, requiredCampLevelByLevel = { 1, 2 }, damageBonusPerLevel = 0.25, fireRateBonusPerLevel = 0.2 }
				local damageLevel, rateLevel, spent = BalanceModel.affordablePostLevels(25, ladder, 1)
				expect(damageLevel).toBe(1)
				expect(rateLevel).toBe(1)
				expect(spent).toBe(20)
				damageLevel, rateLevel, spent = BalanceModel.affordablePostLevels(100, ladder, 1)
				-- level 2 needs camp level 2
				expect(damageLevel + rateLevel).toBe(2)
				damageLevel, rateLevel, spent = BalanceModel.affordablePostLevels(100, ladder, 2)
				expect(damageLevel).toBe(2)
				expect(rateLevel).toBe(2)
				expect(spent).toBe(60)
			end
		)
		it(
			"adds the cooldown rung for a gun with heat and rates its firing share",
			function()
				local ladder = { priceByLevel = { 10, 20 }, requiredCampLevelByLevel = { 1, 1 }, damageBonusPerLevel = 0.25, fireRateBonusPerLevel = 0.2, cooldownBonusPerLevel = 1 / 6, heatFullSec = 4, heatCoolSec = 3 }
				local damageLevel, rateLevel, spent, cooldownLevel = BalanceModel.affordablePostLevels(35, ladder, 1)
				expect(damageLevel).toBe(1)
				expect(rateLevel).toBe(1)
				expect(cooldownLevel).toBe(1)
				expect(spent).toBe(30)
				-- no rung: no change; two rungs cut 3 s of cooling to 2 s
				expect(BalanceModel.cooldownFactor(ladder, 0)).toBeCloseTo(1, 5)
				expect(BalanceModel.cooldownFactor(ladder, 2)).toBeCloseTo((4 / 6) / (4 / 7), 5)
				-- a post without heat is untouched
				expect(BalanceModel.cooldownFactor({ priceByLevel = {}, requiredCampLevelByLevel = {}, damageBonusPerLevel = 0, fireRateBonusPerLevel = 0 }, 3)).toBe(1)
			end
		)
		it(
			"mans a post over the handheld once its upgrades make it better",
			function()
				local ladder = { priceByLevel = { 10 }, requiredCampLevelByLevel = { 1 }, damageBonusPerLevel = 1, fireRateBonusPerLevel = 1 }
				-- post 8 DPS under the handheld's 10 until one damage upgrade doubles it
				local result = BalanceModel.simulate(input({ nights = 1, postDps = 8, postUpgrades = ladder }))
				expect(result.rows[1].postLevel).toBe(2)
				expect(result.rows[1].freeDps).toBeCloseTo(8 * 2 * 2, 5)
			end
		)
		it(
			"steps the camp level through each threshold in turn",
			function()
				expect(BalanceModel.campLevelFor(0, { 20, 80, 250 })).toBe(1)
				expect(BalanceModel.campLevelFor(20, { 20, 80, 250 })).toBe(2)
				expect(BalanceModel.campLevelFor(99, { 20, 80, 250 })).toBe(2)
				expect(BalanceModel.campLevelFor(100, { 20, 80, 250 })).toBe(3)
				expect(BalanceModel.campLevelFor(1000, { 20, 80, 250 })).toBe(4)
			end
		)
	end
)

describe(
	"BalanceModel simulate",
	function()
		it(
			"turns mined HP into ore at the zone's density and refines it",
			function()
				local result = BalanceModel.simulate(input({ nights = 1 }))
				local row = result.rows[1]
				-- 1000 HP of a 2000 HP zone is half its ore
				expect(row.ironPerPlayer).toBeCloseTo(100, 5)
				expect(row.goldPerPlayer).toBeCloseTo(50, 5)
				expect(row.uraniumTotal).toBeCloseTo(5, 5)
				expect(row.zone).toBe(1)
				-- 20 Diamonds is exactly camp level 2, so the 50-Gold pick is bought
				expect(row.campLevel).toBe(2)
				expect(row.pickLevel).toBe(2)
			end
		)
		it(
			"loses mining time to backpack trips that grow with the tunnel's depth",
			function()
				-- 100 s window, 1 ore a second, 10 ore a load, 10 s a trip:
				-- m + m / 10 x 10 = 100, so 50 s of swinging
				expect(BalanceModel.miningSeconds(100, 1, 10, 10)).toBeCloseTo(50, 5)
				expect(BalanceModel.miningSeconds(100, 1, 1000000, 10)).toBeCloseTo(100, 1)
				expect(BalanceModel.miningSeconds(100, 0, 10, 10)).toBe(100)
				expect(BalanceModel.miningSeconds(0, 1, 10, 10)).toBe(0)
				-- a 15-ore backpack and a 64-stud walk at 16 studs a second cut
				-- day 1 against the bottomless one
				local carried = BalanceModel.simulate(input({ nights = 1, backpack = { valueByLevel = { 15 }, priceByLevel = { 0 }, requiredCampLevelByLevel = { 1 } }, refineryToEntranceStuds = 64, refineSec = 2 }))
				local bottomless = BalanceModel.simulate(input({ nights = 1 }))
				expect(carried.rows[1].miningSec).toBeLessThan(bottomless.rows[1].miningSec)
				expect(carried.rows[1].ironPerPlayer).toBeLessThan(bottomless.rows[1].ironPerPlayer)
				expect(bottomless.rows[1].miningSec).toBeCloseTo(100, 3)
			end
		)
		it(
			"moves to the next zone after the advance share and scales Iron and Gold by the crew",
			function()
				local result = BalanceModel.simulate(input({ nights = 3, oreYieldMultiplier = 2, crew = 2 }))
				-- day 1: 2 players at 10 damage mine the 1000 HP zone-1 allowance and
				-- 1000 HP of zone 2; iron is (100 + 100) x 2 yield / 2 players
				local first = result.rows[1]
				expect(first.zone).toBe(2)
				expect(first.ironPerPlayer).toBeCloseTo(200, 5)
				-- uranium is never scaled: 5 from zone 1 plus 25 from zone 2
				expect(first.uraniumTotal).toBeCloseTo(30, 5)
				expect(result.uraniumNight).toBe(1)
			end
		)
		it(
			"advances a crew's tunnel front slower than its digging when the exponent is under one",
			function()
				local thorough = table.clone(ASSUMPTIONS)
				thorough.CREW_ADVANCE_EXPONENT = 0.5
				-- 4 players mine 4000 HP a day but the front only counts half
				-- of it, so day 1 still ends in zone 2 with less taken from it
				local result = BalanceModel.simulate(input({ nights = 1, crew = 4, assumptions = thorough }))
				expect(result.rows[1].zone).toBe(2)
				local linear = BalanceModel.simulate(input({ nights = 1, crew = 4 }))
				expect(linear.rows[1].uraniumTotal).toBeGreaterThan(result.rows[1].uraniumTotal)
			end
		)
		it(
			"never takes more ore than a zone holds",
			function()
				local result = BalanceModel.simulate(input({ nights = 2, assumptions = table.clone(ASSUMPTIONS) }))
				result.rows[1] = nil
				local greedy = table.clone(ASSUMPTIONS)
				greedy.ORE_SELECTIVITY = 100
				local capped = BalanceModel.simulate(input({ nights = 10, assumptions = greedy }))
				local last = capped.rows[#capped.rows]
				expect(last.ironPerPlayer).toBeLessThanOrEqual(600)
				expect(last.uraniumTotal).toBeLessThanOrEqual(110)
			end
		)
		it(
			"measures each night's wave against the free weapons and the towers",
			function()
				local result = BalanceModel.simulate(input({ nights = 3 }))
				local first = result.rows[1]
				-- night 1: budget 10 of zombies at 50 HP a point is 500 HP over 100 s
				expect(first.budget).toBeCloseTo(10, 5)
				expect(first.waveHp).toBeCloseTo(500, 5)
				expect(first.requiredDps).toBeCloseTo(5, 5)
				expect(first.freeDps).toBeCloseTo(10, 5)
				-- 100 Iron: sentry 30, upgrade 15, then a second sentry (12 DPS
				-- for 30) beats the next upgrade (5 for 30), and its upgrade 15
				expect(first.towerCount).toBe(2)
				expect(first.towerDps).toBeCloseTo(40, 5)
				expect(first.slack).toBeCloseTo(50 / 5, 5)
				expect(first.freeOnlySlack).toBeCloseTo(2, 5)
				-- night 3 unlocks the flyer, so the HP per point drops and kinds rise
				expect(result.rows[3].unlockedCount).toBe(2)
			end
		)
		it(
			"records the first night the free weapons alone cannot clear",
			function()
				local result = BalanceModel.simulate(input({ nights = 4, handheldDps = 6 }))
				-- required DPS is 5, 10, ... so 6 free DPS fails from night 2
				expect(result.firstTowerNight).toBe(2)
				local easy = BalanceModel.simulate(input({ nights = 2, handheldDps = 100 }))
				expect(easy.firstTowerNight).toBe(nil)
			end
		)
	end
)

describe(
	"BalanceModel checks",
	function()
		it(
			"flags a harder difficulty whose budget or roster falls below the easier one",
			function()
				local normal = BalanceModel.simulate(input({ nights = 3 }))
				local hard = BalanceModel.simulate(input({ nights = 3, waveSettings = settings({ STARTING_DIFFICULTY = 5, DIFFICULTY_INCREASE_PER_WAVE = 5 }) }))
				local failures = BalanceModel.checkMonotonic({ "Normal", "Hard" }, { normal, hard }, { 3, 3 })
				expect(#failures).toBe(3)
				expect(failures[1]).toContain("Hard night 1 budget 5 is below Normal's 10")
				local ordered = BalanceModel.checkMonotonic({ "Normal", "Hard" }, { hard, normal }, { 3, 3 })
				expect(#ordered).toBe(0)
				-- nights past the easier run's target are not compared
				expect(#BalanceModel.checkMonotonic({ "Normal", "Hard" }, { normal, hard }, { 1, 3 })).toBe(1)
			end
		)
		it(
			"flags survivability, the tower night, and the uranium night against the targets",
			function()
				local result = BalanceModel.simulate(input({ nights = 4, handheldDps = 6 }))
				-- towers first needed night 2, uranium (20) reached on day 2
				local failures = BalanceModel.checkTargets("Normal solo", result, 2, 2, 0)
				expect(#failures).toBe(0)
				-- a crew is not held to the tower night
				expect(#BalanceModel.checkTargets("Crew", result, 2, nil, 0)).toBe(0)
				failures = BalanceModel.checkTargets("Normal solo", result, 3, 3, 0)
				expect(failures[1]).toContain("needs a tower on night 2, before night 3")
				expect(failures[2]).toContain("refines the uranium target on day 2, the target is day 3")
				local hopeless = BalanceModel.simulate(input({ nights = 2, handheldDps = 0, zones = { { ore = {}, hp = 1000, depthStartBlocks = 0, depthBlocks = 10 } }, uraniumTarget = 5 }))
				failures = BalanceModel.checkTargets("Empty", hopeless, 2, 1, 0)
				expect(failures[1]).toContain("night 1 is not clearable on time")
				expect(failures[#failures]).toContain("never refines 5 uranium in 2 nights")
				-- a tolerance of one day accepts day 2 against a target of 3
				expect(#BalanceModel.checkTargets("Normal solo", result, 3, 2, 1)).toBe(0)
			end
		)
		it(
			"flags a player short of Gold after night 1",
			function()
				local result = BalanceModel.simulate(input({ nights = 1 }))
				-- day 1 refines 50 Gold
				expect(#BalanceModel.checkGold("Normal solo", result, 50)).toBe(0)
				expect(BalanceModel.checkGold("Normal solo", result, 51)[1]).toContain("ends night 1 with 50 Gold a player, under 51")
			end
		)
		it(
			"flags a crew that finishes far from the solo run",
			function()
				local solo = BalanceModel.simulate(input({ nights = 4 }))
				local crew = BalanceModel.simulate(input({ nights = 4, crew = 4 }))
				expect(solo.uraniumNight).toBe(2)
				expect(crew.uraniumNight).toBe(1)
				expect(#BalanceModel.checkCrewParity("Crew of 4", solo, crew, 1)).toBe(0)
				expect(#BalanceModel.checkCrewParity("Crew of 4", solo, crew, 0)).toBe(1)
			end
		)
		it(
			"formats a row per night and a closing line",
			function()
				local lines = BalanceModel.formatRows(BalanceModel.simulate(input({ nights = 2 })))
				expect(#lines).toBe(4)
				expect(lines[4]).toContain("uranium target 20 reached on day 2")
			end
		)
		it(
			"measures the final wave a rescue on each day would bring against that day's defenses",
			function()
				local result = BalanceModel.simulate(input({ nights = 3 }))
				-- night 2 needs 10 DPS, so a rescue on day 1 faces 15 with day 1's 50
				expect(result.rows[1].finalWaveSlack).toBeCloseTo(50 / 15, 5)
				expect(result.rows[3].finalWaveSlack).toBe(math.huge)
				local weak = BalanceModel.simulate(input({ nights = 3, handheldDps = 1, zones = { { ore = {}, hp = 1000, depthStartBlocks = 0, depthBlocks = 10 } } }))
				local failures = BalanceModel.checkTargets("Weak", weak, 2, 1, 0)
				expect(failures[#failures - 1]).toContain("cannot hold the final wave on day 2")
			end
		)
	end
)
