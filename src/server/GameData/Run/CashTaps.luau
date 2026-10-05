--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Cash earned in a run (GDD "Earning Cash"), M32. Two of the four taps are
-- built: night milestones, paid at the dawn after the night and saved at
-- once so a lost run keeps them, and the rescue, paid to everyone aboard.
-- Chests and badges wait for their design. Every amount here is a
-- placeholder until the economy is set in rerolls per run.
return {
	-- night survived -> Cash for every player in the run at that dawn
	NIGHT_MILESTONE_CASH = {
		[1] = 5,
		[3] = 10,
		[5] = 15,
		[8] = 25,
		[10] = 40,
		[12] = 60,
		[15] = 100,
	},
	-- Cash for boarding the rescue helicopter, by the run's difficulty
	RESCUE_CASH_BY_DIFFICULTY = {
		[Enums.Difficulty.NORMAL] = 150,
		[Enums.Difficulty.HARD] = 300,
		[Enums.Difficulty.NIGHTMARE] = 500,
	},
	NIGHT_MILESTONE_REASON_FORMAT = "Survived night %d",
	RESCUE_REASON = "Rescued",
}
