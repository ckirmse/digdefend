--!strict

-- The rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31. Once the crew
-- has refined the uranium target, the designer's radio (Camp.Radio, its
-- own prompt) calls the rescue helicopter: the run enters its Rescue
-- state (night look, gate shut), the final wave spawns while the
-- helicopter flies in,
-- it lands RESCUE_FLIGHT_SEC after the call, and it leaves once everyone
-- standing is aboard or BOARDING_TIMEOUT_SEC after landing with someone
-- aboard. Everyone aboard wins (decided 2026-09-24).
return {
	RESCUE_FLIGHT_SEC = 60,
	BOARDING_TIMEOUT_SEC = 30,
	-- the final wave is the next night's wave, this many times over
	FINAL_WAVE_MULTIPLIER = 1.5,
	-- the flown-off helicopter is destroyed this long after takeoff
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,

	BOARD_PROMPT_ACTION_TEXT = "Board",
	BOARD_PROMPT_OBJECT_TEXT = "Rescue helicopter",
	BOARD_PROMPT_MAX_DISTANCE_STUDS = 14,

	CALLED_MESSAGE = "The rescue helicopter is on its way. Hold out",
	LANDED_MESSAGE = "The helicopter has landed. Get aboard",
	WON_ALL_MESSAGE = "The whole crew made it out. The run is won",
	WON_SOME_FORMAT = "%s made it out. The run is won",
	ANNOUNCEMENT_DISPLAY_SEC = 6,
	NOT_READY_FEEDBACK = "Refine the uranium target first",
	ALREADY_ABOARD_FEEDBACK = "You are already aboard",
	NO_SEAT_FEEDBACK = "No seat left",
}
