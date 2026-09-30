--!strict

-- The Defensive Zone grid (GDD "Defensive Zones", "Building Towers"), M26.
-- Every Defensive Zone part in a map is cut into square cells of
-- CELL_SIZE_STUDS from its centre out (PlacementRules.measureZone), and
-- Towers and Traps occupy whole cells. The Wave Areas the monsters walk
-- (M29) share the same cell size. Building is done from the Defense Table's
-- overhead view (GameData/Defenses/Table), so nothing here depends on
-- where the builder stands.
return {
	CELL_SIZE_STUDS = 4,
	-- the cells nearest a wall, a post, or the gate stay empty, whatever
	-- shape the wall line takes: a cell whose centre is closer than this
	-- many cells to a fortification cannot be built on (decided 2026-09-30)
	FORTIFICATION_CLEARANCE_CELLS = 2,
}
