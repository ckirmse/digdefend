--!strict

-- Torches (GDD "Mining Tools"): placed on the surface a player looks at,
-- like Minecraft. A torch on a mine block falls to the ground as a pickup
-- when that block breaks. The server accepts a placement within pick axe
-- reach plus this tolerance of the player.
return {
	REACH_TOLERANCE_STUDS = 6,
	PLACE_COOLDOWN_SEC = 0.25,
	-- how far off the surface the torch's base sits
	SURFACE_OFFSET_STUDS = 0.2,
	-- client light (PointLight) on each torch
	LIGHT_RANGE_STUDS = 24,
	LIGHT_BRIGHTNESS = 1.5,
	-- past this many the oldest torch is removed, so a crew cannot litter
	-- the mine without bound
	MAX_TORCHES = 200,
}
