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
	-- near-linear and then some (2026-09-28, docs/balance-plan.md): the
	-- balance sheet has a crew stripping every zone it passes and hunting
	-- humming uranium, so a crew of four holds four times solo's uranium
	-- by day 10 and the target must match or the run ends early
	URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 2.5, 4.5, 8.0, 10.0, 12.0 },
	-- matched to the uranium table (2026-09-25) so a big crew meets nights
	-- as much bigger as its target is; the map's MIN_GROUP_DIFFICULTY is
	-- multiplied by the same number, so a crew gets the solo number of
	-- groups, each that much bigger, rather than a trickle of small ones
	-- sublinear (2026-09-28): the camp's tower cap is shared, so a big
	-- crew's towers plateau where a solo player's do and only its posts
	-- and faster Iron grow with it. Set so the biggest crew can still hold
	-- Nightmare's final wave; on Normal a crew keeps more margin than solo
	WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.6, 2.1, 2.4, 2.6, 2.8 },
	-- 1 everywhere (decided 2026-09-28, docs/balance-plan.md): a crew's
	-- size scales the night through the wave budget only, never through a
	-- monster's stats, so the two never compound (they did: four players
	-- met 3.25x solo HP). The table stays so a map can bring it back
	ENEMY_HP_MULTIPLIER_BY_PLAYER_COUNT = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
}
