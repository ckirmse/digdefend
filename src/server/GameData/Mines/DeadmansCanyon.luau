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
	-- 1 since 2026-10-08: at 4 the box round the 3-deep tunnel kept every
	-- vein out of the first 7 blocks of the corridor a player digs, so the
	-- 8-block starter band read as empty; one block still keeps the mouth's
	-- faces plain
	veinEntranceClearance = 1,
	-- only gold within 16 blocks of the entrance (designer, 2026-10-07; 20
	-- put the first iron 24 blocks in, too far, and 12 had iron crowding out
	-- the gold): a new player's first Gold goes to mining upgrades before
	-- Iron tempts a tower
	goldOnlyEntranceRadius = 16,
	-- a pocket is a room with a floor 4 by 4 blocks (radius 2) since
	-- 2026-10-08 (designer: the radius 1 rooms were so small a spider woke
	-- right in the player's face and never read as a cave; 4 by 4 the same
	-- day was too big), so every zone's count is a fraction of what it was:
	-- a room is 36 cells against 6, and the counts below keep each zone
	-- about 3% air
	pocketRadiusMin = 2,
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
	-- iron and gold counts are 1.5x what they were on 2026-10-07 (2 ore a rock
	-- instead of 3, so the same ore in half again as many finds; designer)
	defaultZoneWidth = 24,

	zones = {
		{
			-- 0: the starter band (designer, 2026-10-07): the first eight blocks
			-- past the mouth, gold-only and about four times zone 1's gold
			-- density, so whichever way a new player tunnels the first pack is
			-- paid and the pick axe is bought on day 1 on any seed. Its gold
			-- came out of the old zone 1 (230 over the first 20 blocks is
			-- unchanged); iron and uranium wait beyond the gold-only band
			depth = 8,
			-- 2 since 2026-10-08 (was 5): a zone is its height plus its drop, so
			-- the band was 10 rows and half its gold sat below the floor where
			-- nobody digs on day 1; now 7 rows round the floor line
			floorDrop = 2,
			hardness = 1.0,
			tierBias = 1.0,
			iron = 0,
			-- 120 (2026-10-08): 30 more moved out of zone 1 so day 1 pays sooner
			-- 60 later that day: with the clearance at 1 and the band 7 rows the
			-- corridor is full of gold, and day 1 refined 92 against an aim of
			-- 50 (designer); about half the finds in the first 14 blocks
			gold = 60,
			uranium = 0,
			-- 1 since 2026-10-08 (was 4 radius 1 holes): one 4 by 4 room in the
			-- 8 by 7 by 24 band
			pockets = 1,
		},
		{
			-- 1: soft, generous, everything reachable; a shallow dip below the floor
			-- 12 since 2026-10-07: zone 0 took the first 8 of these 20 blocks
			depth = 12,
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
			-- 0 (2026-10-07): the 16-block gold-only band reaches depth 19 and
			-- zone 1 ends at 20, so any iron here is crammed into one row (240
			-- placed 58%, 150 about 70%); zone 1's 240 sits in zone 2, which
			-- starts one row later, so the first iron is still about 17 blocks in
			iron = 0,
			-- 200 (2026-10-07, after 383, 255, and 170 in one day: the first two
			-- bought all three first rungs by dusk, 170 felt starved); the aim is
			-- the pick on day 1 and the backpack nearly, about 45 gold refined on
			-- the designer's day 1 (the report line)
			-- 170 since 2026-10-07: 60 of the 230 moved into zone 0
			-- 225 (2026-10-08): 30 more moved into zone 0
			-- 140 later that day, with zone 0's cut, for the 50-Gold day 1
			gold = 140,
			-- thinner since the third playtest: it hums, so it is found fast
			uranium = 7,
			-- pockets doubled on 2026-09-28 (third playtest: more open
			-- spaces to discover)
			-- tripled again on 2026-10-06 (first M34 run: finding one felt good,
			-- they were rare and small), and wider the deeper the zone
			-- 24 (2026-10-07): small rooms (radius 1) expose a third of the ore the
			-- old merged rooms did, and the day 1 report fell to 2 Refinery trips;
			-- twice as many small rooms restores the discovery without the size
			-- 3 since 2026-10-08 (was 20 radius 1 holes): three 4 by 4 rooms in
			-- 2880 cells is 6% air, a little over what the 20 small ones were
			pockets = 3,
		},
		{
			-- 2: mixed rock, better ore
			depth = 24,
			height = 6,
			floorDrop = 6,
			hardness = 2.0,
			tierBias = 2.0,
			-- zone 1's 240 iron added (2026-10-07, see zone 1)
			-- 360 (2026-10-07, from 720 the same afternoon): with 2 ore a rock the
			-- first iron zone held one iron rock in nine and days 3 to 6 refined
			-- two and a half times the third run's iron; 360 is the old second
			-- zone's density (one in nineteen) and the old first-44-block supply
			iron = 360,
			gold = 255,
			uranium = 8,
			-- 5 since 2026-10-08 (was 18 radius 1 holes): 5% of 6912 cells
			pockets = 5,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 9,
			floorDrop = 9,
			hardness = 3.0,
			tierBias = 3.0,
			-- 221 (2026-10-07, from 332): half again the pre-today supply at tier 3,
			-- not 2.25x; the deeper zones keep their 2.25x for the late drought
			iron = 221,
			gold = 234,
			uranium = 9,
			-- 9 since 2026-10-08 (was 24 radius 2 spheres of 32 cells): 5% of
			-- 10368 cells
			pockets = 9,
		},
		{
			-- 4: cathedral, deep and rich; a modest uranium reserve so a solo
			-- run keeps counting through days 11 to 14 without finishing
			depth = 28,
			height = 12,
			floorDrop = 12,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 249,
			gold = 180,
			uranium = 14,
			-- radius 2 at most in every zone (designer, 2026-10-07: rooms 12 to 20 studs across, never touching; a radius 3 room was 28 studs)
			-- 13 since 2026-10-08 (was 30 spheres): 5% of 16128 cells
			pockets = 13,
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
			iron = 249,
			gold = 180,
			uranium = 362,
			-- 15 since 2026-10-08 (was 30 spheres): 3.5% of 24960 cells
			pockets = 15,
		},
	},
}
