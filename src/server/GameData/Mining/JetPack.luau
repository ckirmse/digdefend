--!strict

-- The jet pack (GDD "Jet Pack"): fuel is the whole design. Seconds of burn
-- by level come from BASE + PER_LEVEL, so the level count is the store's
-- price list, not this file. Height per burn is CLIMB_SPEED x fuel: 18
-- studs (4.5 blocks) at level 1, 42 studs (10.5 blocks) at level 5, under
-- the 72-stud mine (retuned 2026-09-15: 22 x 3 s cleared the mine at level 2).
return {
	BASE_FUEL_SEC = 1.5,
	FUEL_PER_LEVEL_SEC = 0.5,
	-- straight up while burning; walk controls still steer
	CLIMB_SPEED_STUDS_PER_SEC = 12,
	-- the tank refills whenever the pack is not burning, anywhere, at this
	-- many seconds of fuel per second; running it dry locks the pack until
	-- it is full again (decided 2026-09-15, replacing the on-the-ground rule)
	REFILL_RATE = 0.5,
	-- how often the private fuel attribute is written while it changes
	FUEL_REPLICATE_INTERVAL_SEC = 0.1,
}
