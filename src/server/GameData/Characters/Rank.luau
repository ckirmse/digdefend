--!strict

-- Character Rank (GDD "Characters"), the one number that says how built a
-- character is. Every gear row and every filled skill slot scores by its
-- rarity rung; Rank is the total less the new character's baseline, so a
-- fresh character is Rank 1 and a perfect one is the top of the ladder.
-- The points curve upward (designer, 2026-10-12) so the top rungs are the
-- chase: a Legendary row is worth eleven Common ones, and two Rares do
-- not equal an Epic. Rank never reads what a skill does and never
-- reads Nights Survived (GDD: nobody equips a worse build to raise the
-- number, and grinding never out-ranks the gear). Placeholder values
-- until M58 tunes them against the Contract ladder.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	POINTS_BY_RARITY = {
		[Enums.Rarity.COMMON] = 1,
		[Enums.Rarity.UNCOMMON] = 2,
		[Enums.Rarity.RARE] = 4,
		[Enums.Rarity.EPIC] = 7,
		[Enums.Rarity.LEGENDARY] = 11,
	},
	-- subtracted from the total so four Common gear rows and no skills is
	-- Rank 1; seven Legendary rows is Rank 74
	BASELINE_POINTS = 3,
	-- the Rank bands, named with the rarity words so a Rank reads at a
	-- glance in the Queue Menu, over the head, and on a Contract's
	-- recommended Rank: a band starts at MIN_RANK and runs to the next
	BANDS = {
		{ MIN_RANK = 1, RARITY = Enums.Rarity.COMMON },
		{ MIN_RANK = 8, RARITY = Enums.Rarity.UNCOMMON },
		{ MIN_RANK = 18, RARITY = Enums.Rarity.RARE },
		{ MIN_RANK = 34, RARITY = Enums.Rarity.EPIC },
		{ MIN_RANK = 55, RARITY = Enums.Rarity.LEGENDARY },
	},
}
