-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local WaveGenerator = require(game:GetService("ReplicatedStorage").Shared.WaveGenerator)

-- kinds by number so the spec does not depend on the roster
local ZOMBIE = 1
local RUNNER = 2
local BRUTE = 3
local TITAN = 4

local VALUE_BY_KIND = {
	[ZOMBIE] = 2,
	[RUNNER] = 6,
	[BRUTE] = 10,
	[TITAN] = 100,
}

local TUNING: WaveGenerator.Tuning = {
	GROUP_WEIGHT_MIN = 0.5,
	GROUP_WEIGHT_MAX = 1.5,
	LAST_GROUP_WINDOW_SHARE = 0.85,
	SPAWN_TIME_JITTER_SEC = 4,
}

local function settings(overrides: { [string]: any }?): WaveGenerator.Settings
	local value: { [string]: any } = {
		STARTING_DIFFICULTY = 16,
		DIFFICULTY_INCREASE_PER_WAVE = 10,
		GROWTH_PER_WAVE = 0,
		WAVE_DIFFICULTY_RANGE = 4,
		AVAILABLE_ENEMIES = {
			{ KIND = ZOMBIE, WAVE_UNLOCKED = 1 },
			{ KIND = RUNNER, WAVE_UNLOCKED = 2 },
			{ KIND = BRUTE, WAVE_UNLOCKED = 4 },
			{ KIND = TITAN, WAVE_UNLOCKED = 10 },
		},
	}
	for key, override in overrides or {} do
		value[key] = override
	end
	return value :: any
end

local function generate(night: number, seed: number, overrides: { [string]: any }?, multiplier: number?): WaveGenerator.Result
	return WaveGenerator.generate({
		settings = settings(overrides),
		tuning = TUNING,
		night = night,
		difficultyMultiplier = multiplier or 1,
		difficultyValueByKind = VALUE_BY_KIND,
		spawnNumbers = { 1, 2, 3 },
		minGroupDifficulty = 12,
		spawnWindowSec = 90,
		maxGapSec = 20,
		random = Random.new(seed),
	})
end

describe(
	"WaveGenerator.targetDifficulty and unlockedKinds",
	function()
		it(
			"climbs each night, compounds by the growth share, and scales with the party",
			function()
				expect(WaveGenerator.targetDifficulty(settings(), 1, 1)).toBe(16)
				expect(WaveGenerator.targetDifficulty(settings(), 4, 1)).toBe(46)
				expect(WaveGenerator.targetDifficulty(settings(), 4, 1.5)).toBe(69)
				local compounding = settings({ STARTING_DIFFICULTY = 10, DIFFICULTY_INCREASE_PER_WAVE = 4, GROWTH_PER_WAVE = 0.12 })
				expect(WaveGenerator.targetDifficulty(compounding, 1, 1)).toBe(10)
				expect(WaveGenerator.targetDifficulty(compounding, 2, 1)).toBeCloseTo(15.68, 5)
				expect(WaveGenerator.targetDifficulty(compounding, 12, 1)).toBeCloseTo(54 * 1.12 ^ 11, 3)
			end
		)
		it(
			"lists the night's kinds cheapest first and skips unknown ones",
			function()
				expect(WaveGenerator.unlockedKinds(settings(), 1, VALUE_BY_KIND)).toEqual({ ZOMBIE })
				expect(WaveGenerator.unlockedKinds(settings(), 5, VALUE_BY_KIND)).toEqual({ ZOMBIE, RUNNER, BRUTE })
				expect(WaveGenerator.unlockedKinds(settings(), 5, { [RUNNER] = 6 })).toEqual({ RUNNER })
			end
		)
	end
)

