--!strict

-- Handheld weapons (GDD "Weapon (Default Tool)", S12, "Classes"), M24 and
-- the class weapons of 2026-10-16. One entry per Enums.WeaponKind; a
-- weapon plugs in by adding its enum key, an entry here, its source art
-- under GameAssets/Weapons (scripts/studio/build_tool_templates.luau
-- makes the "WEAPON_<KEY>" held template from it), and its own sound set
-- in shared SoundNames (sounds are client-side, so they are not listed
-- here). Every weapon has unlimited reserve ammo and a magazine (decided
-- 2026-09-17), hitscan unless it carries a CONE block (a stream that hits
-- everything in a cone every tick, the Flamethrower, whose magazine is
-- its fuel tank and whose reload is the refill). A SCOPE block gives the
-- client a zoomed aim (the Sniper Rifle); a SECONDARY block is a second
-- trigger that lobs a projectile with a splash (the Assault Rifle's
-- grenade), on its own cooldown.
-- FIRE_INTERVAL_SEC is how often a held input fires; FIRE_COOLDOWN_SEC is
-- the faster rate the server refuses, so latency jitter never drops a
-- legitimate shot. Placeholder numbers until the classes are playtested.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	DEFAULT_WEAPON = Enums.WeaponKind.RIFLE,
	-- how far from the shooter's head the server lets a shot start: the
	-- first-person camera is in the head, the rest is latency
	ORIGIN_TOLERANCE_STUDS = 12,
	-- headshots (2026-10-19): a hit in the head (WeaponRules.HEAD_SHARE of
	-- the target's box) does this much more. 1 is no headshot at all, no
	-- bonus and no callout: the headshot is the Railgun's alone (decided
	-- 2026-10-19), so no hand weapon has one; a kind may still set its own
	-- HEADSHOT_MULTIPLIER
	HEADSHOT_MULTIPLIER = 1,
	BY_KIND = {
		-- a lever-action, to match the art (decided 2026-09-17): five
		-- deliberate, heavy shots, one per lever stroke, then a slow reload
		[Enums.WeaponKind.RIFLE] = {
			DAMAGE = 60,
			FIRE_INTERVAL_SEC = 0.6,
			FIRE_COOLDOWN_SEC = 0.5,
			RANGE_STUDS = 300,
			MAGAZINE_SIZE = 5,
			RELOAD_SEC = 2.5,
		},
		-- the weak-night classes' sidearm: quick, light, short, about two
		-- thirds of the Rifle's damage per second up close and nothing far
		[Enums.WeaponKind.PISTOL] = {
			DAMAGE = 22,
			FIRE_INTERVAL_SEC = 0.3,
			FIRE_COOLDOWN_SEC = 0.25,
			RANGE_STUDS = 120,
			MAGAZINE_SIZE = 8,
			RELOAD_SEC = 1.2,
		},
		-- bolt action: one shot takes most of anything that is not large,
		-- slow between shots and slow to reload, and the scope is the aim
		[Enums.WeaponKind.SNIPER] = {
			DAMAGE = 220,
			FIRE_INTERVAL_SEC = 1.4,
			FIRE_COOLDOWN_SEC = 1.2,
			RANGE_STUDS = 600,
			MAGAZINE_SIZE = 4,
			RELOAD_SEC = 3,
			SCOPE = {
				-- the camera's field of view while the scope is raised; 13 from
				-- 20 on 2026-10-19 (half again the magnification) with the
				-- scope glass drawn over the screen
				FIELD_OF_VIEW = 13,
			},
		},
		-- a short continuous cone: DAMAGE lands on everything in the cone
		-- every tick and each tick stacks a burn; the magazine is the fuel
		-- tank in ticks (six seconds of fire) and the reload its refill
		[Enums.WeaponKind.FLAMETHROWER] = {
			DAMAGE = 5,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			RANGE_STUDS = 22,
			MAGAZINE_SIZE = 60,
			RELOAD_SEC = 3,
			CONE = {
				ANGLE_DEGREES = 24,
				BURN_DAMAGE_PER_SEC = 8,
				BURN_SEC = 3,
			},
		},
		-- fast, accurate, a big magazine and a quick reload, with a grenade
		-- under the barrel on its own cooldown (the second trigger)
		[Enums.WeaponKind.ASSAULT_RIFLE] = {
			DAMAGE = 18,
			FIRE_INTERVAL_SEC = 0.1,
			FIRE_COOLDOWN_SEC = 0.08,
			RANGE_STUDS = 250,
			MAGAZINE_SIZE = 30,
			RELOAD_SEC = 1.6,
			SECONDARY = {
				DAMAGE = 120,
				COOLDOWN_SEC = 8,
				-- the GameAssets/Projectiles part flown by clients; the burst
				-- effect under GameAssets/Effects
				TEMPLATE = "Grenade",
				BLAST_TEMPLATE = "RocketBlast",
				SPEED_STUDS_PER_SEC = 90,
				-- the lob: studs per second squared pulling the grenade down
				GRAVITY_STUDS_PER_SEC2 = 60,
				RANGE_STUDS = 200,
				SPLASH_RADIUS_STUDS = 10,
			},
		},
	},
	-- the dev-tool target dummy (M24): spawned in front of the admin
	TARGET_DUMMY_HP = 200,
	TARGET_DUMMY_SIZE = Vector3.new(4, 6, 2),
	TARGET_DUMMY_DISTANCE_STUDS = 25,
	-- the walking dummy (M27): spawned this far out in front of the admin
	-- and walking a straight line back to where the admin stood, on the
	-- ground or at the air height, hitting a barrier in its way at this rate
	WALKING_DUMMY_HP = 400,
	WALKING_DUMMY_DISTANCE_STUDS = 90,
	WALKING_DUMMY_SPEED_STUDS_PER_SEC = 8,
	WALKING_DUMMY_AIR_HEIGHT_STUDS = 12,
	WALKING_DUMMY_ATTACK_DAMAGE_PER_SEC = 20,
}
