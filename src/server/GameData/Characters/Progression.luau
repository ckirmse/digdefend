--!strict

-- Character progression (GDD "Characters"), M55. A character has no level
-- and no XP (decided 2026-10-12): it counts Nights Survived, one per dawn it
-- is alive at, and that count opens its skill slots. Placeholders until M56
-- tunes them against real runs.
return {
	-- the Nights Survived a character needs for each skill slot, by slot
	-- index; slot 1 is open from the start
	SKILL_SLOT_UNLOCK_NIGHTS = { 0, 15, 50 },
	-- how many characters an account may hold, the free one included
	-- (the second slot is Diamonds, every later one Robux; M37)
	MAX_CHARACTERS = 5,
	-- a player-typed character name is cut to this many characters before
	-- the text filter sees it
	MAX_NAME_LENGTH = 20,
	DEFAULT_NAME_PREFIX = "Character ",
}
