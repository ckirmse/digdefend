--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Diamonds earned in a run (GDD "Earning Diamonds"), M32. Two of the four taps are
-- built: night milestones, paid at the dawn after the night and saved at
-- once so a lost run keeps them, and the rescue, paid to everyone aboard.
-- Chests and badges wait for their design. Every amount here is a
-- placeholder until the economy is set in rerolls per run.
return {
	-- night survived -> Diamonds for every player in the run at that dawn
	NIGHT_MILESTONE_DIAMONDS = {
		[1] = 5,
		[3] = 10,
		[5] = 15,
		[8] = 25,
		[10] = 40,
		[12] = 60,
		[15] = 100,
	},
	-- Diamonds for boarding the rescue helicopter, by the run's difficulty
	RESCUE_DIAMONDS_BY_DIFFICULTY = {
		[Enums.Difficulty.NORMAL] = 150,
		[Enums.Difficulty.HARD] = 300,
		[Enums.Difficulty.NIGHTMARE] = 500,
	},
	-- the day whose dawn pays the milestone (designer's wording, 2026-10-06)
	NIGHT_MILESTONE_REASON_FORMAT = "Day %d Milestone Reached",
	RESCUE_REASON = "Rescued",
}
