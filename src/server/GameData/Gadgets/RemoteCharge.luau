--!strict

-- The Remote Charge, the Pyro's gadget (GDD "Classes", 2026-10-20): a
-- mine the Pyro plants ahead of them by the Auto Turret's placement rules
-- (ground the monsters walk, in the lane or on the gate's doorstep) and
-- blows from anywhere with the detonator in hand, no line of sight: heavy
-- damage to every monster within the burst, and a pool of fire left
-- behind for several seconds. One charge at a time, and a short wait
-- after a detonation before the next mine is in hand (decided
-- 2026-10-20, in place of once a day; a minute at first, then ten, then fifteen seconds the
-- same day). It never breaks rock (dynamite
-- stays the Demolitionist's). Every number is a first guess until the
-- Pyro is played with it.
return {
	-- one level like a Tower (M67), bought with Iron at the Post & Gadget
	-- Upgrades table on the Auto Turret's price curve: a harder, wider
	-- burst and a longer pool
	UPGRADE_PRICE_IRON_BY_LEVEL = { 30, 60, 120, 240 },
	STATS_BY_LEVEL = {
		{ DAMAGE = 150, BURST_RADIUS_STUDS = 14, POOL_SEC = 6 },
		{ DAMAGE = 170, BURST_RADIUS_STUDS = 16, POOL_SEC = 7 },
		{ DAMAGE = 195, BURST_RADIUS_STUDS = 18, POOL_SEC = 8 },
		{ DAMAGE = 225, BURST_RADIUS_STUDS = 20, POOL_SEC = 9 },
		{ DAMAGE = 260, BURST_RADIUS_STUDS = 22, POOL_SEC = 10 },
	},
	-- how long after a detonation the next mine is in hand; the slot's
	-- grey sheet drains down over it
	COOLDOWN_SEC = 15,
	-- the fire pool: this share of the burst's radius, burning what stands
	-- in it like the TNT Launcher's
	POOL_RADIUS_SHARE = 0.7,
	POOL_BURN_DAMAGE_PER_SEC = 12,
	POOL_BURN_SEC = 3,
	POOL_TICK_SEC = 0.5,
	-- the planted mine's footprint (the server keeps an invisible part
	-- this size on the ground; the designer's disc is 4.2 studs across)
	BODY_SIZE = Vector3.new(4.3, 0.5, 4.3),
}
