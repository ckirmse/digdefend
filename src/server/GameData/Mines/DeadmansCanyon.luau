--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The GDD worked example (mine spec section 13). One open mine in a bedrock
-- shell: zones are consecutive depth bands that inherit every unspecified
-- value from the previous zone (zone 1 from the defaults), so the rock gets
-- harder and the ore better the deeper a crew digs. Each zone also drops
-- below the entrance floor line (floorDrop), more the further in, so the
-- mine goes down as well as up (decided 2026-09-15). Pockets are pre-carved
-- caverns to discover. Uranium is spread over every zone so the counter
-- moves from the first swing; the depth HP curve, not a gate, is what keeps
-- the deep uranium from being rushed (decided 2026-09-15).
return {
	mineId = "canyon_default",
	seed = nil,
	origin = Vector3.new(-359.259, -6, -20.911),
	facing = Enums.MineFacing.NEGATIVE_X,

	bedrockThickness = 1,
	-- the mouth: a short tunnel so the crew can walk in and pick a direction
	entranceWidth = 3,
	entranceHeight = 3,
	entranceDepth = 3,
	-- no vein may centre in or spill into the rock within this many blocks
	-- of the entrance tunnel, so the faces a crew sees before its first
	-- swing are plain stone (decided 2026-09-28; was 0)
	veinEntranceClearance = 4,
	pocketRadiusMin = 1,
	pocketRadiusMax = 2,
	-- uranium rocks needed to call the rescue helicopter, solo. The fifth
	-- playtest (2026-09-28) found 40 by day 4 at 26 / 40 / 56: a player who
	-- hunts the hum takes nearly everything in reach, so the first three
	-- zones hold about this much between them (9 / 14 / 20) for a day-10
	-- finish; zone 4 holds a big crew's supply, plentiful enough that its
	-- rate of finding it is set by its rock, not by running out
	-- (2026-09-25's 6 / 9 / 9 / 111 put 80% of a solo target in zones a
	-- solo run never cleared)
	uraniumTarget = 40,

	defaultZoneHeight = 8,
	-- vein counts are single blocks since 2026-09-28: four times the old
	-- iron and gold counts and six times the crystal, the same ore in more,
	-- smaller finds
	defaultZoneWidth = 24,

	zones = {
		{
			-- 1: soft, generous, everything reachable; a shallow dip below the floor
			depth = 20,
			floorDrop = 2,
			hardness = 1.0,
			tierBias = 1.0,
			-- gold ahead of iron (2026-09-28, third playtest: three towers by
			-- night 1 and six Gold in four days; the designer wants ten Gold
			-- by the end of night 1 and an upgrade a day, and Iron felt
			-- abundant)
			iron = 64,
			gold = 136,
			-- six clusters (about 84 Diamonds) so Camp Level 2 (20) needs a
			-- quarter of the zone, not three quarters of it (2026-09-25; two
			-- clusters left one seed with 28 and the level a lottery)
			crystal = 36,
			-- thinner since the third playtest: it hums, so it is found fast
			uranium = 9,
			-- pockets doubled on 2026-09-28 (third playtest: more open
			-- spaces to discover)
			pockets = 4,
		},
		{
			-- 2: mixed rock, better ore
			depth = 24,
			floorDrop = 4,
			hardness = 2.0,
			tierBias = 2.0,
			iron = 64,
			gold = 136,
			crystal = 36,
			uranium = 14,
			pockets = 6,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 12,
			floorDrop = 6,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 64,
			gold = 136,
			crystal = 72,
			uranium = 20,
			pockets = 8,
		},
		{
			-- 4: cathedral, the deepest and richest rock
			depth = 28,
			height = 16,
			floorDrop = 8,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 48,
			gold = 104,
			crystal = 108,
			-- the mine must hold the worst-case target or the generator refuses
			-- it: 40 x 1.7 Nightmare x 12 six players = 816, against
			-- (9 + 14 + 20 + 950) / 1.15 thinned at Nightmare = 863. A big crew lives in this zone from about day
			-- 6 and finds a share of what is left each day, so the supply
			-- stays well above the worst case or the tail drags
			uranium = 950,
			pockets = 10,
		},
	},
}
