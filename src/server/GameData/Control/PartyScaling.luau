--!strict

-- Party scaling (GDD "Party scaling", decided 2026-09-12): the mine is fixed
-- and rock HP never scales; a bigger crew digs faster and meets bigger
-- nights (M30). Iron and Gold are per player, so their drops scale with the
-- party so each player's upgrade curve holds; Diamonds and Uranium are
-- shared and never scaled. Indexed by player count, sampled at dawn (M28)
-- and only ever decreasing during a run. Consumers: ore drops (M19), the
-- uranium target (M20), the waves (M30): the generator aims for the
-- night's difficulty times WAVE_DIFFICULTY_MULTIPLIER (an authored wave's
-- counts are multiplied instead), and every monster spawns with its HP
-- times ENEMY_HP_MULTIPLIER. Sublinear: six players are not six times as
-- effective, so the night grows less than the crew.
return {
	ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.15, 1.3, 1.45, 1.6, 1.75 },
	-- the mine's solo uraniumTarget times this is the rescue target (M20).
	-- Steep (decided 2026-09-25): a crew digs about as many times faster as
	-- it is large, so a modest table let six players finish before the
	-- nights escalated while a solo run had to survive night 8 and beyond;
	-- near-linear keeps every crew size in the mine for a similar number of
	-- nights. The last entry is the worst case the generator checks a
	-- mine's authored uranium against (MineManager, map_tools)
	URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.5, 2.0, 2.5, 3.0, 3.5 },
	-- matched to the uranium table (2026-09-25) so a big crew meets nights
	-- as much bigger as its target is; the map's MIN_GROUP_DIFFICULTY is
	-- multiplied by the same number, so a crew gets the solo number of
	-- groups, each that much bigger, rather than a trickle of small ones
	WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.5, 2.0, 2.5, 3.0, 3.5 },
	ENEMY_HP_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.1, 1.2, 1.3, 1.4, 1.5 },
}
