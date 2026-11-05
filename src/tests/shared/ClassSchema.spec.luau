-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local ClassSchema = require(game:GetService("ReplicatedStorage").Shared.ClassSchema)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local DEFAULTS = {
	maxSkillSlots = 3,
	validSkillIds = { GOLD_DIGGER = true, HANDY = true },
}

local function makeRecord()
	return {
		skills = { ["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.RARE } },
	}
end

describe(
	"ClassSchema.getDefault",
	function()
		it(
			"has no skills, as a fresh table",
			function()
				local record = ClassSchema.getDefault(DEFAULTS)
				expect(record).toEqual({ skills = {} })
				expect(ClassSchema.getDefault(DEFAULTS)).never.toBe(record)
			end
		)
	end
)

describe(
	"ClassSchema.validate",
	function()
		it(
			"passes a good record through with no repairs",
			function()
				local repairs = {}
				local record = makeRecord()
				expect(ClassSchema.validate(record, DEFAULTS, "classes.GUNNER.", repairs)).toBe(record)
				expect(repairs).toEqual({})
			end
		)

		it(
			"drops a bad skill slot, an unknown skill, a bad rarity, and an extra field",
			function()
				local repairs = {}
				local record = makeRecord()
				record.skills["9"] = { skillId = "GOLD_DIGGER", rarity = 1 }
				record.skills["2"] = { skillId = "NOPE", rarity = 1 }
				record.skills["3"] = { skillId = "HANDY", rarity = 99 }
				record.skills["1"].note = "x"
				ClassSchema.validate(record, DEFAULTS, "p.", repairs)
				expect(record.skills["9"]).toBeNil()
				expect(record.skills["2"]).toBeNil()
				expect(record.skills["3"]).toBeNil()
				expect(record.skills["1"]).toEqual({ skillId = "GOLD_DIGGER", rarity = Enums.Rarity.RARE })
				expect(#repairs).toBe(4)
			end
		)

		it(
			"returns nil for a non-table and drops unknown fields",
			function()
				local repairs = {}
				expect(ClassSchema.validate(7, DEFAULTS, "p.", repairs)).toBeNil()
				local record = makeRecord()
				record.name = "old"
				ClassSchema.validate(record, DEFAULTS, "p.", repairs)
				expect(record.name).toBeNil()
				expect(#repairs).toBe(2)
			end
		)
	end
)

describe(
	"ClassSchema.validateRecords",
	function()
		it(
			"keeps records by class name, drops other keys, and defaults a broken record",
			function()
				local repairs = {}
				local records = { GUNNER = makeRecord(), NOPE = makeRecord(), SNIPER = 5 }
				local validated = ClassSchema.validateRecords(records, DEFAULTS, repairs)
				expect(validated).toBe(records)
				expect(validated.NOPE).toBeNil()
				expect(validated.GUNNER).toEqual(makeRecord())
				expect(validated.SNIPER).toEqual(ClassSchema.getDefault(DEFAULTS))
				expect(#repairs).toBe(2)
			end
		)

		it(
			"resets a non-table to empty",
			function()
				local repairs = {}
				expect(ClassSchema.validateRecords("x", DEFAULTS, repairs)).toEqual({})
				expect(repairs).toEqual({ "classes reset" })
			end
		)
	end
)

describe(
	"ClassSchema codecs",
	function()
		it(
			"round-trips skills in slot order with empty slots kept",
			function()
				local skills = { ["2"] = { skillId = "HANDY", rarity = Enums.Rarity.COMMON } }
				local encoded = ClassSchema.encodeSkills(skills, 3)
				expect(ClassSchema.decodeSkills(encoded)).toEqual(skills)
				expect(ClassSchema.decodeSkills("")).toEqual({})
				expect(ClassSchema.decodeSkills("not json")).toEqual({})
			end
		)

		it(
			"round-trips every class record",
			function()
				local records = { GUNNER = makeRecord(), RECRUIT = ClassSchema.getDefault(DEFAULTS) }
				local decoded = ClassSchema.decodeRecords(ClassSchema.encodeRecords(records, 3))
				expect(decoded).toEqual(records)
				expect(ClassSchema.decodeRecords("")).toEqual({})
			end
		)
	end
)
