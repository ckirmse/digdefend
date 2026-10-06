--!strict

-- Tuning for the weight kernel (GDD "The weight kernel"). SPREAD controls how
-- much neighbouring stone tiers and ore tiers bleed into each other. At 1.2
-- a whole-number hardness is 75% its own tier with 12% of each neighbour,
-- so a zone reads as one tier with the occasional harder block (decided
-- 2026-09-15; 1.5 put too much tier 2 next to the entrance). Never drop it
-- to 1.0: a whole-number hardness then yields a single rock type, which
-- reads as flat. Tune once, globally, after seeing a mine in-game.
return {
	SPREAD = 1.2,
	-- blocks from the mine mouth each ore tier may first appear (decided
	-- 2026-09-28: a Gold II vein a few blocks in let a player buy three
	-- upgrades on day 1). Tier 2 from the back of zone 1, tier 3 from
	-- zone 3, tier 4 from zone 4, tier 5 from zone 5 on Deadman's Canyon (zone
	-- 4's last row is depth 96, so tier 5 opens at 97 and never leaks into it)
	TIER_MIN_DEPTH_BLOCKS = { 0, 14, 44, 68, 97 },
	-- tierBias is authored in this range (one per ore tier); hardness runs
	-- from MIN_CENTER to the stone tier count (FILLER_ORDER length). Outside
	-- the range the generator warns and clamps
	MIN_CENTER = 1.0,
	-- 5 since the fifth ore tier (2026-10-06); the ore tier count
	MAX_CENTER = 5.0,
}
