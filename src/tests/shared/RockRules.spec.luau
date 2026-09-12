-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local RockRules = require(game:GetService("ReplicatedStorage").Shared.RockRules)

local RockName = Enums.RockName
local RawResource = Enums.RawResource
local RockKind = Enums.RockKind

-- mirrors GameData/Rocks/Weights and GameData/Control/Difficulty; GameData
-- itself cannot load under jest because it requires through the @game alias
local SPREAD = 1.5
local MIN_CENTER = 1.0
local MAX_CENTER = 4.0
local HARDNESS_SHIFT = 1.0
local DIFFICULTY_VALUE = {
	[Enums.Difficulty.NORMAL] = 1.0,
	[Enums.Difficulty.HARD] = 1.4,
	[Enums.Difficulty.NIGHTMARE] = 1.9,
}

local function makeResource(resource: number, tier: number, hp: number, yield: number, radiusMin: number, radiusMax: number)
	return {
		kind = RockKind.RESOURCE,
		resource = resource,
		tier = tier,
		hp = hp,
		yield = yield,
		clusterRadiusMin = radiusMin,
		clusterRadiusMax = radiusMax,
	}
end

-- mirrors GameData/Rocks/RockDefinitions, transcribed from the GDD tables
local function makeRockTable()
	return {
		FILLER_ORDER = { RockName.SHALE, RockName.SANDSTONE, RockName.GRANITE, RockName.BASALT },
		RESOURCE_TIERS = {
			[RawResource.IRON_ORE] = { RockName.IRON_1, RockName.IRON_2, RockName.IRON_3, RockName.IRON_4 },
			[RawResource.GOLD_ORE] = { RockName.GOLD_1, RockName.GOLD_2, RockName.GOLD_3, RockName.GOLD_4 },
			[RawResource.CRYSTAL] = { RockName.CRYSTAL_1, RockName.CRYSTAL_2, RockName.CRYSTAL_3, RockName.CRYSTAL_4 },
			[RawResource.URANIUM_ORE] = { RockName.URANIUM },
		},
		ROCKS = {
			[RockName.SHALE] = { kind = RockKind.FILLER, hp = 10 },
			[RockName.SANDSTONE] = { kind = RockKind.FILLER, hp = 20 },
			[RockName.GRANITE] = { kind = RockKind.FILLER, hp = 40 },
			[RockName.BASALT] = { kind = RockKind.FILLER, hp = 80 },
			[RockName.IRON_1] = makeResource(RawResource.IRON_ORE, 1, 15, 5, 1, 2),
			[RockName.IRON_2] = makeResource(RawResource.IRON_ORE, 2, 30, 16, 1, 2),
			[RockName.IRON_3] = makeResource(RawResource.IRON_ORE, 3, 60, 48, 1, 2),
			[RockName.IRON_4] = makeResource(RawResource.IRON_ORE, 4, 110, 130, 0, 1),
			[RockName.GOLD_1] = makeResource(RawResource.GOLD_ORE, 1, 20, 5, 1, 2),
			[RockName.GOLD_2] = makeResource(RawResource.GOLD_ORE, 2, 40, 17, 1, 2),
			[RockName.GOLD_3] = makeResource(RawResource.GOLD_ORE, 3, 75, 50, 1, 1),
			[RockName.GOLD_4] = makeResource(RawResource.GOLD_ORE, 4, 140, 145, 0, 1),
			[RockName.CRYSTAL_1] = makeResource(RawResource.CRYSTAL, 1, 30, 3, 1, 1),
			[RockName.CRYSTAL_2] = makeResource(RawResource.CRYSTAL, 2, 60, 9, 1, 1),
			[RockName.CRYSTAL_3] = makeResource(RawResource.CRYSTAL, 3, 110, 24, 0, 1),
			[RockName.CRYSTAL_4] = makeResource(RawResource.CRYSTAL, 4, 200, 65, 0, 1),
			[RockName.URANIUM] = makeResource(RawResource.URANIUM_ORE, 1, 100, 1, 0, 0),
			[RockName.BEDROCK] = { kind = RockKind.BEDROCK },
			[RockName.GATE] = { kind = RockKind.GATE },
		},
	}
