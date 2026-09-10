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
}

return module
