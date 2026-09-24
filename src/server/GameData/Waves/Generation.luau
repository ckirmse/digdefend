--!strict

-- How the wave generator rolls (GDD "Creating Waves"), M30: the same on
-- every map, since a map is tuned through its own GENERATOR table in
-- GameData/Waves/<Map>. Read by MonsterWaveManager into WaveGenerator.
return {
	-- each group's share of the night's difficulty is weighted between
	-- these, so some groups are big and some small
	GROUP_WEIGHT_MIN = 0.5,
	GROUP_WEIGHT_MAX = 1.5,
	-- the last group spawns this far into the spawn window (NIGHT_SPAWN_SEC)
	LAST_GROUP_WINDOW_SHARE = 0.85,
	-- every group but the first moves this far either way from its even spacing
	SPAWN_TIME_JITTER_SEC = 4,
}
