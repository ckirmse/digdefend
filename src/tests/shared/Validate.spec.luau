-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Validate = require(game:GetService("ReplicatedStorage").Shared.Validate)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

describe(
	"Validate primitive checks",
	function()
		it(
			"checks booleans, strings, and tables by type",
			function()
				expect(Validate.isBoolean(false)).toBe(true)
				expect(Validate.isBoolean(0)).toBe(false)
				expect(Validate.isString("")).toBe(true)
				expect(Validate.isString(1)).toBe(false)
				expect(Validate.isTable({})).toBe(true)
				expect(Validate.isTable("{}")).toBe(false)
			end
		)

		it(
			"rejects NaN and infinity as finite numbers",
			function()
				expect(Validate.isNumber(0 / 0)).toBe(true)
				expect(Validate.isFiniteNumber(0 / 0)).toBe(false)
				expect(Validate.isFiniteNumber(math.huge)).toBe(false)
				expect(Validate.isFiniteNumber(-math.huge)).toBe(false)
				expect(Validate.isFiniteNumber(1.5)).toBe(true)
			end
		)

		it(
			"accepts only safe whole numbers as integers",
			function()
				expect(Validate.isInteger(3)).toBe(true)
				expect(Validate.isInteger(-3)).toBe(true)
				expect(Validate.isInteger(3.5)).toBe(false)
				expect(Validate.isInteger(2 ^ 53)).toBe(false)
				expect(Validate.isInteger(2 ^ 53 - 1)).toBe(true)
			end
		)

		it(
			"distinguishes arrays from dictionaries",
			function()
				expect(Validate.isArray({})).toBe(true)
				expect(Validate.isArray({ 1, 2, 3 })).toBe(true)
				expect(Validate.isArray({ a = 1 })).toBe(false)
				expect(Validate.isArray({ 1, 2, a = 3 })).toBe(false)
				expect(Validate.isArray("nope")).toBe(false)
			end
		)

		it(
			"bounds table size",
			function()
				expect(Validate.isTableBelowSize({ 1, 2 }, 2)).toBe(true)
				expect(Validate.isTableBelowSize({ 1, 2, 3 }, 2)).toBe(false)
				expect(Validate.isTableBelowSize(5, 2)).toBe(false)
			end
		)
	end
)

describe(
	"Validate.isTableShape",
	function()
		local shape = {
			padIndex = "positiveInteger",
		}

		it(
			"accepts a matching payload",
			function()
				expect(Validate.isTableShape({ padIndex = 2 }, shape)).toBe(true)
			end
		)

		it(
			"rejects a missing key",
			function()
				expect((Validate.isTableShape({}, shape))).toBe(false)
			end
		)

		it(
			"rejects a wrong value type",
			function()
				expect((Validate.isTableShape({ padIndex = "1" }, shape))).toBe(false)
				expect((Validate.isTableShape({ padIndex = 0 }, shape))).toBe(false)
				expect((Validate.isTableShape({ padIndex = 1.5 }, shape))).toBe(false)
			end
		)

		it(
			"rejects extra keys",
			function()
				expect((Validate.isTableShape({ padIndex = 1, sneaky = true }, shape))).toBe(false)
			end
		)

		it(
			"rejects non-table payloads",
			function()
				expect((Validate.isTableShape(nil, shape))).toBe(false)
				expect((Validate.isTableShape(5, shape))).toBe(false)
			end
		)

		it(
			"returns a reason on failure and none on success",
			function()
				local isValid, reason = Validate.isTableShape({ padIndex = 1 }, shape)
				expect(isValid).toBe(true)
				expect(reason).toBeNil()
				local isValidMissing, reasonMissing = Validate.isTableShape({}, shape)
				expect(isValidMissing).toBe(false)
				expect(reasonMissing).toEqual(expect.any("string"))
			end
		)
	end
)

