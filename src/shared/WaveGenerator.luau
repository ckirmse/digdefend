--!strict

-- Generates a night's wave from a map's parameters (GDD "Creating Waves",
-- group rule decided 2026-09-23), M30. Pure: data and a Random in, a
-- WaveRules.Wave out, so any night on any map can be previewed and unit
-- tested without playing. The target difficulty climbs each night: a
-- linear step (DifficultyIncreasePerWave) compounded by a percent
-- (GrowthPerWave, decided 2026-09-24: the crew's power compounds, so the
-- night must too), times the party's wave multiplier; it is split into
-- as many groups as it can pay the map's MIN_GROUP_DIFFICULTY for (one
-- knob, decided 2026-09-24), of uneven shares none below that minimum,
-- each filled by drawing unlocked kinds at random until nothing fits
-- (no one-kind rule, decided 2026-09-24), topped up or trimmed to within
-- WaveDifficultyRange of the target, spread over the map's
-- WAVE_SPAWN_LENGTH_SEC with the biggest group last, and sent to random
-- spawns, never the same one
-- twice running. Difficulty (Normal, Hard, Nightmare) is a different set
-- of parameters per map, never a stat multiplier (decided 2026-09-24).
local WaveRules = require(script.Parent.WaveRules)

local WaveGenerator = {}

export type AvailableEnemy = {
	KIND: number,
	-- the first night this kind may appear
	WAVE_UNLOCKED: number,
}

-- one difficulty's entry in a GameData/Waves/<Map> GENERATOR table
export type Settings = {
	STARTING_DIFFICULTY: number,
	DIFFICULTY_INCREASE_PER_WAVE: number,
	-- the target also grows by this share every night (0.12 is 12%); 0
	-- keeps the climb linear
	GROWTH_PER_WAVE: number,
	WAVE_DIFFICULTY_RANGE: number,
	AVAILABLE_ENEMIES: { AvailableEnemy },
}

-- GameData/Waves/Generation: how the rule rolls, the same on every map
export type Tuning = {
	GROUP_WEIGHT_MIN: number,
	GROUP_WEIGHT_MAX: number,
	LAST_GROUP_WINDOW_SHARE: number,
	SPAWN_TIME_JITTER_SEC: number,
}

export type Input = {
	settings: Settings,
	tuning: Tuning,
	night: number,
	-- the party's wave multiplier (PartyScaling), 1 for a solo run
	difficultyMultiplier: number,
	-- GameData/Monsters/Roster DIFFICULTY_VALUE by kind
	difficultyValueByKind: { [number]: number },
	spawnNumbers: { number },
	-- the map's rule: a group is made for every MIN_GROUP_DIFFICULTY the
	-- night can pay, none worth less; the last group spawns this long after
	-- night fall (WAVE_SPAWN_LENGTH_SEC)
	minGroupDifficulty: number,
	spawnWindowSec: number,
	-- no two groups in a row are further apart than this (MAX_TIME_BETWEEN_GROUPS_SEC)
	maxGapSec: number,
	random: Random,
}

export type Result = {
	wave: WaveRules.Wave,
	targetDifficulty: number,
	totalDifficulty: number,
}

-- a group while it is being filled: how many of each kind
type Counts = { [number]: number }

-- (starting + increase per night) times (1 + growth) to the night, times the party
function WaveGenerator.targetDifficulty(settings: Settings, night: number, difficultyMultiplier: number): number
	local nightIndex = math.max(math.floor(night), 1) - 1
	local linear = settings.STARTING_DIFFICULTY + settings.DIFFICULTY_INCREASE_PER_WAVE * nightIndex
	local growth = (1 + math.max(settings.GROWTH_PER_WAVE, 0)) ^ nightIndex
	return linear * growth * difficultyMultiplier
end

-- the kinds that may appear on the night and have a difficulty value,
-- cheapest first (ties by kind, so the order is stable)
function WaveGenerator.unlockedKinds(settings: Settings, night: number, difficultyValueByKind: { [number]: number }): { number }
	local kinds = {}
	for _, entry in settings.AVAILABLE_ENEMIES do
		if entry.WAVE_UNLOCKED <= night and difficultyValueByKind[entry.KIND] ~= nil and not table.find(kinds, entry.KIND) then
			table.insert(kinds, entry.KIND)
		end
	end
	table.sort(
		kinds,
		function(first: number, second: number): boolean
			local firstValue = difficultyValueByKind[first]
			local secondValue = difficultyValueByKind[second]
			if firstValue ~= secondValue then
				return firstValue < secondValue
			end
			return first < second
		end
	)
	return kinds
end

function WaveGenerator.groupDifficulty(group: WaveRules.Group, difficultyValueByKind: { [number]: number }): number
	local total = 0
	for _, entry in group.ENEMIES do
		total += (difficultyValueByKind[entry.KIND] or 0) * entry.COUNT
	end
	return total
end

