--!strict

-- The Geiger Counter (GDD "Geiger Counter"): a dial beside the day clock,
-- shown in mining mode, whose three rings light as the player closes on a
-- uranium rock, buried or exposed. It replaced the uranium hum (2026-09-30).
-- Bought in the Mining Supplies Store and upgraded twice (prices in
-- GameData/Store/MiningSupplies; the fourth upgrade was dropped on
-- 2026-10-06 as one range too many). Placeholders until tuned in play.
return {
	-- how far each level detects uranium, measured to the rock's nearest
	-- face. Entry 1 is not owning one; the list length is the level count
	-- and must match the store's price list
	RANGE_STUDS_BY_LEVEL = { 0, 20, 30, 40 },
	-- the distance each ring lights at, outer ring first, one list per level
	-- (entry 1 is not owning one). The outer ring is the level's range; the
	-- inner ring stays at 8 studs (two blocks) at every level so the last
	-- stretch of the hunt is always as tight (designer, 2026-10-06: at 40
	-- studs a 40% inner ring covered four blocks each way and the rock was
	-- hard to pin down). Was shares of the range, 1 / 0.65 / 0.4
	RING_STUDS_BY_LEVEL = {
		{},
		{ 20, 13, 8 },
		{ 30, 16, 8 },
		{ 40, 20, 8 },
	},
	-- how often the client measures the distance to the nearest uranium
	SCAN_INTERVAL_SEC = 0.2,
}
