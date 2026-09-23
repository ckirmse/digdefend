--!strict

-- Deadman's Canyon's waves (GDD "Setting Up Waves"), M29. SPAWN_RADIUS_STUDS
-- scatters a group around its spawn part (Camp.MonsterSpawns, by number);
-- LEASH_DISTANCE_STUDS is how far a monster may leave the Wave Area after
-- a player, set very high to start so there is no safe spot just past it.
-- WAVES holds the hand-authored waves, one per night: each group spawns
-- SPAWN_TIME_SEC after night falls at spawn SPAWN_LOCATION, and ENEMIES
-- lists how many of which kinds. M29 has one test wave; a night without an
-- entry replays the last authored one until the wave generator exists (M30).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local MonsterKind = Enums.MonsterKind

return {
	SPAWN_RADIUS_STUDS = 15,
	LEASH_DISTANCE_STUDS = 1000,
	WAVES = {
		{
			NIGHT = 1,
			GROUPS = {
				{
					ENEMIES = {
						{ KIND = MonsterKind.ZOMBIE_1, COUNT = 12 },
					},
					SPAWN_LOCATION = 2,
					SPAWN_TIME_SEC = 0,
				},
				{
					ENEMIES = {
						{ KIND = MonsterKind.RUNNER_1, COUNT = 4 },
					},
					SPAWN_LOCATION = 1,
					SPAWN_TIME_SEC = 15,
				},
				{
					ENEMIES = {
						{ KIND = MonsterKind.BOMBER_1, COUNT = 2 },
						{ KIND = MonsterKind.ZOMBIE_1, COUNT = 6 },
					},
					SPAWN_LOCATION = 3,
					SPAWN_TIME_SEC = 30,
				},
				{
					ENEMIES = {
						{ KIND = MonsterKind.FLYER_1, COUNT = 2 },
					},
					SPAWN_LOCATION = 2,
					SPAWN_TIME_SEC = 45,
				},
				{
					ENEMIES = {
						{ KIND = MonsterKind.BRUTE_1, COUNT = 2 },
						{ KIND = MonsterKind.LAUNCHER_1, COUNT = 1 },
						{ KIND = MonsterKind.ZOMBIE_2, COUNT = 10 },
					},
					SPAWN_LOCATION = 2,
					SPAWN_TIME_SEC = 70,
				},
			},
		},
	},
}
