--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- A Play session in Studio has no party teleport data, so the run needs a
-- map and difficulty from somewhere; the "start run as" dev tool can switch
-- them afterwards.
return {
	MAP = Enums.Map.DEADMANS_CANYON,
	DIFFICULTY = Enums.Difficulty.NORMAL,
}
