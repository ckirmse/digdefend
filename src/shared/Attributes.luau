--!strict

-- every instance attribute name used for server/client communication; never use
-- raw strings at call sites
local module

module = {
	USER_ID = "UserId",
	DISPLAY_NAME = "DisplayName",
	IS_READY = "IsReady",
	IS_ADMIN = "IsAdmin",
	LOAD_STATUS = "LoadStatus",
	SERVER_START_TIME = "ServerStartTime",
	SCHEMA_VERSION = "SchemaVersion",
	SHADOW_TYPE = "ShadowType",
	-- GameMetadata
	PLACE_KIND = "PlaceKind",
	-- JSON of the party config the Create Party menu needs (lobby only; see
	-- PartyRules.encodeConfig / decodeConfig)
	PARTY_CONFIG = "PartyConfig",
	-- GameMetadata in the gameplay place: the run the lobby sent (RunManager)
	RUN_MAP = "RunMap",
	RUN_DIFFICULTY = "RunDifficulty",
	RUN_PLAYER_COUNT = "RunPlayerCount",
	RUN_HOST_USER_ID = "RunHostUserId",
	-- the seed the current mine was generated with (MineManager), for bug reports
	MINE_SEED = "MineSeed",
	-- on the client-only MineBlocks folder: ClientMineManager's live streaming numbers
	MINE_RENDERED_COUNT = "MineRenderedCount",
	MINE_POOLED_COUNT = "MinePooledCount",
	MINE_LAST_REFRESH_MS = "MineLastRefreshMs",
	-- on each rendered block part (client only): the grid cell index it shows
	MINE_CELL_INDEX = "MineCellIndex",
	-- tools (ToolManager, gameplay): the equipped Enums.ToolKind (0 = none) is
	-- public on AllPlayers so every client shows the held model, and repeated
	-- on CurrentPlayer; the slot list and pick axe level are private
	EQUIPPED_TOOL = "EquippedTool",
	TOOL_SLOTS = "ToolSlots",
	-- JSON of { [toolKind] = count } for consumables (MiningRules codec)
	TOOL_COUNTS = "ToolCounts",
	-- public as well, for the tool bar and store displays
	PICK_AXE_LEVEL = "PickAxeLevel",
	-- on the held Tool instance ToolManager builds: the GameAssets/Tools
	-- template it came from, so an upgrade rebuilds it
	TOOL_TEMPLATE = "ToolTemplate",
	-- Mining Supplies Store upgrade tracks (M21): private run state
	BOOTS_LEVEL = "BootsLevel",
	JET_PACK_LEVEL = "JetPackLevel",
	-- jet pack (JetPackManager): the tank is private, the burning flag is
	-- public so every client shows the flame
	JET_PACK_FUEL_SEC = "JetPackFuelSec",
	JET_PACK_FUEL_MAX_SEC = "JetPackFuelMaxSec",
	-- true from running dry until the tank is full again
	IS_JET_PACK_LOCKED = "IsJetPackLocked",
	IS_JET_PACK_BURNING = "IsJetPackBurning",
	-- GameMetadata (gameplay): the store catalogue as JSON (StoreRules codec)
	-- and the jet pack tuning the client animates from
	STORE_CATALOG = "StoreCatalog",
	JET_PACK_CLIMB_SPEED = "JetPackClimbSpeed",
	-- GameMetadata (gameplay): pick axe input tuning the client needs
	PICK_AXE_HIT_INTERVAL_SEC = "PickAxeHitIntervalSec",
	PICK_AXE_REACH_STUDS = "PickAxeReachStuds",
	-- backpack (BackpackManager, gameplay): private CurrentPlayer run state,
	-- one count per raw resource plus level and capacity in ore units
	BACKPACK_LEVEL = "BackpackLevel",
	BACKPACK_CAPACITY = "BackpackCapacity",
	BACKPACK_IRON_ORE = "BackpackIronOre",
	BACKPACK_GOLD_ORE = "BackpackGoldOre",
	BACKPACK_CRYSTAL = "BackpackCrystal",
	BACKPACK_URANIUM_ORE = "BackpackUraniumOre",
	-- refinery (RefineryManager, gameplay): private CurrentPlayer balances
	BALANCE_IRON_BARS = "BalanceIronBars",
	BALANCE_GOLD_BARS = "BalanceGoldBars",
	-- GameMetadata (gameplay): the shared camp progress every client shows;
	-- CampDiamondsRequired is 0 at the top level
	CAMP_LEVEL = "CampLevel",
	CAMP_DIAMONDS = "CampDiamonds",
	CAMP_DIAMONDS_REQUIRED = "CampDiamondsRequired",
	URANIUM_TOTAL = "UraniumTotal",
	URANIUM_TARGET = "UraniumTarget",
	REFINE_DURATION_SEC = "RefineDurationSec",
	-- on each ore pickup shadow part (Tags.ORE_PICKUP): what lies there
	PICKUP_RESOURCE = "PickupResource",
	PICKUP_AMOUNT = "PickupAmount",
	-- a dropped consumable instead: the Enums.ToolKind lying there
	PICKUP_TOOL = "PickupTool",
	-- on each thrown dynamite part (Tags.DYNAMITE): server time it explodes
	DYNAMITE_EXPLODE_TIME = "DynamiteExplodeTime",
	-- on every helicopter model (Tags.HELICOPTER): Enums.HelicopterPhase
	HELICOPTER_PHASE = "HelicopterPhase",
	-- on each helicopter pad model: PadIndex is Studio-authored, the rest is
	-- runtime party state written only by PartyManager (GDD "Helicopter Pads")
	PAD_INDEX = "PadIndex",
	PAD_STATE = "PadState",
	PAD_HOST_USER_ID = "PadHostUserId",
	PAD_MAP = "PadMap",
	PAD_DIFFICULTY = "PadDifficulty",
	PAD_MAX_PLAYERS = "PadMaxPlayers",
	PAD_VISIBILITY = "PadVisibility",
	PAD_PLAYER_COUNT = "PadPlayerCount",
	-- server time (GetServerTimeNow) the active pad timer expires; 0 when none;
	-- clients count down locally from it
	PAD_TIMER_END_TIME = "PadTimerEndTime",
	-- on each HUD loadout slot frame: the Enums.LoadoutSlot value it shows
	LOADOUT_SLOT = "LoadoutSlot",
	-- CurrentPlayer (private)
	CASH = "Cash",
	LOADOUT_WEAPON = "LoadoutWeapon",
	LOADOUT_POST = "LoadoutPost",
	LOADOUT_DEFENSE_1 = "LoadoutDefense1",
	LOADOUT_DEFENSE_2 = "LoadoutDefense2",
	LOADOUT_DEFENSE_3 = "LoadoutDefense3",
	DAILY_REWARD_LAST_CLAIMED_DAY = "DailyRewardLastClaimedDay",
	DAILY_REWARD_NEXT_CLAIM_TIME = "DailyRewardNextClaimTime",
	-- on each structure shadow part (StructureManager, M23): what it is and
	-- its health
	STRUCTURE_ID = "StructureId",
	STRUCTURE_KIND = "StructureKind",
	STRUCTURE_HP = "StructureHp",
	STRUCTURE_MAX_HP = "StructureMaxHp",
	-- rubble: true from the blow that emptied it until it is rebuilt, so HP
	-- climbing from zero reads as a rebuild, not a standing wall
	STRUCTURE_IS_DESTROYED = "StructureIsDestroyed",
	-- on the gate's shadow: clients tween the door leaves to match
	GATE_IS_OPEN = "GateIsOpen",
	-- GameMetadata: the shared tier of the gate, walls, and posts; whether it
	-- is night (the real clock is M28); door tween time for the clients
	FORTIFICATION_TIER = "FortificationTier",
	-- GameMetadata, the Workbench sign: Iron donated toward the next tier,
	-- what that tier costs (0 at the top tier), and the Camp Level it needs
	FORTIFICATION_POOL = "FortificationPool",
	FORTIFICATION_POOL_REQUIRED = "FortificationPoolRequired",
	FORTIFICATION_REQUIRED_CAMP_LEVEL = "FortificationRequiredCampLevel",
	IS_NIGHT = "IsNight",
	GATE_DOOR_TWEEN_SEC = "GateDoorTweenSec",
	-- GameMetadata: Hammer tuning the client needs to swing and to price a
	-- repair ("4 Iron Bars for 10 HP")
	REPAIR_CHUNK_HP = "RepairChunkHp",
	REPAIR_CHUNK_IRON = "RepairChunkIron",
	HAMMER_HIT_INTERVAL_SEC = "HammerHitIntervalSec",
	HAMMER_REACH_STUDS = "HammerReachStuds",
	-- icon capture pipeline (see docs/icon-capture.md, IconFramingFormat, ApplyIconFramings)
	-- on the Loading ScreenGui; src/first/loading.client.luau uses the literals
	-- because nothing in ReplicatedStorage has replicated when it runs
	LOADING_HANDOFF = "LoadingHandoff",
	LOADING_SHOWN_AT = "LoadingShownAt",
	ICON_FRAMING = "IconFraming",
	ICON_IMAGE_ID = "IconImageId",
}

return module
