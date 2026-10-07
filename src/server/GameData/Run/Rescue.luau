--!strict

-- The rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31. Once the crew
-- has refined the uranium target, the designer's radio (Camp.Radio, its
-- own prompt) calls the rescue helicopter: the clock stops and a countdown
-- runs for FINAL_WAVE_DELAY_SEC (the Rescue Wait state, 2026-10-07), then
-- the run enters its Rescue state (night look, gate shut) and the final
-- wave spawns while the helicopter flies in; it lands RESCUE_FLIGHT_SEC
-- after the wave arrives, and it leaves once everyone standing is aboard
-- or BOARDING_TIMEOUT_SEC after landing with someone aboard. Everyone
-- aboard wins (decided 2026-09-24).
return {
	-- the breather between the radio call and the final wave
	FINAL_WAVE_DELAY_SEC = 30,
	RESCUE_FLIGHT_SEC = 60,
	BOARDING_TIMEOUT_SEC = 30,
	-- the final wave is the next night's wave, this many times over
	FINAL_WAVE_MULTIPLIER = 1.25,
	-- the flown-off helicopter is destroyed this long after takeoff
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,

	BOARD_PROMPT_ACTION_TEXT = "Board",
	BOARD_PROMPT_OBJECT_TEXT = "Rescue helicopter",
	BOARD_PROMPT_MAX_DISTANCE_STUDS = 14,

	-- green (good news) when the target is first reached and when the
	-- rescue is called (2026-10-06); the rest stay blue announcements
	READY_MESSAGE = "Uranium target reached! Call in the rescue helicopter on the radio",
	CALLED_MESSAGE = "The rescue helicopter is on its way. Hold out",
	LANDED_MESSAGE = "The helicopter has arrived. Board it now!",
	WON_ALL_MESSAGE = "The whole crew made it out. The run is won",
	WON_SOME_FORMAT = "%s made it out. The run is won",
	ANNOUNCEMENT_DISPLAY_SEC = 6,
	NOT_READY_FEEDBACK = "Refine the uranium target first",
	ALREADY_ABOARD_FEEDBACK = "You are already aboard",
	NO_SEAT_FEEDBACK = "No seat left",
}
