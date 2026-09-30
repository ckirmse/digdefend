-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GeigerRules = require(game:GetService("ReplicatedStorage").Shared.GeigerRules)

local RANGES = { 0, 20, 30, 40, 50 }
local RING_SHARES = { 1, 0.5, 0.25 }
local BLOCK_SIZE = 4

describe(
	"GeigerRules.distanceToBlock",
	function()
		it(
			"measures to the nearest face, not the centre",
			function()
				local center = Vector3.new(10, 0, 0)
				expect(GeigerRules.distanceToBlock(Vector3.new(0, 0, 0), center, BLOCK_SIZE)).toBeCloseTo(8, 5)
				expect(GeigerRules.distanceToBlock(Vector3.new(10, 7, 0), center, BLOCK_SIZE)).toBeCloseTo(5, 5)
			end
		)
		it(
			"is 0 inside or touching the block",
			function()
				local center = Vector3.new(10, 0, 0)
				expect(GeigerRules.distanceToBlock(Vector3.new(10.5, 1, -1), center, BLOCK_SIZE)).toBe(0)
				expect(GeigerRules.distanceToBlock(Vector3.new(8, 0, 0), center, BLOCK_SIZE)).toBe(0)
			end
		)
		it(
			"measures to the corner when off on every axis",
			function()
				-- 3, 4, 12 past the faces is 13 to the corner
				expect(GeigerRules.distanceToBlock(Vector3.new(5, 6, 14), Vector3.new(0, 0, 0), BLOCK_SIZE)).toBeCloseTo(13, 5)
			end
		)
	end
)

describe(
	"GeigerRules.rangeForLevel",
	function()
		it(
			"reads the level's range and nothing for the unowned level",
			function()
				expect(GeigerRules.rangeForLevel(RANGES, 1)).toBe(0)
				expect(GeigerRules.rangeForLevel(RANGES, 2)).toBe(20)
				expect(GeigerRules.rangeForLevel(RANGES, 5)).toBe(50)
			end
		)
		it(
			"clamps a level outside the list",
			function()
				expect(GeigerRules.rangeForLevel(RANGES, 0)).toBe(0)
				expect(GeigerRules.rangeForLevel(RANGES, 9)).toBe(50)
				expect(GeigerRules.rangeForLevel({}, 2)).toBe(0)
			end
		)
	end
)

describe(
	"GeigerRules.litRingCount",
	function()
		it(
			"lights one ring per threshold crossed at the base range",
			function()
				expect(GeigerRules.litRingCount(21, 20, RING_SHARES)).toBe(0)
				expect(GeigerRules.litRingCount(20, 20, RING_SHARES)).toBe(1)
				expect(GeigerRules.litRingCount(11, 20, RING_SHARES)).toBe(1)
				expect(GeigerRules.litRingCount(10, 20, RING_SHARES)).toBe(2)
				expect(GeigerRules.litRingCount(6, 20, RING_SHARES)).toBe(2)
				expect(GeigerRules.litRingCount(5, 20, RING_SHARES)).toBe(3)
				expect(GeigerRules.litRingCount(0, 20, RING_SHARES)).toBe(3)
			end
		)
		it(
			"scales every ring with an upgraded range",
			function()
				expect(GeigerRules.litRingCount(45, 50, RING_SHARES)).toBe(1)
				expect(GeigerRules.litRingCount(25, 50, RING_SHARES)).toBe(2)
				expect(GeigerRules.litRingCount(12.5, 50, RING_SHARES)).toBe(3)
			end
		)
		it(
			"lights nothing with no uranium found or no range",
			function()
				expect(GeigerRules.litRingCount(nil, 20, RING_SHARES)).toBe(0)
				expect(GeigerRules.litRingCount(1, 0, RING_SHARES)).toBe(0)
			end
		)
	end
)

describe(
	"GeigerRules ring shares codec",
	function()
		it(
			"round-trips the list",
			function()
				local decoded = GeigerRules.decodeRingShares(GeigerRules.encodeRingShares(RING_SHARES))
				expect(decoded).toEqual(RING_SHARES)
			end
		)
		it(
			"returns nil for garbage",
			function()
				expect(GeigerRules.decodeRingShares(nil)).toBe(nil)
				expect(GeigerRules.decodeRingShares("not json")).toBe(nil)
				expect(GeigerRules.decodeRingShares('["a"]')).toBe(nil)
			end
		)
	end
)
