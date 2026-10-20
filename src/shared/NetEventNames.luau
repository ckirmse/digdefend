--!strict

-- Every message on the single RemoteEvent is named here. Client→server names
-- start with "Try"; server→client names start with "Notify". The prefix is a
-- reminder that clients request and the server decides.
local module

module = {
	TRY_DEV_TOOL = "TryDevTool",
	-- the Character Select Menu (M37): pick the character to bring, buy the
	-- next slot (Diamonds, or a Robux prompt), rename one (filtered). The
	-- records themselves arrive as CurrentPlayer attributes and the
	-- Characters folder; the notify is the buyer's sound and toast
	TRY_SELECT_CHARACTER = "TrySelectCharacter",
	TRY_BUY_CHARACTER_SLOT = "TryBuyCharacterSlot",
	TRY_RENAME_CHARACTER = "TryRenameCharacter",
	-- equips a cosmetic on a character's slot (an empty id clears it)
	TRY_SET_COSMETIC = "TrySetCosmetic",
	NOTIFY_CHARACTER_SLOT_BOUGHT = "NotifyCharacterSlotBought",
	-- the character sheet's rerolls (M37): one result per roll (new stars,
	-- or one skill), which the player keeps or undoes with the price spent
	-- either way. The result is held on the server until resolved
	TRY_REROLL_GEAR = "TryRerollGear",
	TRY_RESOLVE_GEAR_ROLL = "TryResolveGearRoll",
	TRY_REROLL_SKILL = "TryRerollSkill",
	TRY_RESOLVE_SKILL_ROLL = "TryResolveSkillRoll",
	NOTIFY_GEAR_ROLL_OFFER = "NotifyGearRollOffer",
	NOTIFY_SKILL_ROLL_OFFER = "NotifySkillRollOffer",
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
	-- to every client, naming the refining player ({ userId, ... }): what
	-- left their backpack (the suck-in), then, after the grind, what was
	-- paid out. Everyone sees the icons fly; only that player's client
	-- plays the sounds and moves its HUD. Balances arrive as attributes.
	-- Refining itself is automatic at the Refinery, not a message
	NOTIFY_REFINE_STARTED = "NotifyRefineStarted",
	NOTIFY_REFINE_COMPLETED = "NotifyRefineCompleted",
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
	-- Repair Mode (M23): one Hammer swing at a structure, by id. The new HP
	-- comes back on the structure's shadow attributes; the notify is only
	-- the hammer blow every nearby client hears
	TRY_REPAIR_STRUCTURE = "TryRepairStructure",
	NOTIFY_STRUCTURE_REPAIRED = "NotifyStructureRepaired",
	-- alerts to every client (2026-09-25): a wall fell (the message names
	-- its number) and the Refinery came under attack; both carry the text
	-- and how long the red alert box shows it
	NOTIFY_WALL_DESTROYED = "NotifyWallDestroyed",
	NOTIFY_REFINERY_ATTACKED = "NotifyRefineryAttacked",
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
	-- { attribute } at the Weapons Table; answered by { attribute, level, price }
	TRY_UPGRADE_WEAPON = "TryUpgradeWeapon",
	NOTIFY_WEAPON_UPGRADED = "NotifyWeaponUpgraded",
	-- the second trigger (the Assault Rifle's grenade, 2026-10-16)
	TRY_FIRE_WEAPON_SECONDARY = "TryFireWeaponSecondary",
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
	NOTIFY_POST_UPGRADED = "NotifyPostUpgraded",
	-- the class posts (2026-10-16): the trigger held or released (a
	-- spin-up or a charge starts and ends with it), a pool of fire, an
	-- armed mine laid and blown, and a magnet pull
	TRY_SET_POST_TRIGGER = "TrySetPostTrigger",
	NOTIFY_POST_POOL_STARTED = "NotifyPostPoolStarted",
	NOTIFY_POST_MINE_PLACED = "NotifyPostMinePlaced",
	NOTIFY_POST_MINE_REMOVED = "NotifyPostMineRemoved",
	NOTIFY_POST_PULL = "NotifyPostPull",
	-- every projectile a weapon or post launches (ProjectileManager,
	-- 2026-10-16; the post rocket messages of M25 folded into these):
	-- clients fly a copy from the launch and end it where the server says
	NOTIFY_PROJECTILE_LAUNCHED = "NotifyProjectileLaunched",
	NOTIFY_PROJECTILE_ENDED = "NotifyProjectileEnded",
	-- placements (M26). Building is a request naming the kind, the area, and
	-- the cell; the server checks Build Mode (the Defense Table), the
	-- loadout, the Tower limit, the cells, and the Iron, then spawns a
	-- shadow (Tags.PLACEMENT). Selling and upgrading come from the table's
	-- view and the Tower Menu. The notifies are the sounds for the player
	-- concerned
	TRY_BUILD_PLACEMENT = "TryBuildPlacement",
	TRY_SELL_PLACEMENT = "TrySellPlacement",
	-- the owner picks a placement up at the Defense Table and sets it down
	-- on other cells, free of charge, keeping its level and HP (2026-09-30)
	TRY_MOVE_PLACEMENT = "TryMovePlacement",
	TRY_UPGRADE_TOWER = "TryUpgradeTower",
	TRY_SET_TOWER_TARGET_PRIORITY = "TrySetTowerTargetPriority",
	NOTIFY_PLACEMENT_BUILT = "NotifyPlacementBuilt",
	NOTIFY_PLACEMENT_SOLD = "NotifyPlacementSold",
	NOTIFY_TOWER_UPGRADED = "NotifyTowerUpgraded",
	-- the Defense Table (DefenseTableManager): the Exit button. Entering is
	-- the table's prompt, heard by the server directly
	TRY_EXIT_BUILD_MODE = "TryExitBuildMode",
	-- behaviour (M27), to every client: a Tower fired at the listed target
	-- ids (one for a shot, the chain in order for a bolt; a cone Tower
	-- sends none, its shadow's IsAttacking attribute is the flame), and a
	-- Trap went off (spikes up, a mine or snare spent)
	NOTIFY_TOWER_FIRED = "NotifyTowerFired",
	NOTIFY_TRAP_TRIGGERED = "NotifyTrapTriggered",
	-- Tower repair (M27, decided 2026-09-22): one Hammer swing at a Tower by
	-- id, exactly the wall flow (TryRepairStructure); the notify is the
	-- hammer blow for everyone nearby
	-- the request also serves a repairable Trap (the Wall, 2026-09-30); the
	-- name is kept
	TRY_REPAIR_TOWER = "TryRepairTower",
	NOTIFY_TOWER_REPAIRED = "NotifyTowerRepaired",
	-- the day and night loop (M28), to every client: a day began (the
	-- announcement to show), and the run ended (won or lost, the reason)
	NOTIFY_RUN_DAY_STARTED = "NotifyRunDayStarted",
	NOTIFY_RUN_NIGHT_STARTED = "NotifyRunNightStarted",
	NOTIFY_RUN_ENDED = "NotifyRunEnded",
	-- the rescue's lines for the announcement box (M31)
	NOTIFY_RESCUE_ANNOUNCEMENT = "NotifyRescueAnnouncement",
	-- monsters (M29), to every client; positions travel separately as
	-- packed snapshots on the monster UnreliableRemoteEvent. Spawned and
	-- died are batched per server tick; a late joiner gets every live
	-- monster in one spawned message
	NOTIFY_MONSTERS_SPAWNED = "NotifyMonstersSpawned",
	NOTIFY_MONSTERS_DIED = "NotifyMonstersDied",
	NOTIFY_MONSTER_PROJECTILE = "NotifyMonsterProjectile",
	NOTIFY_MONSTER_BLAST = "NotifyMonsterBlast",
	-- a monster took a new target it announces (a lurker's alert cry, M62)
	NOTIFY_MONSTER_ALERT = "NotifyMonsterAlert",
	-- death and revives (M32). A dead player asks for the revive their
	-- Results Menu offers ({ reviveKind }: their own or the crew's); the
	-- server spends a saved credit or opens Roblox's purchase prompt. A
	-- Friend Revive is the tombstone's ProximityPrompt, heard by the server
	-- directly. To each living player: a line for the announcement box
	-- (someone died, the day starts over). To every client: someone came
	-- back ({ userId, reviveKind }); the state itself is the public IsDead
	-- attribute
	TRY_REVIVE = "TryRevive",
	NOTIFY_REVIVE_ANNOUNCEMENT = "NotifyReviveAnnouncement",
	NOTIFY_PLAYER_REVIVED = "NotifyPlayerRevived",
	-- Spectate Mode: a dead player names who they are watching ({ userId },
	-- 0 to stop), so the server streams the world and the monsters round
	-- that player instead of the DeathRoom
	TRY_SPECTATE = "TrySpectate",
	-- Give Currency (M32): { targetUserId, goldBars, ironBars } after the
	-- menu's Confirm; both players hear the result as feedback text
	TRY_GIVE_CURRENCY = "TryGiveCurrency",
	-- to every client: a gift went through ({ senderUserId, targetUserId,
	-- goldBars, ironBars }), so the bars are seen flying from one player
	-- to the other
	NOTIFY_CURRENCY_GIVEN = "NotifyCurrencyGiven",
	-- a dead player, or anyone once the run is over, asks to go back to
	-- the lobby (the Results Menu's and the Spectate bar's button)
	TRY_RETURN_TO_LOBBY = "TryReturnToLobby",
	-- to one client: Diamonds was earned ({ amount, reason }), for the toast;
	-- the balance itself is the Diamonds attribute
	NOTIFY_DIAMONDS_EARNED = "NotifyDiamondsEarned",
	-- the Auto Turret (M66): place it where the ghost stands ({ position,
	-- yawDegrees }), pick up the one standing, and to every client: a
	-- turret fired at a target id (the tracer)
	TRY_PLACE_AUTO_TURRET = "TryPlaceAutoTurret",
	TRY_PICK_UP_AUTO_TURRET = "TryPickUpAutoTurret",
	NOTIFY_AUTO_TURRET_FIRED = "NotifyAutoTurretFired",
	-- the Binoculars (2026-10-19): tag the monster under the reticle
	TRY_TAG_MONSTER = "TryTagMonster",
	-- the Stim Shot (2026-10-19): use it, and the word back that it landed
	TRY_USE_STIM_SHOT = "TryUseStimShot",
	NOTIFY_STIM_SHOT_USED = "NotifyStimShotUsed",
	-- the Remote Charge (2026-10-20): plant one at the player's feet, blow
	-- every one planted, and to every client: where they burst
	-- ({ positions, radius }), for the blasts
	TRY_PLACE_REMOTE_CHARGE = "TryPlaceRemoteCharge",
	TRY_DETONATE_REMOTE_CHARGE = "TryDetonateRemoteCharge",
	NOTIFY_REMOTE_CHARGE_DETONATED = "NotifyRemoteChargeDetonated",
	-- gadget upgrades (M67): buy the class gadget's next level at the Post
	-- & Gadget Upgrades table, and to that client: it went through
	-- ({ level, price }), for the sound
	TRY_UPGRADE_GADGET = "TryUpgradeGadget",
	NOTIFY_GADGET_UPGRADED = "NotifyGadgetUpgraded",
}

return module