function WaveGenerator.waveDifficulty(wave: WaveRules.Wave, difficultyValueByKind: { [number]: number }): number
	local total = 0
	for _, group in wave.GROUPS do
		total += WaveGenerator.groupDifficulty(group, difficultyValueByKind)
	end
	return total
end

local function countsDifficulty(counts: Counts, difficultyValueByKind: { [number]: number }): number
	local total = 0
	for kind, count in counts do
		total += difficultyValueByKind[kind] * count
	end
	return total
end

local function countsUnits(counts: Counts): number
	local units = 0
	for _, count in counts do
		units += count
	end
	return units
end

-- the group as authored data, cheapest kind first
local function toEnemies(counts: Counts, difficultyValueByKind: { [number]: number }): { WaveRules.EnemyCount }
	local kinds = {}
	for kind in counts do
		table.insert(kinds, kind)
	end
	table.sort(
		kinds,
		function(first: number, second: number): boolean
			if difficultyValueByKind[first] ~= difficultyValueByKind[second] then
				return difficultyValueByKind[first] < difficultyValueByKind[second]
			end
			return first < second
		end
	)
	local enemies = {}
	for _, kind in kinds do
		table.insert(enemies, {
			KIND = kind,
			COUNT = counts[kind],
		})
	end
	return enemies
end

-- how many groups the night splits into: one for every
-- MIN_GROUP_DIFFICULTY it can pay, and always at least one
function WaveGenerator.groupCount(targetDifficulty: number, minGroupDifficulty: number): number
	return math.max(1, math.floor(targetDifficulty / math.max(minGroupDifficulty, 1e-6)))
end

-- each group's share of the target from its weight, with any share under
-- the minimum raised to it at the biggest share's expense (the count was
-- chosen so the night can afford that)
function WaveGenerator.groupShares(targetDifficulty: number, weights: { number }, minGroupDifficulty: number): { number }
	local weightSum = 0
	for _, weight in weights do
		weightSum += weight
	end
	local shares = {}
	for _, weight in weights do
		table.insert(shares, targetDifficulty * weight / weightSum)
	end
	if #shares * minGroupDifficulty > targetDifficulty then
		return shares
	end
	for index, share in shares do
		if share >= minGroupDifficulty then
			continue
		end
		local biggestIndex = index
		for otherIndex, other in shares do
			if other > shares[biggestIndex] then
				biggestIndex = otherIndex
			end
		end
		shares[biggestIndex] -= minGroupDifficulty - share
		shares[index] = minGroupDifficulty
	end
	return shares
end

-- the unlocked kinds worth no more than `budget`
local function fittingKinds(budget: number, kinds: { number }, difficultyValueByKind: { [number]: number }): { number }
	local fitting = {}
	for _, kind in kinds do
		if difficultyValueByKind[kind] <= budget then
			table.insert(fitting, kind)
		end
	end
	return fitting
end

