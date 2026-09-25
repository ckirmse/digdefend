--!strict

-- Deadman's Canyon's waves (GDD "Setting Up Waves"), M29 and M30.
-- SPAWN_RADIUS_STUDS scatters a group around its spawn part
-- (Camp.MonsterSpawns, by number); LEASH_DISTANCE_STUDS is how far a
-- monster may leave the Wave Area after a player, set very high to start
-- so there is no safe spot just past it.
-- WAVES holds hand-authored waves, one per night (NIGHT, then GROUPS of
-- ENEMIES at SPAWN_LOCATION, SPAWN_TIME_SEC after night falls); every
-- night without one is generated (WaveGenerator) from GENERATOR, one
-- entry per Enums.Difficulty: the night-1 difficulty, how much each night
-- adds and by what share it compounds (the crew's power compounds, so the
-- night must too; decided 2026-09-24), how close a wave must land, and
-- each kind's first night. Difficulty is these
-- parameters, never a stat multiplier: Hard starts higher, compounds
-- faster, and unlocks every kind two nights earlier than Normal,
-- Nightmare four. On Normal the target runs 10, 16, 23, 31, 41 ... 84 on
-- night 8, 190 on night 12. Every number is
-- first-pass tuning for M34's playtest.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local MonsterKind = Enums.MonsterKind

return {
	SPAWN_RADIUS_STUDS = 15,
	LEASH_DISTANCE_STUDS = 1000,
	-- a generated night makes one group for every MIN_GROUP_DIFFICULTY it
	-- can pay, none worth less (so a small night is one big group, not a
	-- trickle), and its groups spawn over this long after night fall (the
	-- sky's NIGHT_SPAWN_SEC is separate). The crew's wave multiplier scales
	-- this too (2026-09-25), so a crew gets the solo group count, bigger
	MIN_GROUP_DIFFICULTY = 40,
	WAVE_SPAWN_LENGTH_SEC = 60,
	-- and no two of its groups in a row are further apart than this, so a
	-- night of two groups is not one group, a long lull, then the other
	MAX_TIME_BETWEEN_GROUPS_SEC = 10,
	WAVES = {},
	GENERATOR = {
		[Enums.Difficulty.NORMAL] = {
			STARTING_DIFFICULTY = 18,
			DIFFICULTY_INCREASE_PER_WAVE = 18,
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
			STARTING_DIFFICULTY = 14,
			DIFFICULTY_INCREASE_PER_WAVE = 5,
			GROWTH_PER_WAVE = 0.15,
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
					WAVE_UNLOCKED = 12,
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
			STARTING_DIFFICULTY = 18,
			DIFFICULTY_INCREASE_PER_WAVE = 6,
			GROWTH_PER_WAVE = 0.18,
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
					WAVE_UNLOCKED = 10,
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
