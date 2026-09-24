--!strict

-- Pure rules for running a night's wave (GDD "Creating Waves"), M29: which
-- authored wave a night plays, its groups in spawn order, how far the
-- remaining groups move up when the field is empty so there is never dead
-- time, and where in a spawn's radius a monster appears. MonsterWaveManager
-- runs the wave with these; the wave generator (M30) will add its own.
local WaveRules = {}

export type EnemyCount = {
	KIND: number,
	COUNT: number,
}

export type Group = {
	ENEMIES: { EnemyCount },
	SPAWN_LOCATION: number,
	SPAWN_TIME_SEC: number,
}

export type Wave = {
	NIGHT: number,
	GROUPS: { Group },
}

-- one GameData/Waves/<Map> file; GENERATOR is WaveGenerator.Settings per
-- Enums.Difficulty, typed loosely here so WaveRules stays below WaveGenerator
export type MapWaves = {
	SPAWN_RADIUS_STUDS: number,
	LEASH_DISTANCE_STUDS: number,
	WAVES: { Wave },
	-- a generated night makes another group only once it can afford this
	-- much for it; and how long after night fall its last group spawns
	MIN_GROUP_DIFFICULTY: number,
	WAVE_SPAWN_LENGTH_SEC: number,
	-- a generated night's groups are never further apart than this
	MAX_TIME_BETWEEN_GROUPS_SEC: number,
	GENERATOR: { [number]: any },
}

type IndexedGroup = {
	index: number,
	group: Group,
}

-- the wave authored for the night, nil when there is none (M30: such a
-- night is generated instead of replaying an earlier one)
function WaveRules.waveForNight(waves: { Wave }, night: number): Wave?
	for _, wave in waves do
		if wave.NIGHT == night then
			return wave
		end
	end
	return nil
end

-- an authored wave scaled to the party: every count times the multiplier,
-- rounded half up, never below one (the party's lever on hand-made nights)
function WaveRules.scaleWave(wave: Wave, multiplier: number): Wave
	local groups = {}
	for _, group in wave.GROUPS do
		local enemies = {}
		for _, entry in group.ENEMIES do
			table.insert(enemies, {
				KIND = entry.KIND,
				COUNT = math.max(1, math.floor(entry.COUNT * multiplier + 0.5)),
			})
		end
		table.insert(groups, {
			ENEMIES = enemies,
			SPAWN_LOCATION = group.SPAWN_LOCATION,
			SPAWN_TIME_SEC = group.SPAWN_TIME_SEC,
		})
	end
	return {
		NIGHT = wave.NIGHT,
		GROUPS = groups,
	}
end

-- the groups by spawn time; groups at the same time keep their authored order
function WaveRules.orderedGroups(wave: Wave): { Group }
	local indexed: { IndexedGroup } = {}
	for index, group in wave.GROUPS do
		table.insert(indexed, {
			index = index,
			group = group,
		})
	end
	table.sort(
		indexed,
		function(first: IndexedGroup, second: IndexedGroup): boolean
			if first.group.SPAWN_TIME_SEC ~= second.group.SPAWN_TIME_SEC then
				return first.group.SPAWN_TIME_SEC < second.group.SPAWN_TIME_SEC
			end
			return first.index < second.index
		end
	)
	local ordered = {}
	for _, entry in indexed do
		table.insert(ordered, entry.group)
	end
	return ordered
end

-- when a group is due: its time after night fall, less what the wave has
-- already moved up
function WaveRules.dueTime(group: Group, nightStartTime: number, shiftSec: number): number
	return nightStartTime + group.SPAWN_TIME_SEC - shiftSec
end

-- the field is empty and the next group is still waiting: how much every
-- remaining group moves up so the next one spawns now (decided 2026-09-23)
function WaveRules.shiftForEmptyField(nextDueTime: number, now: number): number
	return math.max(0, nextDueTime - now)
end

-- a flat point within the radius of a spawn, spread evenly over the disc
function WaveRules.scatter(center: Vector3, radiusStuds: number, random: Random): Vector3
	local angle = random:NextNumber(0, 2 * math.pi)
	local distance = radiusStuds * math.sqrt(random:NextNumber())
	return Vector3.new(center.X + math.cos(angle) * distance, center.Y, center.Z + math.sin(angle) * distance)
end

-- every monster a group spawns, in its authored order
function WaveRules.groupKinds(group: Group): { number }
	local kinds = {}
	for _, entry in group.ENEMIES do
		for _ = 1, math.max(0, math.floor(entry.COUNT)) do
			table.insert(kinds, entry.KIND)
		end
	end
	return kinds
end

return WaveRules
