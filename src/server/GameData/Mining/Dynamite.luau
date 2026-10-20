--!strict

-- Dynamite (GDD "Mining Tools", "Classes"): the Demolitionist's gadget
-- since 2026-10-20 (sold in the Mining Supplies Store before): thrown
-- ahead of the player, explodes after a fuse, clears every rock within a
-- block radius (1 = the 3x3x3 cube around the stick; blocks are 4 studs),
-- and hurts every monster within the blast. Ore inside lands on the ground.
return {
	-- the Demolitionist holds one stick at a time, and the next is in hand
	-- RESPAWN_SEC after a throw, day or night (decided 2026-10-20, over a
	-- stock of three a day: a stick always coming back is a stick thrown,
	-- never hoarded; about three a day at the day's length). The slot's
	-- grey sheet drains down over the wait
	RESPAWN_SEC = 90,
	FUSE_SEC = 3,
	BLAST_RADIUS_BLOCKS = 1,
	-- the blast on the monsters (the Tank Destroyer, 2026-10-20): this much
	-- to every one within the radius, the thrower credited; first guesses
	MONSTER_DAMAGE = 120,
	MONSTER_BLAST_RADIUS_STUDS = 10,
	-- released this far ahead of the player's root, at this speed, with an
	-- upward arc so it lands roughly ten studs out (raised 2026-09-15 in
	-- play). Inside the player's own reach since 2026-10-20: three studs
	-- out put the stick inside a rock face the player stood against, and
	-- the push-out dropped it at their feet; the stick ignores characters
	-- through a collision group, so it leaves from the chest unhindered
	THROW_OFFSET_STUDS = 1.5,
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
