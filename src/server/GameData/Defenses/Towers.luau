--!strict

-- Towers (GDD "Defenses", "Tower Types"), M26 and M27: the automated
-- defense units a player's three Defense loadout slots bring into a run,
-- built on the Defensive Zone grid for Iron and upgraded four times for
-- Iron. One entry per Enums.TowerKind; a new Tower plugs in by adding its
-- enum key, an entry here, and a model of that key's name under
-- GameAssets/Towers.
-- STATS_BY_LEVEL has five rows: level 1 is the Tower as built and each
-- further row is what one upgrade makes it, so an upgrade can change any
-- mix of stats. UPGRADE_PRICE_IRON_BY_LEVEL[N] is the price of reaching
-- level N + 1. FOOTPRINT_CELLS is columns by rows on the grid
-- (GameData/Defenses/Placement fixes the cell size). Upgrades are never
-- gated by Camp Level (GDD "Camp Level": Towers are never capped).
-- STAT_ROWS names the four stats the Tower Menu shows for the kind, in
-- order (a Frost Tower never lists a Damage of 0). BEHAVIOR is everything
-- about how the kind fights that no upgrade changes: which targets it may
-- hit, the attack shape (Enums.TowerAttack), the cone angle and damage
-- tick for a cone, the rest between flames, the jump distance and stun
-- for a chain, and whether a turret turns on the base. Every number is a
-- placeholder until enemies exist to tune against (M30).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- every new player starts with this one unlocked and in slot 1
	DEFAULT_TOWER = Enums.TowerKind.SENTRY_GUN,
	MAX_ACTIVE_TOWERS_PER_PLAYER = 5,
	PRICE_RESOURCE = Enums.RefinedResource.IRON_BAR,
	-- selling returns this share of everything spent on the Tower
	SELL_SHARE = 0.5,
	MENU_PROMPT_ACTION_TEXT = "Upgrade/Sell",
	PROMPT_MAX_DISTANCE_STUDS = 10,
	-- a shot leaves the turret this far above the Tower's base pose
	MUZZLE_HEIGHT_STUDS = 3,
	BY_KIND = {
		[Enums.TowerKind.SENTRY_GUN] = {
			BUILD_PRICE_IRON = 30,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 15, 30, 60, 120 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.FIRE_RATE, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.SINGLE,
				TARGETS_GROUND = true,
				TARGETS_AIR = false,
				HAS_TURRET = true,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 6, FIRE_INTERVAL_SEC = 0.5, RANGE_STUDS = 40, MAX_HP = 150 },
				{ DAMAGE = 8, FIRE_INTERVAL_SEC = 0.45, RANGE_STUDS = 44, MAX_HP = 180 },
				{ DAMAGE = 10, FIRE_INTERVAL_SEC = 0.4, RANGE_STUDS = 48, MAX_HP = 220 },
				{ DAMAGE = 13, FIRE_INTERVAL_SEC = 0.35, RANGE_STUDS = 52, MAX_HP = 270 },
				{ DAMAGE = 16, FIRE_INTERVAL_SEC = 0.3, RANGE_STUDS = 60, MAX_HP = 330 },
			},
		},
		-- FLAME_SEC is how long each flame lasts (the designer's "fire
		-- rate"); DAMAGE lands every TICK_INTERVAL_SEC while it burns, and
		-- the turret rests REST_SEC between flames
		[Enums.TowerKind.FLAMETHROWER] = {
			BUILD_PRICE_IRON = 45,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 20, 40, 80, 160 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.FLAME_LENGTH, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.CONE,
				TARGETS_GROUND = true,
				TARGETS_AIR = false,
				HAS_TURRET = true,
				CONE_ANGLE_DEGREES = 60,
				TICK_INTERVAL_SEC = 0.2,
				REST_SEC = 1.5,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 3, FLAME_SEC = 2, RANGE_STUDS = 18, MAX_HP = 180 },
				{ DAMAGE = 4, FLAME_SEC = 2.4, RANGE_STUDS = 20, MAX_HP = 220 },
				{ DAMAGE = 5, FLAME_SEC = 2.8, RANGE_STUDS = 22, MAX_HP = 270 },
				{ DAMAGE = 6, FLAME_SEC = 3.2, RANGE_STUDS = 24, MAX_HP = 330 },
				{ DAMAGE = 8, FLAME_SEC = 4, RANGE_STUDS = 28, MAX_HP = 400 },
			},
		},
		[Enums.TowerKind.AA_TURRET] = {
			BUILD_PRICE_IRON = 53,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 20, 40, 80, 160 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.FIRE_RATE, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.SINGLE,
				TARGETS_GROUND = false,
				TARGETS_AIR = true,
				HAS_TURRET = true,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 10, FIRE_INTERVAL_SEC = 0.4, RANGE_STUDS = 70, MAX_HP = 150 },
				{ DAMAGE = 13, FIRE_INTERVAL_SEC = 0.36, RANGE_STUDS = 76, MAX_HP = 180 },
				{ DAMAGE = 16, FIRE_INTERVAL_SEC = 0.32, RANGE_STUDS = 82, MAX_HP = 220 },
				{ DAMAGE = 20, FIRE_INTERVAL_SEC = 0.28, RANGE_STUDS = 90, MAX_HP = 270 },
				{ DAMAGE = 25, FIRE_INTERVAL_SEC = 0.24, RANGE_STUDS = 100, MAX_HP = 330 },
			},
		},
		-- no damage: every SLOW_SEC of frost takes SLOW_SHARE of the speed
		-- of everything in the cone for SLOW_SEC (StatusRules; the strongest
		-- slow wins). The frost pulses for FLAME_SEC and rests REST_SEC
		[Enums.TowerKind.FROST_TOWER] = {
			BUILD_PRICE_IRON = 45,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 20, 40, 80, 160 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.SLOW_RATE, Enums.TowerStat.FREEZE_LENGTH, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.CONE,
				TARGETS_GROUND = true,
				TARGETS_AIR = false,
				HAS_TURRET = true,
				CONE_ANGLE_DEGREES = 60,
				TICK_INTERVAL_SEC = 0.5,
				FLAME_SEC = 2,
				REST_SEC = 1,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 0, SLOW_SHARE = 0.3, SLOW_SEC = 2, RANGE_STUDS = 24, MAX_HP = 200 },
				{ DAMAGE = 0, SLOW_SHARE = 0.35, SLOW_SEC = 2.5, RANGE_STUDS = 28, MAX_HP = 240 },
				{ DAMAGE = 0, SLOW_SHARE = 0.4, SLOW_SEC = 3, RANGE_STUDS = 32, MAX_HP = 290 },
				{ DAMAGE = 0, SLOW_SHARE = 0.5, SLOW_SEC = 3.5, RANGE_STUDS = 36, MAX_HP = 350 },
				{ DAMAGE = 0, SLOW_SHARE = 0.6, SLOW_SEC = 4, RANGE_STUDS = 42, MAX_HP = 420 },
			},
		},
		-- no turret: the bolt hits the picked target and jumps to
		-- CHAIN_COUNT more, each within CHAIN_JUMP_STUDS of the last, every
		-- FIRE_INTERVAL_SEC, stunning each for STUN_SEC
		[Enums.TowerKind.TESLA_COIL] = {
			BUILD_PRICE_IRON = 60,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 25, 50, 100, 200 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.DAMAGE, Enums.TowerStat.FIRE_RATE, Enums.TowerStat.RANGE, Enums.TowerStat.CHAIN_COUNT },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.CHAIN,
				TARGETS_GROUND = true,
				TARGETS_AIR = true,
				HAS_TURRET = false,
				CHAIN_JUMP_STUDS = 14,
				STUN_SEC = 0.4,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 12, FIRE_INTERVAL_SEC = 1.2, RANGE_STUDS = 30, CHAIN_COUNT = 1, MAX_HP = 170 },
				{ DAMAGE = 15, FIRE_INTERVAL_SEC = 1.1, RANGE_STUDS = 33, CHAIN_COUNT = 2, MAX_HP = 200 },
				{ DAMAGE = 19, FIRE_INTERVAL_SEC = 1, RANGE_STUDS = 36, CHAIN_COUNT = 2, MAX_HP = 240 },
				{ DAMAGE = 24, FIRE_INTERVAL_SEC = 0.9, RANGE_STUDS = 40, CHAIN_COUNT = 3, MAX_HP = 290 },
				{ DAMAGE = 30, FIRE_INTERVAL_SEC = 0.8, RANGE_STUDS = 45, CHAIN_COUNT = 4, MAX_HP = 350 },
			},
		},
		[Enums.TowerKind.SNIPER_TOWER] = {
			BUILD_PRICE_IRON = 68,
			UPGRADE_PRICE_IRON_BY_LEVEL = { 25, 50, 100, 200 },
			FOOTPRINT_CELLS = { 4, 4 },
			STAT_ROWS = { Enums.TowerStat.FIRE_RATE, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP, Enums.TowerStat.RANGE },
			BEHAVIOR = {
				ATTACK = Enums.TowerAttack.SINGLE,
				TARGETS_GROUND = true,
				TARGETS_AIR = false,
				HAS_TURRET = true,
			},
			STATS_BY_LEVEL = {
				{ DAMAGE = 40, FIRE_INTERVAL_SEC = 2.5, RANGE_STUDS = 120, MAX_HP = 200 },
				{ DAMAGE = 50, FIRE_INTERVAL_SEC = 2.3, RANGE_STUDS = 130, MAX_HP = 240 },
				{ DAMAGE = 62, FIRE_INTERVAL_SEC = 2.1, RANGE_STUDS = 140, MAX_HP = 290 },
				{ DAMAGE = 78, FIRE_INTERVAL_SEC = 1.9, RANGE_STUDS = 155, MAX_HP = 350 },
				{ DAMAGE = 100, FIRE_INTERVAL_SEC = 1.7, RANGE_STUDS = 175, MAX_HP = 420 },
			},
		},
	},
}
