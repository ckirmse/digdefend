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
-- each kind's first night. Difficulty is these parameters, never a stat
-- multiplier. The curves were set from the balance sheet on 2026-09-28
-- (docs/balance-plan.md) against the wall progression the designer
-- asked for: on Normal, night 2 dents a wall, night 3 nearly breaks one,
-- night 4 breaks one (the second playtest, at 27 / 27 / 10%, broke a
-- wall on night 2 and three structures on night 3); Hard and Nightmare
-- bring Runners, Bombers, and Brutes on night 2 and break a wall that
-- night, and are the same unlock order shifted two and four nights
-- earlier, each above the easier tier through its target night. A small
-- start keeps Normal's first nights gentle and the increment makes night
-- 10 a real fight; every tier climbs mostly by increment, so its last
-- nights stay under a solo crew's ceiling once backpack trips eat the
-- late days. Normal starts at 22 since 2026-09-29, when the machine gun
-- lost a fifth of its damage and Bombers were priced for their blast,
-- so night 3 still only nearly breaks a wall. The sixth playtest (2026-09-29) found the waves too soft
-- while mining felt right, so the group minimum doubled (nights 2 to 5
-- arrive as one group, which is what breaks a wall), and the run grew
-- to 15 nights (Hard 18, Nightmare 21): a crew's power plateaus once
-- the tower cap and the last pick are reached, so every tier now climbs
-- by increment with only a few percent of compounding, or nights 12 and
-- on outgrow the ceiling. The balance sheet (BalanceAudit at
-- startup, the Monsters dev panel) checks it all.
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
	MIN_GROUP_DIFFICULTY = 80,
	-- 90 and 30 since the eighth playtest (2026-09-29, lost on night 8):
	-- two groups 10 s apart were one wave, and a wall fell before the
	-- gunner could turn to the second; a two-group night is now 0 and
	-- 30 s, a five-group night spreads over about 80 s
	WAVE_SPAWN_LENGTH_SEC = 90,
	-- and no two of its groups in a row are further apart than this, so a
	-- night of two groups is not one group, a long lull, then the other
	MAX_TIME_BETWEEN_GROUPS_SEC = 30,
	WAVES = {},
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
