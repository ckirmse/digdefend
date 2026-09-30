--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The balance targets and the model's assumptions (docs/balance-plan.md,
-- decided 2026-09-28). BalanceModel (shared, pure) turns GameData into a
-- night-by-night sheet of income against threat; BalanceAudit runs it for
-- every map, difficulty, and crew size at gameplay startup and warns when
-- a target is missed, so a tuning change shows its effect before a
-- playtest. The targets are the designer's answers; the assumptions are
-- the model's guesses about how people play, to be corrected from the run
-- reports, never from the data they are checked against.
return {
	-- the night the run should end on, solo (about 7.5 minutes a cycle);
	-- the uranium target and the curve are tuned so a crew of any size
	-- gets there in the same number of nights. Ten nights felt too short
	-- in the sixth playtest (2026-09-29), so Normal is 15 and the harder
	-- tiers step above it; Nightmare is 20, not 21, because a solo crew's
	-- power plateaus at the tower cap and the last pick, and no curve
	-- that stays above Hard's is holdable on a day-21 final wave. Hard
	-- and Nightmare are provisional until Normal feels right in play
	TARGET_NIGHTS = {
		[Enums.Difficulty.NORMAL] = 15,
		[Enums.Difficulty.HARD] = 18,
		[Enums.Difficulty.NIGHTMARE] = 20,
	},
	-- the first night the leak should break a tier 1 wall segment, solo
	-- (decided 2026-09-28): the night two before dents one, the night
	-- before nearly breaks one. The model's leak is what the crew cannot
	-- kill before it walks to the wall. This replaced "the first night the
	-- free weapons find difficult" the same day: it is the same intent,
	-- measured by what the player sees. The sheet still prints the night
	-- the free weapons' slack falls under TOWER_NEEDED_SLACK
	-- Hard and Nightmare bring Runners, Bombers, and Brutes on night 2,
	-- and those break a wall whatever the budget, so their breach is
	-- night 2 (2026-09-28, the simulator pass)
	BREACH_NIGHT = {
		[Enums.Difficulty.NORMAL] = 4,
		[Enums.Difficulty.HARD] = 2,
		[Enums.Difficulty.NIGHTMARE] = 2,
	},
	-- Gold a player should hold by the end of night 1 (decided 2026-09-28):
	-- enough for a first mining or post upgrade, and about one a day after
	-- (20 since the upgrade ladders doubled in price and effect the same
	-- day, with gold rock yields doubled to keep pace)
	GOLD_BY_NIGHT_1 = 20,
	-- a run is on target when the uranium is refined within this many days
	-- of TARGET_NIGHTS; a crew gets more room, since how fast a crew
	-- strips a zone is the model's least certain guess
	TARGET_NIGHT_TOLERANCE = 1,
	CREW_TARGET_NIGHT_TOLERANCE = 2,
	-- crew sizes the audit checks
	AUDIT_CREW_SIZES = { 1, 4, 6 },
	-- maps held to the targets; a map still being authored is left out
	-- until its mine and waves are its own (the dev panel's sheet works
	-- for any map)
	AUDITED_MAPS = { Enums.Map.DEADMANS_CANYON },
	-- a crew is on target when it reaches the uranium target within this
	-- many nights of the solo run
	CREW_PARITY_NIGHTS = 2,
	-- nights the audit simulates past the longest target, so the final
	-- wave and the overrun are visible too
	AUDIT_EXTRA_NIGHTS = 4,

	ASSUMPTIONS = {
		-- seconds of a day not spent mining or walking ore to the refinery:
		-- shopping, building, dusk (the walks themselves are modelled from
		-- the backpack, the boots, and the tunnel's depth)
		-- (40 since the fifth playtest, 2026-09-28: the log put pick 3 on
		-- day 3 and 40 uranium on day 4, and the fit below reproduces it;
		-- 60 since 2026-09-29, when the day grew from 300 to 320 s and the
		-- extra 20 s of sunset are for setting up defenses, not mining)
		DAY_OVERHEAD_SEC = 60,
		-- studs from the refinery to the mine mouth on Deadman's Canyon
		-- (measured 2026-09-28: 64); the walk grows by the tunnel's depth
		REFINERY_TO_ENTRANCE_STUDS = 64,
		-- players dig toward ore they can see rather than through filler at
		-- random, so ore per HP mined is higher than the zone's average
		-- (2.5 put the third playtest's day-1 Iron where it was seen, with
		-- seven-block veins; 0.8 since the seventh playtest, 2026-09-29:
		-- single-block iron in a gold-rich mine yielded about 190 Iron by
		-- night 10 against the 480 the old value predicted)
		ORE_SELECTIVITY = 0.8,
		-- gold is dug for once it is worth digging for (2.0 fits the fifth
		-- playtest: about 370 Gold by the end of day 3)
		GOLD_SELECTIVITY = 2.0,
		-- a crew moves on to the next zone once it has mined this share of
		-- the zone's HP; it tunnels through, it never clears. The least
		-- known number here: the run report calibrates it
		ZONE_ADVANCE_SHARE = 0.15,
		-- share of a tower's paper DPS that lands: monsters are out of range
		-- part of the night and shots overkill
		TOWER_COVERAGE = 0.6,
		-- share of the night a player is firing rather than moving,
		-- repairing, or taking cover (0.5 makes the first playtest's "night
		-- 4 felt dangerous" the night the free weapons alone stop clearing)
		WEAPON_UPTIME = 0.5,
		-- a night is cleared on time when the wave's HP is gone this long
		-- after the last group spawns
		CLEAR_SLACK_SEC = 60,
		-- share of Iron the crew puts into towers; the rest is walls, repairs,
		-- and traps
		DEFENSE_IRON_SHARE = 0.8,
		-- how each player splits their Gold: the pick axe, the backpack, the
		-- boots, their post's upgrades; the rest is consumables
		PICK_AXE_GOLD_SHARE = 0.4,
		BACKPACK_GOLD_SHARE = 0.25,
		BOOTS_GOLD_SHARE = 0.1,
		POST_GOLD_SHARE = 0.25,
		-- the share of a post's paper DPS a player gets out of it: shots
		-- that miss, and the trigger held into an overheat or released
		-- early (the machine-gun post is the yardstick for player damage,
		-- decided 2026-09-28; its overheat is the main limit)
		POST_EFFECTIVENESS = 0.6,
		-- seconds a monster walks from its spawn to the camp wall
		WALL_WALK_SEC = 20,
		-- the leak spreads itself over about this many wall segments and
		-- the gate (the first playtest's night 3 broke two walls and the
		-- gate); the breach is the one that takes its share
		WALL_SEGMENTS_HIT = 3,
		-- uranium hums within a few blocks and a crew hunts it, so it is
		-- found more readily than the zone's average ore, but not so much
		-- that a crew strips a zone's supply in a day
		-- (10 fits the fifth playtest: 40 uranium by day 4)
		URANIUM_SELECTIVITY = 10.0,
		-- the free weapons' slack under which a night feels difficult
		TOWER_NEEDED_SLACK = 1.75,
		-- a crew strips a zone more than it advances: the tunnel front moves
		-- with the crew's HP to this power (six players advance about three
		-- times as fast as one, not six)
		CREW_ADVANCE_EXPONENT = 0.6,
	},
}
