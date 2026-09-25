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
	UPGRADE_PRICE_BY_LEVEL = { 15, 30, 60, 120 },
	BONUS_PER_LEVEL_BY_ATTRIBUTE = {
		[Enums.PostAttribute.DAMAGE] = 0.25,
		[Enums.PostAttribute.FIRE_RATE] = 0.2,
		-- a base starts slow and an upgraded one turns twice as fast at
		-- level 2, three times at level 4 (decided 2026-09-18)
		[Enums.PostAttribute.TURN_SPEED] = 0.5,
		[Enums.PostAttribute.RANGE] = 0.2,
	},
	-- how far from the muzzle the server lets a shot start: the client's
	-- base may be a fraction of a second ahead of the last aim it sent
	ORIGIN_TOLERANCE_STUDS = 8,
	-- how many degrees past the turn speed a yaw report may run, for the
	-- same reason
	YAW_TOLERANCE_DEGREES = 15,
	BY_KIND = {
		[Enums.PostWeaponKind.MACHINE_GUN] = {
			DAMAGE = 12,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			TURN_SPEED_DEGREES_PER_SEC = 22,
			RANGE_STUDS = 350,
			FIELD_OF_VIEW = 30,
			PITCH_MIN_DEGREES = -40,
			PITCH_MAX_DEGREES = 45,
			-- overheat (decided 2026-09-18): holding the trigger for FULL_SEC
			-- fills the heat; it then refuses to fire until fully cooled, which
			-- takes COOL_SEC from full. Heat only cools once the trigger rests
			HEAT = {
				FULL_SEC = 3,
				COOL_SEC = 3,
			},
		},
		[Enums.PostWeaponKind.ROCKET_LAUNCHER] = {
			DAMAGE = 150,
			-- the reload is the launcher's fire rate (decided 2026-09-18): one
			-- rocket every RELOAD_SEC, and Fire Rate upgrades shorten it
			FIRE_INTERVAL_SEC = 6,
			FIRE_COOLDOWN_SEC = 5.8,
			TURN_SPEED_DEGREES_PER_SEC = 12,
			RANGE_STUDS = 500,
			FIELD_OF_VIEW = 40,
			PITCH_MIN_DEGREES = -35,
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