-- one group's fill: kinds drawn one at a time at random from those that
-- still fit what is left, until nothing fits, so cheap kinds come in
-- numbers and strong ones in ones and twos, mixed as the draws fall (no
-- one-kind rule, decided 2026-09-24). Returns the counts and what was spent
local function fillGroup(budget: number, kinds: { number }, difficultyValueByKind: { [number]: number }, random: Random): (Counts, number)
	local counts: Counts = {}
	local left = budget
	while true do
		local fitting = fittingKinds(left, kinds, difficultyValueByKind)
		if #fitting == 0 then
			break
		end
		local kind = fitting[random:NextInteger(1, #fitting)]
		counts[kind] = (counts[kind] or 0) + 1
		left -= difficultyValueByKind[kind]
	end
	-- nothing fit at all: the cheapest kind, one of it, so no group is ever empty
	if next(counts) == nil then
		counts[kinds[1]] = 1
	end
	return counts, countsDifficulty(counts, difficultyValueByKind)
end

-- a spawn at random, never the one the previous group used when there is a choice
function WaveGenerator.pickSpawn(spawnNumbers: { number }, previous: number?, random: Random): number
	if #spawnNumbers == 1 then
		return spawnNumbers[1]
	end
	local choices = {}
	for _, spawnNumber in spawnNumbers do
		if spawnNumber ~= previous then
			table.insert(choices, spawnNumber)
		end
	end
	return choices[random:NextInteger(1, #choices)]
end

-- the groups' spawn times: spread from night fall to LAST_GROUP_WINDOW_SHARE
-- of the window, each moved a little at random, the first always at 0, in
-- ascending order so the biggest group (last) still comes last, and no
-- gap longer than maxGapSec (a night with few groups bunches them up
-- rather than leaving a long lull; decided 2026-09-24)
function WaveGenerator.spawnTimes(groupCount: number, spawnWindowSec: number, maxGapSec: number, tuning: Tuning, random: Random): { number }
	local times = {}
	local span = spawnWindowSec * tuning.LAST_GROUP_WINDOW_SHARE
	for index = 1, groupCount do
		local base = if groupCount > 1 then (index - 1) / (groupCount - 1) * span else 0
		local jitter = if index == 1 then 0 else random:NextNumber(-tuning.SPAWN_TIME_JITTER_SEC, tuning.SPAWN_TIME_JITTER_SEC)
		table.insert(times, math.clamp(base + jitter, 0, spawnWindowSec))
	end
	table.sort(times)
	for index = 2, #times do
		times[index] = math.min(times[index], times[index - 1] + maxGapSec)
	end
	return times
end

function WaveGenerator.generate(input: Input): Result
	local settings = input.settings
	local tuning = input.tuning
	local valueByKind = input.difficultyValueByKind
	local random = input.random
	local target = WaveGenerator.targetDifficulty(settings, input.night, input.difficultyMultiplier)
	local kinds = WaveGenerator.unlockedKinds(settings, input.night, valueByKind)
	local wave: WaveRules.Wave = {
		NIGHT = input.night,
		GROUPS = {},
	}
	if #kinds == 0 or #input.spawnNumbers == 0 then
		return {
			wave = wave,
			targetDifficulty = target,
			totalDifficulty = 0,
		}
	end
	local groupCount = WaveGenerator.groupCount(target, input.minGroupDifficulty)
	-- uneven shares: some groups big, some small, none under the minimum
	local weights = {}
	for _ = 1, groupCount do
		table.insert(weights, random:NextNumber(tuning.GROUP_WEIGHT_MIN, tuning.GROUP_WEIGHT_MAX))
	end
	local shares = WaveGenerator.groupShares(target, weights, input.minGroupDifficulty)
	local groups: { Counts } = {}
	local carry = 0
	for index = 1, groupCount do
		local budget = shares[index] + carry
		local counts, spent = fillGroup(budget, kinds, valueByKind, random)
		carry = budget - spent
		table.insert(groups, counts)
	end
	-- land within range of the target: top up with random kinds that fit
	-- the shortfall, or trim one unit at a time from the biggest group,
	-- never emptying one
	local total = 0
	for _, counts in groups do
		total += countsDifficulty(counts, valueByKind)
	end
	local range = settings.WAVE_DIFFICULTY_RANGE
	while total < target - range do
		local fitting = fittingKinds(target + range - total, kinds, valueByKind)
		if #fitting == 0 then
			break
		end
		local kind = fitting[random:NextInteger(1, #fitting)]
		local counts = groups[random:NextInteger(1, #groups)]
		counts[kind] = (counts[kind] or 0) + 1
		total += valueByKind[kind]
	end
	while total > target + range do
		local biggest: Counts? = nil
		local biggestUnits = 1
		for _, counts in groups do
			local units = countsUnits(counts)
			if units > biggestUnits then
				biggest = counts
				biggestUnits = units
			end
		end
		if not biggest then
			break
		end
		-- the cheapest kind in that group goes first, so its character holds
		local trimKind: number? = nil
		for kind in biggest do
			if trimKind == nil or valueByKind[kind] < valueByKind[trimKind :: number] then
				trimKind = kind
			end
		end
		local kind = trimKind :: number
		if total - valueByKind[kind] < target - range then
			break
		end
		biggest[kind] -= 1
		if biggest[kind] == 0 then
			biggest[kind] = nil
		end
		total -= valueByKind[kind]
	end
	-- the night builds to a peak: groups in ascending order of difficulty
	table.sort(
		groups,
		function(first: Counts, second: Counts): boolean
			return countsDifficulty(first, valueByKind) < countsDifficulty(second, valueByKind)
		end
	)
	local times = WaveGenerator.spawnTimes(#groups, input.spawnWindowSec, input.maxGapSec, tuning, random)
	local previousSpawn: number? = nil
	for index, counts in groups do
		local spawnNumber = WaveGenerator.pickSpawn(input.spawnNumbers, previousSpawn, random)
		previousSpawn = spawnNumber
		table.insert(wave.GROUPS, {
			ENEMIES = toEnemies(counts, valueByKind),
			SPAWN_LOCATION = spawnNumber,
			SPAWN_TIME_SEC = times[index],
		})
	end
	return {
		wave = wave,
		targetDifficulty = target,
		totalDifficulty = total,
	}
end

-- the wave in words for the preview dev tool and the Output
function WaveGenerator.describe(result: Result, difficultyValueByKind: { [number]: number }, nameOf: (kind: number) -> string): { string }
	local wave = result.wave
	local lines = {
		string.format("Night %d: %d group(s), difficulty %d (target %d)", wave.NIGHT, #wave.GROUPS, result.totalDifficulty, math.round(result.targetDifficulty)),
	}
	for _, group in WaveRules.orderedGroups(wave) do
		local parts = {}
		for _, entry in group.ENEMIES do
			table.insert(parts, `{entry.COUNT}x {nameOf(entry.KIND)}`)
		end
		table.insert(lines, string.format("  %3ds at spawn %d: %s (%d)", math.round(group.SPAWN_TIME_SEC), group.SPAWN_LOCATION, table.concat(parts, ", "), WaveGenerator.groupDifficulty(group, difficultyValueByKind)))
	end
	return lines
end

return WaveGenerator
