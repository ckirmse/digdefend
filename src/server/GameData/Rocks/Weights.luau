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
	-- tierBias is authored in this range (one per ore tier); hardness runs
	-- from MIN_CENTER to the stone tier count (FILLER_ORDER length). Outside
	-- the range the generator warns and clamps
	MIN_CENTER = 1.0,
	MAX_CENTER = 4.0,
}
