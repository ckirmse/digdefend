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

-- one GameData/Waves/<Map> file
export type MapWaves = {
	SPAWN_RADIUS_STUDS: number,
	LEASH_DISTANCE_STUDS: number,
	WAVES: { Wave },
}

type IndexedGroup = {
	index: number,
	group: Group,
}

-- the wave authored for the night; a night without one replays the latest
-- authored night before it, and nil when none comes before it
function WaveRules.waveForNight(waves: { Wave }, night: number): Wave?
	local best: Wave? = nil
	for _, wave in waves do
		if wave.NIGHT == night then
			return wave
		end
		if wave.NIGHT < night and (best == nil or wave.NIGHT > best.NIGHT) then
			best = wave
		end
	end
	return best
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
