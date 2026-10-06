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
	pocketRadiusMin = 1,
	pocketRadiusMax = 2,
	-- mirrors Deadman's Canyon (6 / 9 / 9 / 111 against 30) until this map is designed
	uraniumTarget = 40,

	defaultZoneHeight = 5,
	-- vein counts are single blocks since 2026-09-28: four times the old
	-- iron and gold counts, the same ore in more,
	-- smaller finds
	defaultZoneWidth = 24,

	zones = {
		{
			depth = 20,
			floorDrop = 5,
			hardness = 1.0,
			tierBias = 1.0,
			iron = 240,
			gold = 255,
			uranium = 7,
			pockets = 6,
			pocketRadiusMin = 1,
			pocketRadiusMax = 2,
		},
		{
			depth = 24,
			height = 6,
			floorDrop = 6,
			hardness = 2.0,
			tierBias = 2.0,
			iron = 240,
			gold = 170,
			uranium = 8,
			pockets = 9,
			pocketRadiusMin = 2,
			pocketRadiusMax = 2,
		},
		{
			depth = 24,
			height = 9,
			floorDrop = 9,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 221,
			gold = 156,
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
			iron = 166,
			gold = 120,
			uranium = 14,
			pockets = 15,
			pocketRadiusMin = 2,
			pocketRadiusMax = 3,
		},
		{
			-- Deadman's Canyon's fifth zone (2026-09-29), copied as a placeholder
			depth = 40,
			height = 13,
			floorDrop = 13,
			hardness = 5.0,
			-- tier 5 ore (2026-10-06): zone 5 pays for its harder rock
			tierBias = 5.0,
			iron = 166,
			gold = 120,
			uranium = 362,
			pockets = 15,
			pocketRadiusMin = 2,
			pocketRadiusMax = 3,
		},
	},
}
