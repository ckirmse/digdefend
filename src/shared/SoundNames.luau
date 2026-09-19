--!strict

-- Every 2D sound the client can play, by the name of its AudioPlayer under
-- SoundService.Sfx (or SoundService.Music). The designer authors the players
-- and their asset ids in Studio; ClientSoundManager warns at startup for any
-- name listed here with no player. Never use raw strings at call sites.
export type WeaponSfx = {
	FIRE: string,
	RELOAD: string,
	EMPTY: string,
	HIT: string,
}

export type PostWeaponSfx = {
	FIRE: string,
	HIT: string,
	-- projectile kinds only: the 3D loop on the rocket in flight and the burst
	FLIGHT: string?,
	EXPLODE: string?,
}

local sfx = {
	COINS_ADDED = "CoinsAdded",
	SALE_SUCCESS = "SaleSuccess",
	ROCK_HIT = "RockHit",
	RESOURCE_HIT = "ResourceHit",
	ROCK_BREAK = "RockBreak",
	ORE_PICKUP = "OrePickup",
	REFINERY_GRIND = "RefineryGrind",
	REFINERY_PAYOUT = "RefineryPayout",
	-- M22: the crew's Camp Level just rose (2D, everyone)
	CAMP_LEVEL_UP = "CampLevelUp",
	-- M21: store and consumables
	STORE_PURCHASE = "StorePurchase",
	DYNAMITE_FUSE = "DynamiteFuse",
	DYNAMITE_EXPLODE = "DynamiteExplode",
	TORCH_PLACE = "TorchPlace",
	-- every Hammer swing that lands a repair (M23)
	HAMMER_HIT = "HammerHit",
	-- M24: every weapon has its own four sounds, never shared ones
	-- (decided 2026-09-17). Fire is 3D from the muzzle; reload, the dry
	-- click, and the hit confirm are the shooter's own
	RIFLE_FIRE = "RifleFire",
	RIFLE_RELOAD = "RifleReload",
	RIFLE_EMPTY = "RifleEmpty",
	RIFLE_HIT = "RifleHit",
	JET_PACK_BURN = "JetPackBurn",
	-- M25: post weapons have no magazine, so two sounds each: fire (3D from
	-- the muzzle, one clip per shot) and the gunner's hit confirm. Named
	-- Post_<Weapon>_<Action> (decided 2026-09-18)
	MACHINE_GUN_FIRE = "Post_MachineGun_Fire",
	MACHINE_GUN_HIT = "Post_MachineGun_Hit",
	ROCKET_LAUNCHER_FIRE = "Post_RocketLauncher_Fire",
	ROCKET_LAUNCHER_HIT = "Post_RocketLauncher_Hit",
	ROCKET_LAUNCHER_FLIGHT = "Post_RocketLauncher_Flight",
	ROCKET_LAUNCHER_EXPLODE = "Post_RocketLauncher_Explode",
	-- the machinery whirring while the gunner turns or tilts their post
	-- weapon: a 2D loop for the gunner only, playing only while the aim
	-- moves, so the slow view reads as the machine moving (decided 2026-09-18)
	POST_TURN = "Post_Turn",
	-- 3D loop on every helicopter while its rotor turns (ClientHelicopterManager)
	HELICOPTER = "Helicopter",
	-- 2D: something just stopped working for you (backpack full, tank dry)
	FAIL = "Fail",
}

-- each weapon's sound set, by its Enums.WeaponKind key. A new weapon adds its
-- four names to Sfx above and a row here; WeaponRules.spec fails for a
-- weapon kind without one
local weaponSfxByKindName: { [string]: WeaponSfx } = {
	RIFLE = {
		FIRE = sfx.RIFLE_FIRE,
		RELOAD = sfx.RIFLE_RELOAD,
		EMPTY = sfx.RIFLE_EMPTY,
		HIT = sfx.RIFLE_HIT,
	},
}

-- each post weapon's sound set, by its Enums.PostWeaponKind key;
-- PostRules.spec fails for a kind without one
local postWeaponSfxByKindName: { [string]: PostWeaponSfx } = {
	MACHINE_GUN = {
		FIRE = sfx.MACHINE_GUN_FIRE,
		HIT = sfx.MACHINE_GUN_HIT,
	},
	ROCKET_LAUNCHER = {
		FIRE = sfx.ROCKET_LAUNCHER_FIRE,
		HIT = sfx.ROCKET_LAUNCHER_HIT,
		FLIGHT = sfx.ROCKET_LAUNCHER_FLIGHT,
		EXPLODE = sfx.ROCKET_LAUNCHER_EXPLODE,
	},
}

local module = {
	Sfx = sfx,
	Music = {},
	WeaponSfxByKindName = weaponSfxByKindName,
	PostWeaponSfxByKindName = postWeaponSfxByKindName,
}

return module
