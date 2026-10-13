--!strict

-- Hat cosmetics (GDD "Characters", cosmetics direction), a first pass on
-- 2026-10-12 ahead of M61: Roblox-made catalogue hats as placeholders,
-- loaded by HatManager at startup and worn in place of the player's own
-- hat when a character has one equipped. Keyed by the id a character's
-- save names, so an id is never renamed once a save can hold it. Only
-- Roblox-made items here (decided 2026-10-12: a UGC creator's item is
-- never handed out); the studio's own hats join when their art lands.
return {
	-- worn by every character until the player picks another (designer,
	-- 2026-10-12); a save with no hat is repaired to this one
	DEFAULT_HAT_ID = "HARD_HAT",
	BY_ID = {
		HARD_HAT = { ASSET_ID = 118940168191934, NAME = "Hard Hat" },
		RED_CAP = { ASSET_ID = 1028606, NAME = "Red Baseball Cap" },
		FEDORA = { ASSET_ID = 1029025, NAME = "Classic Fedora" },
		TOP_HAT = { ASSET_ID = 1073690, NAME = "White Top Hat" },
		TRAFFIC_CONE = { ASSET_ID = 1082932, NAME = "Traffic Cone" },
		BUCKET = { ASSET_ID = 1081239, NAME = "Bucket" },
		PIRATE_HAT = { ASSET_ID = 1028859, NAME = "Pirate Captain's Hat" },
		VALKYRIE = { ASSET_ID = 1365767, NAME = "Valkyrie Helm" },
	},
}
