--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The Refinery (GDD "Refining Ore"): refined units per ore, and how long the
-- machine grinds before paying out. One to one for now (decided 2026-09-14).
return {
	RATE_BY_RAW = {
		[Enums.RawResource.IRON_ORE] = 1,
		[Enums.RawResource.GOLD_ORE] = 1,
		[Enums.RawResource.CRYSTAL] = 1,
		[Enums.RawResource.URANIUM_ORE] = 1,
	},
	-- the prompt is disabled while the machine grinds; the client plays the
	-- suck-in for this long before the payout flies out
	REFINE_DURATION_SEC = 2,
	-- the proximity prompt's texts (GDD "Refining Ore")
	PROMPT_ACTION_TEXT = "Refine Raw Resources",
	PROMPT_OBJECT_TEXT = "Refinery",
	PROMPT_MAX_DISTANCE_STUDS = 10,
}
