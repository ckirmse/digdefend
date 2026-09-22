--!strict

-- The run's day and night loop (GDD "Wave Cycle"), M28. A day lasts
-- DAY_SEC with the gate open; its last DUSK_SHARE is dusk, which only
-- changes the clock's picture. Night shuts the gate, enemies spawn over
-- NIGHT_SPAWN_SEC (M29), and the night lasts until every enemy is dead.
-- Until enemies exist a night also ends NIGHT_PLACEHOLDER_SEC after the
-- spawn window; M29 sets that to 0 so only the enemies end a night.
-- The day-start announcement is DAY_START_FORMAT with the day number,
-- the crew size, and the two party multipliers; the loss announcements
-- name the cause. Every number here is designer tuning.
return {
	-- once everyone the lobby sent is Ready (or the arrival timeout has
	-- passed), the run waits this long in the morning look before day 1
	PRE_DAY_SEC = 10,
	DAY_SEC = 300,
	DUSK_SHARE = 0.2,
	NIGHT_SPAWN_SEC = 90,
	NIGHT_PLACEHOLDER_SEC = 30,
	-- the dev tool's "Dusk now" runs what is left of the day down over
	-- this long, so the sky blends to night begin instead of snapping
	FORCED_DUSK_SEC = 3,
	DAY_START_FORMAT = "Day %d. Crew of %d. Ore %.2fx, Uranium target %.2fx",
	DAY_START_DISPLAY_SEC = 6,
	LOST_REFINERY_MESSAGE = "The Refinery has fallen. The run is lost",
	LOST_ALL_DEAD_MESSAGE = "The whole crew is down. The run is lost",
	LOST_DISPLAY_SEC = 10,
	-- the sky (decided 2026-09-22): the looks are shared LightingPresets
	-- per map (DAY_START, DAY_END, NIGHT_START, NIGHT_END, each with its
	-- own ClockTime). Over a day the sky blends day start into day end;
	-- the night's first DUSK_TRANSITION_SEC blend day end into night
	-- start, then night start blends into night end over NIGHT_SPAWN_SEC
	-- and night end holds until the wave is done. A cleared night blends
	-- back to day start over DAWN_TRANSITION_SEC and only then does the
	-- day clock start
	LIGHTING_DUSK_TRANSITION_SEC = 1,
	LIGHTING_DAWN_TRANSITION_SEC = 1,
}
