--!strict

-- Character progression (GDD "Characters", M55). A character has no level
-- and no XP (decided 2026-10-12): it counts Nights Survived, one per dawn it
-- is alive at. The count opened its skill slots until M70 (2026-11-02):
-- since then a skill slot opens when the class gacha rolls a class the
-- player already owns (GameData/Gacha/Gacha), and Nights Survived is a
-- record on the card alone.
return {
	-- how many characters an account may hold, the free one included
	-- (the second slot is Diamonds, every later one Robux; M37)
	MAX_CHARACTERS = 5,
	-- a player-typed character name is cut to this many characters before
	-- the text filter sees it
	MAX_NAME_LENGTH = 20,
	DEFAULT_NAME_PREFIX = "Character ",
}
