-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Attributes = require(game:GetService("ReplicatedStorage").Shared.Attributes)
local BackpackRules = require(game:GetService("ReplicatedStorage").Shared.BackpackRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local RawResource = Enums.RawResource

-- mirrors GameData/Mining/Backpack and GameData/Control/PartyScaling
local CAPACITY_BY_LEVEL = { 50, 100, 200, 400 }
local ORE_YIELD_BY_COUNT = { 1.0, 1.15, 1.3, 1.45, 1.6, 1.75 }

describe(
	"BackpackRules.capacityForLevel",
	function()
		it(
			"reads and clamps",
			function()
				expect(BackpackRules.capacityForLevel(CAPACITY_BY_LEVEL, 1)).toBe(50)
				expect(BackpackRules.capacityForLevel(CAPACITY_BY_LEVEL, 4)).toBe(400)
				expect(BackpackRules.capacityForLevel(CAPACITY_BY_LEVEL, 7)).toBe(400)
				expect(BackpackRules.capacityForLevel(CAPACITY_BY_LEVEL, 0)).toBe(50)
			end
		)
	end
)

describe(
	"BackpackRules.yieldForBreak",
	function()
		it(
			"scales Iron and Gold by party size, rounded half up",
			function()
				expect(BackpackRules.yieldForBreak(5, RawResource.IRON_ORE, 1, ORE_YIELD_BY_COUNT)).toBe(5)
				-- 5 x 1.15 = 5.75 -> 6
				expect(BackpackRules.yieldForBreak(5, RawResource.IRON_ORE, 2, ORE_YIELD_BY_COUNT)).toBe(6)
				-- 17 x 1.3 = 22.1 -> 22
				expect(BackpackRules.yieldForBreak(17, RawResource.GOLD_ORE, 3, ORE_YIELD_BY_COUNT)).toBe(22)
				-- 145 x 1.75 = 253.75 -> 254
				expect(BackpackRules.yieldForBreak(145, RawResource.GOLD_ORE, 6, ORE_YIELD_BY_COUNT)).toBe(254)
			end
		)

		it(
			"never scales Crystal or Uranium",
			function()
				expect(BackpackRules.yieldForBreak(24, RawResource.CRYSTAL, 6, ORE_YIELD_BY_COUNT)).toBe(24)
				expect(BackpackRules.yieldForBreak(1, RawResource.URANIUM_ORE, 6, ORE_YIELD_BY_COUNT)).toBe(1)
			end
		)
	end
)

describe(
	"BackpackRules.add",
	function()
		it(
			"fills to capacity and reports the overflow",
			function()
				local contents = {}
				local added, overflow = BackpackRules.add(contents, 50, RawResource.IRON_ORE, 30)
				expect(added).toBe(30)
				expect(overflow).toBe(0)
				added, overflow = BackpackRules.add(contents, 50, RawResource.GOLD_ORE, 30)
				expect(added).toBe(20)
				expect(overflow).toBe(10)
				expect(contents[RawResource.IRON_ORE]).toBe(30)
				expect(contents[RawResource.GOLD_ORE]).toBe(20)
				expect(BackpackRules.getTotal(contents)).toBe(50)
				expect(BackpackRules.isFull(contents, 50)).toBe(true)
			end
		)

		it(
			"takes nothing when full and ignores non-positive amounts",
			function()
				local contents = { [RawResource.CRYSTAL] = 50 }
				local added, overflow = BackpackRules.add(contents, 50, RawResource.IRON_ORE, 7)
				expect(added).toBe(0)
				expect(overflow).toBe(7)
				expect(contents[RawResource.IRON_ORE]).toBeNil()
				added, overflow = BackpackRules.add({}, 50, RawResource.IRON_ORE, 0)
				expect(added).toBe(0)
				expect(overflow).toBe(0)
			end
		)

		it(
			"takeAll empties the backpack and returns what it held",
			function()
				local contents = { [RawResource.IRON_ORE] = 12, [RawResource.URANIUM_ORE] = 2 }
				local taken = BackpackRules.takeAll(contents)
				expect(taken).toEqual({ [RawResource.IRON_ORE] = 12, [RawResource.URANIUM_ORE] = 2 })
				expect(BackpackRules.getTotal(contents)).toBe(0)
			end
		)
	end
)

describe(
	"BackpackRules.attributeForResource",
	function()
		it(
			"names an attribute for every raw resource",
			function()
				for _, resource in Enums.getAllValues(RawResource) do
					expect(BackpackRules.attributeForResource(resource)).never.toBeNil()
				end
				expect(BackpackRules.attributeForResource(RawResource.IRON_ORE)).toBe(Attributes.BACKPACK_IRON_ORE)
				expect(BackpackRules.attributeForResource(99)).toBeNil()
			end
		)
	end
)
