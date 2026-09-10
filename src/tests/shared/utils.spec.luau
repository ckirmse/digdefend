-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local utils = require(game:GetService("ReplicatedStorage").Shared.utils)

describe(
	"utils.abbreviateNumber",
	function()
		it(
			"returns an integer string for values under 1000",
			function()
				expect(utils.abbreviateNumber(0)).toBe("0")
				expect(utils.abbreviateNumber(1)).toBe("1")
				expect(utils.abbreviateNumber(999)).toBe("999")
			end
		)

		it(
			"floors fractional values below 1000",
			function()
				expect(utils.abbreviateNumber(42.9)).toBe("42")
			end
		)

		it(
			"abbreviates thousands through trillions",
			function()
				expect(utils.abbreviateNumber(1000)).toBe("1.00K")
				expect(utils.abbreviateNumber(1500)).toBe("1.50K")
				expect(utils.abbreviateNumber(1e6)).toBe("1.00M")
				expect(utils.abbreviateNumber(2.5e6)).toBe("2.50M")
				expect(utils.abbreviateNumber(1e9)).toBe("1.00B")
				expect(utils.abbreviateNumber(1e12)).toBe("1.00T")
			end
		)

		it(
			"keeps using T past a thousand trillion",
			function()
				expect(utils.abbreviateNumber(1e15)).toBe("1000.00T")
			end
		)

		it(
			"handles negative numbers",
			function()
				expect(utils.abbreviateNumber(-42)).toBe("-42")
				expect(utils.abbreviateNumber(-1000)).toBe("-1.00K")
			end
		)
	end
)

describe(
	"utils.convertDurationSecToString",
	function()
		it(
			"formats minutes and seconds",
			function()
				expect(utils.convertDurationSecToString(0)).toBe(" 0:00")
				expect(utils.convertDurationSecToString(65)).toBe(" 1:05")
				expect(utils.convertDurationSecToString(599)).toBe(" 9:59")
			end
		)

		it(
			"adds hours when needed",
			function()
				expect(utils.convertDurationSecToString(3600)).toBe(" 1:00:00")
				expect(utils.convertDurationSecToString(3661)).toBe(" 1:01:01")
			end
		)

		it(
			"adds days when needed",
			function()
				expect(utils.convertDurationSecToString(86400)).toBe("1:00:00:00")
				expect(utils.convertDurationSecToString(90061)).toBe("1:01:01:01")
			end
		)
	end
)

describe(
	"utils string helpers",
	function()
		it(
			"capitalizes only the first letter",
			function()
				expect(utils.capitalize("hello")).toBe("Hello")
				expect(utils.capitalize("Hello")).toBe("Hello")
				expect(utils.capitalize("")).toBe("")
				expect(utils.capitalize("9lives")).toBe("9lives")
			end
		)

		it(
			"trims surrounding whitespace",
			function()
				expect(utils.trimString("  hi  ")).toBe("hi")
				expect(utils.trimString("hi")).toBe("hi")
				expect(utils.trimString("\t\n hi there \n")).toBe("hi there")
				expect(utils.trimString("   ")).toBe("")
			end
		)

		it(
			"wraps text in a rich text font color tag",
			function()
				expect(utils.getColoredText("hi", Color3.fromRGB(255, 0, 0))).toBe("<font color=\"#ff0000\">hi</font>")
			end
		)
	end
)

describe(
	"utils copy helpers",
	function()
		it(
			"deep copies nested tables without sharing references",
			function()
				local original = { a = 1, nested = { b = 2, list = { 1, 2, 3 } } }
				local copy = utils.deepCopy(original)
				expect(copy).toEqual(original)
				expect(copy).never.toBe(original)
				expect(copy.nested).never.toBe(original.nested)
				expect(copy.nested.list).never.toBe(original.nested.list)
			end
		)

		it(
			"deep copies self-referencing tables without looping forever",
			function()
				local original: { [string]: any } = { name = "loop" }
				original.self = original
				local copy = utils.deepCopy(original)
				expect(copy.self).toBe(copy)
				expect(copy.name).toBe("loop")
			end
		)

		it(
			"deep copies metatables",
			function()
				local metatable = { __index = { inherited = true } }
				local original = setmetatable({}, metatable)
				local copy = utils.deepCopy(original)
				expect(copy.inherited).toBe(true)
				expect(getmetatable(copy)).never.toBe(metatable)
			end
		)

		it(
			"shallow copies only the top level",
			function()
				local original = { a = 1, nested = { b = 2 } }
				local copy = utils.shallowCopy(original)
				expect(copy).toEqual(original)
				expect(copy).never.toBe(original)
				expect(copy.nested).toBe(original.nested)
			end
		)

		it(
			"returns non-tables unchanged from both copy helpers",
			function()
				expect(utils.deepCopy(5)).toBe(5)
				expect(utils.deepCopy("s")).toBe("s")
				expect(utils.shallowCopy(nil)).toBeNil()
			end
		)
	end
)

describe(
	"utils table and array helpers",
	function()
		it(
			"counts entries in dictionaries and arrays",
			function()
				expect(utils.getTableSize({})).toBe(0)
				expect(utils.getTableSize({ 1, 2, 3 })).toBe(3)
				expect(utils.getTableSize({ a = 1, b = 2 })).toBe(2)
			end
		)

		it(
			"finds values in arrays",
			function()
				local array = { "a", "b", "c" }
				expect(utils.doesArrayContain(array, "b")).toBe(true)
				expect(utils.doesArrayContain(array, "z")).toBe(false)
				expect(utils.arrayFindIndexOf(array, "c")).toBe(3)
				expect(utils.arrayFindIndexOf(array, "z")).toBeNil()
			end
		)

		it(
			"appends in place",
			function()
				local array = { 1, 2 }
				utils.arrayAppend(array, { 3, 4 })
				expect(array).toEqual({ 1, 2, 3, 4 })
				utils.arrayAppend(array, {})
				expect(array).toEqual({ 1, 2, 3, 4 })
			end
		)

		it(
			"unions arrays keeping first-seen order without duplicates",
			function()
				expect(utils.getArrayUnion({ 1, 2, 2, 3 }, { 3, 4, 1 })).toEqual({ 1, 2, 3, 4 })
				expect(utils.getArrayUnion({}, {})).toEqual({})
				expect(utils.getArrayUnion({ "a" }, {})).toEqual({ "a" })
			end
		)
	end
)

describe(
	"utils vector helpers",
	function()
		it(
			"measures magnitude ignoring the Y axis",
			function()
				expect(utils.getMagnitudeXZ(Vector3.new(3, 100, 4))).toBe(5)
				expect(utils.getMagnitudeXZSquared(Vector3.new(3, 100, 4))).toBe(25)
				expect(utils.getMagnitudeXZ(Vector3.new(0, 7, 0))).toBe(0)
			end
		)
	end
)
