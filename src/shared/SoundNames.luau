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
		ROCK_BREAK = "RockBreak",
		ORE_PICKUP = "OrePickup",
	},
	Music = {},
}

return module
