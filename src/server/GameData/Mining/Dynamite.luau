--!strict

-- Dynamite (GDD "Mining Tools"): thrown ahead of the player, explodes after
-- a fuse, and clears every rock within a block radius (1 = the 3x3x3 cube
-- around the stick; blocks are 4 studs). Ore inside lands on the ground.
return {
	FUSE_SEC = 3,
	BLAST_RADIUS_BLOCKS = 1,
	-- released this far ahead of the player's root, at this speed, with an
	-- upward arc so it lands roughly ten studs out (raised 2026-09-15 in play)
	THROW_OFFSET_STUDS = 3,
	THROW_SPEED_STUDS_PER_SEC = 30,
	THROW_UPWARD_SPEED_STUDS_PER_SEC = 12,
	-- the server refuses throws faster than this
	THROW_COOLDOWN_SEC = 0.5,
	-- the thrower's client simulates the stick, so the server refuses a blast
	-- that ended up further than a throw plus a tumble could carry it
	MAX_BLAST_DISTANCE_STUDS = 60,
	-- a stick that has not exploded by then (fell out of the world) is removed
	MAX_LIFETIME_SEC = 10,
}
