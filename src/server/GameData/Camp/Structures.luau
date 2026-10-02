--!strict

-- Camp structures with HP (GDD "Walls", "Gate", "Refinery", "Wall Repair"),
-- M23. Per kind: max HP by tier (the list length fixes the top tier).
-- Repair works like mining (decided 2026-09-17): in Repair Mode every Hammer
-- swing at a damaged structure adds the structure's tier's chunk of HP for
-- its chunk of Iron (REPAIR_CHUNK_HP_BY_TIER, REPAIR_CHUNK_IRON_BY_TIER), a
-- short last chunk paying its share rounded up. A destroyed structure is
-- rubble, and stays rubble while it is rebuilt swing by swing from zero,
-- until its HP reaches REBUILD_STAND_SHARE of its maximum (1 = fully
-- rebuilt, decided 2026-09-17: a wall that stands up after one swing can be
-- flickered in front of the horde for 2 Iron a time). The gate, the walls, and the look of the
-- posts share one fortification tier (decided 2026-09-17: a half-wood,
-- half-concrete wall reads as a bug), paid for by the whole crew at the
-- Workbench: each press donates FORTIFICATION_DONATION_IRON into a shared
-- pool, and the tier goes up by itself when the pool reaches
-- FORTIFICATION_UPGRADE_IRON_TO_TIER (entry 1 unused: a camp starts at tier
-- 1); every structure keeps its share of HP through the upgrade. The Camp
-- Level each tier needs lives in GameData/Camp/Level with the other gates.
-- Placeholder numbers until enemies exist to tune against.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_KIND = {
		-- walls and the gate raised 50% on 2026-09-25 after the five-player
		-- test (waves now scale with the crew like the uranium target)
		[Enums.StructureKind.WALL] = {
			MAX_HP_BY_TIER = { 300, 600, 1200 },
		},
		[Enums.StructureKind.GATE] = {
			MAX_HP_BY_TIER = { 450, 900, 1800 },
		},
		-- the Refinery shares the fortification tier with the walls and the
		-- gate since 2026-09-29 (its tier was the Camp Level, which is out
		-- of the game for now), and doubles a tier as they do
		[Enums.StructureKind.REFINERY] = {
			MAX_HP_BY_TIER = { 1000, 2000, 4000 },
		},
	},
	-- the solo price of each tier; a crew pays this times its wave
	-- multiplier (PartyScaling), rounded up to whole donations, since the
	-- pool is the one camp-wide Iron sink and a crew of six earns about
	-- ten times solo's Iron for the same walls (decided 2026-09-29)
	FORTIFICATION_UPGRADE_IRON_TO_TIER = { 0, 150, 400 },
	FORTIFICATION_DONATION_IRON = 10,
	-- the Walls Table in the defense building (2026-10-01, replacing the
	-- Workbench by the gate); the action text names the donation so players
	-- know they pay in increments: "Contribute 10 Iron"
	WALLS_TABLE_PROMPT_ACTION_FORMAT = "Contribute %d Iron",
	WALLS_TABLE_PROMPT_OBJECT_TEXT = "Walls Table",
	WALLS_TABLE_PROMPT_MAX_DISTANCE_STUDS = 10,
	-- alerts (2026-09-25): a wall falling and the Refinery coming under attack
	-- are announced to everyone in the red alert box, for ALERT_DISPLAY_SEC.
	-- The Refinery is under attack while any live monster is within
	-- REFINERY_ATTACK_RADIUS_STUDS of its box (MonsterManager checks every
	-- REFINERY_ATTACK_POLL_SEC); the alert fires once per attack, and the
	-- siren every client loops runs until the last one leaves the radius.
	-- A wall that falls also plays its 3D collapse from where it stood,
	-- full out to WALL_COLLAPSE_FULL_VOLUME_STUDS and gone past
	-- WALL_COLLAPSE_SILENT_STUDS
	-- the box a monster measures its attack reach to is the wall's (or the
	-- gate's) box grown this much on every side (decided 2026-09-30), so a
	-- monster stands a stud further back while it beats on the wall
	MONSTER_ATTACK_PADDING_STUDS = 1,
	WALL_DESTROYED_MESSAGE_FORMAT = "Wall %d destroyed",
	REFINERY_ATTACKED_MESSAGE = "The Refinery is under attack",
	ALERT_DISPLAY_SEC = 4,
	REFINERY_ATTACK_RADIUS_STUDS = 20,
	REFINERY_ATTACK_POLL_SEC = 0.25,
	WALL_COLLAPSE_FULL_VOLUME_STUDS = 30,
	WALL_COLLAPSE_SILENT_STUDS = 250,
	-- what one Hammer swing adds and costs, by the structure's tier: both
	-- double a tier with the wall's HP (decided 2026-09-29: at 10 HP a swing
	-- a tier 3 wall took two minutes to rebuild), so a full repair takes the
	-- same swings at every tier and the same Iron per HP. A Tower is
	-- repaired at tier 1. One Iron per ten HP since the eighth playtest
	-- (2026-09-29): at two, rebuilding the two walls that fall most nights
	-- was 120 Iron, six Sentries, and no tower went up after day 3
	REPAIR_CHUNK_HP_BY_TIER = { 10, 20, 40 },
	REPAIR_CHUNK_IRON_BY_TIER = { 1, 2, 4 },
	REBUILD_STAND_SHARE = 1,
	-- the Hammer swings like the pick axe: how often a held input swings,
	-- the faster rate the server refuses (latency jitter never drops a
	-- legitimate swing), and how far the reticle reaches (5 studs past the
	-- pick axe, 2026-09-17: a wall is big, and 12 meant hugging it)
	HAMMER_HIT_INTERVAL_SEC = 0.45,
	HAMMER_HIT_COOLDOWN_SEC = 0.35,
	HAMMER_REACH_STUDS = 17,
	-- extra distance the server allows to the structure's bounds, covering
	-- movement latency
	HAMMER_REACH_TOLERANCE_STUDS = 6,
	GATE_DOOR_TWEEN_SEC = 0.6,
}
