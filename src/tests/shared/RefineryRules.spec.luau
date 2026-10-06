-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local RefineryRules = require(game:GetService("ReplicatedStorage").Shared.RefineryRules)

local RawResource = Enums.RawResource
local RefinedResource = Enums.RefinedResource

-- mirrors GameData/Refinery/Refinery and PartyScaling
local RATE_BY_RAW = {
	[RawResource.IRON_ORE] = 1,
	[RawResource.GOLD_ORE] = 1,
	[RawResource.URANIUM_ORE] = 1,
}
local URANIUM_TARGET_BY_COUNT = { 1.0, 1.5, 2.0, 2.5, 3.0, 3.5 }

describe(
	"RefineryRules.convert",
	function()
		it(
			"maps every ore to its refined resource one to one",
			function()
				local refined = RefineryRules.convert({
					[RawResource.IRON_ORE] = 5,
					[RawResource.GOLD_ORE] = 3,
					[RawResource.URANIUM_ORE] = 1,
				}, RATE_BY_RAW)
				expect(refined[RefinedResource.IRON_BAR]).toBe(5)
				expect(refined[RefinedResource.GOLD_BAR]).toBe(3)
				expect(refined[RefinedResource.URANIUM]).toBe(1)
			end
		)

		it(
			"floors fractional rates and skips empty or unknown entries",
			function()
				local refined = RefineryRules.convert({
					[RawResource.IRON_ORE] = 7,
					[RawResource.GOLD_ORE] = 0,
					[99] = 4,
				}, { [RawResource.IRON_ORE] = 0.5 })
				expect(refined[RefinedResource.IRON_BAR]).toBe(3)
				expect(refined[RefinedResource.GOLD_BAR]).toBeNil()
				expect(next(refined, RefinedResource.IRON_BAR)).toBeNil()
			end
		)

		it(
			"returns an empty table for an empty backpack",
			function()
				expect(next(RefineryRules.convert({}, RATE_BY_RAW))).toBeNil()
			end
		)
	end
)

describe(
	"RefineryRules.uraniumTarget",
	function()
		it(
			"scales the solo target by party size, rounds to the nearest 5 with halves up, and clamps",
			function()
				expect(RefineryRules.uraniumTarget(25, 1, URANIUM_TARGET_BY_COUNT)).toBe(25)
				-- 25 x 1.5 = 37.5 -> 40
				expect(RefineryRules.uraniumTarget(25, 2, URANIUM_TARGET_BY_COUNT)).toBe(40)
				-- 25 x 2.5 = 62.5 -> 65
				expect(RefineryRules.uraniumTarget(25, 4, URANIUM_TARGET_BY_COUNT)).toBe(65)
				-- 25 x 3.5 = 87.5 -> 90
				expect(RefineryRules.uraniumTarget(25, 6, URANIUM_TARGET_BY_COUNT)).toBe(90)
				expect(RefineryRules.uraniumTarget(25, 9, URANIUM_TARGET_BY_COUNT)).toBe(90)
				expect(RefineryRules.uraniumTarget(25, 0, URANIUM_TARGET_BY_COUNT)).toBe(25)
				-- 21 x 2.0 = 42 -> 40, below the half
				expect(RefineryRules.uraniumTarget(21, 3, URANIUM_TARGET_BY_COUNT)).toBe(40)
				-- the difficulty multiplies on top: 25 x 2.5 x 1.3 = 81.25 -> 80
				expect(RefineryRules.uraniumTarget(25, 4, URANIUM_TARGET_BY_COUNT, 1.3)).toBe(80)
				-- 25 x 3.5 x 1.3 = 113.75 -> 115, the worst case the generator checks
				expect(RefineryRules.uraniumTarget(25, 6, URANIUM_TARGET_BY_COUNT, 1.3)).toBe(115)
			end
		)

		it(
			"never rounds a target below one step",
			function()
				expect(RefineryRules.roundUraniumTarget(1)).toBe(5)
				expect(RefineryRules.roundUraniumTarget(2.4)).toBe(5)
				expect(RefineryRules.roundUraniumTarget(7.5)).toBe(10)
			end
		)
	end
)
