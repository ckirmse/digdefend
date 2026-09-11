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
	-- icon capture pipeline (see docs/icon-capture.md, IconFramingFormat, ApplyIconFramings)
	-- on the Loading ScreenGui; src/first/loading.client.luau uses the literals
	-- because nothing in ReplicatedStorage has replicated when it runs
	LOADING_HANDOFF = "LoadingHandoff",
	LOADING_SHOWN_AT = "LoadingShownAt",
	ICON_FRAMING = "IconFraming",
	ICON_IMAGE_ID = "IconImageId",
}

return module
