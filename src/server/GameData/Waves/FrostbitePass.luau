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
	MIN_GROUP_DIFFICULTY = 40,
	WAVE_SPAWN_LENGTH_SEC = 45,
	-- and no two of its groups in a row are further apart than this, so a
	-- night of two groups is not one group, a long lull, then the other
	MAX_TIME_BETWEEN_GROUPS_SEC = 20,
	WAVES = {},
	GENERATOR = {
		[Enums.Difficulty.NORMAL] = {
			STARTING_DIFFICULTY = 10,
			DIFFICULTY_INCREASE_PER_WAVE = 4,
			GROWTH_PER_WAVE = 0.12,
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
					WAVE_UNLOCKED = 14,
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
			STARTING_DIFFICULTY = 10,
			DIFFICULTY_INCREASE_PER_WAVE = 4,
			GROWTH_PER_WAVE = 0.12,
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
					WAVE_UNLOCKED = 14,
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
		[Enums.Difficulty.NIGHTMARE] = {
			STARTING_DIFFICULTY = 10,
			DIFFICULTY_INCREASE_PER_WAVE = 4,
			GROWTH_PER_WAVE = 0.12,
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
					WAVE_UNLOCKED = 14,
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
	},
}
