--!strict

-- Handheld weapons (GDD "Weapon (Default Tool)", S12), M24. One entry per
-- Enums.WeaponKind; a loadout weapon plugs in by adding its enum key, an
-- entry here, a "WEAPON_<KEY>" held template, and its own sound set in
-- shared SoundNames (sounds are client-side, so they are not listed here).
-- Every weapon is hitscan with unlimited reserve ammo and a magazine
-- (decided 2026-09-17).
-- FIRE_INTERVAL_SEC is how often a held input fires; FIRE_COOLDOWN_SEC is
-- the faster rate the server refuses, so latency jitter never drops a
-- legitimate shot. Placeholder numbers until enemies exist to tune against.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	DEFAULT_WEAPON = Enums.WeaponKind.RIFLE,
	-- how far from the shooter's head the server lets a shot start: the
	-- first-person camera is in the head, the rest is latency
	ORIGIN_TOLERANCE_STUDS = 12,
	BY_KIND = {
		-- a lever-action, to match the art (decided 2026-09-17): five
		-- deliberate, heavy shots, one per lever stroke, then a slow reload
		[Enums.WeaponKind.RIFLE] = {
			DAMAGE = 30,
			FIRE_INTERVAL_SEC = 0.6,
			FIRE_COOLDOWN_SEC = 0.5,
			RANGE_STUDS = 300,
			MAGAZINE_SIZE = 5,
			RELOAD_SEC = 2.5,
		},
	},
	-- the dev-tool target dummy (M24): spawned in front of the admin
	TARGET_DUMMY_HP = 200,
	TARGET_DUMMY_SIZE = Vector3.new(4, 6, 2),
	TARGET_DUMMY_DISTANCE_STUDS = 25,
}
