--!strict

-- Gameplay place arrival tuning (M14). The camp helicopter waits for the
-- party to load in, then flies off.
return {
	-- seconds after the first arrival before the helicopter leaves even if a
	-- party member never showed up
	ARRIVAL_TIMEOUT_SEC = 45,
	-- pause once everyone is Ready before the helicopter lifts off
	TAKEOFF_DELAY_SEC = 3,
	-- the flown-off helicopter is destroyed this long after takeoff
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,
	-- lift applied when a character is placed on its spawn part
	SPAWN_LIFT_STUDS = 3,
}
