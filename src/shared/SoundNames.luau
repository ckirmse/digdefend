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
	-- a weapon with a secondary launcher (the Assault Rifle's grenade):
	-- its launch and its burst
	SECONDARY_FIRE: string?,
	SECONDARY_EXPLODE: string?,
}

export type PostWeaponSfx = {
	FIRE: string,
	HIT: string,
	-- projectile kinds only: the 3D loop on the rocket in flight and the burst
	FLIGHT: string?,
	EXPLODE: string?,
	-- the Minigun's spin-up, the Railgun's charge, the AA Launcher's lock
	-- tone: the gunner's own, 2D, played where the mechanic starts
	WINDUP: string?,
	-- the Fault Line Drill's rock-breaking loop, ridden along the crack's
	-- front by ClientFaultLineManager (2026-10-22)
	CRACK: string?,
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
	-- M23: the walls and gate reached a new tier (2D, everyone)
	FORTIFICATION_TIER_UP = "FortificationTierUp",
	-- M21: store and consumables
	STORE_PURCHASE = "StorePurchase",
	DYNAMITE_FUSE = "DynamiteFuse",
	DYNAMITE_EXPLODE = "DynamiteExplode",
	TORCH_PLACE = "TorchPlace",
	-- every Hammer swing that lands a repair (M23)
	HAMMER_HIT = "HammerHit",
	-- the pocket lurker (M62): 3D, from where the spider is
	CAVE_SPIDER_WALK = "CaveSpiderWalk",
	CAVE_SPIDER_ALERT = "CaveSpiderAlert",
	CAVE_SPIDER_ATTACK = "CaveSpiderAttack",
	CAVE_SPIDER_DIE = "CaveSpiderDie",
	-- the Blockface (M68): 3D from its block; the hum while a player stands
	-- near an awake face (the burst's laugh is a Sound on the designer's
	-- model)
	BLOCKFACE_HUM = "BlockfaceHum",
	-- the Chase (M68): its release cry, 3D from the body as it wakes (the
	-- roster's ALERT; the designer's asset, 2026-10-26)
	CHASE_RELEASE = "ChaseRelease",
	-- M24: every weapon has its own four sounds, never shared ones
	-- (decided 2026-09-17). Fire is 3D from the muzzle; reload, the dry
	-- click, and the hit confirm are the shooter's own
	RIFLE_FIRE = "RifleFire",
	RIFLE_RELOAD = "RifleReload",
	RIFLE_EMPTY = "RifleEmpty",
	RIFLE_HIT = "RifleHit",
	-- the class weapons (2026-10-16), the same four each; the Assault
	-- Rifle's grenade adds a launch and a burst
	PISTOL_EMPTY = "PistolEmpty",
	PISTOL_HIT = "PistolHit",
	SNIPER_FIRE = "SniperFire",
	SNIPER_RELOAD = "SniperReload",
	SNIPER_EMPTY = "SniperEmpty",
	SNIPER_HIT = "SniperHit",
	FLAMETHROWER_FIRE = "FlamethrowerFire",
	FLAMETHROWER_RELOAD = "FlamethrowerReload",
	FLAMETHROWER_EMPTY = "FlamethrowerEmpty",
	FLAMETHROWER_HIT = "FlamethrowerHit",
	ASSAULT_RIFLE_FIRE = "AssaultRifleFire",
	ASSAULT_RIFLE_EMPTY = "AssaultRifleEmpty",
	ASSAULT_RIFLE_HIT = "AssaultRifleHit",
	ASSAULT_RIFLE_GRENADE_FIRE = "AssaultRifleGrenadeFire",
	JET_PACK_BURN = "JetPackBurn",
	-- the Binoculars' tag landing (2026-10-19), the tagger's own
	BINOCULARS_TAG = "BinocularsTag",
	-- the Stim Shot going in (2026-10-19), the user's own
	STIM_SHOT_USE = "StimShotUse",
	-- the player's own hit (2026-10-26): 2D, theirs alone, on every drop
	-- in their health
	PLAYER_HURT = "PlayerHurt",
	-- the Remote Charge's detonator beeping as its button goes down
	-- (2026-10-20), the user's own
	REMOTE_CHARGE_DETONATE = "RemoteChargeDetonate",
	-- M25: post weapons have no magazine, so two sounds each: fire (3D from
	-- the muzzle, one clip per shot) and the gunner's hit confirm. Named
	-- Post_<Weapon>_<Action> (decided 2026-09-18)
	MACHINE_GUN_FIRE = "Post_MachineGun_Fire",
	MACHINE_GUN_HIT = "Post_MachineGun_Hit",
	ROCKET_LAUNCHER_FIRE = "Post_RocketLauncher_Fire",
	ROCKET_LAUNCHER_HIT = "Post_RocketLauncher_Hit",
	ROCKET_LAUNCHER_FLIGHT = "Post_RocketLauncher_Flight",
	ROCKET_LAUNCHER_EXPLODE = "Post_RocketLauncher_Explode",
	-- the class posts (2026-10-16): fire and hit each; a projectile kind
	-- adds its flight loop and burst, the Minigun its spin-up, the Railgun
	-- its charge, the AA Launcher its lock tone
	MINI_GUN_FIRE = "Post_Minigun_Fire",
	MINI_GUN_HIT = "Post_Minigun_Hit",
	MINI_GUN_SPIN = "Post_Minigun_Spin",
	RAIL_GUN_FIRE = "Post_Railgun_Fire",
	RAIL_GUN_HIT = "Post_Railgun_Hit",
	RAIL_GUN_CHARGE = "Post_Railgun_Charge",
	MORTAR_HIT = "Post_Mortar_Hit",
	MORTAR_FLIGHT = "Post_Mortar_Flight",
	-- the Missile Launcher's lock tone; it fires, flies, hits, and bursts
	-- with the Rocket Launcher's sounds (decided 2026-10-20)
	AA_LAUNCHER_LOCK = "Post_AALauncher_Lock",
	MACHINE_GUN_AUTOMATED_FIRE = "Post_AutoMachineGun_Fire",
	MACHINE_GUN_AUTOMATED_HIT = "Post_AutoMachineGun_Hit",
	MINE_LAYER_FIRE = "Post_MineLayer_Fire",
	MINE_LAYER_HIT = "Post_MineLayer_Hit",
	MINE_LAYER_FLIGHT = "Post_MineLayer_Flight",
	MINE_LAYER_EXPLODE = "Post_MineLayer_Explode",
	TESLA_ARC_FIRE = "Post_TeslaArc_Fire",
	TESLA_ARC_HIT = "Post_TeslaArc_Hit",
	DRILL_GUN_HIT = "Post_DrillGun_Hit",
	-- the bit whirring in flight (designer, 2026-10-22)
	DRILL_GUN_FLIGHT = "Post_DrillGun_Flight",
	-- rock breaking, looped at the crack's front as it races out of the
	-- ground where the drill landed, silent once the crack stops growing
	DRILL_GUN_CRACK = "Post_DrillGun_Crack",
	SAW_GUN_FIRE = "Post_SawGun_Fire",
	SAW_GUN_HIT = "Post_SawGun_Hit",
	SAW_GUN_FLIGHT = "Post_SawGun_Flight",
	SAW_GUN_EXPLODE = "Post_SawGun_Explode",
	MAGNET_GUN_FIRE = "Post_MagnetGun_Fire",
	MAGNET_GUN_HIT = "Post_MagnetGun_Hit",
	-- the machinery whirring while the gunner turns or tilts their post
	-- weapon: a 2D loop for the gunner only, playing only while the aim
	-- moves, so the slow view reads as the machine moving (decided 2026-09-18)
	POST_TURN = "Post_Turn",
	-- M26: a Tower or Trap went down on the grid, and one was sold back
	PLACEMENT_BUILD = "PlacementBuild",
	PLACEMENT_SELL = "PlacementSell",
	-- 3D loop on every helicopter while its rotor turns (ClientHelicopterManager)
	HELICOPTER = "Helicopter",
	-- the rescue escape (M75): 3D at the helicopter as it settles on the
	-- pad and as it lifts off (the lift-off in the lobby too); 2D for
	-- everyone as a crewmate boards, the RESCUE HELICOPTER INCOMING sting
	-- once the radio's dispatch message has played (the dispatch itself
	-- is the designer's Rescue Sound on the radio model), and the sting as
	-- the Results Menu opens on a won run
	HELICOPTER_TOUCHDOWN = "Helicopter_Touchdown",
	HELICOPTER_LIFTOFF = "Helicopter_Liftoff",
	RESCUE_BOARD = "Rescue_Board",
	RESCUE_INCOMING = "Rescue_Incoming",
	RESCUE_WIN = "Rescue_Win",
	-- the landed helicopter's countdown flashes red; this rings with its
	-- first flash so nobody misses it (designer, 2026-10-27)
	RESCUE_LANDED = "Rescue_Landed",
	-- the pulsing hum of exposed uranium rock and dropped uranium ore, one
	-- shared loop with an emitter per block or pickup, heard within 15
	-- studs (designer, 2026-10-07; ClientMineManager, ClientOrePickupManager)
	URANIUM_HUM = "UraniumHum",
	-- 2D: something just stopped working for you (backpack full, tank dry)
	FAIL = "Fail",
	-- the Flare Gun's shot (2026-10-21), the gunner's own, 3D at the muzzle
	FLARE_FIRE = "Gadget_Flare_Fire",
	-- the Ore Scanner's sweep (2026-10-22), 3D from the scanner's spot for
	-- everyone in range as the sphere grows
	ORE_SCAN = "Gadget_Ore_Scan",
	-- 2D: the Game Over screen (this player died, or the Refinery fell; M32)
	GAME_OVER = "GameOver",
	-- M28: a new day (the rooster) and a new night (the bell), with the
	-- DayNightNumber card
	ROOSTER = "Rooster",
	-- the day card's own sting, 2D, as the card appears on every day
	-- (designer, 2026-10-21); the rooster joins it from day 2
	DAY_CARD = "DayCard",
	NIGHT_BELL = "NightBell",
	-- alerts (2026-09-25): a wall fell (2D, everyone, with the red alert),
	-- the 3D collapse from where the wall stood (server-side), and the
	-- siren every client hears once per red flash of the Refinery HP bar
	-- while the Refinery is under attack (M33; a loop before that)
	WALL_DESTROYED = "WallDestroyed",
	WALL_COLLAPSE = "WallCollapse",
	REFINERY_UNDER_ATTACK = "RefineryUnderAttack",
	-- 2D loops only the counter's owner hears (ClientGeigerCounterManager,
	-- 2026-09-30): exactly one plays at a time, the one for how many of the
	-- dial's rings are lit, and none with no ring lit
	GEIGER_1 = "Geiger1",
	GEIGER_2 = "Geiger2",
	GEIGER_3 = "Geiger3",
	-- menus (designer, 2026-10-13): every menu button clicks
	-- (ClientButtonSoundManager); a REROLL button plays its own sound
	-- instead; the roll screen ticks on every image the NEW box flips to
	-- and chimes when the result lands (ClientCharacterSheetManager)
	BUTTON_CLICK = "ButtonClick",
	REROLL = "Reroll",
	REROLL_SPIN = "RerollSpin",
	REROLL_REVEAL = "RerollReveal",
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
	-- the Pistol fires and reloads with the Rifle's sounds (decided 2026-10-19)
	PISTOL = {
		FIRE = sfx.RIFLE_FIRE,
		RELOAD = sfx.RIFLE_RELOAD,
		EMPTY = sfx.PISTOL_EMPTY,
		HIT = sfx.PISTOL_HIT,
	},
	SNIPER = {
		FIRE = sfx.SNIPER_FIRE,
		RELOAD = sfx.SNIPER_RELOAD,
		EMPTY = sfx.SNIPER_EMPTY,
		HIT = sfx.SNIPER_HIT,
	},
	FLAMETHROWER = {
		FIRE = sfx.FLAMETHROWER_FIRE,
		RELOAD = sfx.FLAMETHROWER_RELOAD,
		EMPTY = sfx.FLAMETHROWER_EMPTY,
		HIT = sfx.FLAMETHROWER_HIT,
	},
	-- the Assault Rifle reloads with the Rifle's sound and its grenade
	-- bursts with the Rocket Launcher's (decided 2026-10-19)
	ASSAULT_RIFLE = {
		FIRE = sfx.ASSAULT_RIFLE_FIRE,
		RELOAD = sfx.RIFLE_RELOAD,
		EMPTY = sfx.ASSAULT_RIFLE_EMPTY,
		HIT = sfx.ASSAULT_RIFLE_HIT,
		SECONDARY_FIRE = sfx.ASSAULT_RIFLE_GRENADE_FIRE,
		SECONDARY_EXPLODE = sfx.ROCKET_LAUNCHER_EXPLODE,
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
	MINI_GUN = {
		FIRE = sfx.MINI_GUN_FIRE,
		HIT = sfx.MINI_GUN_HIT,
		WINDUP = sfx.MINI_GUN_SPIN,
	},
	RAIL_GUN = {
		FIRE = sfx.RAIL_GUN_FIRE,
		HIT = sfx.RAIL_GUN_HIT,
		WINDUP = sfx.RAIL_GUN_CHARGE,
	},
	-- the shell leaves and bursts with the Assault Rifle's grenade
	-- (decided 2026-10-20)
	MORTAR = {
		FIRE = sfx.ASSAULT_RIFLE_GRENADE_FIRE,
		HIT = sfx.MORTAR_HIT,
		FLIGHT = sfx.MORTAR_FLIGHT,
		EXPLODE = sfx.ROCKET_LAUNCHER_EXPLODE,
	},
	-- the Missile Launcher: the Rocket Launcher's sounds and its own lock tone
	AA_LAUNCHER = {
		FIRE = sfx.ROCKET_LAUNCHER_FIRE,
		HIT = sfx.ROCKET_LAUNCHER_HIT,
		FLIGHT = sfx.ROCKET_LAUNCHER_FLIGHT,
		EXPLODE = sfx.ROCKET_LAUNCHER_EXPLODE,
		WINDUP = sfx.AA_LAUNCHER_LOCK,
	},
	MACHINE_GUN_AUTOMATED = {
		FIRE = sfx.MACHINE_GUN_AUTOMATED_FIRE,
		HIT = sfx.MACHINE_GUN_AUTOMATED_HIT,
	},
	MINE_LAYER = {
		FIRE = sfx.MINE_LAYER_FIRE,
		HIT = sfx.MINE_LAYER_HIT,
		FLIGHT = sfx.MINE_LAYER_FLIGHT,
		EXPLODE = sfx.MINE_LAYER_EXPLODE,
	},
	TESLA_ARC = {
		FIRE = sfx.TESLA_ARC_FIRE,
		HIT = sfx.TESLA_ARC_HIT,
	},
	-- the drill leaves with the grenade launcher's thump (designer,
	-- 2026-10-22); no EXPLODE, the sand burst where it lands is silent
	-- under the crack's rock-breaking loop
	DRILL_GUN = {
		FIRE = sfx.ASSAULT_RIFLE_GRENADE_FIRE,
		HIT = sfx.DRILL_GUN_HIT,
		FLIGHT = sfx.DRILL_GUN_FLIGHT,
		CRACK = sfx.DRILL_GUN_CRACK,
	},
	SAW_GUN = {
		FIRE = sfx.SAW_GUN_FIRE,
		HIT = sfx.SAW_GUN_HIT,
		FLIGHT = sfx.SAW_GUN_FLIGHT,
		EXPLODE = sfx.SAW_GUN_EXPLODE,
	},
	MAGNET_GUN = {
		FIRE = sfx.MAGNET_GUN_FIRE,
		HIT = sfx.MAGNET_GUN_HIT,
	},
}

