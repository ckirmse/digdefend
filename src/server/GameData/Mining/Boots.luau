--!strict

-- Boots (GDD "Boots"): walk speed only, by level. Level 1 is Roblox's
-- default so a new player moves as they expect. The list length is the
-- level count; placeholders until tuned in play.
return {
	-- twice the step of the first pass, at twice the price (2026-09-28)
	WALK_SPEED_BY_LEVEL = { 16, 20, 24, 28, 32 },
}
