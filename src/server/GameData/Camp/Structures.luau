--!strict

-- Camp structures with HP (GDD "Walls", "Gate", "Refinery", "Wall Repair"),
-- M23. Per kind: max HP by tier (the list length fixes the top tier).
-- Repair works like mining (decided 2026-09-17): in Repair Mode every Hammer
-- swing at a damaged structure adds REPAIR_CHUNK_HP for REPAIR_CHUNK_IRON, a
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
		-- never bought: the Refinery's tier is the Camp Level, so Diamonds
		-- toughen it (one entry per camp level)
		[Enums.StructureKind.REFINERY] = {
			MAX_HP_BY_TIER = { 1000, 1500, 2200, 3000 },
		},
	},
	FORTIFICATION_UPGRADE_IRON_TO_TIER = { 0, 150, 400 },
	FORTIFICATION_DONATION_IRON = 10,
	WORKBENCH_PROMPT_ACTION_TEXT = "Donate Iron",
	WORKBENCH_PROMPT_OBJECT_TEXT = "Workbench",
	WORKBENCH_PROMPT_MAX_DISTANCE_STUDS = 10,
	-- alerts (2026-09-25): a wall falling and the Refinery coming under attack
	-- are announced to everyone in the red alert box, for ALERT_DISPLAY_SEC.
	-- The Refinery is under attack while any live monster is within
	-- REFINERY_ATTACK_RADIUS_STUDS of its box (MonsterManager checks every
	-- REFINERY_ATTACK_POLL_SEC); the alert fires once per attack, and the
	-- siren every client loops runs until the last one leaves the radius.
	-- A wall that falls also plays its 3D collapse from where it stood,
	-- full out to WALL_COLLAPSE_FULL_VOLUME_STUDS and gone past
	-- WALL_COLLAPSE_SILENT_STUDS
	WALL_DESTROYED_MESSAGE_FORMAT = "Wall %d destroyed",
	REFINERY_ATTACKED_MESSAGE = "The Refinery is under attack",
	ALERT_DISPLAY_SEC = 4,
	REFINERY_ATTACK_RADIUS_STUDS = 20,
	REFINERY_ATTACK_POLL_SEC = 0.25,
	WALL_COLLAPSE_FULL_VOLUME_STUDS = 30,
	WALL_COLLAPSE_SILENT_STUDS = 250,
	REPAIR_CHUNK_HP = 10,
	REPAIR_CHUNK_IRON = 2,
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
