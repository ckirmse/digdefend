--!strict

-- Frostbite Pass's waves (GDD "Setting Up Waves"), M29: the same shape as
-- Deadman's Canyon's. The map has no camp yet, so nothing here is played;
-- the entry exists so every map has one (M42 authors the real waves).
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
						{ KIND = MonsterKind.ZOMBIE_1, COUNT = 10 },
					},
					SPAWN_LOCATION = 1,
					SPAWN_TIME_SEC = 0,
				},
			},
		},
	},
}
