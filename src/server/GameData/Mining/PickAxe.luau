--!strict

-- The pick axe (GDD "Pick Axe", "Mining Rock"). Six levels since
-- 2026-10-06 (five by the 2026-09-15 decision; the sixth is the late Gold
-- sink and one-shots tier 5 stone, M34), but the list length is the only
-- thing that fixes it. Everyone is level 1 until
-- the Mining Supplies Store (M21).
return {
	-- HP removed from a rock per hit, by pick axe level: each level triples
	-- the last and costs three times as much (decided 2026-09-28: the mine
	-- is a simulator, small numbers first, every upgrade a jump, big
	-- numbers by the end; rock HP quadruples a tier to meet it)
	DAMAGE_BY_LEVEL = { 5, 15, 45, 135, 400, 1200 },
	-- how often a held input swings
	HIT_INTERVAL_SEC = 0.45,
	-- the server refuses hits faster than this; a little under the client
	-- interval so latency jitter never drops a legitimate swing
	HIT_COOLDOWN_SEC = 0.35,
	-- how far the reticle reaches; 12 studs is the 3-block pickaxe reach the
	-- mine generator assumes
	REACH_STUDS = 12,
	-- extra distance the server allows between the player and the block
	-- centre, covering the block's half size and movement latency
	REACH_TOLERANCE_STUDS = 6,
}
