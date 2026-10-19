--!strict

-- Posts and post weapons (GDD "Posts", "Post Types", "Classes"), M25 and
-- the class posts of 2026-10-16. One entry per Enums.PostWeaponKind; a new
-- post weapon plugs in by adding its enum key, an entry here, a model of
-- that key's name under GameAssets/PostWeapons, and its sound set in
-- shared SoundNames. Post weapons have no magazine (decided 2026-09-18):
-- the fire interval is the only limit on a hold.
-- FIRE_INTERVAL_SEC is how often a held input fires; FIRE_COOLDOWN_SEC is
-- the faster rate the server refuses, so latency jitter never drops a
-- legitimate shot. Every attribute can be upgraded four times; upgrade N
-- adds BONUS_PER_LEVEL of the base stat (fire rate shortens the interval by
-- the same share) and costs UPGRADE_PRICE_BY_LEVEL[N] Iron Bars (M63,
-- 2026-10-11: Gold buys mining and Iron buys defense, so a post rung is
-- never weighed against a pick; Gold until then); the menu opens at the
-- Post Upgrade Table.
--
-- The optional blocks, each read by PostManager where it applies:
-- PROJECTILE: fires a projectile instead of a hitscan ray; it flies at
--   SPEED, pulled down by GRAVITY_STUDS_PER_SEC2 when set (a lob), and
--   where it first meets the world or a damageable deals DAMAGE to
--   everything within SPLASH_RADIUS_STUDS; RANGE_STUDS is how far it
--   flies before bursting in the air. IS_PIERCING flies on through every
--   damageable it meets, hurting each once (the Saw Gun). HOMING turns
--   it toward a locked target.
-- HEAT: an overheating gun (see the Machine Gun).
-- RELOAD_SEC: a gun that reloads after every shot.
-- SPIN_UP: the first shot after the trigger has rested waits SEC after
--   the trigger closes (the Minigun; fixed, no upgrade shortens it, so
--   letting go to re-aim always costs the spin-up; decided 2026-10-19).
-- CHARGE: hold to charge for SEC, release to fire (the Railgun; Fire Rate
--   shortens it). PIERCE: the shot carries on through COUNT damageables
--   (plus one per Damage level) for full damage each.
-- POOL: the burst leaves a pool for SEC that stacks a burn on everything
--   standing in it (the Napalm Mortar; Damage widens the pool).
-- LOCK: aiming near a flyer for SEC locks it (up to COUNT at once, each
--   within ANGLE_DEGREES of the barrel); the shot fires one homing
--   missile per lock, or one straight missile at DUMB_FIRE_DAMAGE_SHARE
--   of the damage with no lock (the AA Launcher).
-- IS_UNMANNED: nobody mans it; the server aims it at the nearest target
--   and fires it (the Auto Machine Gun), its damage already scaled.
-- MINES: the lob lands as an armed mine that blows when a ground monster
--   comes within TRIGGER_RADIUS_STUDS; MAX_ARMED at once (the oldest
--   fizzles past it) and every mine fizzles at dawn (the Mine Layer).
-- CHAIN: the hit jumps to COUNT more targets, each within JUMP_STUDS of
--   the last, for full damage each (the Tesla Arc; Range lengthens the jump).
-- SALVAGE: every monster the shot kills drops IRON_PER_KILL Iron Bars at
--   its feet, up to CAP_PER_NIGHT (the Salvage Gun).
-- PULL: no damage; every monster within RADIUS_STUDS of where the shot
--   lands is drawn to that point for SEC at SPEED_STUDS_PER_SEC (the
--   Magnet Gun).
-- Placeholder numbers until the classes are playtested.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local DAMAGE = Enums.PostAttribute.DAMAGE
local FIRE_RATE = Enums.PostAttribute.FIRE_RATE
local TURN_SPEED = Enums.PostAttribute.TURN_SPEED
local RANGE = Enums.PostAttribute.RANGE
local HEADSHOT = Enums.PostAttribute.HEADSHOT
local COOLDOWN = Enums.PostAttribute.COOLDOWN