end

local function expectWeights(actual: { number }, expected: { number })
	expect(#actual).toBe(#expected)
	for index, value in expected do
		expect(actual[index]).toBeCloseTo(value, 6)
	end
end

describe(
	"RockRules.weights",
	function()
		-- the GDD hardness table at spread 1.5, one row per case
		local GDD_ROWS = {
			{ center = 1.0, weights = { 0.75, 0.25, 0, 0 } },
			{ center = 1.2, weights = { 0.65, 0.35, 0, 0 } },
			{ center = 2.0, weights = { 0.2, 0.6, 0.2, 0 } },
			{ center = 2.5, weights = { 0, 0.5, 0.5, 0 } },
			{ center = 3.0, weights = { 0, 0.2, 0.6, 0.2 } },
			{ center = 3.7, weights = { 0, 0, 0.4, 0.6 } },
			{ center = 4.0, weights = { 0, 0, 0.25, 0.75 } },
		}

		for _, row in GDD_ROWS do
			it(
				"matches the GDD table at hardness " .. row.center,
				function()
					expectWeights(RockRules.weights(row.center, 4, SPREAD), row.weights)
				end
			)
		end

		it(
			"always sums to one",
			function()
				for center = 1, 4, 0.1 do
					local total = 0
					for _, weight in RockRules.weights(center, 4, SPREAD) do
						total += weight
					end
					expect(total).toBeCloseTo(1, 9)
				end
			end
		)

		it(
			"never mixes more than three types at spread 1.5",
			function()
				for center = 1, 4, 0.05 do
					local nonZero = 0
					for _, weight in RockRules.weights(center, 4, SPREAD) do
						if weight > 0 then
							nonZero += 1
						end
					end
					expect(nonZero).toBeLessThanOrEqual(3)
				end
			end
		)

		it(
			"brings all four types in at mid hardness when spread is 2.0",
			function()
				local weights = RockRules.weights(2.5, 4, 2.0)
				for _, weight in weights do
					expect(weight).toBeGreaterThan(0)
				end
			end
		)

		it(
			"collapses to a single rock at whole-number hardness when spread is 1.0, which the GDD warns against",
			function()
				expectWeights(RockRules.weights(2, 4, 1.0), { 0, 1, 0, 0 })
			end
		)

		it(
			"handles a single category",
			function()
				expectWeights(RockRules.weights(1, 1, SPREAD), { 1 })
			end
		)

		it(
			"falls back to the nearest category instead of dividing by zero",
			function()
				expectWeights(RockRules.weights(10, 4, SPREAD), { 0, 0, 0, 1 })
			end
		)
	end
)

describe(
	"RockRules.clampCenter",
	function()
		it(
			"passes in-range values through untouched",
			function()
				local value, wasClamped = RockRules.clampCenter(2.1, MIN_CENTER, MAX_CENTER)
				expect(value).toBe(2.1)
				expect(wasClamped).toBe(false)
			end
		)

		it(
			"clamps at both ends and reports it",
			function()
				local low, lowClamped = RockRules.clampCenter(0.3, MIN_CENTER, MAX_CENTER)
				expect(low).toBe(1)
				expect(lowClamped).toBe(true)
				local high, highClamped = RockRules.clampCenter(5, MIN_CENTER, MAX_CENTER)
				expect(high).toBe(4)
				expect(highClamped).toBe(true)
			end
		)
	end
)

describe(
	"RockRules.resolveHardnessWeights",
	function()
		it(
			"keys the kernel by filler rock in table order",
			function()
				local byRock = RockRules.resolveHardnessWeights(3.0, makeRockTable().FILLER_ORDER, SPREAD)
				expect(byRock[RockName.SHALE]).toBeCloseTo(0, 6)
				expect(byRock[RockName.SANDSTONE]).toBeCloseTo(0.2, 6)
				expect(byRock[RockName.GRANITE]).toBeCloseTo(0.6, 6)
				expect(byRock[RockName.BASALT]).toBeCloseTo(0.2, 6)
			end
		)
	end
)

describe(
	"RockRules.resolveTierCounts",
	function()
		it(
			"splits 30 iron at tierBias 2.0 into 6 / 18 / 6 / 0 as the GDD says",
			function()
				expect(RockRules.resolveTierCounts(30, 2.0, 4, SPREAD)).toEqual({ 6, 18, 6, 0 })
			end
		)

		it(
			"always sums to the requested count",
			function()
				for count = 0, 40 do
					for tierBias = 1, 4, 0.1 do
						local counts = RockRules.resolveTierCounts(count, tierBias, 4, SPREAD)
						local total = 0
						for _, value in counts do
							total += value
						end
						expect(total).toBe(count)
					end
				end
			end
		)

		it(
			"gives leftover clusters to the tiers with the largest remainder",
			function()
				-- 10 at 1.0: exact 7.5 / 2.5; both remainders tie so the lower tier wins
				expect(RockRules.resolveTierCounts(10, 1.0, 4, SPREAD)).toEqual({ 8, 2, 0, 0 })
				-- 7 at 3.0: exact 0 / 1.4 / 4.2 / 1.4; tier 2 wins the tie over tier 4
				expect(RockRules.resolveTierCounts(7, 3.0, 4, SPREAD)).toEqual({ 0, 2, 4, 1 })
			end
		)

		it(
			"places a single-tier resource directly",
			function()
				expect(RockRules.resolveTierCounts(8, 1.0, 1, SPREAD)).toEqual({ 8 })
			end
		)
	end
)

describe(
	"RockRules.pickWeightedIndex",
	function()
		it(
			"is reproducible from a seed and only ever picks non-zero weights",
			function()
				local weights = { 0, 0.2, 0.6, 0.2 }
				local first = {}
				local random = Random.new(1234)
				for _ = 1, 50 do
					table.insert(first, RockRules.pickWeightedIndex(random, weights))
				end
				local second = {}
				random = Random.new(1234)
				for _ = 1, 50 do
					table.insert(second, RockRules.pickWeightedIndex(random, weights))
				end
				expect(second).toEqual(first)
				for _, index in first do
					expect(index).never.toBe(1)
				end
			end
		)

		it(
			"lands near the weights over many rolls",
			function()
				local weights = { 0.75, 0.25, 0, 0 }
				local counts = { 0, 0, 0, 0 }
				local random = Random.new(42)
				local rolls = 20000
				for _ = 1, rolls do
					local index = RockRules.pickWeightedIndex(random, weights)
					counts[index] += 1
				end
				expect(counts[1] / rolls).toBeCloseTo(0.75, 1)
				expect(counts[2] / rolls).toBeCloseTo(0.25, 1)
				expect(counts[3]).toBe(0)
				expect(counts[4]).toBe(0)
			end
		)
	end
)

describe(
	"RockRules difficulty transform",
	function()
		it(
			"leaves Normal untouched",
			function()
				local normal = DIFFICULTY_VALUE[Enums.Difficulty.NORMAL]
				expect(RockRules.effectiveHardness(2.1, normal, HARDNESS_SHIFT, MIN_CENTER, MAX_CENTER)).toBeCloseTo(2.1, 9)
				expect(RockRules.effectiveVeinCount(30, normal)).toBe(30)
			end
		)

		it(
			"reproduces the GDD Nightmare example for chamber 2",
			function()
				local nightmare = DIFFICULTY_VALUE[Enums.Difficulty.NIGHTMARE]
				expect(RockRules.effectiveHardness(2.1, nightmare, HARDNESS_SHIFT, MIN_CENTER, MAX_CENTER)).toBeCloseTo(3.0, 9)
				expect(RockRules.effectiveVeinCount(30, nightmare)).toBe(16)
				expect(RockRules.effectiveVeinCount(18, nightmare)).toBe(9)
				expect(RockRules.effectiveVeinCount(6, nightmare)).toBe(3)
			end
		)

		it(
			"clamps hardness at the top of the range",
			function()
				local nightmare = DIFFICULTY_VALUE[Enums.Difficulty.NIGHTMARE]
				expect(RockRules.effectiveHardness(3.7, nightmare, HARDNESS_SHIFT, MIN_CENTER, MAX_CENTER)).toBe(4)
			end
		)

		it(
			"rounds half up and can round small counts to zero",
			function()
				expect(RockRules.effectiveVeinCount(21, 1.4)).toBe(15)
				expect(RockRules.effectiveVeinCount(3, 1.4)).toBe(2)
				expect(RockRules.effectiveVeinCount(1, 1.9)).toBe(1)
				expect(RockRules.effectiveVeinCount(0, 1.9)).toBe(0)
			end
		)
	end
)

describe(
	"RockRules.validateRockTable",
	function()
		it(
			"accepts the GDD rock table",
			function()
				local isValid, message = RockRules.validateRockTable(makeRockTable())
				expect(message).toBeNil()
				expect(isValid).toBe(true)
			end
		)

		it(
			"covers every RockName and every RawResource",
			function()
				local rockTable = makeRockTable()
				for _, rockName in Enums.getAllValues(RockName) do
					expect(rockTable.ROCKS[rockName]).never.toBeNil()
				end
				for _, resource in Enums.getAllValues(RawResource) do
					expect(rockTable.RESOURCE_TIERS[resource]).never.toBeNil()
				end
			end
		)

		it(
			"names a missing rock",
			function()
				local rockTable = makeRockTable()
				rockTable.ROCKS[RockName.GOLD_3] = nil
				local isValid, message = RockRules.validateRockTable(rockTable)
				expect(isValid).toBe(false)
				expect(message).toContain("GOLD_3")
			end
		)

		it(
			"rejects filler rocks out of hardness order",
			function()
				local rockTable = makeRockTable()
				rockTable.FILLER_ORDER = { RockName.SHALE, RockName.GRANITE, RockName.SANDSTONE, RockName.BASALT }
				local isValid, message = RockRules.validateRockTable(rockTable)
				expect(isValid).toBe(false)
				expect(message).toContain("SANDSTONE")
			end
		)

		it(
			"rejects a resource rock whose declared tier disagrees with its position",
			function()
				local rockTable = makeRockTable()
				rockTable.ROCKS[RockName.IRON_2].tier = 3
				local isValid, message = RockRules.validateRockTable(rockTable)
				expect(isValid).toBe(false)
				expect(message).toContain("IRON_2")
			end
		)

		it(
			"rejects a rock listed under the wrong resource",
			function()
				local rockTable = makeRockTable()
				rockTable.RESOURCE_TIERS[RawResource.GOLD_ORE][2] = RockName.IRON_2
				local isValid, message = RockRules.validateRockTable(rockTable)
				expect(isValid).toBe(false)
				expect(message).toContain("IRON_2")
			end
		)

		it(
			"rejects bad numbers and extra fields",
			function()
				local rockTable = makeRockTable()
				rockTable.ROCKS[RockName.SHALE].hp = 0
				expect((RockRules.validateRockTable(rockTable))).toBe(false)

				rockTable = makeRockTable()
				rockTable.ROCKS[RockName.CRYSTAL_1].clusterRadiusMax = 0
				expect((RockRules.validateRockTable(rockTable))).toBe(false)

				rockTable = makeRockTable()
				rockTable.ROCKS[RockName.BEDROCK].hp = 50
				expect((RockRules.validateRockTable(rockTable))).toBe(false)

				rockTable = makeRockTable()
				rockTable.ROCKS[99] = { kind = RockKind.FILLER, hp = 5 }
				expect((RockRules.validateRockTable(rockTable))).toBe(false)
			end
		)
	end
)
