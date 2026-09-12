--!strict

-- The backpack (GDD "Backpack", "Collecting Ore"): raw ore capacity by level,
-- counted in ore units. Four levels by decision; the list length fixes it.
-- Everyone is level 1 until the Mining Supplies Store (M21).
return {
	CAPACITY_BY_LEVEL = { 50, 100, 200, 400 },
	-- ore that did not fit lands on the ground near the broken block and is
	-- collected by any player walking within this distance with room
	PICKUP_RADIUS_STUDS = 5,
	-- how far a dropped pickup scatters from the block centre
	DROP_SCATTER_STUDS = 1.5,
	-- how often the server checks players against nearby pickups
	PICKUP_POLL_SEC = 0.25,
	-- a pickup nobody takes disappears after this
	PICKUP_LIFETIME_SEC = 120,
	-- the oldest pickups are removed past this count so a mining spree cannot
	-- litter the mine without bound
	MAX_PICKUPS = 300,
}
