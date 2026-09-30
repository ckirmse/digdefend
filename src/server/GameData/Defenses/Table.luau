--!strict

-- The Defense Table (GDD "Defense Table"): the map table in the Defense
-- Store. Its prompt puts a player in Build Mode, an overhead view of the
-- Defensive Zone where Towers and Traps are bought, placed, upgraded, and
-- sold. The camera numbers travel to the client as GameMetadata.
-- Placeholders until tuned in play.
return {
	PROMPT_ACTION_TEXT = "Build Defenses",
	PROMPT_OBJECT_TEXT = "Defense Table",
	-- a tap, not a hold: nothing is spent by opening the table
	PROMPT_HOLD_SEC = 0,
	PROMPT_MAX_DISTANCE_STUDS = 10,
	-- leaving waits this long at most for the camp around the player to
	-- stream back in before the camera returns to them
	EXIT_STREAM_TIMEOUT_SEC = 3,
	-- the overhead camera: how far it sits from the point it looks at (the
	-- zoom, with its limits), and how steeply it looks down (90 is straight
	-- down; a little less shows the fronts of the Towers)
	CAMERA_DISTANCE_STUDS = 150,
	CAMERA_MIN_DISTANCE_STUDS = 50,
	CAMERA_MAX_DISTANCE_STUDS = 300,
	CAMERA_PITCH_DEGREES = 65,
	-- panning with the keyboard or a thumbstick, in screen heights per second
	-- so it feels the same at every zoom
	CAMERA_PAN_SCREENS_PER_SEC = 0.9,
}
