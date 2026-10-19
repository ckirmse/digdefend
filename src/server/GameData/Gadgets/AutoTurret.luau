--!strict

-- The Auto Turret, the Gunner's gadget (GDD "Classes", M66): a compact
-- sentry carried in the GADGET tool slot and placed anywhere in camp off
-- the defensive grid. Free, one standing at a time per player, picked up
-- and moved at will, weaker and shorter-ranged than a level 1 Sentry Gun
-- (12 damage every 0.5 s at 40 studs, 150 HP). Monsters treat it as a
-- player: the player-hunters attack it, the tower destroyers walk past.
-- Every number is a first guess (2026-10-19) until the Gunner is played
-- with it.
return {
	-- one level like a Tower (M67), bought with Iron at the Post & Gadget
	-- Upgrades table on the Sentry Gun's price curve; every number moves a
	-- step. Level 1 is 2026-10-19's first night: three times the first
	-- range and twice the rate, the damage doubled back (32 a second)
	UPGRADE_PRICE_IRON_BY_LEVEL = { 30, 60, 120, 240 },
	STATS_BY_LEVEL = {
		{ DAMAGE = 8, FIRE_INTERVAL_SEC = 0.25, RANGE_STUDS = 90, MAX_HP = 100 },
		{ DAMAGE = 10, FIRE_INTERVAL_SEC = 0.23, RANGE_STUDS = 96, MAX_HP = 120 },
		{ DAMAGE = 13, FIRE_INTERVAL_SEC = 0.21, RANGE_STUDS = 102, MAX_HP = 145 },
		{ DAMAGE = 17, FIRE_INTERVAL_SEC = 0.19, RANGE_STUDS = 110, MAX_HP = 175 },
		{ DAMAGE = 22, FIRE_INTERVAL_SEC = 0.17, RANGE_STUDS = 120, MAX_HP = 210 },
	},
	-- a spot must sit within this of the path grid's ground height, so a
	-- roof over walkable ground is refused (a basic zombie cannot reach it)
	GROUND_LEVEL_TOLERANCE_STUDS = 3,
	-- the ghost hangs this far ahead of the player, flat; the server allows
	-- the tolerance on top for a step taken since the client measured
	PLACE_DISTANCE_STUDS = 15,
	PLACE_TOLERANCE_STUDS = 6,
	-- ground is a surface whose normal points at least this much up
	-- (0.8 is about 37 degrees); steeper is a slope or a wall
	MIN_GROUND_NORMAL_Y = 0.8,
	-- a destroyed turret comes back at the next dawn (2026-10-19, replacing
	-- a five minute cooldown): the button greys out until the day starts
	-- a turret standing within this of the Refinery guards it: monsters
	-- weigh it against the Refinery itself, the nearer winning, where a
	-- turret further out is a player target that the Refinery outranks
	-- (2026-10-19: a turret beside the Refinery was never attacked)
	REFINERY_GUARD_RADIUS_STUDS = 50,
	-- like a Decoy: a monster inside this range prefers the turret to any
	-- plain target of the same type, the Refinery it is touching included
	DRAW_RANGE_STUDS = 30,
	-- the server's hit box for monsters, sized to the designer's model
	HIT_BOX_SIZE = Vector3.new(4.5, 3, 2.5),
	-- where its shots leave, above the ground it stands on
	MUZZLE_HEIGHT_STUDS = 2.4,
	-- the raycast that finds the ground under a requested spot: from this
	-- far above it to this far below
	GROUND_RAY_ABOVE_STUDS = 3,
	GROUND_RAY_BELOW_STUDS = 8,
}