-- 2D music under SoundService.Music
local music = {
	-- plays from the top as dusk begins, the day's dusk before every night
	-- (2026-09-25), and fades out across night fall (2026-10-02)
	DUSK_SONG_1 = "DuskSong1",
	-- the final night's song: from the RESCUE HELICOPTER INCOMING flash
	-- going down, looping through the breather, out across the final
	-- night's fall like the dusk song (designer, 2026-10-27)
	FINAL_NIGHT_SONG = "FinalNightSong",
	-- the ride out: from the last crew member boarding, in from 5 s in
	-- over 5 s, looping, out as the Results Menu comes (designer,
	-- 2026-10-27)
	RESCUE_EXIT_SONG = "RescueExitSong",
	-- the outdoors, looping while the player is out of the mine
	-- (ClientAmbienceManager, 2026-10-21)
	OUTDOOR_AMBIENCE = "OutdoorAmbience",
	-- the night's loop, in over 3 s as night falls and out over 1 s at its
	-- end (ClientRunCycleManager, designer, 2026-10-21); out over 3 s for a
	-- player who dies, or a run lost or won, mid-night (2026-10-27)
	NIGHT_SONG = "NightSong",
	-- the lobby's track, looping from the moment a player is Ready there
	-- (designer, 2026-10-14)
	LOBBY = "LobbyMusic",
	-- starts as the Game Over screen fades to black and plays out over the
	-- Results Menu, looping, until the player leaves the menu (M32)
	GAME_OVER = "GameOver",
}

