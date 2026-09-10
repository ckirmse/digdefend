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
	ICON_FRAMING = "IconFraming",
	ICON_IMAGE_ID = "IconImageId",
}

return module
