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
		-- M21: store and consumables
		STORE_PURCHASE = "StorePurchase",
		DYNAMITE_FUSE = "DynamiteFuse",
		DYNAMITE_EXPLODE = "DynamiteExplode",
		TORCH_PLACE = "TorchPlace",
		JET_PACK_BURN = "JetPackBurn",
		-- 3D loop on every helicopter from spawn until it is destroyed
		HELICOPTER = "Helicopter",
		-- 2D: something just stopped working for you (backpack full, tank dry)
		FAIL = "Fail",
	},
	Music = {},
}

return module
