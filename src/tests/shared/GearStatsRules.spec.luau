-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GearStatsRules = require(game:GetService("ReplicatedStorage").Shared.GearStatsRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local RIFLE = {
	DAMAGE = 60,
	FIRE_INTERVAL_SEC = 0.6,
	FIRE_COOLDOWN_SEC = 0.5,
	RANGE_STUDS = 300,
	MAGAZINE_SIZE = 5,
	RELOAD_SEC = 2.5,
}

local MACHINE_GUN = {
	DAMAGE = 12,
	FIRE_INTERVAL_SEC = 0.1,
	RANGE_STUDS = 350,
	TURN_SPEED_DEGREES_PER_SEC = 22,
	HEAT = { FULL_SEC = 4, COOL_SEC = 3 },
}

local ROCKET_LAUNCHER = {
	DAMAGE = 200,
	FIRE_INTERVAL_SEC = 6,
	RANGE_STUDS = 500,
	TURN_SPEED_DEGREES_PER_SEC = 12,
	RELOAD_SEC = 6,
	PROJECTILE = { TEMPLATE = "Rocket", SPEED_STUDS_PER_SEC = 120, SPLASH_RADIUS_STUDS = 12 },
}

local SENTRY = {
	BUILD_PRICE_IRON = 60,
	UPGRADE_PRICE_IRON_BY_LEVEL = { 30, 60, 120, 240 },
	FOOTPRINT_CELLS = { 4, 4 },
	STAT_ROWS = { Enums.TowerStat.FIRE_RATE, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
	STATS_BY_LEVEL = {
		{ DAMAGE = 12, FIRE_INTERVAL_SEC = 0.5, RANGE_STUDS = 40, MAX_HP = 150 },
		{ DAMAGE = 16, FIRE_INTERVAL_SEC = 0.45, RANGE_STUDS = 44, MAX_HP = 180 },
	},
}

local function labels(rows)
	local out = {}
	for _, row in rows do
		table.insert(out, row.label .. "=" .. row.value)
	end
	return out
end

describe(
	"GearStatsRules rows",
	function()
		it(
			"lists a weapon's damage, rate, range, magazine, and reload",
			function()
				expect(labels(GearStatsRules.weaponRows(RIFLE))).toEqual({
					"Damage=60",
					"Fire rate=1.7/s",
					"Range=300 studs",
					"Magazine=5",
					"Reload=2.5s",
				})
			end
		)

		it(
			"lists a post weapon's rate or reload, and its heat or splash",
			function()
				expect(labels(GearStatsRules.postWeaponRows(MACHINE_GUN))).toEqual({
					"Damage=12",
					"Fire rate=10/s",
					"Range=350 studs",
					"Turn speed=22 deg/s",
					"Overheat after=4s",
					"Cooldown=3s",
				})
				expect(labels(GearStatsRules.postWeaponRows(ROCKET_LAUNCHER))).toEqual({
					"Damage=200",
					"Reload=6s",
					"Range=500 studs",
					"Turn speed=12 deg/s",
					"Splash=12 studs",
				})
			end
		)

		it(
			"lists a tower as built, in the Tower Menu's rows and words",
			function()
				expect(labels(GearStatsRules.towerRows(SENTRY))).toEqual({
					"Fire Rate=2.0/s",
					"Damage=12",
					"HP=150",
					"Range=40",
				})
			end
		)
	end
)

describe(
	"GearStatsRules catalogue codec",
	function()
		it(
			"round-trips slots and kinds by name and drops what it does not know",
			function()
				local catalogue = {
					[Enums.GearSlot.WEAPON] = { [Enums.WeaponKind.RIFLE] = GearStatsRules.weaponRows(RIFLE) },
					[Enums.GearSlot.TOWER_1] = { [Enums.TowerKind.SENTRY_GUN] = GearStatsRules.towerRows(SENTRY) },
				}
				local decoded = GearStatsRules.decodeCatalogue(GearStatsRules.encodeCatalogue(catalogue))
				expect(decoded).toEqual(catalogue)
				expect(GearStatsRules.decodeCatalogue("")).toEqual({})
				expect(GearStatsRules.decodeCatalogue(nil)).toEqual({})
				expect(GearStatsRules.decodeCatalogue('{"NOPE":{"RIFLE":[]},"WEAPON":{"NOPE":[]}}')).toEqual({ [Enums.GearSlot.WEAPON] = {} })
			end
		)
	end
)
