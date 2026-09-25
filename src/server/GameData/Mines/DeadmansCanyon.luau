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
	veinEntranceClearance = 0,
	pocketRadiusMin = 1,
	pocketRadiusMax = 2,
	-- uranium rocks needed to call the rescue helicopter, solo. Authored
	-- uranium per zone is 20%, 30%, 30% of this and the rest in zone 4, so a
	-- crew clearing the first three zones is 80% of the way (decided
	-- 2026-09-25 after a 50 minute solo playtest found none at 2/4/8/20
	-- against 20; raised from 25 the same day)
	uraniumTarget = 30,

	defaultZoneHeight = 8,
	defaultZoneWidth = 24,

	zones = {
		{
			-- 1: soft, generous, everything reachable; a shallow dip below the floor
			depth = 20,
			floorDrop = 2,
			hardness = 1.0,
			tierBias = 1.0,
			-- iron and gold near even (2026-09-15: gold has the store to feed,
			-- iron's sinks arrive with walls and traps)
			iron = 22,
			gold = 20,
			-- six clusters (about 84 Diamonds) so Camp Level 2 (20) needs a
			-- quarter of the zone, not three quarters of it (2026-09-25; two
			-- clusters left one seed with 28 and the level a lottery)
			crystal = 6,
			uranium = 6,
			pockets = 2,
		},
		{
			-- 2: mixed rock, better ore
			depth = 24,
			floorDrop = 4,
			hardness = 2.0,
			tierBias = 2.0,
			iron = 22,
			gold = 22,
			crystal = 6,
			uranium = 9,
			pockets = 3,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 12,
			floorDrop = 6,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 22,
			gold = 22,
			crystal = 12,
			uranium = 9,
			pockets = 4,
		},
		{
			-- 4: cathedral, the deepest and richest rock
			depth = 28,
			height = 16,
			floorDrop = 8,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 16,
			gold = 20,
			crystal = 18,
			-- the mine must hold the worst-case target or the generator refuses
			-- it: 30 x 1.3 Nightmare x 3.5 six players = 136.5, rounded to the
			-- nearest 5 = 135, so 6 + 9 + 9 + 111
			uranium = 111,
			pockets = 5,
		},
	},
}
