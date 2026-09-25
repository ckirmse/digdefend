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
	veinEntranceClearance = 0,
	pocketRadiusMin = 1,
	pocketRadiusMax = 2,
	-- mirrors Deadman's Canyon (6 / 9 / 9 / 111 against 30) until this map is designed
	uraniumTarget = 30,

	defaultZoneHeight = 8,
	defaultZoneWidth = 24,

	zones = {
		{
			depth = 20,
			hardness = 1.0,
			tierBias = 1.0,
			iron = 34,
			gold = 12,
			crystal = 6,
			uranium = 6,
			pockets = 2,
		},
		{
			depth = 24,
			hardness = 2.0,
			tierBias = 2.0,
			iron = 30,
			gold = 18,
			crystal = 6,
			uranium = 9,
			pockets = 3,
		},
		{
			depth = 24,
			height = 12,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 22,
			gold = 22,
			crystal = 12,
			uranium = 9,
			pockets = 4,
		},
		{
			depth = 28,
			height = 16,
			hardness = 4.0,
			tierBias = 4.0,
			iron = 16,
			gold = 20,
			crystal = 18,
			uranium = 111,
			pockets = 5,
		},
	},
}
