--!strict

-- Every 2D sound the client can play, by the name of its AudioPlayer under
-- SoundService.Sfx (or SoundService.Music). The designer authors the players
-- and their asset ids in Studio; ClientSoundManager warns at startup for any
-- name listed here with no player. Never use raw strings at call sites.
local module

module = {
	Sfx = {
		COINS_ADDED = "CoinsAdded",
		SALE_SUCCESS = "SaleSuccess",
		ROCK_HIT = "RockHit",
		RESOURCE_HIT = "ResourceHit",
		ROCK_BREAK = "RockBreak",
		ORE_PICKUP = "OrePickup",
		REFINERY_GRIND = "RefineryGrind",
		REFINERY_PAYOUT = "RefineryPayout",
	},
	Music = {},
}

return module
