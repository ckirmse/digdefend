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
	-- the helicopter spawns at the far end of its way out and flies in
	-- for this long before the landing time; at most RESCUE_FLIGHT_SEC,
	-- and the same as GameData/Control/Helicopter's
	APPROACH_SEC = 30,
	BOARDING_TIMEOUT_SEC = 30,
	-- with nobody aboard the helicopter leaves empty after this long on
	-- the pad and the run is lost
	EMPTY_DEPARTURE_SEC = 45,
	-- the final wave is the next night's wave, this many times over
	FINAL_WAVE_MULTIPLIER = 1.25,
	-- the flown-off helicopter is destroyed this long after takeoff; the
	-- departure (GameData/Control/Helicopter) must finish inside it
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,
	-- a rider's camera watches the lift-off this long before the title
	-- card and the Results Menu (10 before the sunset, 30 before the
	-- designer brought the card forward, 2026-10-27)
	RIDE_SEC = 24,
	-- the full helicopter leaving into a sunset (designer, 2026-10-27): the
	-- sky turns back from night to the day's end over the first, then on
	-- back to the day's start over the second (a single 30 s then 15 s
	-- turn to an hour before the day's end came first)
	SUNSET_TO_DAY_END_SEC = 2,
	SUNSET_TO_DAY_START_SEC = 300,
	-- once the ride's camera starts its final drift the turn back slows:
	-- from wherever the sky is then to the day's start over this long
	-- (designer, 2026-10-28; it stood still from that moment before)
	SUNSET_FINAL_TO_DAY_START_SEC = 900,

	-- a standing player boards by touching the landed helicopter (designer,
	-- 2026-10-27; a Board prompt before): within this far of its body
	BOARD_TOUCH_MARGIN_STUDS = 2,

	-- green (good news) when the target is first reached (2026-10-06);
	-- the rest stay blue announcements. The call itself has no line since
	-- 2026-10-27 (the clients' INCOMING flash tells it)
	READY_MESSAGE = "Uranium target reached! Call in the rescue helicopter on the radio",
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
