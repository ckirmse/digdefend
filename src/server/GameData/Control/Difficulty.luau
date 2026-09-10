--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Difficulty transform for mine generation (GDD "Difficulty"):
--   effectiveHardness = clamp(hardness + (difficulty - 1) * HARDNESS_SHIFT, 1, 4)
--   effectiveVeinCount = round(baseCount / difficulty)
return {
	HARDNESS_SHIFT = 1.0,

	DIFFICULTY_VALUE = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.4,
		[Enums.Difficulty.NIGHTMARE] = 1.9,
	},
}