-- the gun sits a dozen studs over the ground, so a monster at the foot
-- of the tower needs a steep look down (-70 since 2026-09-30, was -40);
-- all the way up (designer, 2026-10-06: Flyers hovered over a post the
-- gunner could not raise to; 89 rather than 90 so the gun's look
-- direction never degenerates straight up)
local PITCH_MIN_DEGREES = -70
local PITCH_MAX_DEGREES = 89

return {
	-- every new player starts with this one unlocked and equipped
	DEFAULT_POST_WEAPON = Enums.PostWeaponKind.MACHINE_GUN,
	-- 0 since 2026-09-25: a post is every player's guaranteed role and the
	-- choice is where, not whether, so a price was only friction before the
	-- first night. Kept as the knob for the day posts become unequal; the
	-- sign has no price line any more, so a price above 0 needs one back
	CLAIM_PRICE_GOLD = 0,
	CLAIM_PROMPT_ACTION_TEXT = "Claim Post",
	CLAIM_PROMPT_HOLD_SEC = 1,
	CLAIM_PROMPT_MAX_DISTANCE_STUDS = 12,
	-- the prompt hangs this far below the sign's centre so it never covers the text
	CLAIM_PROMPT_DROP_STUDS = 3,
	USE_PROMPT_ACTION_TEXT = "Use",
	PROMPT_MAX_DISTANCE_STUDS = 10,
	-- the Post Upgrade Table in the defense building (2026-10-01), where the
	-- upgrade menu now opens; anyone may trigger it, a player without a
	-- post is told to claim one first
	-- the table upgrades the class's post and its gadget (M67, 2026-10-19)
	TABLE_PROMPT_ACTION_TEXT = "Post & Gadget Upgrades",
	TABLE_PROMPT_OBJECT_TEXT = "Upgrade Table",
	TABLE_PROMPT_MAX_DISTANCE_STUDS = 10,
	-- Iron since M63 (2026-10-11; 15 / 90 / 270 / 800 Gold before, the pick
	-- axe's ladder after a cheap first rung). Day 1 refines no Iron by
	-- design, so night 1 is fought on bare posts and the first rung is a
	-- day-2 buy from a day's Iron (solo about 19); the rest climb with the
	-- fortification ladder (150 / 400 solo) so a post is still climbing on
	-- the last night. First guess pending the designer's scan
	UPGRADE_PRICE_BY_LEVEL = { 10, 40, 120, 300 },
	BONUS_PER_LEVEL_BY_ATTRIBUTE = {
		[DAMAGE] = 0.25,
		[FIRE_RATE] = 0.2,
		-- a base starts slow and an upgraded one turns twice as fast at
		-- level 2, three times at level 4 (decided 2026-09-18)
		[TURN_SPEED] = 0.5,
		[RANGE] = 0.2,
		-- the Machine Gun's fourth attribute (2026-09-29, replacing Range,
		-- which its 350 studs never needed): each level takes this share of
		-- the base cool time off, the same half second every rung, so the
		-- overheated gun cools from full in 3 / 2.5 / 2 / 1.5 / 1 s
		[COOLDOWN] = 1 / 6,
		-- the Railgun's Headshot (2026-10-19): a quarter added to the
		-- multiple per level, 3x to 4x, so a maxed gun still needs several
		-- landed heads for a Launcher or a Titan
		[HEADSHOT] = 0.25,
	},
	-- how far from the muzzle the server lets a shot start: the client's
	-- base may be a fraction of a second ahead of the last aim it sent
	ORIGIN_TOLERANCE_STUDS = 8,
	-- headshots (2026-10-19): a hitscan shot (a plain one or a pierce) in
	-- the head does this much more; a kind may set its own HEADSHOT_MULTIPLIER
	HEADSHOT_MULTIPLIER = 1.5,
	-- how many degrees past the turn speed a yaw report may run, for the
	-- same reason
	YAW_TOLERANCE_DEGREES = 15,
	-- how much under the full charge or spin-up the server still accepts a
	-- shot, for the same clock jitter
	WINDUP_TOLERANCE_SEC = 0.1,
	-- an unmanned post fires once its barrel is within this of its target
	UNMANNED_AIM_TOLERANCE_DEGREES = 4,
	BY_KIND = {
		-- about 69 DPS sustained through the overheat, against the rifle's
		-- 55: a post is a stationary, exposed commitment and must be worth
		-- leaving the rifle for (2026-09-28), but 15 damage (85 sustained,
		-- 150 while firing) made every enemy feel easy in the seventh
		-- playtest, so 12 since 2026-09-29
		[Enums.PostWeaponKind.MACHINE_GUN] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, COOLDOWN },
			DAMAGE = 12,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			TURN_SPEED_DEGREES_PER_SEC = 22,
			RANGE_STUDS = 350,
			FIELD_OF_VIEW = 30,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			-- overheat (decided 2026-09-18): holding the trigger for FULL_SEC
			-- fills the heat; it then refuses to fire until fully cooled, which
			-- takes COOL_SEC from full. Heat only cools once the trigger rests
			HEAT = {
				FULL_SEC = 4,
				COOL_SEC = 3,
			},
		},
		-- 33 DPS to one target, about a hundred into a group at the 12-stud
		-- splash (2026-09-28); the Demolitionist's since 2026-10-15
		[Enums.PostWeaponKind.ROCKET_LAUNCHER] = {
			-- Range matters here: it is how far a rocket flies before bursting
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 200,
			-- the reload is the launcher's fire rate (decided 2026-09-18): one
			-- rocket every RELOAD_SEC, and Fire Rate upgrades shorten it
			FIRE_INTERVAL_SEC = 6,
			FIRE_COOLDOWN_SEC = 5.8,
			TURN_SPEED_DEGREES_PER_SEC = 12,
			RANGE_STUDS = 500,
			FIELD_OF_VIEW = 40,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			-- the reload bar's length, shortened by Fire Rate like the interval
			RELOAD_SEC = 6,
			PROJECTILE = {
				-- the GameAssets/Projectiles model; its nose points away from its TailAttachment
				TEMPLATE = "Rocket",
				-- the GameAssets/Effects model cloned at the burst point
				BLAST_TEMPLATE = "RocketBlast",
				SPEED_STUDS_PER_SEC = 120,
				SPLASH_RADIUS_STUDS = 12,
			},
		},
		-- the Gunner: spins up for half a second, then a stream with more
		-- damage per second than the Machine Gun, three times the heat
		-- budget, a slower turn; Fire Rate shortens the spin-up
		[Enums.PostWeaponKind.MINI_GUN] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, COOLDOWN },
			-- 9 from 10 (2026-10-19): with the Gunner's 1.25 and the 11 s cycle
			-- (1 s spin, 6 s fire, 4 s cool) a burst averages about 102 a
			-- second against the Machine Gun's 69, the +50% the designer asked for
			DAMAGE = 9,
			FIRE_INTERVAL_SEC = 0.06,
			FIRE_COOLDOWN_SEC = 0.045,
			TURN_SPEED_DEGREES_PER_SEC = 16,
			RANGE_STUDS = 350,
			FIELD_OF_VIEW = 30,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			-- a burst weapon, not a sprinkler (2026-10-19, from 12 s of fire
			-- and a 0.5 s spin-up after the first Gunner playtest): half
			-- again the Machine Gun's budget, and a full second to spin up
			HEAT = {
				FULL_SEC = 6,
				COOL_SEC = 4,
			},
			SPIN_UP = {
				SEC = 1,
			},
		},
		-- the Sniper: hold to charge, release to fire a shot that goes
		-- through two bodies in a line for the share of full damage the
		-- charge reached; Fire Rate shortens the charge. The pierce no
		-- longer grows with Damage (2026-10-19): with the headshot and a
		-- shorter charge a level 4 gun through seven bodies was the Saw
		-- Gun's lane with the Sniper's damage
		[Enums.PostWeaponKind.RAIL_GUN] = {
			-- Headshot in place of Range (2026-10-19): 600 studs already
			-- reaches past every spawn, so Range bought nothing
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, HEADSHOT },
			-- the Sniper Rifle's headshot: a full charge in the head is 780
			HEADSHOT_MULTIPLIER = 3,
			DAMAGE = 260,
			-- the charge is the only pace (2026-10-19): no reload, and an
			-- interval short enough that a snap shot can follow a snap shot
			FIRE_INTERVAL_SEC = 0.5,
			FIRE_COOLDOWN_SEC = 0.4,
			TURN_SPEED_DEGREES_PER_SEC = 10,
			RANGE_STUDS = 600,
			-- the Sniper Rifle's zoom, behind the same scope glass (2026-10-19)
			FIELD_OF_VIEW = 13,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			-- a full charge takes this long and the shot does the share of
			-- full damage the trigger was held to (2026-10-19, from 1.2 s and
			-- all-or-nothing): a snap shot is a weak shot, a held one the full
			CHARGE = {
				SEC = 4,
			},
			PIERCE = {
				COUNT = 2,
				COUNT_PER_DAMAGE_LEVEL = 0,
			},
		},
		-- the Pyro: lobs a shell that bursts into a pool of fire where it
		-- lands, burning for several seconds and stacking on anything that
		-- stays; slow fire, the skill is the pool on the path; Range reaches
		-- past the wall, Damage widens the pool
		[Enums.PostWeaponKind.MORTAR] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 60,
			FIRE_INTERVAL_SEC = 5,
			FIRE_COOLDOWN_SEC = 4.8,
			TURN_SPEED_DEGREES_PER_SEC = 12,
			RANGE_STUDS = 260,
			FIELD_OF_VIEW = 45,
			PITCH_MIN_DEGREES = -30,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			RELOAD_SEC = 5,
			PROJECTILE = {
				TEMPLATE = "NapalmShell",
				BLAST_TEMPLATE = "RocketBlast",
				SPEED_STUDS_PER_SEC = 110,
				GRAVITY_STUDS_PER_SEC2 = 60,
				SPLASH_RADIUS_STUDS = 8,
			},
			POOL = {
				RADIUS_STUDS = 10,
				SEC = 6,
				BURN_DAMAGE_PER_SEC = 12,
				BURN_SEC = 3,
				-- how often the pool stacks its burn on what stands in it
				TICK_SEC = 0.5,
			},
		},
		-- the Air Defense: hold the reticle near a flyer for a moment and it
		-- locks with a tone, up to three at once, one missile each, bursting
		-- near the target so a cluster is shredded; against the ground a
		-- missile dumb-fires with a small splash weaker than a Rocket
		[Enums.PostWeaponKind.AA_LAUNCHER] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 90,
			FIRE_INTERVAL_SEC = 3,
			FIRE_COOLDOWN_SEC = 2.8,
			TURN_SPEED_DEGREES_PER_SEC = 20,
			RANGE_STUDS = 400,
			FIELD_OF_VIEW = 40,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			RELOAD_SEC = 3,
			PROJECTILE = {
				TEMPLATE = "AAMissile",
				BLAST_TEMPLATE = "RocketBlast",
				SPEED_STUDS_PER_SEC = 140,
				SPLASH_RADIUS_STUDS = 8,
				HOMING = {
					TURN_DEGREES_PER_SEC = 240,
				},
			},
			LOCK = {
				SEC = 0.8,
				ANGLE_DEGREES = 8,
				COUNT = 3,
				DUMB_FIRE_DAMAGE_SHARE = 0.5,
			},
		},
		-- the Ranger's: nobody mans it; it picks the nearest target in
		-- range, turns to it, and fires the Machine Gun's burst at 60% of
		-- its damage (decided 2026-10-16), so the Ranger fights on foot
		[Enums.PostWeaponKind.MACHINE_GUN_AUTOMATED] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, COOLDOWN },
			DAMAGE = 7.2,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			TURN_SPEED_DEGREES_PER_SEC = 30,
			RANGE_STUDS = 200,
			FIELD_OF_VIEW = 30,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			HEAT = {
				FULL_SEC = 4,
				COOL_SEC = 3,
			},
			IS_UNMANNED = true,
		},
		-- the Engineer: lobs proximity mines onto the path that arm where
		-- they land and blow when stepped on; a dozen armed at once, the
		-- oldest fizzling past the cap, all fizzling at dawn
		[Enums.PostWeaponKind.MINE_LAYER] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 110,
			FIRE_INTERVAL_SEC = 2,
			FIRE_COOLDOWN_SEC = 1.8,
			TURN_SPEED_DEGREES_PER_SEC = 16,
			RANGE_STUDS = 180,
			FIELD_OF_VIEW = 45,
			PITCH_MIN_DEGREES = -30,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			RELOAD_SEC = 2,
			PROJECTILE = {
				TEMPLATE = "ProximityMine",
				BLAST_TEMPLATE = "RocketBlast",
				SPEED_STUDS_PER_SEC = 80,
				GRAVITY_STUDS_PER_SEC2 = 60,
				SPLASH_RADIUS_STUDS = 9,
			},
			MINES = {
				MAX_ARMED = 12,
				TRIGGER_RADIUS_STUDS = 4,
				-- a mine lies dormant this long after landing before it arms
				ARM_SEC = 1,
			},
		},
		-- the Electrician: a sustained arc on the target that jumps to the
		-- nearest other monsters, so damage rises with how tightly they
		-- bunch; worse than a Rocket on one big monster, best in the game at
		-- a jammed gate; Range lengthens the jump
		[Enums.PostWeaponKind.TESLA_ARC] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 9,
			FIRE_INTERVAL_SEC = 0.2,
			FIRE_COOLDOWN_SEC = 0.16,
			TURN_SPEED_DEGREES_PER_SEC = 20,
			RANGE_STUDS = 160,
			FIELD_OF_VIEW = 35,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			CHAIN = {
				COUNT = 3,
				JUMP_STUDS = 12,
			},
		},
		-- the Prospector: a weak fast shot, and every monster it kills drops
		-- Iron Bars at its feet for anyone to pick up, capped per night so
		-- it never prints money
		[Enums.PostWeaponKind.SALVAGE_GUN] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 8,
			FIRE_INTERVAL_SEC = 0.12,
			FIRE_COOLDOWN_SEC = 0.1,
			TURN_SPEED_DEGREES_PER_SEC = 24,
			RANGE_STUDS = 300,
			FIELD_OF_VIEW = 30,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			SALVAGE = {
				IRON_PER_KILL = 2,
				CAP_PER_NIGHT = 60,
			},
		},
		-- the Hauler: launches a spinning saw blade that flies in a line and
		-- cuts through every monster it meets for full damage until its
		-- range runs out; slow fire, a long flat shot
		[Enums.PostWeaponKind.SAW_GUN] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 70,
			FIRE_INTERVAL_SEC = 1.5,
			FIRE_COOLDOWN_SEC = 1.3,
			TURN_SPEED_DEGREES_PER_SEC = 14,
			RANGE_STUDS = 220,
			FIELD_OF_VIEW = 35,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			RELOAD_SEC = 1.5,
			PROJECTILE = {
				TEMPLATE = "SawBlade",
				SPEED_STUDS_PER_SEC = 100,
				SPLASH_RADIUS_STUDS = 0,
				IS_PIERCING = true,
			},
		},
		-- the Medic: no damage; fire at a spot and every monster within a
		-- radius of it is pulled there for a few seconds, off a crewmate, off
		-- the gate, into the Saw Gun's line; Range widens the pull
		[Enums.PostWeaponKind.MAGNET_GUN] = {
			UPGRADE_ATTRIBUTES = { DAMAGE, FIRE_RATE, TURN_SPEED, RANGE },
			DAMAGE = 0,
			FIRE_INTERVAL_SEC = 6,
			FIRE_COOLDOWN_SEC = 5.8,
			TURN_SPEED_DEGREES_PER_SEC = 18,
			RANGE_STUDS = 250,
			FIELD_OF_VIEW = 40,
			PITCH_MIN_DEGREES = PITCH_MIN_DEGREES,
			PITCH_MAX_DEGREES = PITCH_MAX_DEGREES,
			RELOAD_SEC = 6,
			PULL = {
				RADIUS_STUDS = 18,
				SEC = 3,
				SPEED_STUDS_PER_SEC = 14,
			},
		},
	},
}
