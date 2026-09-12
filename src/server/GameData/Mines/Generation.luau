--!strict

-- Global mine generation tuning (GDD "Randomized Mine Creation").
return {
	-- blocks a player can mine upward from a standing start; the report uses
	-- it to flag chambers that are mostly decoration
	PICKAXE_REACH_BLOCKS = 3,
	-- a corridor taller than reach but below "full" is only sensible with a
	-- climbing mechanic; the generator warns while this is false
	IS_CLIMBING_ENABLED = false,
	-- the uranium target scales with party size (GDD "Party scaling"); every
	-- mine must author enough uranium for the largest party. Placeholder
	-- until the PartyScaling table lands at M18, when it must read from there.
	MAX_PARTY_URANIUM_TARGET_MULTIPLIER = 1.25,
}
