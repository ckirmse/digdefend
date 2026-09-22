--!strict

-- An enum table maps SCREAMING_SNAKE_CASE key names to unique integer values, and may also carry a
-- PublicNames sub-table holding the player-facing string for some or all of those keys. Keys with
-- no player-facing name are simply absent from PublicNames, so lookups into it are optional.
--
-- EnumTable is the parameter type for the helpers below. It has to be `any` rather than a table
-- type like `{ [string]: number | PublicNames }`: table indexers are invariant in Luau, so the
-- precise inferred type of a literal like Difficulty (NORMAL: number, ..., PublicNames: {...}) is
-- not assignable to an indexer whose value type is that union. The helpers recover the real types
-- with typeof() guards instead.
export type PublicNames = { [string]: string? }
export type EnumTable = any

local module

module = {
	PlayerLifecycle = {
		LOADING = 1,
		READY = 2,
		LEAVING = 3,
		GONE = 4,
	},
	-- replicated on the Player instance so the loading screen can react before
	-- the CurrentPlayer folder exists
	LoadStatus = {
		LOADING_DATA = 1,
		RETRYING = 2,
		READY = 3,
	},
	PlaceKind = {
		LOBBY = 1,
		GAMEPLAY = 2,
		-- local place files and unpublished Studio sessions have PlaceId 0
		STUDIO = 3,
	},
	Map = {
		DEADMANS_CANYON = 1,
		FROSTBITE_PASS = 2,

		PublicNames = {
			DEADMANS_CANYON = "Deadman's Canyon",
			FROSTBITE_PASS = "Frostbite Pass",
		},
	},
	Difficulty = {
		NORMAL = 1,
		HARD = 2,
		NIGHTMARE = 3,

		PublicNames = {
			NORMAL = "Normal",
			HARD = "Hard",
			NIGHTMARE = "Nightmare",
		},
	},
	RawResource = {
		IRON_ORE = 1,
		GOLD_ORE = 2,
		CRYSTAL = 3,
		URANIUM_ORE = 4,

		PublicNames = {
			IRON_ORE = "Iron Ore",
			GOLD_ORE = "Gold Ore",
			CRYSTAL = "Crystal",
			URANIUM_ORE = "Uranium Ore",
		},
	},
	RefinedResource = {
		IRON_BAR = 1,
		GOLD_BAR = 2,
		DIAMOND = 3,
		URANIUM = 4,

		PublicNames = {
			IRON_BAR = "Iron Bar",
			GOLD_BAR = "Gold Bar",
			DIAMOND = "Diamond",
			URANIUM = "Uranium",
		},
	},
	-- one helicopter pad's party lifecycle (GDD "Helicopter Pads")
	PadState = {
		IDLE = 1,
		CONFIGURING = 2,
		BOARDING = 3,
		DEPARTING = 4,

		PublicNames = {
			IDLE = "Open",
			CONFIGURING = "Setting Up",
			BOARDING = "Now Boarding",
			DEPARTING = "Departing",
		},
	},
	PartyVisibility = {
		PUBLIC = 1,
		FRIENDS_ONLY = 2,

		PublicNames = {
			PUBLIC = "Public",
			FRIENDS_ONLY = "Friends Only",
		},
	},
	-- which pad menu a client should show (NotifyPartyMenu)
	PartyMenu = {
		NONE = 1,
		CREATE = 2,
		QUEUE = 3,
	},
	-- what a helicopter model is doing, set by the server as the
	-- HelicopterPhase attribute and animated by ClientHelicopterManager
	HelicopterPhase = {
		IDLE = 1,
		SPINNING = 2,
		FLYING = 3,
	},
	-- what a player can hold (GDD "Tools"); the tool bar shows these in a
	-- stable order and only one is equipped at a time
	ToolKind = {
		PICK_AXE = 1,
		WEAPON = 2,
		-- consumables bought at the Mining Supplies Store (M21); the count
		-- held travels beside the slot list
		TORCH = 3,
		DYNAMITE = 4,
		-- equipping it is Repair Mode (M23): structure HP shows and every
		-- swing repairs what the reticle is on
		HAMMER = 5,
		-- Build Mode (M26): no held model; equipping it swaps the tool
		-- bar for the Tower and Trap loadout
		DEFENSES = 6,

		PublicNames = {
			PICK_AXE = "Pick Axe",
			WEAPON = "Weapon",
			TORCH = "Torch",
			DYNAMITE = "Dynamite",
			HAMMER = "Hammer",
			DEFENSES = "Defenses",
		},
	},
	-- handheld weapons (GDD S12), M24. The WEAPON tool slot holds one of
	-- these for the run; definitions are in GameData/Weapons/Handheld. Keys
	-- double as the held template names ("WEAPON_<KEY>" under GameAssets/Tools)
	WeaponKind = {
		RIFLE = 1,

		PublicNames = {
			RIFLE = "Rifle",
		},
	},
	-- mounted post weapons (GDD "Posts"), M25. The POST loadout slot names
	-- one for the run; definitions are in GameData/Posts/PostWeapons. Keys
	-- double as the model names under GameAssets/PostWeapons
	PostWeaponKind = {
		MACHINE_GUN = 1,
		ROCKET_LAUNCHER = 2,

		PublicNames = {
			MACHINE_GUN = "Machine Gun",
			ROCKET_LAUNCHER = "Rocket Launcher",
		},
	},
	-- what a post weapon upgrade raises (GDD "Post Weapon Upgrades"): four
	-- upgrades each, bought with Gold at the post's workbench
	PostAttribute = {
		DAMAGE = 1,
		FIRE_RATE = 2,
		TURN_SPEED = 3,
		RANGE = 4,

		PublicNames = {
			DAMAGE = "Damage",
			FIRE_RATE = "Fire Rate",
			TURN_SPEED = "Turn Speed",
			RANGE = "Range",
		},
	},
	-- automated defense units (GDD "Defenses"), M26. The three DEFENSE
	-- loadout slots name up to three for the run; definitions are in
	-- GameData/Defenses/Towers. Keys double as the model names under
	-- GameAssets/Towers
	TowerKind = {
		SENTRY_GUN = 1,
		FLAMETHROWER = 2,
		AA_TURRET = 3,
		FROST_TOWER = 4,
		TESLA_COIL = 5,
		SNIPER_TOWER = 6,

		PublicNames = {
			SENTRY_GUN = "Sentry Gun",
			FLAMETHROWER = "Flamethrower",
			AA_TURRET = "AA Turret",
			FROST_TOWER = "Frost Tower",
			TESLA_COIL = "Tesla Coil",
			SNIPER_TOWER = "Sniper Tower",
		},
	},
	-- consumable placements bought at the Defense Store (GDD "Traps"), M26;
	-- definitions in GameData/Defenses/Traps, models under GameAssets/Traps,
	-- one "<Key>Stand" per kind in the store
	TrapKind = {
		WALL = 1,
		SPIKE_TRAP = 2,
		GOO_PIT = 3,
		LAND_MINE = 4,
		BEAR_TRAP = 5,
		DECOY = 6,

		PublicNames = {
			WALL = "Wall",
			SPIKE_TRAP = "Spike Trap",
			GOO_PIT = "Goo Pit",
			LAND_MINE = "Land Mine",
			BEAR_TRAP = "Bear Trap",
			DECOY = "Decoy",
		},
	},
	-- what a placement on the grid is: a Tower (paid on build, upgradable)
	-- or a Trap (consumed from the inventory)
	PlacementKind = {
		TOWER = 1,
		TRAP = 2,

		PublicNames = {
			TOWER = "Tower",
			TRAP = "Trap",
		},
	},
	-- which enemy in range a Tower shoots first (GDD "Upgrading and Selling
	-- Towers"); the targeting itself is M27
	TargetPriority = {
		CLOSEST = 1,
		FURTHEST = 2,
		STRONGEST = 3,
		WEAKEST = 4,

		PublicNames = {
			CLOSEST = "Closest",
			FURTHEST = "Furthest",
			STRONGEST = "Strongest",
			WEAKEST = "Weakest",
		},
	},
	-- the numbers the Tower Menu lists and an upgrade may raise; each kind
	-- names its four in GameData/Defenses/Towers STAT_ROWS (M27)
	TowerStat = {
		FIRE_RATE = 1,
		RANGE = 2,
		DAMAGE = 3,
		HP = 4,
		FLAME_LENGTH = 5,
		SLOW_RATE = 6,
		FREEZE_LENGTH = 7,
		CHAIN_COUNT = 8,

		PublicNames = {
			FIRE_RATE = "Fire Rate",
			RANGE = "Range",
			DAMAGE = "Damage",
			HP = "HP",
			FLAME_LENGTH = "Flame Length",
			SLOW_RATE = "Slow Rate",
			FREEZE_LENGTH = "Freeze Length",
			CHAIN_COUNT = "Chain Count",
		},
	},
	-- the shape of a Tower's attack (GDD "Tower Types"), M27: one shot at
	-- the picked target, a cone that hits everything in front of the
	-- turret for a while, or a bolt that chains from the picked target
	TowerAttack = {
		SINGLE = 1,
		CONE = 2,
		CHAIN = 3,
	},
	-- what a Trap does (GDD "Trap Types"), M27: a barrier that blocks and
	-- takes hits, spikes that pop under a crosser and recharge, goo that
	-- slows crossers, a mine that blows once, a snare that holds one
	-- crosser once
	TrapBehavior = {
		BARRIER = 1,
		SPIKES = 2,
		GOO = 3,
		MINE = 4,
		SNARE = 5,
	},
	-- a Spike Trap's state, on its shadow for the clients to draw
	TrapState = {
		DOWN = 1,
		UP = 2,
		RECHARGING = 3,
	},
	-- camp structures with HP (GDD "Walls", "Gate", "Refinery"), M23
	StructureKind = {
		WALL = 1,
		GATE = 2,
		REFINERY = 3,

		PublicNames = {
			WALL = "Wall",
			GATE = "Gate",
			REFINERY = "Refinery",
		},
	},
	-- one stand each in the Mining Supplies Store (GDD "Mining Supplies
	-- Store"); keys double as the stand model names ("<KEY>Stand" in
	-- PascalCase is looked up through StoreRules.standNameForItem)
	StoreItem = {
		PICK_AXE = 1,
		BOOTS = 2,
		BACKPACK = 3,
		JET_PACK = 4,
		TORCH = 5,
		DYNAMITE = 6,

		PublicNames = {
			PICK_AXE = "Pick Axe",
			BOOTS = "Boots",
			BACKPACK = "Backpack",
			JET_PACK = "Jet Pack",
			TORCH = "Torch",
			DYNAMITE = "Dynamite",
		},
	},
	-- what a stand offers a given player right now (StoreRules.getOffer)
	StoreOffer = {
		AVAILABLE = 1,
		LOCKED = 2,
		MAXED = 3,
	},
	-- the direction a player walks to enter a mine; 90 degree steps keep
	-- blocks axis-aligned (GDD "Coordinate model")
	MineFacing = {
		POSITIVE_X = 1,
		NEGATIVE_X = 2,
		POSITIVE_Z = 3,
		NEGATIVE_Z = 4,
	},
	RockKind = {
		FILLER = 1,
		RESOURCE = 2,
		BEDROCK = 3,
	},
	-- every rock in the global rock table (GDD "Rock definitions"). One integer
	-- per grid cell in the generated mine; keys double as the template names
	-- under ReplicatedStorage/Rocks. PublicNames match the hand-placed rock
	-- strings in the GDD ("Crystal 3").
	RockName = {
		STONE_1 = 1,
		STONE_2 = 2,
		STONE_3 = 3,
		STONE_4 = 4,
		STONE_5 = 5,
		IRON_1 = 6,
		IRON_2 = 7,
		IRON_3 = 8,
		IRON_4 = 9,
		GOLD_1 = 10,
		GOLD_2 = 11,
		GOLD_3 = 12,
		GOLD_4 = 13,
		CRYSTAL_1 = 14,
		CRYSTAL_2 = 15,
		CRYSTAL_3 = 16,
		CRYSTAL_4 = 17,
		URANIUM = 18,
		BEDROCK = 19,

		PublicNames = {
			STONE_1 = "Stone 1",
			STONE_2 = "Stone 2",
			STONE_3 = "Stone 3",
			STONE_4 = "Stone 4",
			STONE_5 = "Stone 5",
			IRON_1 = "Iron 1",
			IRON_2 = "Iron 2",
			IRON_3 = "Iron 3",
			IRON_4 = "Iron 4",
			GOLD_1 = "Gold 1",
			GOLD_2 = "Gold 2",
			GOLD_3 = "Gold 3",
			GOLD_4 = "Gold 4",
			CRYSTAL_1 = "Crystal 1",
			CRYSTAL_2 = "Crystal 2",
			CRYSTAL_3 = "Crystal 3",
			CRYSTAL_4 = "Crystal 4",
			URANIUM = "Uranium",
			BEDROCK = "Bedrock",
		},
	},
	-- the five loadout slots carried into a run; keys double as save-data keys
	-- the run's day and night loop (GDD "Wave Cycle"), M28
	RunState = {
		DAY = 1,
		NIGHT = 2,
		WON = 3,
		LOST = 4,
		-- the crew is landing: morning look, no clock yet, day 1 follows
		WAITING = 5,

		PublicNames = {
			DAY = "Day",
			NIGHT = "Night",
			WON = "Rescued",
			LOST = "Lost",
			WAITING = "Landing",
		},
	},
	-- which two sky looks the client is blending between (LightingPresets):
	-- day start into day end over a day, day end into night start over the
	-- dusk seconds, night start into night end over the spawn window, night
	-- end back to day start over the dawn stretch
	SkyStage = {
		DAY = 1,
		DUSK = 2,
		NIGHT = 3,
		DAWN = 4,
	},
	-- the day clock's picture: day, the last stretch of a day, night
	ClockPhase = {
		DAY = 1,
		DUSK = 2,
		NIGHT = 3,
	},
	LoadoutSlot = {
		WEAPON = 1,
		POST = 2,
		DEFENSE_1 = 3,
		DEFENSE_2 = 4,
		DEFENSE_3 = 5,

		PublicNames = {
			WEAPON = "Weapon",
			POST = "Post",
			DEFENSE_1 = "Defense",
			DEFENSE_2 = "Defense",
			DEFENSE_3 = "Defense",
		},
	},

	getCount = function(tbl: EnumTable): number
		if typeof(tbl) ~= "table" then
			warn("first parameter to getCount() needs to be the enum table")
			return 0
		end
		local count = 0
		for _, value in tbl do
			if typeof(value) ~= "number" then
				continue
			end
			count += 1
		end
		return count
	end,
	getAllValues = function(tbl: EnumTable): { number }
		if typeof(tbl) ~= "table" then
			warn("first parameter to getAllValues() needs to be the enum table")
			return {}
		end
		local values = {}
		for _, value in tbl do
			if typeof(value) ~= "number" then
				continue
			end
			table.insert(values, value)
		end
		table.sort(values)
		return values
	end,
	isValidValue = function(tbl: EnumTable, value: any): boolean
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums isValidValue() needs to be the enum table")
			return false
		end
		for _, enumValue in tbl do
			if typeof(enumValue) ~= "number" then
				continue
			end
			if enumValue == value then
				return true
			end
		end
		return false
	end,
	getName = function(tbl: EnumTable, value: any): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getName() needs to be the enum table")
			return nil
		end
		for key, enumValue in tbl do
			if typeof(enumValue) ~= "number" then
				continue
			end
			if enumValue == value then
				return key
			end
		end
		warn("invalid enum to getName " .. tostring(value))
		return nil
	end,
	getValueByName = function(tbl: EnumTable, name: string): number?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getValueByName() needs to be the enum table")
			return nil
		end
		local value = tbl[name]
		if typeof(value) == "number" then
			return value
		end
		warn("invalid enum to getValueByName " .. tostring(name))
		return nil
	end,
	getPublicName = function(tbl: EnumTable, value: any): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getPublicName() needs to be the enum table")
			return nil
		end
		if value == nil then
			return nil
		end
		local key = nil
		for candidateKey, enumValue in tbl do
			if typeof(enumValue) == "number" and enumValue == value then
				key = candidateKey
				break
			end
		end
		if key == nil then
			warn("invalid enum to getPublicName " .. tostring(value))
			return nil
		end
		if not tbl.PublicNames then
			warn("enum table has no public names, including for key " .. key)
			return nil
		end
		return tbl.PublicNames[key]
	end,
}

return module
