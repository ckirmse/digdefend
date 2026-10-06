--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The GDD worked example (mine spec section 13). One open mine in a bedrock
-- shell: zones are consecutive depth bands that inherit every unspecified
-- value from the previous zone (zone 1 from the defaults), so the rock gets
-- harder and the ore better the deeper a crew digs. Each zone is split
-- evenly about the entrance floor line (floorDrop rows below it, the same
-- height above; designer, 2026-10-06, replacing a mine that mostly rose
-- above the entrance), so the mine goes down as much as up. Pockets are pre-carved
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

	defaultZoneHeight = 5,
	-- vein counts are single blocks since 2026-09-28: four times the old
	-- iron and gold counts, the same ore in more,
	-- smaller finds
	defaultZoneWidth = 24,

	zones = {
		{
			-- 1: soft, generous, everything reachable; a shallow dip below the floor
			depth = 20,
			floorDrop = 5,
			hardness = 1.0,
			tierBias = 1.0,
			-- iron tripled (2026-09-29, seventh playtest: Iron was hard to
			-- find, three unupgraded Sentries in ten days, the Refinery fell
			-- on night 10; the sheet refitted to that run wants about this
			-- much for its nine towers by night 10). The day before, the
			-- third playtest had cut iron under gold because three towers
			-- went up by night 1; that was with seven-block veins
			-- iron and gold up 25% in zones 1 and 2 and 15% in zones 3 to 5
			-- (2026-10-05, playtest feedback: resources too scarce; was
			-- 192 / 136 in zones 1 to 3 and 144 / 104 in zones 4 and 5)
			-- zone 1 gold up another 50% the same day (170 to 255)
			iron = 240,
			gold = 255,
			-- thinner since the third playtest: it hums, so it is found fast
			uranium = 7,
			-- pockets doubled on 2026-09-28 (third playtest: more open
			-- spaces to discover)
			-- tripled again on 2026-10-06 (first M34 run: finding one felt good,
			-- they were rare and small), and wider the deeper the zone
			pockets = 12,
			pocketRadiusMin = 1,
			pocketRadiusMax = 2,
		},
		{
			-- 2: mixed rock, better ore
			depth = 24,
			height = 6,
			floorDrop = 6,
			hardness = 2.0,
			tierBias = 2.0,
			iron = 240,
			gold = 170,
			uranium = 8,
			pockets = 18,
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 9,
			floorDrop = 9,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 221,
			gold = 156,
			uranium = 9,
			pockets = 24,
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
		{
			-- 4: cathedral, deep and rich; a modest uranium reserve so a solo
			-- run keeps counting through days 11 to 14 without finishing
			depth = 28,
			height = 12,
			floorDrop = 12,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 166,
			gold = 120,
			uranium = 14,
			pockets = 30,
			pocketRadiusMin = 2,
			pocketRadiusMax = 3,
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
			height = 13,
			floorDrop = 13,
			hardness = 5.0,
			-- tier 5 ore (2026-10-06): zone 5 pays for its harder rock
			tierBias = 5.0,
			iron = 166,
			gold = 120,
			uranium = 362,
			pockets = 30,
			pocketRadiusMin = 2,
			pocketRadiusMax = 3,
		},
	},
}