-- the names the lobby place plays (2026-10-09): its SoundService carries
-- only these, so the startup audit expects only these there; the gameplay
-- place is expected to author every name above
local lobbySfxNames: { string } = {
	sfx.COINS_ADDED,
	sfx.SALE_SUCCESS,
	sfx.HELICOPTER,
	sfx.HELICOPTER_LIFTOFF,
	sfx.BUTTON_CLICK,
	sfx.REROLL,
	sfx.REROLL_SPIN,
	sfx.REROLL_REVEAL,
}
local lobbyMusicNames: { string } = {
	music.LOBBY,
}

local module = {
	Sfx = sfx,
	Music = music,
	LobbySfxNames = lobbySfxNames,
	LobbyMusicNames = lobbyMusicNames,
	WeaponSfxByKindName = weaponSfxByKindName,
	PostWeaponSfxByKindName = postWeaponSfxByKindName,
	-- a launch heard by everyone, by the GameAssets/Projectiles template
	-- flown (the launch notification carries no gadget kind): the flare
	-- gun's shot (2026-10-21), 3D at the muzzle; the shooter plays it at
	-- once and skips the notification's copy
	ProjectileLaunchSfxByTemplate = {
		Flare = sfx.FLARE_FIRE,
	} :: { [string]: string },
}

return module
