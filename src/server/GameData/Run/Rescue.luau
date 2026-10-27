--!strict

-- The rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31. Once the crew
-- has refined the uranium target, the designer's radio (Camp.Radio, its
-- own prompt) calls the rescue helicopter: the clock stops and a countdown
-- runs for FINAL_WAVE_DELAY_SEC (the Rescue Wait state, 2026-10-07), then
-- the run enters its Rescue state (night look, gate shut) and the final
-- wave spawns while the helicopter flies in; it lands RESCUE_FLIGHT_SEC
-- after the wave arrives (in the air for the last APPROACH_SEC of that,
-- M75), and it leaves once everyone standing is aboard, BOARDING_TIMEOUT_SEC
-- after landing with someone aboard, or EMPTY_DEPARTURE_SEC after landing
-- with nobody aboard, which loses the run (M75; it waited forever before).
-- Everyone aboard wins (decided 2026-09-24).
return {
	-- the call sequence the clients play before the breather begins (the
	-- radio's dispatch message, about 6 s, then the 6 s INCOMING flash);
	-- the breather's countdown starts this long after the call
	CALL_SEQUENCE_SEC = 12,
	-- how long the dispatch message runs: when the INCOMING flash goes up
	-- on the clients, the mine's monsters fade away (designer, 2026-10-27)
	DISPATCH_SEC = 6,
	-- the breather between the call sequence and the final wave; the sky
	-- eases from where the day stood to its end across it (designer,
	-- 2026-10-27; 30 s and a still sky before)
	FINAL_WAVE_DELAY_SEC = 90,
	RESCUE_FLIGHT_SEC = 60,
	-- the helicopter spawns at the pad's ApproachSpawn and flies in for
	-- this long before the landing time; at most RESCUE_FLIGHT_SEC
	APPROACH_SEC = 20,
	BOARDING_TIMEOUT_SEC = 30,
	-- with nobody aboard the helicopter leaves empty after this long on
	-- the pad and the run is lost
	EMPTY_DEPARTURE_SEC = 45,
	-- the final wave is the next night's wave, this many times over
	FINAL_WAVE_MULTIPLIER = 1.25,
	-- the flown-off helicopter is destroyed this long after takeoff; the
	-- departure (GameData/Control/Helicopter) must finish inside it
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,
	-- a rider's camera follows the lift-off this long before the screen
	-- fades to the Results Menu
	RIDE_SEC = 10,

	-- the template's authored BoardPrompt is used; these dress a prompt
	-- made in code when a template has none
	BOARD_PROMPT_ACTION_TEXT = "Board",
	BOARD_PROMPT_OBJECT_TEXT = "Rescue helicopter",
	BOARD_PROMPT_MAX_DISTANCE_STUDS = 14,

	-- green (good news) when the target is first reached and when the
	-- rescue is called (2026-10-06); the rest stay blue announcements
	READY_MESSAGE = "Uranium target reached! Call in the rescue helicopter on the radio",
	CALLED_MESSAGE = "The rescue helicopter is on its way. Hold out",
	LANDED_MESSAGE = "The helicopter has arrived. Board it now!",
	BOARDED_FORMAT = "%s is aboard (%d / %d)",
	WON_ALL_MESSAGE = "The whole crew made it out. The run is won",
	WON_SOME_FORMAT = "%s made it out. The run is won",
	LEFT_EMPTY_MESSAGE = "The helicopter left with nobody aboard. The run is lost",
	ANNOUNCEMENT_DISPLAY_SEC = 6,
	NOT_READY_FEEDBACK = "Refine the uranium target first",
	-- the radio answers a night call with this (designer, 2026-10-27)
	NIGHT_FEEDBACK = "You can only call in a rescue helicopter in the day time",
	ALREADY_ABOARD_FEEDBACK = "You are already aboard",
	NO_SEAT_FEEDBACK = "No seat left",
}
