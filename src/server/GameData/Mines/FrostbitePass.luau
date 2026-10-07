--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- PLACEHOLDER: a copy of Deadman's Canyon until Frostbite Pass is authored.
-- See DeadmansCanyon for what each field means.
return {
	mineId = "frostbite_default",
	seed = nil,
	origin = Vector3.new(0, 0, 0),
	facing = Enums.MineFacing.NEGATIVE_X,

	bedrockThickness = 1,
	entranceWidth = 3,
	entranceHeight = 3,
	entranceDepth = 3,
	-- no vein may centre in or spill into the rock within this many blocks
	-- of the entrance tunnel, so the faces a crew sees before its first
	-- swing are plain stone (decided 2026-09-28; was 0)
	veinEntranceClearance = 4,
	-- only gold within 16 blocks of the entrance (designer, 2026-10-07; 20
	-- put the first iron 24 blocks in, too far, and 12 had iron crowding out
	-- the gold): a new player's first Gold goes to mining upgrades before
	-- Iron tempts a tower
	goldOnlyEntranceRadius = 16,
	pocketRadiusMin = 1,
	pocketRadiusMax = 2,
	-- mirrors Deadman's Canyon (6 / 9 / 9 / 111 against 30) until this map is designed
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
			floorDrop = 5,
			hardness = 1.0,
			tierBias = 1.0,
			iron = 0,
			gold = 90,
			uranium = 0,
			pockets = 4,
			pocketRadiusMin = 1,
			pocketRadiusMax = 1,
		},
		{
			depth = 12,
			floorDrop = 5,
			hardness = 1.0,
			tierBias = 1.0,
			-- 0 (2026-10-07): the 16-block gold-only band reaches depth 19 and
			-- zone 1 ends at 20, so any iron here is crammed into one row (240
			-- placed 58%, 150 about 70%); zone 1's 240 sits in zone 2, which
			-- starts one row later, so the first iron is still about 17 blocks in
			iron = 0,
			gold = 255,
			uranium = 7,
			-- doubled with Deadman's Canyon's (2026-10-07): small rooms expose less ore
			pockets = 10,
			-- radius 1 only in zones 1 and 2 (designer, 2026-10-07): small rooms early so a new player cannot get lost; rooms scale up from zone 3
			pocketRadiusMin = 1,
			pocketRadiusMax = 1,
		},
		{
			depth = 24,
			height = 6,
			floorDrop = 6,
			hardness = 2.0,
			tierBias = 2.0,
			-- 360 (2026-10-07, from 720 the same afternoon): with 2 ore a rock the
			-- first iron zone held one iron rock in nine and days 3 to 6 refined
			-- two and a half times the third run's iron; 360 is the old second
			-- zone's density (one in nineteen) and the old first-44-block supply
			iron = 360,
			gold = 255,
			uranium = 8,
			pockets = 9,
			pocketRadiusMin = 1,
			pocketRadiusMax = 1,
		},
		{
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
			pockets = 12,
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
		{
			depth = 28,
			height = 12,
			floorDrop = 12,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 249,
			gold = 180,
			uranium = 14,
			pockets = 15,
			-- radius 2 at most in every zone (designer, 2026-10-07: rooms 12 to 20 studs across, never touching; a radius 3 room was 28 studs)
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
		{
			-- Deadman's Canyon's fifth zone (2026-09-29), copied as a placeholder
			depth = 40,
			height = 13,
			floorDrop = 13,
			hardness = 5.0,
			-- tier 5 ore (2026-10-06): zone 5 pays for its harder rock
			tierBias = 5.0,
			iron = 249,
			gold = 180,
			uranium = 362,
			pockets = 15,
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
	},
}
