--!strict

-- Global mine generation tuning (GDD "Randomized Mine Creation").
return {
	-- blocks a player can mine upward from a standing start; the report uses
	-- it to flag zones that are mostly decoration
	PICKAXE_REACH_BLOCKS = 3,
	-- an entrance taller than reach is only sensible with a climbing
	-- mechanic; the generator warns while this is false
	IS_CLIMBING_ENABLED = false,
}