describe(
	"WaveGenerator.generate",
	function()
		it(
			"lands within range of the target on every night and seed",
			function()
				for night = 1, 12 do
					for seed = 1, 20 do
						local result = generate(night, seed)
						local target = result.targetDifficulty
						expect(WaveGenerator.waveDifficulty(result.wave, VALUE_BY_KIND)).toBe(result.totalDifficulty)
						expect(result.totalDifficulty >= target - 4).toBe(true)
						expect(result.totalDifficulty <= target + 4).toBe(true)
					end
				end
			end
		)
		it(
			"only uses kinds unlocked by the night, and never an empty group",
			function()
				for seed = 1, 20 do
					local result = generate(3, seed)
					for _, group in result.wave.GROUPS do
						expect(#group.ENEMIES > 0).toBe(true)
						for _, entry in group.ENEMIES do
							expect(entry.KIND == ZOMBIE or entry.KIND == RUNNER).toBe(true)
							expect(entry.COUNT > 0).toBe(true)
						end
					end
				end
			end
		)
		it(
			"makes one group per minimum the night can pay",
			function()
				expect(WaveGenerator.groupCount(16, 12)).toBe(1)
				expect(WaveGenerator.groupCount(46, 12)).toBe(3)
				expect(WaveGenerator.groupCount(5, 12)).toBe(1)
				for seed = 1, 20 do
					-- night 1 is 16: one group; night 4 is 46: three
					expect(#generate(1, seed).wave.GROUPS).toBe(1)
					expect(#generate(4, seed).wave.GROUPS).toBe(3)
					for night = 1, 12 do
						local wave = generate(night, seed).wave
						if #wave.GROUPS > 1 then
							for _, group in wave.GROUPS do
								-- a share is the minimum; the fill can leave a little unspent
								expect(WaveGenerator.groupDifficulty(group, VALUE_BY_KIND) >= 12 - 6).toBe(true)
							end
						end
					end
				end
				local shares = WaveGenerator.groupShares(48, { 0.5, 1.5, 1.5, 0.5 }, 12)
				expect(shares[1]).toBe(12)
				expect(shares[4]).toBe(12)
				expect(shares[1] + shares[2] + shares[3] + shares[4]).toBeCloseTo(48, 5)
			end
		)
		it(
			"spawns the biggest group last, inside the window, never the same spawn twice running",
			function()
				for seed = 1, 20 do
					local groups = generate(8, seed).wave.GROUPS
					local lastDifficulty = 0
					local lastTime = -1
					local lastSpawn = nil
					for index, group in groups do
						local difficulty = WaveGenerator.groupDifficulty(group, VALUE_BY_KIND)
						expect(difficulty >= lastDifficulty).toBe(true)
						expect(group.SPAWN_TIME_SEC >= lastTime).toBe(true)
						expect(group.SPAWN_TIME_SEC <= 90).toBe(true)
						if index > 1 then
							expect(group.SPAWN_TIME_SEC - lastTime <= 20 + 1e-6).toBe(true)
						end
						expect(group.SPAWN_LOCATION ~= lastSpawn).toBe(true)
						if index == 1 then
							expect(group.SPAWN_TIME_SEC).toBe(0)
						end
						lastDifficulty = difficulty
						lastTime = group.SPAWN_TIME_SEC
						lastSpawn = group.SPAWN_LOCATION
					end
				end
			end
		)
		it(
			"caps the gap between groups",
			function()
				local times = WaveGenerator.spawnTimes(3, 90, 20, TUNING, Random.new(1))
				expect(times[1]).toBe(0)
				expect(times[2] <= 20).toBe(true)
				expect(times[3] <= 40).toBe(true)
				local loose = WaveGenerator.spawnTimes(3, 90, 1000, TUNING, Random.new(1))
				expect(loose[3] > 40).toBe(true)
			end
		)
		it(
			"mixes kinds within a group rather than filling it with one",
			function()
				local mixed = 0
				for seed = 1, 20 do
					for _, group in generate(6, seed).wave.GROUPS do
						if #group.ENEMIES > 1 then
							mixed += 1
						end
					end
				end
				expect(mixed >= 15).toBe(true)
			end
		)
		it(
			"is the same wave for the same seed",
			function()
				expect(generate(6, 7)).toEqual(generate(6, 7))
			end
		)
		it(
			"makes an empty wave when nothing is unlocked or there is no spawn",
			function()
				local none = generate(1, 1, { AVAILABLE_ENEMIES = { { KIND = TITAN, WAVE_UNLOCKED = 5 } } })
				expect(#none.wave.GROUPS).toBe(0)
				expect(none.totalDifficulty).toBe(0)
				local noSpawn = WaveGenerator.generate({
					settings = settings(),
					tuning = TUNING,
					night = 1,
					difficultyMultiplier = 1,
					difficultyValueByKind = VALUE_BY_KIND,
					spawnNumbers = {},
					minGroupDifficulty = 12,
					spawnWindowSec = 90,
					maxGapSec = 20,
					random = Random.new(1),
				})
				expect(#noSpawn.wave.GROUPS).toBe(0)
			end
		)
		it(
			"describes a wave one group per line",
			function()
				local lines = WaveGenerator.describe(generate(2, 3), VALUE_BY_KIND, function(kind: number): string
					return "kind" .. kind
				end)
				expect(#lines).toBe(#generate(2, 3).wave.GROUPS + 1)
				expect(lines[1]:find("Night 2") ~= nil).toBe(true)
			end
		)
	end
)
