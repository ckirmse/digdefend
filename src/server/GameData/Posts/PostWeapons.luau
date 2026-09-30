--!strict

-- Posts and post weapons (GDD "Posts"), M25. One entry per
-- Enums.PostWeaponKind; a new post weapon plugs in by adding its enum key,
-- an entry here, a model of that key's name under GameAssets/PostWeapons,
-- and its sound pair in shared SoundNames. Post weapons have no magazine
-- (decided 2026-09-18): the fire interval is the only limit on a hold.
-- FIRE_INTERVAL_SEC is how often a held input fires; FIRE_COOLDOWN_SEC is
-- the faster rate the server refuses, so latency jitter never drops a
-- legitimate shot. Every attribute can be upgraded four times; upgrade N
-- adds BONUS_PER_LEVEL of the base stat (fire rate shortens the interval by
-- the same share) and costs UPGRADE_PRICE_BY_LEVEL[N] Gold Bars, gated by
-- GameData/Camp/Level. A kind with a PROJECTILE block fires a rocket
-- instead of a hitscan ray: the server flies it in a straight line at
-- SPEED and, where it first meets the world or a damageable, deals DAMAGE
-- to everything within SPLASH_RADIUS_STUDS; RANGE_STUDS is how far it flies
-- before bursting in the air. Placeholder numbers until enemies exist to
-- tune against.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

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
	UPGRADE_PROMPT_ACTION_TEXT = "Upgrade",
	PROMPT_MAX_DISTANCE_STUDS = 10,
	-- a cheap first rung, then the pick axe's ladder (2026-09-29):
	-- 15 / 30 / 60 / 120 maxed three attributes by day 7 in the seventh
	-- playtest, before the run was half done; the first rung stays a
	-- night-2 buy (the sheet's nights 2 and 3 hinge on it) and the rest
	-- triple so the post is still climbing on the last night
	UPGRADE_PRICE_BY_LEVEL = { 15, 90, 270, 800 },
	BONUS_PER_LEVEL_BY_ATTRIBUTE = {
		[Enums.PostAttribute.DAMAGE] = 0.25,
		[Enums.PostAttribute.FIRE_RATE] = 0.2,
		-- a base starts slow and an upgraded one turns twice as fast at
		-- level 2, three times at level 4 (decided 2026-09-18)
		[Enums.PostAttribute.TURN_SPEED] = 0.5,
		[Enums.PostAttribute.RANGE] = 0.2,
		-- the Machine Gun's fourth attribute (2026-09-29, replacing Range,
		-- which its 350 studs never needed): each level takes this share of
		-- the base cool time off, the same half second every rung, so the
		-- overheated gun cools from full in 3 / 2.5 / 2 / 1.5 / 1 s
		[Enums.PostAttribute.COOLDOWN] = 1 / 6,
	},
	-- how far from the muzzle the server lets a shot start: the client's
	-- base may be a fraction of a second ahead of the last aim it sent
	ORIGIN_TOLERANCE_STUDS = 8,
	-- how many degrees past the turn speed a yaw report may run, for the
	-- same reason
	YAW_TOLERANCE_DEGREES = 15,
	BY_KIND = {
		-- about 69 DPS sustained through the overheat, against the rifle's
		-- 55: a post is a stationary, exposed commitment and must be worth
		-- leaving the rifle for (2026-09-28), but 15 damage (85 sustained,
		-- 150 while firing) made every enemy feel easy in the seventh
		-- playtest, so 12 since 2026-09-29
		[Enums.PostWeaponKind.MACHINE_GUN] = {
			UPGRADE_ATTRIBUTES = {
				Enums.PostAttribute.DAMAGE,
				Enums.PostAttribute.FIRE_RATE,
				Enums.PostAttribute.TURN_SPEED,
				Enums.PostAttribute.COOLDOWN,
			},
			DAMAGE = 12,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			TURN_SPEED_DEGREES_PER_SEC = 22,
			RANGE_STUDS = 350,
			FIELD_OF_VIEW = 30,
			-- the gun sits a dozen studs over the ground, so a monster at the foot
			-- of the tower needs a steep look down (-70 since 2026-09-30, was -40)
			PITCH_MIN_DEGREES = -70,
			PITCH_MAX_DEGREES = 45,
			-- overheat (decided 2026-09-18): holding the trigger for FULL_SEC
			-- fills the heat; it then refuses to fire until fully cooled, which
			-- takes COOL_SEC from full. Heat only cools once the trigger rests
			HEAT = {
				FULL_SEC = 4,
				COOL_SEC = 3,
			},
		},
		-- 33 DPS to one target, about a hundred into a group at the 12-stud
		-- splash (2026-09-28)
		[Enums.PostWeaponKind.ROCKET_LAUNCHER] = {
			-- Range matters here: it is how far a rocket flies before bursting
			UPGRADE_ATTRIBUTES = {
				Enums.PostAttribute.DAMAGE,
				Enums.PostAttribute.FIRE_RATE,
				Enums.PostAttribute.TURN_SPEED,
				Enums.PostAttribute.RANGE,
			},
			DAMAGE = 200,
			-- the reload is the launcher's fire rate (decided 2026-09-18): one
			-- rocket every RELOAD_SEC, and Fire Rate upgrades shorten it
			FIRE_INTERVAL_SEC = 6,
			FIRE_COOLDOWN_SEC = 5.8,
			TURN_SPEED_DEGREES_PER_SEC = 12,
			RANGE_STUDS = 500,
			FIELD_OF_VIEW = 40,
			-- as the Machine Gun: a monster at the foot of the tower (was -35)
			PITCH_MIN_DEGREES = -70,
			PITCH_MAX_DEGREES = 60,
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
	},
}
