-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GeigerRules = require(game:GetService("ReplicatedStorage").Shared.GeigerRules)

local RANGES = { 0, 20, 30, 40, 50 }
local RING_STUDS = { 20, 10, 5 }
local RING_STUDS_BY_LEVEL = { {}, { 20, 13, 8 }, { 30, 16, 8 } }
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
	"GeigerRules.ringStudsForLevel",
	function()
		it(
			"reads the level's rings and none for the unowned level or past the table",
			function()
				expect(GeigerRules.ringStudsForLevel(RING_STUDS_BY_LEVEL, 1)).toEqual({})
				expect(GeigerRules.ringStudsForLevel(RING_STUDS_BY_LEVEL, 2)).toEqual({ 20, 13, 8 })
				expect(GeigerRules.ringStudsForLevel(RING_STUDS_BY_LEVEL, 3.9)).toEqual({ 30, 16, 8 })
				expect(GeigerRules.ringStudsForLevel(RING_STUDS_BY_LEVEL, 7)).toEqual({})
			end
		)
	end
)

describe(
	"GeigerRules.litRingCount",
	function()
		it(
			"lights each ring once the rock is within its own distance",
			function()
				expect(GeigerRules.litRingCount(21, RING_STUDS)).toBe(0)
				expect(GeigerRules.litRingCount(20, RING_STUDS)).toBe(1)
				expect(GeigerRules.litRingCount(11, RING_STUDS)).toBe(1)
				expect(GeigerRules.litRingCount(10, RING_STUDS)).toBe(2)
				expect(GeigerRules.litRingCount(6, RING_STUDS)).toBe(2)
				expect(GeigerRules.litRingCount(5, RING_STUDS)).toBe(3)
				expect(GeigerRules.litRingCount(0, RING_STUDS)).toBe(3)
			end
		)
		it(
			"keeps the inner ring at the same distance whatever the level",
			function()
				expect(GeigerRules.litRingCount(9, RING_STUDS_BY_LEVEL[2])).toBe(2)
				expect(GeigerRules.litRingCount(9, RING_STUDS_BY_LEVEL[3])).toBe(2)
				expect(GeigerRules.litRingCount(8, RING_STUDS_BY_LEVEL[2])).toBe(3)
				expect(GeigerRules.litRingCount(8, RING_STUDS_BY_LEVEL[3])).toBe(3)
			end
		)
		it(
			"lights nothing with no rock found or no rings",
			function()
				expect(GeigerRules.litRingCount(nil, RING_STUDS)).toBe(0)
				expect(GeigerRules.litRingCount(1, {})).toBe(0)
			end
		)
	end
)

describe(
	"GeigerRules ring codec",
	function()
		it(
			"round-trips the ring distances",
			function()
				local decoded = GeigerRules.decodeRingStuds(GeigerRules.encodeRingStuds(RING_STUDS))
				expect(decoded).toEqual(RING_STUDS)
			end
		)
		it(
			"returns nil for garbage",
			function()
				expect(GeigerRules.decodeRingStuds(nil)).toBe(nil)
				expect(GeigerRules.decodeRingStuds("not json")).toBe(nil)
				expect(GeigerRules.decodeRingStuds('["a"]')).toBe(nil)
			end
		)
	end
)
