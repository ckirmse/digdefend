--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Difficulty lives in the waves (decided 2026-09-12); in the mine it only
-- makes ore scarcer. GDD "Difficulty" (mine spec section 7):
--   effectiveHardness = clamp(hardness + (difficulty - 1) * HARDNESS_SHIFT, 1, 4)
--   effectiveVeinCount = round(baseCount / VEIN_DIVISOR)
--   uranium: round(baseCount / URANIUM_VEIN_DIVISOR)   (its own lever)
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

	-- the uranium target is the mine's solo number times this (M31, decided
	-- 2026-09-24), on top of the party multiplier; the generator checks the
	-- mine's supply against the worst case of both. Hard lengthens its run
	-- through the thinner supply alone (URANIUM_VEIN_DIVISOR); Nightmare
	-- needs the bigger target too, since a solo player who hunts humming
	-- uranium is barely slowed by thinning it, while thinning it further
	-- starves a big crew (docs/balance-plan.md, 2026-09-28)
	URANIUM_TARGET_MULTIPLIER = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.2,
		[Enums.Difficulty.NIGHTMARE] = 1.7,
	},

	-- the mine's own lever: authored vein counts are divided by this
	VEIN_DIVISOR = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.1,
		[Enums.Difficulty.NIGHTMARE] = 1.05,
	},
	-- uranium's divisor (decided 2026-09-28, docs/balance-plan.md): steeper
	-- than the ore's, because a crew finds uranium in proportion to what
	-- is left and a harder difficulty's longer run needs it found slower;
	-- the generator still checks the thinned supply against the worst
	-- case, so no difficulty can ship unwinnable
	URANIUM_VEIN_DIVISOR = {
		[Enums.Difficulty.NORMAL] = 1.0,
		[Enums.Difficulty.HARD] = 1.1,
		[Enums.Difficulty.NIGHTMARE] = 1.15,
	},
}
