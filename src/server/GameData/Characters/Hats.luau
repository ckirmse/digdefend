--!strict

-- Hat cosmetics (GDD "Characters", cosmetics direction), a first pass on
-- 2026-10-12 ahead of M61: hats loaded by HatManager at startup and worn
-- in place of the player's own hat when a character has one equipped.
-- Keyed by the id a character's save names, so an id is never renamed
-- once a save can hold it. Only the designer's Hard Hat since 2026-10-13
-- (the seven Roblox-made placeholder hats were cut); the studio's own
-- hats join when their art lands, and a UGC creator's item is never
-- handed out (decided 2026-10-12).
return {
	-- worn by every character until the player picks another (designer,
	-- 2026-10-12); a save with no hat is repaired to this one
	DEFAULT_HAT_ID = "HARD_HAT",
	BY_ID = {
		HARD_HAT = { ASSET_ID = 118940168191934, NAME = "Hard Hat" },
	},
}
