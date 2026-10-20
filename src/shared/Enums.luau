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
		URANIUM_ORE = 3,

		PublicNames = {
			IRON_ORE = "Iron Ore",
			GOLD_ORE = "Gold Ore",
			URANIUM_ORE = "Uranium Ore",
		},
	},
	RefinedResource = {
		IRON_BAR = 1,
		GOLD_BAR = 2,
		URANIUM = 3,

		PublicNames = {
			IRON_BAR = "Iron Bar",
			GOLD_BAR = "Gold Bar",
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
		-- the class's gadget (GDD "Classes", M66): one slot, filled by the
		-- Enums.GadgetKind the class carries (the GadgetKind attribute)
		GADGET = 6,

		PublicNames = {
			PICK_AXE = "Pick Axe",
			WEAPON = "Weapon",
			TORCH = "Torch",
			DYNAMITE = "Dynamite",
			HAMMER = "Hammer",
			GADGET = "Gadget",
		},
	},
	-- handheld weapons (GDD S12), M24. The WEAPON tool slot holds one of
	-- these for the run; definitions are in GameData/Weapons/Handheld. Keys
	-- double as the held template names ("WEAPON_<KEY>" under GameAssets/Tools)
	WeaponKind = {
		RIFLE = 1,
		-- the four class weapons (GDD "Classes", 2026-10-16); the key is
		-- also the designer's source model under GameAssets/Weapons
		PISTOL = 2,
		SNIPER = 3,
		FLAMETHROWER = 4,
		ASSAULT_RIFLE = 5,

		PublicNames = {
			RIFLE = "Rifle",
			PISTOL = "Pistol",
			SNIPER = "Sniper Rifle",
			FLAMETHROWER = "Flamethrower",
			ASSAULT_RIFLE = "Assault Rifle",
		},
	},
	-- mounted post weapons (GDD "Posts"), M25. The POST loadout slot names
	-- one for the run; definitions are in GameData/Posts/PostWeapons. Keys
	-- double as the model names under GameAssets/PostWeapons
	PostWeaponKind = {
		MACHINE_GUN = 1,
		ROCKET_LAUNCHER = 2,
		-- the ten class posts (GDD "Classes", "Post Types", 2026-10-16),
		-- named as the designer's models under GameAssets/PostWeapons
		MINI_GUN = 3,
		RAIL_GUN = 4,
		MORTAR = 5,
		AA_LAUNCHER = 6,
		MACHINE_GUN_AUTOMATED = 7,
		MINE_LAYER = 8,
		TESLA_ARC = 9,
		SALVAGE_GUN = 10,
		SAW_GUN = 11,
		MAGNET_GUN = 12,

		PublicNames = {
			MACHINE_GUN = "Machine Gun",
			ROCKET_LAUNCHER = "Rocket Launcher",
			MINI_GUN = "Minigun",
			RAIL_GUN = "Railgun",
			MORTAR = "TNT Launcher",
			AA_LAUNCHER = "AA Launcher",
			MACHINE_GUN_AUTOMATED = "Auto Machine Gun",
			MINE_LAYER = "Mine Layer",
			TESLA_ARC = "Tesla Arc",
			SALVAGE_GUN = "Salvage Gun",
			SAW_GUN = "Saw Gun",
			MAGNET_GUN = "Magnet Gun",
		},
	},
	-- what a handheld weapon upgrade raises (GDD "Weapon Upgrades"): four
	-- upgrades each, bought with Gold at the Weapons Table in the defense
	-- building (decided 2026-10-01); definitions in GameData/Weapons/Upgrades
	WeaponAttribute = {
		DAMAGE = 1,
		AMMO = 2,
		RANGE = 3,

		PublicNames = {
			DAMAGE = "Damage",
			AMMO = "Ammo",
			RANGE = "Range",
		},
	},
	-- what a post weapon upgrade raises (GDD "Post Weapon Upgrades"): four
	-- upgrades each, bought with Gold at the Post Upgrade Table
	PostAttribute = {
		DAMAGE = 1,
		FIRE_RATE = 2,
		TURN_SPEED = 3,
		RANGE = 4,
		-- how fast an overheated gun cools (2026-09-29); each kind lists
		-- which four of these it offers in GameData/Posts/PostWeapons
		COOLDOWN = 5,
		-- the Railgun's headshot multiple (2026-10-19), in place of a Range
		-- no monster ever spawns beyond
		HEADSHOT = 6,
		-- the TNT Launcher's rows (2026-10-20): how wide the shell bursts
		-- and the pool spreads, how hard its fire hurts, how long it burns
		IMPACT_RADIUS = 7,
		FIRE_DAMAGE = 8,
		FIRE_LENGTH = 9,

		PublicNames = {
			DAMAGE = "Damage",
			FIRE_RATE = "Fire Rate",
			TURN_SPEED = "Turn Speed",
			RANGE = "Range",
			COOLDOWN = "Cooldown",
			HEADSHOT = "Headshot",
			IMPACT_RADIUS = "Impact Radius",
			FIRE_DAMAGE = "Fire Damage",
			FIRE_LENGTH = "Fire Length",
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
	-- what a player just did at the Defense Table, for listeners such as
	-- the run report (M34)
	PlacementAction = {
		BUILT = 1,
		UPGRADED = 2,
		SOLD = 3,
	},
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
	-- every monster (GDD "Monster Types"), M29: one entry per tier, the tier
	-- number in the key. Stats in GameData/Monsters/Roster, models under
	-- GameAssets/Monsters (a kind may borrow another's model)
	MonsterKind = {
		ZOMBIE_1 = 1,
		ZOMBIE_2 = 2,
		ZOMBIE_3 = 3,
		RUNNER_1 = 4,
		RUNNER_2 = 5,
		RUNNER_3 = 6,
		BRUTE_1 = 7,
		BRUTE_2 = 8,
		BRUTE_3 = 9,
		LAUNCHER_1 = 10,
		BOMBER_1 = 11,
		BOMBER_2 = 12,
		BOMBER_3 = 13,
		FLYER_1 = 14,
		FLYER_2 = 15,
		FLYER_3 = 16,
		TITAN_1 = 17,
		TITAN_2 = 18,
		-- the pocket lurker (M62): lives in the mine, never in a wave
		CAVE_SPIDER = 19,

		PublicNames = {
			ZOMBIE_1 = "Zombie",
			ZOMBIE_2 = "Zombie II",
			ZOMBIE_3 = "Zombie III",
			RUNNER_1 = "Runner",
			RUNNER_2 = "Runner II",
			RUNNER_3 = "Runner III",
			BRUTE_1 = "Brute",
			BRUTE_2 = "Brute II",
			BRUTE_3 = "Brute III",
			LAUNCHER_1 = "Launcher",
			BOMBER_1 = "Bomber",
			BOMBER_2 = "Bomber II",
			BOMBER_3 = "Bomber III",
			FLYER_1 = "Flyer",
			FLYER_2 = "Flyer II",
			FLYER_3 = "Flyer III",
			TITAN_1 = "Titan",
			TITAN_2 = "Titan II",
			CAVE_SPIDER = "Cave Spider",
		},
	},
	-- what a monster can attack (GDD "Monster Creation & Behavior"); every
	-- monster goes for the Refinery first, so it is never listed in data
	MonsterTargetType = {
		PLAYERS = 1,
		TOWERS = 2,
		TRAPS = 3,
		WALLS = 4,
		REFINERY = 5,
	},
	MonsterAttackType = {
		MELEE = 1,
		RANGED = 2,
	},
	MonsterTraversal = {
		LAND = 1,
		AIR = 2,
		-- walks any surface of the mine, cell to cell, with no gravity (M62)
		CRAWL = 3,
	},
	-- what a monster is doing, in its snapshot for the client's animation:
	-- moving (walk), or standing at a target (idle, with an attack clip on
	-- every attack)
	MonsterAction = {
		MOVING = 1,
		ENGAGED = 2,
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
		COMPASS = 7,
		GEIGER_COUNTER = 8,

		PublicNames = {
			PICK_AXE = "Pick Axe",
			BOOTS = "Boots",
			BACKPACK = "Backpack",
			JET_PACK = "Jet Pack",
			TORCH = "Torch",
			DYNAMITE = "Dynamite",
			COMPASS = "Compass",
			GEIGER_COUNTER = "Geiger Counter",
		},
	},
	-- what a stand offers a given player right now (StoreRules.getOffer)
	StoreOffer = {
		AVAILABLE = 1,
		MAXED = 2,
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
	-- strings in the GDD ("Gold 3").
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
		IRON_5 = 10,
		GOLD_1 = 11,
		GOLD_2 = 12,
		GOLD_3 = 13,
		GOLD_4 = 14,
		GOLD_5 = 15,
		URANIUM = 16,
		BEDROCK = 17,

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
			IRON_5 = "Iron 5",
			GOLD_1 = "Gold 1",
			GOLD_2 = "Gold 2",
			GOLD_3 = "Gold 3",
			GOLD_4 = "Gold 4",
			GOLD_5 = "Gold 5",
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
		-- the helicopter is called (M31): night look, the final wave, then
		-- boarding, until it leaves (Won)
		RESCUE = 6,
		-- the helicopter is called but the final wave is not here yet
		-- (2026-10-07): the clock stops and the sky holds while a countdown
		-- runs; RESCUE follows when the wave arrives
		RESCUE_WAIT = 7,

		PublicNames = {
			DAY = "Day",
			NIGHT = "Night",
			WON = "Rescued",
			LOST = "Lost",
			WAITING = "Landing",
			RESCUE = "Rescue",
			RESCUE_WAIT = "Final wave coming",
		},
	},
	-- why a run ended, for the screen that says so
	RunEndReason = {
		RESCUED = 1,
		REFINERY_DESTROYED = 2,
		CREW_DEAD = 3,
	},
	-- the three ways a dead player comes back (GDD "Health and Revives",
	-- M32), each its own Robux developer product; keys double as the
	-- save-data keys of the revive credits
	ReviveKind = {
		SELF = 1,
		FRIEND = 2,
		TEAM = 3,

		PublicNames = {
			SELF = "Revive",
			FRIEND = "Friend Revive",
			TEAM = "Team Revive",
		},
	},
	-- what a dead player's Results Menu offers right now: nothing (the 60
	-- seconds ran out), their own Revive, or the crew's Team Revive
	ReviveOffer = {
		NONE = 1,
		SELF = 2,
		TEAM = 3,
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
	-- how healthy a camp structure reads on the Camp Map (CampMapRules, M33)
	StructureHealthBand = {
		FULL = 1,
		HIGH = 2,
		MID = 3,
		LOW = 4,
		DESTROYED = 5,
	},
	-- the gear rows on a character's sheet (M55; GDD "Characters"): a
	-- weapon, a post weapon, and two towers (decided 2026-10-12). Each names
	-- a kind and carries a star count, 1 to 5. The LoadoutSlot enum of the
	-- bought-unlock loadout (WEAPON, POST, DEFENSE_1 to 3) was replaced by
	-- this on 2026-10-12
	GearSlot = {
		WEAPON = 1,
		POST = 2,
		TOWER_1 = 3,
		TOWER_2 = 4,

		PublicNames = {
			WEAPON = "Weapon",
			POST = "Post",
			TOWER_1 = "Tower",
			TOWER_2 = "Tower",
		},
	},
	-- the launch classes (GDD "Classes", designed 2026-10-15; M64). A
	-- character record is one of these; the class's kit and its buff and
	-- debuff live in GameData/Classes/Roster. Saved by key name, so a value
	-- may be renumbered. The Recruit is the free one every player starts as
	ClassKind = {
		RECRUIT = 1,
		GUNNER = 2,
		SNIPER = 3,
		PYRO = 4,
		AIR_DEFENSE = 5,
		RANGER = 6,
		ENGINEER = 7,
		ELECTRICIAN = 8,
		PROSPECTOR = 9,
		DEMOLITIONIST = 10,
		HAULER = 11,
		MEDIC = 12,

		PublicNames = {
			RECRUIT = "Recruit",
			GUNNER = "Gunner",
			SNIPER = "Sniper",
			PYRO = "Pyro",
			AIR_DEFENSE = "Air Defense",
			RANGER = "Ranger",
			ENGINEER = "Engineer",
			ELECTRICIAN = "Electrician",
			PROSPECTOR = "Prospector",
			DEMOLITIONIST = "Demolitionist",
			HAULER = "Hauler",
			MEDIC = "Medic",
		},
	},
	-- the modifier table a class's buff and debuff are entries in (GDD
	-- "Classes"; M64): every stat a class may scale, each defaulting to
	-- 1.0 and read through ClassRules.modifier in the one place that stat
	-- is computed. Applied as of 2026-10-16: MINING_POWER (MiningManager),
	-- HANDHELD_DAMAGE (WeaponManager), POST_DAMAGE (PostManager),
	-- TOWER_BUILD_COST and TRAP_COST (PlacementManager), REPAIR_SPEED and
	-- REPAIR_COST (StructureManager, PlacementManager), BACKPACK_CAPACITY
	-- (BackpackManager), MOVE_SPEED (BootsManager), MAX_HEALTH
	-- (ReviveManager, 2026-10-19). The rest are recorded in the roster for
	-- content that does not exist yet and do nothing until their system
	-- reads them. MOVE_SPEED and MINING_POWER are the core stats every
	-- class states outright (ClassRules.CORE_MODIFIERS); MAX_HEALTH is
	-- applied but no class sets it (dropped as a core stat 2026-10-19).
	-- A modifier that would only touch a thing one class alone owns is
	-- not a modifier but that thing's own GameData number (decided
	-- 2026-10-20: the Gunner's Post Damage folded into the Minigun, the
	-- Pyro's Burn Length, the Electrician's Tower Fire Rate, and the
	-- Demolitionist's Dynamite Damage dropped)
	ClassModifier = {
		MINING_POWER = 1,
		HANDHELD_DAMAGE = 2,
		POST_DAMAGE = 3,
		TOWER_BUILD_COST = 4,
		TRAP_COST = 5,
		REPAIR_SPEED = 6,
		REPAIR_COST = 7,
		BACKPACK_CAPACITY = 8,
		MOVE_SPEED = 9,
		-- not yet applied (see above)
		ORE_YIELD = 10,
		LARGE_MONSTER_DAMAGE = 11,
		FLYER_DAMAGE = 12,
		GROUND_DAMAGE = 13,
		MAX_HEALTH = 14,

		PublicNames = {
			MINING_POWER = "Mining Power",
			HANDHELD_DAMAGE = "Weapon Damage",
			POST_DAMAGE = "Post Damage",
			TOWER_BUILD_COST = "Tower Build Cost",
			TRAP_COST = "Trap Cost",
			REPAIR_SPEED = "Repair Speed",
			REPAIR_COST = "Repair Cost",
			BACKPACK_CAPACITY = "Backpack Capacity",
			MOVE_SPEED = "Move Speed",
			ORE_YIELD = "Ore Yield",
			LARGE_MONSTER_DAMAGE = "Damage to Large Monsters",
			FLYER_DAMAGE = "Damage to Flyers",
			GROUND_DAMAGE = "Damage to Ground Monsters",
			MAX_HEALTH = "Health",
		},
	},
	-- the class-only tool each class carries (GDD "Classes"; M64). Named
	-- here so the roster is data, but none is built yet: no tool bar slot,
	-- no behaviour, no model. NONE is the Recruit's empty slot
	GadgetKind = {
		NONE = 1,
		AUTO_TURRET = 2,
		BINOCULARS = 3,
		REMOTE_CHARGE = 4,
		GROUNDING_NET = 5,
		STIM_SHOT = 6,
		BUILD_TABLET = 7,
		STORM_ROD = 8,
		ORE_SCANNER = 9,
		DYNAMITE = 10,
		ORE_CART = 11,
		MEDKIT = 12,

		PublicNames = {
			NONE = "None",
			AUTO_TURRET = "Auto Turret",
			BINOCULARS = "Binoculars",
			REMOTE_CHARGE = "Remote Charge",
			GROUNDING_NET = "Grounding Net",
			STIM_SHOT = "Stim Shot",
			BUILD_TABLET = "Build Tablet",
			STORM_ROD = "Storm Rod",
			ORE_SCANNER = "Ore Scanner",
			DYNAMITE = "Dynamite",
			ORE_CART = "Ore Cart",
			MEDKIT = "Medkit",
		},
	},
	-- skill families (GDD "Characters"): every skill belongs to one; two of
	-- a family give a title and three its set bonus (M56)
	SkillFamily = {
		DIGGING = 1,
		HAULING = 2,
		DEMOLITION = 3,
		BUILDING = 4,
		GUNNERY = 5,
		MARKSMANSHIP = 6,

		PublicNames = {
			DIGGING = "Digging",
			HAULING = "Hauling",
			DEMOLITION = "Demolition",
			BUILDING = "Building",
			GUNNERY = "Gunnery",
			MARKSMANSHIP = "Marksmanship",
		},
	},
	-- the one rarity ladder (designer, 2026-10-12; five tiers, replacing
	-- the four-tier skill rarity and the star rating the sheet showed for
	-- gear): a gear row's 1 to 5 stars read as these words, and a skill
	-- carries one directly. Saved by value, so never renumbered
	Rarity = {
		COMMON = 1,
		UNCOMMON = 2,
		RARE = 3,
		EPIC = 4,
		LEGENDARY = 5,

		PublicNames = {
			COMMON = "Common",
			UNCOMMON = "Uncommon",
			RARE = "Rare",
			EPIC = "Epic",
			LEGENDARY = "Legendary",
		},
	},
	-- what a character slot is bought with (M37): the second slot Diamonds,
	-- every later one Robux
	SlotCurrency = {
		DIAMONDS = 1,
		ROBUX = 2,

		PublicNames = {
			DIAMONDS = "Diamonds",
			ROBUX = "Robux",
		},
	},
	-- the skin slots a character equips (M61; reserved in the save from
	-- M55). Skins are owned by the account and equipped per character; the
	-- helicopter skin is account-wide, so it is not a slot here
	CosmeticSlot = {
		PICK_AXE = 1,
		HAMMER = 2,
		WEAPON = 3,
		POST_WEAPON = 4,
		TOWER = 5,
		JET_PACK = 6,
		BACKPACK = 7,
		HELMET = 8,

		PublicNames = {
			PICK_AXE = "Pick Axe",
			HAMMER = "Hammer",
			WEAPON = "Weapon",
			POST_WEAPON = "Post Weapon",
			TOWER = "Tower",
			JET_PACK = "Jet Pack",
			BACKPACK = "Backpack",
			HELMET = "Helmet",
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
