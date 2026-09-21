--!strict

-- The Defensive Zone grid (GDD "Defensive Zones", "Building Towers"), M26.
-- Every Defensive Zone part in a map is cut into square cells of
-- CELL_SIZE_STUDS from its centre out (PlacementRules.measureZone), and
-- Towers and Traps occupy whole cells. The Wave Areas the monsters walk
-- (M29) share the same cell size. In Build Mode the preview stands
-- PREVIEW_DISTANCE_STUDS in front of the player, and the server refuses a
-- build further than BUILD_MAX_DISTANCE_STUDS from the player's root,
-- which covers the preview distance, a big footprint, and movement latency.
return {
	CELL_SIZE_STUDS = 4,
	PREVIEW_DISTANCE_STUDS = 20,
	BUILD_MAX_DISTANCE_STUDS = 44,
}
