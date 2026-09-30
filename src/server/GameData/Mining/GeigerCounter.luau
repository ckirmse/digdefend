--!strict

-- The Geiger Counter (GDD "Geiger Counter"): a dial beside the day clock,
-- shown in mining mode, whose three rings light as the player closes on a
-- uranium rock, buried or exposed. It replaced the uranium hum (2026-09-30).
-- Bought in the Mining Supplies Store and upgraded three times (prices in
-- GameData/Store/MiningSupplies). Placeholders until tuned in play.
return {
	-- how far each level detects uranium, measured to the rock's nearest
	-- face. Entry 1 is not owning one; the list length is the level count
	-- and must match the store's price list
	RANGE_STUDS_BY_LEVEL = { 0, 20, 30, 40, 50 },
	-- the share of the range each ring lights at, inner ring first: at the
	-- base range of 20 studs the rings light at 20, 13, and 8 studs (was
	-- 20, 10, 5 until 2026-09-30: 5 studs only lit with the rock in reach)
	RING_RANGE_SHARES = { 1, 0.65, 0.4 },
	-- how often the client measures the distance to the nearest uranium
	SCAN_INTERVAL_SEC = 0.2,
}