describe(
	"Validate.isValueType named types",
	function()
		it(
			"checks number ranges",
			function()
				expect(Validate.isValueType(0, "nonnegativeNumber")).toBe(true)
				expect((Validate.isValueType(-0.1, "nonnegativeNumber"))).toBe(false)
				expect(Validate.isValueType(0.1, "positiveNumber")).toBe(true)
				expect((Validate.isValueType(0, "positiveNumber"))).toBe(false)
				expect((Validate.isValueType(0 / 0, "number"))).toBe(false)
			end
		)

		it(
			"checks integer ranges",
			function()
				expect(Validate.isValueType(0, "nonnegativeInteger")).toBe(true)
				expect((Validate.isValueType(-1, "nonnegativeInteger"))).toBe(false)
				expect(Validate.isValueType(1, "positiveInteger")).toBe(true)
				expect((Validate.isValueType(0, "positiveInteger"))).toBe(false)
				expect((Validate.isValueType(1.5, "integer"))).toBe(false)
			end
		)

		it(
			"caps string length",
			function()
				expect(Validate.isValueType(string.rep("a", 4096), "string")).toBe(true)
				expect((Validate.isValueType(string.rep("a", 4097), "string"))).toBe(false)
			end
		)

		it(
			"rejects unknown type names",
			function()
				expect((Validate.isValueType(1, "notARealType"))).toBe(false)
			end
		)
	end
)

describe(
	"Validate.isValueType structured types",
	function()
		it(
			"handles optional fields",
			function()
				local testType = { type = "string", optional = true }
				expect(Validate.isValueType(nil, testType)).toBe(true)
				expect(Validate.isValueType("hi", testType)).toBe(true)
				expect((Validate.isValueType(5, testType))).toBe(false)
			end
		)

		it(
			"handles typed arrays",
			function()
				local testType = { type = "array", elementType = "positiveInteger" }
				expect(Validate.isValueType({ 1, 2, 3 }, testType)).toBe(true)
				expect((Validate.isValueType({ 1, "x" }, testType))).toBe(false)
				expect((Validate.isValueType({ a = 1 }, testType))).toBe(false)
			end
		)

		it(
			"handles array length and nonempty constraints",
			function()
				expect(Validate.isValueType({ 1, 1, 1 }, { type = "array", elementType = "integer", length = 3 })).toBe(true)
				expect((Validate.isValueType({ 1, 1 }, { type = "array", elementType = "integer", length = 3 }))).toBe(false)
				expect((Validate.isValueType({}, { type = "array", elementType = "integer", nonempty = true }))).toBe(false)
			end
		)

		it(
			"handles enum types",
			function()
				local testType = { type = "enum", name = "Difficulty" }
				expect(Validate.isValueType(Enums.Difficulty.NORMAL, testType)).toBe(true)
				expect(Validate.isValueType(Enums.Difficulty.NIGHTMARE, testType)).toBe(true)
				expect((Validate.isValueType(99, testType))).toBe(false)
				expect((Validate.isValueType(1, { type = "enum", name = "NoSuchEnum" }))).toBe(false)
			end
		)

		it(
			"handles nested table shapes",
			function()
				local testType = { type = "table", shape = { count = "nonnegativeInteger" } }
				expect(Validate.isValueType({ count = 0 }, testType)).toBe(true)
				expect((Validate.isValueType({ count = -1 }, testType))).toBe(false)
				expect((Validate.isValueType({ count = 1, extra = true }, testType))).toBe(false)
			end
		)

		it(
			"treats a bare table with no type field as a shape",
			function()
				local bareShape = { count = "integer" }
				expect(Validate.isValueType({ count = 1 }, bareShape)).toBe(true)
				expect((Validate.isValueType({ count = "x" }, bareShape))).toBe(false)
			end
		)

		it(
			"requires an actual table for a shapeless table type",
			function()
				local testType = { type = "table" }
				expect(Validate.isValueType({}, testType)).toBe(true)
				expect(Validate.isValueType({ anything = true }, testType)).toBe(true)
				expect((Validate.isValueType(5, testType))).toBe(false)
				expect((Validate.isValueType({}, { type = "table", nonempty = true }))).toBe(false)
			end
		)
	end
)
