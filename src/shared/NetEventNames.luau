--!strict

-- Every message on the single RemoteEvent is named here. Client→server names
-- start with "Try"; server→client names start with "Notify". The prefix is a
-- reminder that clients request and the server decides.
local module

module = {
	TRY_DEV_TOOL = "TryDevTool",
	-- helicopter pad parties (GDD "Helicopter Pads"); joining is by touch, not message
	TRY_CREATE_PARTY = "TryCreateParty",
	TRY_LEAVE_PARTY = "TryLeaveParty",
	TRY_LAUNCH_PARTY = "TryLaunchParty",
	NOTIFY_PLAYER_FEEDBACK = "NotifyPlayerFeedback",
	-- tells one client which pad menu to show (Enums.PartyMenu) and whether it hosts
	NOTIFY_PARTY_MENU = "NotifyPartyMenu",
	-- the generated mine (gameplay place): a header with dimensions, placement,
	-- and chunk count, then the run-length-encoded cells in buffer chunks
	-- (MineGridCodec); a version ties chunks to their header so a regenerate
	-- mid-stream cannot mix two mines
	NOTIFY_MINE_HEADER = "NotifyMineHeader",
	NOTIFY_MINE_CHUNK = "NotifyMineChunk",
	-- the client asks for the mine once its handlers are connected; the server
	-- never pushes it at Ready, because the RemoteEvent does not queue
	-- messages fired before the client connects (that lost the mine on slow loads)
	TRY_REQUEST_MINE = "TryRequestMine",
	-- tools and mining (gameplay place, GDD "Tools" and "Mining Rock")
	TRY_EQUIP_TOOL = "TryEquipTool",
	TRY_HIT_ROCK = "TryHitRock",
	-- every client: a block took damage (crack state) or broke (clear the cell)
	NOTIFY_ROCK_DAMAGED = "NotifyRockDamaged",
	NOTIFY_ROCK_BROKEN = "NotifyRockBroken",
	-- to one client: ore reached their backpack (from a break or a pickup)
	-- with the world position it came from, so its icon flies into the HUD
	-- backpack; the counts themselves arrive as attributes
	NOTIFY_ORE_COLLECTED = "NotifyOreCollected",
	-- to the refining player: what left their backpack (the suck-in), then,
	-- after the grind, what was paid out (the fly-to-HUD); balances arrive as
	-- attributes. Refining itself is a ProximityPrompt trigger, not a message
	NOTIFY_REFINE_STARTED = "NotifyRefineStarted",
	NOTIFY_REFINE_COMPLETED = "NotifyRefineCompleted",
	-- to every client, once per payout that raises the Camp Level (M22)
	NOTIFY_CAMP_LEVEL_UP = "NotifyCampLevelUp",
	-- mining consumables (M21). Buying is a ProximityPrompt trigger on the
	-- stand, not a message. Throwing and placing are requests; the results
	-- are shadow parts (Tags.DYNAMITE / Tags.TORCH) and NotifyRockBroken
	TRY_THROW_DYNAMITE = "TryThrowDynamite",
	TRY_PLACE_TORCH = "TryPlaceTorch",
	-- every client: a blast happened here (sound and smoke)
	NOTIFY_DYNAMITE_EXPLODED = "NotifyDynamiteExploded",
	-- to one client: a store purchase went through (the sound and the toast)
	NOTIFY_STORE_PURCHASE = "NotifyStorePurchase",
	-- jet pack: the client asks to start and stop burning; the fuel and the
	-- burning flag come back as attributes
	TRY_JET_PACK_START = "TryJetPackStart",
	TRY_JET_PACK_STOP = "TryJetPackStop",
	-- Build Mode (M23): one Hammer swing at a structure, by id. The new HP
	-- comes back on the structure's shadow attributes; the notify is only
	-- the hammer blow every nearby client hears
	TRY_REPAIR_STRUCTURE = "TryRepairStructure",
	NOTIFY_STRUCTURE_REPAIRED = "NotifyStructureRepaired",
	-- the Workbench (M23): donating is a ProximityPrompt trigger, not a
	-- message. To the donor: Iron went into the pool (the sound). To every
	-- client: the pool filled and the fortifications went up a tier
	NOTIFY_FORTIFICATION_DONATED = "NotifyFortificationDonated",
	NOTIFY_FORTIFICATION_UPGRADED = "NotifyFortificationUpgraded",
	-- Weapon Mode (M24): one shot, as the ray the client aimed; the server
	-- decides what it hit. Ammo and the reload come back as attributes. To
	-- every client: a shot was fired from here to there (tracer, 3D sound is
	-- server-side), and which damageable it hit if any
	TRY_FIRE_WEAPON = "TryFireWeapon",
	TRY_RELOAD_WEAPON = "TryReloadWeapon",
	NOTIFY_WEAPON_FIRED = "NotifyWeaponFired",
	-- where the player is looking, up or down, a few times a second while
	-- it changes; comes back to everyone as the public AimPitchDegrees
	TRY_SET_AIM = "TrySetAim",
	-- posts (M25). Claiming and mounting are ProximityPrompts (the sign's
	-- and the weapon's Use), which the server hears directly; the claimer
	-- gets the notify for the sound and the mount comes back as the
	-- MannedPostIndex attribute. Leaving is a request. Aim is the base yaw
	-- and gun pitch a few times a second, checked against the turn speed
	-- and echoed on the weapon model. A shot is the muzzle ray; every
	-- client hears where it went
	TRY_DISMOUNT_POST = "TryDismountPost",
	TRY_SET_POST_AIM = "TrySetPostAim",
	TRY_FIRE_POST_WEAPON = "TryFirePostWeapon",
	TRY_UPGRADE_POST = "TryUpgradePost",
	NOTIFY_POST_CLAIMED = "NotifyPostClaimed",
	NOTIFY_POST_WEAPON_FIRED = "NotifyPostWeaponFired",
	-- a projectile post weapon instead: every client flies the rocket from
	-- the launch, and the burst says where it ended and how many it hit
	NOTIFY_POST_ROCKET_LAUNCHED = "NotifyPostRocketLaunched",
	NOTIFY_POST_ROCKET_EXPLODED = "NotifyPostRocketExploded",
	NOTIFY_POST_UPGRADED = "NotifyPostUpgraded",
}

return module
