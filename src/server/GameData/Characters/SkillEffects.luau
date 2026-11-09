--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- What each skill does to a run (M56, designed with the designer
-- 2026-11-09; the names and words are in Skills.luau). A skill is one of
-- two shapes: MODIFIERS multiply a class modifier, the same axis a class
-- buff rides, so a system keeps reading one number through
-- ClassManager:getModifier and the menus price by the same table; PARAMS
-- are the numbers of a rule the gameplay SkillManager answers at one
-- hook. A skill marked "(cannot stack)" in its words is a crew skill: the
-- hook asks SkillManager:crewHas and applies it once for everyone. Every
-- id here must be in Skills.luau; ClassManager checks that at startup.
return {
	BY_ID = {
		-- Mining
		ROCKET_SCIENCE = {
			MODIFIERS = { [Enums.ClassModifier.JET_PACK_FUEL] = 1.2 },
		},
		LONG_HAUL = {
			-- BootsManager, through SkillManager's speed provider, while the
			-- backpack is full
			PARAMS = { FULL_BACKPACK_SPEED_MULTIPLIER = 1.1 },
		},
		QUICK_REFINER = {
			MODIFIERS = { [Enums.ClassModifier.REFINE_DURATION] = 0.5 },
		},
		HARDENED_PICK = {
			-- MiningManager: a hit on a uranium rock does this much more, so
			-- the rock takes a tenth fewer hits
			PARAMS = { URANIUM_DAMAGE_MULTIPLIER = 1 / 0.9 },
		},
		RICH_SEAM = {
			-- MiningManager: this many extra hits' worth of damage on the
			-- first swing at a whole gold rock
			PARAMS = { GOLD_FIRST_HIT_BONUS_HITS = 1 },
		},
		THICK_SKULL = {
			-- ReviveManager: damage from a mine monster is scaled by this
			PARAMS = { MINE_MONSTER_DAMAGE_MULTIPLIER = 0.5 },
		},
		URANIUM_SEEKER = {
			-- the client's Geiger Counter draws the arrow; no number
		},
		GOLD_DIGGER = {
			-- SkillManager, once per run at the run's start or the player's
			-- Ready, whichever is later
			PARAMS = { STARTING_GOLD_BARS = 20 },
		},
		DEEP_POCKETS = {
			MODIFIERS = { [Enums.ClassModifier.BACKPACK_CAPACITY] = 1.1 },
		},
		CLEAN_BREAK = {
			-- MiningManager: the chance a swing breaks the rock outright
			PARAMS = { ONE_SWING_BREAK_CHANCE = 0.1 },
		},
		STEADY_SWING = {
			MODIFIERS = { [Enums.ClassModifier.MINING_SPEED] = 1.1 },
		},
		MOTHER_LODE = {
			-- MiningManager: every nth rock the player breaks pays double
			PARAMS = { EVERY_NTH_BREAK = 10, ORE_MULTIPLIER = 2 },
		},

		-- Combat
		FAST_RELOAD = {
			MODIFIERS = { [Enums.ClassModifier.WEAPON_RELOAD] = 0.8 },
		},
		QUICK_HANDS = {
			MODIFIERS = { [Enums.ClassModifier.POST_TURN_SPEED] = 1.15 },
		},
		DEEP_LUNGS = {
			-- JetPackManager, through SkillManager's drain provider, at night
			PARAMS = { NIGHT_FUEL_DRAIN_MULTIPLIER = 0.8 },
		},
		BIG_CLIP = {
			MODIFIERS = { [Enums.ClassModifier.WEAPON_MAGAZINE] = 1.2 },
		},
		COOL_BARREL = {
			MODIFIERS = { [Enums.ClassModifier.POST_RELOAD] = 0.8 },
		},
		THICK_SKIN = {
			-- ReviveManager: damage from any monster at night is scaled by this
			PARAMS = { NIGHT_DAMAGE_TAKEN_MULTIPLIER = 0.8 },
		},
		NIGHT_OWL = {
			-- WeaponManager and PostManager: every shot at night
			PARAMS = { NIGHT_DAMAGE_MULTIPLIER = 1.1 },
		},
		GUNSLINGER = {
			MODIFIERS = { [Enums.ClassModifier.HANDHELD_DAMAGE] = 1.1 },
		},
		HEADHUNTER = {
			-- WeaponManager and PostManager: a weapon with no headshot of its
			-- own fires with this multiple for a holder (the Railgun keeps
			-- its own); 1.25 by the designer's call, 2026-11-09
			PARAMS = { HEADSHOT_MULTIPLIER = 1.25 },
		},
		POST_POWERHOUSE = {
			MODIFIERS = { [Enums.ClassModifier.POST_DAMAGE] = 1.1 },
		},
		LAST_STAND = {
			-- SkillManager publishes the fire rate multiple while the holder's
			-- health share is below the threshold
			PARAMS = { HEALTH_SHARE_BELOW = 0.25, FIRE_RATE_MULTIPLIER = 1.25 },
		},
		CHAIN_REACTION = {
			-- DamageableManager: a killing blow by a holder deals this share of
			-- its damage to every body within the radius of the kill
			PARAMS = { DAMAGE_SHARE = 0.25, RADIUS_STUDS = 6 },
		},

		-- Building
		QUICK_FIX = {
			MODIFIERS = { [Enums.ClassModifier.HAMMER_SWING_SPEED] = 1.25 },
		},
		HANDY = {
			MODIFIERS = { [Enums.ClassModifier.REPAIR_SPEED] = 1.2 },
		},
		SCRAP_SAVER = {
			MODIFIERS = { [Enums.ClassModifier.TRAP_COST] = 0.9 },
		},
		NIGHT_SHIFT = {
			-- BootsManager, through SkillManager's speed provider, inside the
			-- camp's area at night
			PARAMS = { CAMP_NIGHT_SPEED_MULTIPLIER = 1.1 },
		},
		FIELD_ENGINEER = {
			-- PlacementManager: the camp's Tower allowance, once for the crew
			PARAMS = { EXTRA_TOWERS = 1 },
		},
		REINFORCED = {
			-- PlacementManager: a Tower's max HP when built or upgraded, once
			-- for the crew
			PARAMS = { TOWER_MAX_HP_MULTIPLIER = 1.2 },
		},
		SPARE_PARTS = {
			MODIFIERS = { [Enums.ClassModifier.REPAIR_COST] = 0.9 },
		},
		STURDY_WALLS = {
			-- StructureManager: every wall's and the gate's max HP, once for
			-- the crew
			PARAMS = { WALL_MAX_HP_MULTIPLIER = 1.1 },
		},
		FOREMAN = {
			MODIFIERS = { [Enums.ClassModifier.TOWER_COST] = 0.9 },
		},
		GENEROUS = {
			-- StructureManager: the Iron a donation counts for, per Iron paid
			PARAMS = { DONATION_MULTIPLIER = 1.25 },
		},
		FORTRESS = {
			-- StructureManager: damage to the Refinery, once for the crew
			PARAMS = { REFINERY_DAMAGE_MULTIPLIER = 0.85 },
		},
		MASTER_BUILDER = {
			-- StructureManager: the share of max HP rubble needs to stand for
			-- a holder's swing (any at all; REBUILD_STAND_SHARE otherwise)
			PARAMS = { REBUILD_STAND_SHARE = 0 },
		},
	},
	-- the monsters that live in the mine, for Thick Skull
	MINE_MONSTER_KINDS = {
		Enums.MonsterKind.CAVE_SPIDER,
		Enums.MonsterKind.BLOCKFACE,
		Enums.MonsterKind.CHASE,
	},
}
