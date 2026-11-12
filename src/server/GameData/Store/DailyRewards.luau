--!strict

-- Daily Rewards (GDD "Daily Rewards Menu", M39; the format of Lucky
-- Squares). REWARDS is the list of tiles the menu shows, in order: tile 1
-- is day 1, and the LAST tile repeats for every day after it (with eight
-- tiles it reads "Day 8+"). To change the number of days, add or remove
-- entries; the menu's grid holds eight comfortably (two rows of four).
--
-- A tile is one of:
--   { KIND = DIAMONDS, AMOUNT = n }
--   { KIND = KEYS, AMOUNT = n }
--   { KIND = COSMETIC, COSMETIC_ID = "<id in Cosmetics/Catalogue>", DUPLICATE_DIAMONDS = n }
-- A cosmetic the player already owns pays DUPLICATE_DIAMONDS instead.
-- Every amount here is a placeholder until the economy is tuned.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- the wait a claim starts before the next day opens
	CLAIM_INTERVAL_SEC = 86400,
	REWARDS = {
		{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 10 },
		{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 15 },
		{ KIND = Enums.DailyRewardKind.KEYS, AMOUNT = 1 },
		{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 20 },
		{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 25 },
		{ KIND = Enums.DailyRewardKind.KEYS, AMOUNT = 2 },
		{ KIND = Enums.DailyRewardKind.COSMETIC, COSMETIC_ID = "TEST_PICK_AXE", DUPLICATE_DIAMONDS = 50 },
		{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 20 },
	},
}
