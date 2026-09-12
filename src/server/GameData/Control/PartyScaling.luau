--!strict

-- Party scaling (GDD "Party scaling", decided 2026-09-12): the mine is fixed
-- and rock HP never scales; a bigger crew digs faster and meets bigger
-- nights (M30). Iron and Gold are per player, so their drops scale with the
-- party so each player's upgrade curve holds; Diamonds and Uranium are
-- shared and never scaled. Indexed by player count, sampled at dawn (M28)
-- and only ever decreasing during a run. First consumer is ore drops (M19).
return {
	ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.15, 1.3, 1.45, 1.6, 1.75 },
}
