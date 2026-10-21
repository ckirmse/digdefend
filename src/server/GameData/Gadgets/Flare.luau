--!strict

-- The Flare, Air Defense's gadget (decided 2026-10-20 in place of the
-- Grounding Net, which only mattered on a flyer night; a flare gun since
-- 2026-10-21, a throw before): a flare fired from the gun in hand that
-- lights where it lands, and every monster within its radius, air or
-- ground, goes for it instead of what it was hunting, standing over it
-- until it burns out. It has no HP, so nothing finishes it early; it is
-- the crowd-control pull the Missile Launcher's small bursts want, where
-- the Decoy is a wall built in the day. One shot, then a wait. No
-- upgrades (designer, 2026-10-21: only a gadget that must keep pace with
-- the waves or the mine scales; a pull does the same job on night 1 and
-- night 10). Every number is a first guess until the class is played
-- with it.
return {
	-- how long a lit flare burns, and how far it draws monsters from
	BURN_SEC = 12,
	DRAW_RADIUS_STUDS = 30,
	-- how long after a shot the next flare is in hand; the slot's grey
	-- sheet drains down over it
	COOLDOWN_SEC = 45,
	-- the shot, flown by ProjectileManager the grenade's way: the
	-- GameAssets/Projectiles part the clients fly, its speed, the pull
	-- down that arcs it, and how far it flies before dropping dead in
	-- the air
	FIRE = {
		TEMPLATE = "Flare",
		SPEED_STUDS_PER_SEC = 80,
		GRAVITY_STUDS_PER_SEC2 = 40,
		RANGE_STUDS = 220,
	},
	-- a flare that ends in the air (on a monster, or at its range) drops
	-- to the ground under it, this far at most; further and it is lost
	GROUND_DROP_STUDS = 80,
	-- the lit flare's footprint for the monsters (an invisible part this
	-- size on the ground is what they walk to)
	BODY_SIZE = Vector3.new(2, 1.5, 2),
}
