--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Difficulty lives in the waves (decided 2026-09-12); in the mine it only
-- makes ore scarcer. GDD "Difficulty" (mine spec section 7):
--   effectiveHardness = clamp(hardness + (difficulty - 1) * HARDNESS_SHIFT, 1, 4)
--   effectiveVeinCount = round(baseCount / VEIN_DIVISOR)   (uranium exempt)
return {
	-- 0 keeps rock identical on every difficulty; the knob exists for a map
	-- that deliberately wants grittier rock at Nightmare
	HARDNESS_SHIFT = 0.0,

	-- the general scalar other systems (waves) read
	DIFFICULTY_VALUE = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.4,
		[Enums.Difficulty.NIGHTMARE] = 1.9,
	},

	-- the mine's own lever: authored vein counts are divided by this
	VEIN_DIVISOR = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.2,
		[Enums.Difficulty.NIGHTMARE] = 1.4,
	},
}
