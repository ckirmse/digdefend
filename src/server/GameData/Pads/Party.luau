--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Helicopter pad party tuning (GDD "Helicopter Pads – Party Creation/Teleports").
-- Every pad is identical; the host configures the run from these lists.
-- MAPS and DIFFICULTIES are ordered: the Create Party carousels show them in
-- this order. A requirement names a completion the host must hold; a
-- difficulty requirement is checked on the selected map unless it names one.
-- PartyRules.validateConfig checks this table at lobby startup.
return {
	-- seconds a host has to press Create before the pad is released
	CREATION_TIMEOUT_SEC = 30,
	-- seconds after Create before the party auto-launches
	BOARDING_TIMEOUT_SEC = 120,
	-- countdown once the party is full
	CAPACITY_TIME_SEC = 3,
	-- upper bound of the players stepper; never above helicopter seat count
	MAX_PARTY_SIZE = 6,
	DEFAULT_MAX_PLAYERS = 4,
	DEFAULT_VISIBILITY = Enums.PartyVisibility.PUBLIC,

	MAPS = {
		{
			map = Enums.Map.DEADMANS_CANYON,
			thumbnail = "rbxassetid://0",
		},
		{
			map = Enums.Map.FROSTBITE_PASS,
			thumbnail = "rbxassetid://0",
			requires = {
				map = Enums.Map.DEADMANS_CANYON,
				difficulty = Enums.Difficulty.NORMAL,
			},
		},
	},

	DIFFICULTIES = {
		{
			difficulty = Enums.Difficulty.NORMAL,
		},
		{
			difficulty = Enums.Difficulty.HARD,
			requires = {
				difficulty = Enums.Difficulty.NORMAL,
			},
		},
		{
			difficulty = Enums.Difficulty.NIGHTMARE,
			requires = {
				difficulty = Enums.Difficulty.HARD,
			},
		},
	},
}
