--!strict

-- Frostbite Pass's waves (GDD "Setting Up Waves"), M29 and M30: the same
-- shape as Deadman's Canyon's, with its Normal generator settings on every
-- difficulty as a stand-in. The map has no camp yet, so nothing here is
-- played; the entry exists so every map has one (M42 authors the real
-- waves).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local MonsterKind = Enums.MonsterKind

return {
	SPAWN_RADIUS_STUDS = 15,
	LEASH_DISTANCE_STUDS = 1000,
	-- a generated night makes one group for every MIN_GROUP_DIFFICULTY it
	-- can pay, none worth less (so a small night is one big group, not a
	-- trickle), and its groups spawn over this long after night fall (the
	-- sky's NIGHT_SPAWN_SEC is separate)
	MIN_GROUP_DIFFICULTY = 80,
	-- the bar climbs 5 a night (2026-10-01): in the ninth playtest every
	-- group from night 7 to 13 was 80 to 130 points and died in under ten
	-- seconds while the next was still 25 s out, so a late night was only
	-- more of the same; night 13 now makes three groups of 140+ and the
	-- gap floor below lets them land on each other
	MIN_GROUP_DIFFICULTY_PER_NIGHT = 5,
	WAVE_SPAWN_LENGTH_SEC = 90,
	-- and no two of its groups in a row are further apart than this, so a
	-- night of two groups is not one group, a long lull, then the other
	MAX_TIME_BETWEEN_GROUPS_SEC = 30,
	-- and that limit tightens 2 s a night to a floor of 8 s (2026-10-01),
	-- so by night 12 the groups overlap instead of queueing
	GROUP_GAP_SHRINK_SEC_PER_NIGHT = 2,
	MIN_TIME_BETWEEN_GROUPS_SEC = 8,
	WAVES = {},
	-- Deadman's Canyon's curves, copied on 2026-09-28 so the balance audit
	-- holds this map to the same targets until it is authored for real
	GENERATOR = {
		[Enums.Difficulty.NORMAL] = {
			STARTING_DIFFICULTY = 22,
			DIFFICULTY_INCREASE_PER_WAVE = 16,
			GROWTH_PER_WAVE = 0.08,
			WAVE_DIFFICULTY_RANGE = 4,
			AVAILABLE_ENEMIES = {
				{
					KIND = MonsterKind.ZOMBIE_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.RUNNER_1,
					WAVE_UNLOCKED = 2,
				},
				{
					KIND = MonsterKind.BOMBER_1,
					WAVE_UNLOCKED = 3,
				},
				{
					KIND = MonsterKind.ZOMBIE_2,
					WAVE_UNLOCKED = 4,
				},
				{
					KIND = MonsterKind.BRUTE_1,
					WAVE_UNLOCKED = 4,
				},
				{
					KIND = MonsterKind.FLYER_1,
					WAVE_UNLOCKED = 5,
				},
				{
					KIND = MonsterKind.RUNNER_2,
					WAVE_UNLOCKED = 6,
				},
				{
					KIND = MonsterKind.BOMBER_2,
					WAVE_UNLOCKED = 7,
				},
				{
					KIND = MonsterKind.ZOMBIE_3,
					WAVE_UNLOCKED = 8,
				},
				{
					KIND = MonsterKind.BRUTE_2,
					WAVE_UNLOCKED = 8,
				},
				{
					KIND = MonsterKind.LAUNCHER_1,
					WAVE_UNLOCKED = 9,
				},
				{
					KIND = MonsterKind.FLYER_2,
					WAVE_UNLOCKED = 10,
				},
				{
					KIND = MonsterKind.RUNNER_3,
					WAVE_UNLOCKED = 11,
				},
				{
					KIND = MonsterKind.BOMBER_3,
					WAVE_UNLOCKED = 12,
				},
				{
					KIND = MonsterKind.BRUTE_3,
					WAVE_UNLOCKED = 12,
				},
				{
					KIND = MonsterKind.TITAN_1,
					WAVE_UNLOCKED = 11,
				},
				{
					KIND = MonsterKind.FLYER_3,
					WAVE_UNLOCKED = 15,
				},
				{
					KIND = MonsterKind.TITAN_2,
					WAVE_UNLOCKED = 20,
				},
			},
		},
		[Enums.Difficulty.HARD] = {
			-- a steeper climb from a low start, every kind two nights earlier
			STARTING_DIFFICULTY = 28,
			DIFFICULTY_INCREASE_PER_WAVE = 33,
			GROWTH_PER_WAVE = 0.03,
			WAVE_DIFFICULTY_RANGE = 4,
			AVAILABLE_ENEMIES = {
				{
					KIND = MonsterKind.ZOMBIE_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.RUNNER_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.BOMBER_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.ZOMBIE_2,
					WAVE_UNLOCKED = 2,
				},
				{
					KIND = MonsterKind.BRUTE_1,
					WAVE_UNLOCKED = 2,
				},
				{
					KIND = MonsterKind.FLYER_1,
					WAVE_UNLOCKED = 3,
				},
				{
					KIND = MonsterKind.RUNNER_2,
					WAVE_UNLOCKED = 4,
				},
				{
					KIND = MonsterKind.BOMBER_2,
					WAVE_UNLOCKED = 5,
				},
				{
					KIND = MonsterKind.ZOMBIE_3,
					WAVE_UNLOCKED = 6,
				},
				{
					KIND = MonsterKind.BRUTE_2,
					WAVE_UNLOCKED = 6,
				},
				{
					KIND = MonsterKind.LAUNCHER_1,
					WAVE_UNLOCKED = 7,
				},
				{
					KIND = MonsterKind.FLYER_2,
					WAVE_UNLOCKED = 8,
				},
				{
					KIND = MonsterKind.RUNNER_3,
					WAVE_UNLOCKED = 9,
				},
				{
					KIND = MonsterKind.BOMBER_3,
					WAVE_UNLOCKED = 10,
				},
				{
					KIND = MonsterKind.BRUTE_3,
					WAVE_UNLOCKED = 10,
				},
				{
					KIND = MonsterKind.TITAN_1,
					WAVE_UNLOCKED = 9,
				},
				{
					KIND = MonsterKind.FLYER_3,
					WAVE_UNLOCKED = 13,
				},
				{
					KIND = MonsterKind.TITAN_2,
					WAVE_UNLOCKED = 18,
				},
			},
		},
		[Enums.Difficulty.NIGHTMARE] = {
			-- the same climb from a higher start, every kind four nights earlier
			STARTING_DIFFICULTY = 34,
			DIFFICULTY_INCREASE_PER_WAVE = 42,
			GROWTH_PER_WAVE = 0.02,
			WAVE_DIFFICULTY_RANGE = 5,
			AVAILABLE_ENEMIES = {
				{
					KIND = MonsterKind.ZOMBIE_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.RUNNER_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.BOMBER_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.ZOMBIE_2,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.BRUTE_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.FLYER_1,
					WAVE_UNLOCKED = 1,
				},
				{
					KIND = MonsterKind.RUNNER_2,
					WAVE_UNLOCKED = 2,
				},
				{
					KIND = MonsterKind.BOMBER_2,
					WAVE_UNLOCKED = 3,
				},
				{
					KIND = MonsterKind.ZOMBIE_3,
					WAVE_UNLOCKED = 4,
				},
				{
					KIND = MonsterKind.BRUTE_2,
					WAVE_UNLOCKED = 4,
				},
				{
					KIND = MonsterKind.LAUNCHER_1,
					WAVE_UNLOCKED = 5,
				},
				{
					KIND = MonsterKind.FLYER_2,
					WAVE_UNLOCKED = 6,
				},
				{
					KIND = MonsterKind.RUNNER_3,
					WAVE_UNLOCKED = 7,
				},
				{
					KIND = MonsterKind.BOMBER_3,
					WAVE_UNLOCKED = 8,
				},
				{
					KIND = MonsterKind.BRUTE_3,
					WAVE_UNLOCKED = 8,
				},
				{
					KIND = MonsterKind.TITAN_1,
					WAVE_UNLOCKED = 7,
				},
				{
					KIND = MonsterKind.FLYER_3,
					WAVE_UNLOCKED = 11,
				},
				{
					KIND = MonsterKind.TITAN_2,
					WAVE_UNLOCKED = 16,
				},
			},
		},
	},
}
