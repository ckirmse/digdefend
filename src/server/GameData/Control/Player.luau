-- Persistent player data tuning. PROFILE_STORE_NAME is the DataStore key
-- namespace; bumping it abandons every existing save, so change it only with
-- a deliberate migration plan.
return {
	PROFILE_STORE_NAME = "DigDefendPlayerData_v1",
	PROFILE_KEY_PREFIX = "p_",
	STARTING_CASH = 0,
	-- bounds the ProfileStore retry loop so a DataStore outage strands nobody on
	-- the loading screen forever; past this the player is kicked with a message
	DATA_LOAD_TIMEOUT_SEC = 30,
	-- how long BindToClose waits for in-flight exits to finish saving
	BIND_TO_CLOSE_TIMEOUT_SEC = 25,
}
