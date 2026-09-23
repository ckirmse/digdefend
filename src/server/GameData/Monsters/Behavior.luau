--!strict

-- How every monster moves, fights, and reaches the clients (GDD "Monster
-- Creation & Behavior", "Monster Performance"), M29. The server steps all
-- monsters together TICK_RATE_HZ times a second, not every frame. Each
-- player receives a monster's position every tick while it is within
-- NEAR_DISTANCE_STUDS of them and moving, every MID_EVERY_TICKS ticks out
-- to MID_DISTANCE_STUDS, and every FAR_EVERY_TICKS ticks otherwise (and
-- when it stands still), packed into packets of at most SNAPSHOT_MAX_BYTES
-- (the engine drops unreliable messages past 1000 bytes). Clients draw the NEAR_ANIMATED_MAX closest
-- monsters fully animated, the rest within HELD_POSE_DISTANCE_STUDS in a
-- held pose, and anything further as the one-part Proxy; nothing is ever
-- hidden for distance. Every number here is placeholder tuning.
return {
	TICK_RATE_HZ = 10,
	NEAR_DISTANCE_STUDS = 80,
	MID_DISTANCE_STUDS = 200,
	MID_EVERY_TICKS = 2,
	FAR_EVERY_TICKS = 4,
	SNAPSHOT_MAX_BYTES = 900,
	-- the client draws this far behind the newest snapshot so it has two to
	-- blend between; a monster sent less often carries on at its last speed
	INTERPOLATION_DELAY_SEC = 0.15,
	NEAR_ANIMATED_MAX = 40,
	HELD_POSE_DISTANCE_STUDS = 250,

	-- time between attacks for a monster whose Roster entry has none
	DEFAULT_ATTACK_INTERVAL_SEC = 1.5,
	-- a ground monster's next cell is a barrier: entering it costs this many
	-- cell steps more, so any open way round under this length is taken
	BARRIER_COST_CELLS = 60,
	-- a projectile's speed (M29 has one, the Fireball)
	PROJECTILE_SPEED_STUDS_PER_SEC = 60,
	-- ground monsters push apart within this distance of each other
	SEPARATION_STUDS = 4,
	-- every monster walks its own lane, up to this far to either side of
	-- the shared route (chosen at spawn), so a crowd moves as a band rather
	-- than a line; the lane narrows wherever the ground does, as at the gate
	LANE_SPREAD_STUDS = 12,
	-- a monster heads straight for the point this many cells along its
	-- route when nothing is in the way, so it walks smooth lines rather
	-- than cell to cell
	LOOKAHEAD_CELLS = 8,
	-- the most the path grid is recomputed, however often defenses change
	PATH_RECOMPUTE_MIN_SEC = 0.5,
	-- until Revives (M32) a monster can bring a player down to this, not below
	PLAYER_MIN_HEALTH = 1,
	-- the most monsters alive at once; a spawn past it waits
	MAX_ALIVE = 500,
	-- the stress test dev tool spawns this many at most per press
	STRESS_TEST_MAX = 500,
}
