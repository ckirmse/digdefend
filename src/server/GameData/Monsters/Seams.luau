--!strict

-- The Seam (M68, designed 2026-10-26, GDD "Monster Types": Seam): the face
-- in the rock that bursts. It never attacks; any swing breaks its block in
-- one hit whatever the pick, and the break is the danger: the block bursts
-- into smoke that does BURST_DAMAGE to every player within
-- BURST_RADIUS_STUDS and shoves them back (designer, 2026-10-26: the
-- damage is the break, not the swing, and the smoke is what seems to do
-- it), so dynamite from a distance is the safe kill and a point-blank
-- swing is the mistake. Weapons pass through it. It drifts over the
-- mine's surface cells a face at a time and spreads onto neighbouring
-- stone, never ore, so a vein under it is blocked rather than eaten. As
-- common as spiders (designer): COUNT of them asleep in buried stone
-- cells drawn from the mine's seed from zone MIN_ZONE_INDEX down, never
-- beside a pocket room, woken when a neighbouring block is cleared. Its
-- kind's row is in Monsters/Roster.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	KIND = Enums.MonsterKind.SEAM,
	-- faces per mine (designer, 2026-10-26: 20 from zone 3 for the first
	-- play, then 50 from zone 2 the same day)
	COUNT = 50,
	-- the first zone (the mine file's index) a face may lie in: zone 2
	-- in the designer's numbering, the first iron band, as the spiders
	MIN_ZONE_INDEX = 3,
	-- a different stream from the lurkers' so the two draws are independent
	SEED_OFFSET = 9191,
	-- the burst when a block of it is broken: the damage to every player
	-- within the radius (the smoke's reach; designer, 2026-10-26: half of
	-- the base 100 health, a flat number, so two mistakes kill), and their
	-- shove down the tunnel
	BURST_DAMAGE = 50,
	BURST_RADIUS_STUDS = 8,
	BURST_KNOCKBACK_STUDS = 12,
	-- a face steps to a neighbouring exposed stone block this often
	DRIFT_INTERVAL_SEC = 8,
	-- a face spreads onto a neighbouring stone block this often, to at
	-- most SPREAD_MAX_BLOCKS blocks held at once; a spread block is a face
	-- too, and breaking any of them bursts
	SPREAD_INTERVAL_SEC = 60,
	SPREAD_MAX_BLOCKS = 3,
	-- the sounds, 3D from the block: the hum an awake face repeats and the
	-- crack as it spreads (the burst's laugh and smoke are the designer's,
	-- on the model, played by the clients)
	HUM_INTERVAL_SEC = 6,
	HUM_FULL_VOLUME_STUDS = 4,
	HUM_SILENT_STUDS = 12,
	CRACK_FULL_VOLUME_STUDS = 6,
	CRACK_SILENT_STUDS = 30,
}
