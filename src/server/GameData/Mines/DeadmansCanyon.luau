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
	-- hunts the hum takes nearly everything in reach. For the 15-night run
	-- (2026-09-29) the counter should climb about three a day and never
	-- jump (the designer's ask: constant progress toward the goal, not a
	-- bunch at once), so each zone holds a little more than the last and
	-- the sheet has a solo player at 40 on day 14; zone 5 holds a big
	-- crew's supply, plentiful enough that its rate of finding it is set
	-- by its rock, not by running out
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
			-- iron tripled (2026-09-29, seventh playtest: Iron was hard to
			-- find, three unupgraded Sentries in ten days, the Refinery fell
			-- on night 10; the sheet refitted to that run wants about this
			-- much for its nine towers by night 10). The day before, the
			-- third playtest had cut iron under gold because three towers
			-- went up by night 1; that was with seven-block veins
			iron = 192,
			gold = 136,
			-- crystal removed from the spawns (2026-09-29) while the camp-level
			-- gates are open for testing; was 36 / 36 / 72 / 108 / 108
			crystal = 0,
			-- thinner since the third playtest: it hums, so it is found fast
			uranium = 7,
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
			iron = 192,
			gold = 136,
			crystal = 0,
			uranium = 8,
			pockets = 6,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 12,
			floorDrop = 6,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 192,
			gold = 136,
			crystal = 0,
			uranium = 9,
			pockets = 8,
		},
		{
			-- 4: cathedral, deep and rich; a modest uranium reserve so a solo
			-- run keeps counting through days 11 to 14 without finishing
			depth = 28,
			height = 16,
			floorDrop = 8,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 144,
			gold = 104,
			crystal = 0,
			uranium = 14,
			pockets = 10,
		},
		{
			-- 5: the abyss (added 2026-09-29 for the 15-night run): the
			-- hardest stone, the best ore, and the big crew's uranium supply.
			-- The mine must hold the worst-case target or the generator
			-- refuses it: 40 x 1.7 Nightmare x 5 six players = 340, against
			-- (7 + 8 + 9 + 14 + 362) / 1.15 thinned at Nightmare = 348.
			-- Uranium may sit at any height since 2026-09-29 (it was held to
			-- the floor rows before, and 1,500 in 28 rows of that band hung
			-- the generator). A big crew lives here from about day 10 and
			-- finds a share of what is left each day
			depth = 40,
			height = 16,
			floorDrop = 10,
			hardness = 5.0,
			tierBias = 4.0,
			iron = 144,
			gold = 104,
			crystal = 0,
			uranium = 362,
			pockets = 10,
		},
	},
}
