--!strict

-- The Flare, Air Defense's gadget (decided 2026-10-20 in place of the
-- Grounding Net, which only mattered on a flyer night): a lit flare
-- thrown like dynamite that every monster within its radius, air or
-- ground, goes for instead of what it was hunting, standing over it
-- until it burns out. It has no HP, so nothing finishes it early; it is
-- the crowd-control pull the Missile Launcher's small bursts want, where
-- the Decoy is a wall built in the day. One throw, then a wait. Every
-- number is a first guess until the class is played with it.
return {
	-- one level like a Tower (M67), bought with Iron at the Post & Gadget
	-- Upgrades table on the Auto Turret's price curve: it burns longer
	-- and draws from further (designer, 2026-10-20)
	UPGRADE_PRICE_IRON_BY_LEVEL = { 30, 60, 120, 240 },
	STATS_BY_LEVEL = {
		{ BURN_SEC = 12, DRAW_RADIUS_STUDS = 30 },
		{ BURN_SEC = 14, DRAW_RADIUS_STUDS = 34 },
		{ BURN_SEC = 16, DRAW_RADIUS_STUDS = 38 },
		{ BURN_SEC = 18, DRAW_RADIUS_STUDS = 42 },
		{ BURN_SEC = 20, DRAW_RADIUS_STUDS = 48 },
	},
	-- how long after a throw the next flare is in hand; the slot's grey
	-- sheet drains down over it
	COOLDOWN_SEC = 45,
	-- the throw: released this far ahead of the player's root, at this
	-- speed, with an upward arc (the dynamite's numbers)
	THROW_OFFSET_STUDS = 1.5,
	THROW_SPEED_STUDS_PER_SEC = 30,
	THROW_UPWARD_SPEED_STUDS_PER_SEC = 12,
	-- the flare lights where it lies this long after the throw
	LIGHT_DELAY_SEC = 1.5,
	-- the thrower's client simulates it, so the server refuses a flare
	-- that ended up further than a throw plus a tumble could carry it
	MAX_LAND_DISTANCE_STUDS = 60,
	-- the thrown stick's physics body
	STICK_SIZE = Vector3.new(0.4, 1.4, 0.4),
	-- the lit flare's footprint for the monsters (an invisible part this
	-- size on the ground is what they walk to)
	BODY_SIZE = Vector3.new(2, 1.5, 2),
}
