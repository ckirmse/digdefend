--!strict

-- Tuning for the weight kernel (GDD "The weight kernel"). SPREAD controls how
-- much neighbouring filler rocks and ore tiers bleed into each other. At 1.5 a
-- chamber never mixes more than three rock types; at 2.0 all four appear at
-- mid hardness. Never drop it to 1.0: a whole-number hardness then yields a
-- single rock type, which reads as flat. Tune once, globally, after seeing a
-- mine in-game.
return {
	SPREAD = 1.5,
	-- hardness and tierBias are authored in this range; outside it the
	-- generator warns and clamps
	MIN_CENTER = 1.0,
	MAX_CENTER = 4.0,
}
