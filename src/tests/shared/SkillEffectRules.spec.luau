-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local SkillEffectRules = require(game:GetService("ReplicatedStorage").Shared.SkillEffectRules)

local EFFECTS = {
	STEADY_SWING = { MODIFIERS = { [Enums.ClassModifier.MINING_SPEED] = 1.1 } },
	DEEP_POCKETS = { MODIFIERS = { [Enums.ClassModifier.BACKPACK_CAPACITY] = 1.1 } },
	QUICK_FIX = { MODIFIERS = { [Enums.ClassModifier.HAMMER_SWING_SPEED] = 1.25 } },
	MOTHER_LODE = { PARAMS = { EVERY_NTH_BREAK = 10 } },
	HEADHUNTER = { PARAMS = { HEADSHOT_MULTIPLIER = 1.25 } },
}

describe("SkillEffectRules.skillIdsOf", function()
	it("lists the held skills in slot order and nothing for no record", function()
		local record = { skills = { ["3"] = { skillId = "C", rarity = 1 }, ["1"] = { skillId = "A", rarity = 1 } } }
		expect(SkillEffectRules.skillIdsOf(record)).toEqual({ "A", "C" })
		expect(SkillEffectRules.skillIdsOf(nil)).toEqual({})
	end)
end)

describe("SkillEffectRules.combineModifiers", function()
	it("multiplies a skill onto the class's axis and leaves the class table alone", function()
		local classModifiers = { [Enums.ClassModifier.MINING_SPEED] = 1.2, [Enums.ClassModifier.MOVE_SPEED] = 1.0 }
		local combined = SkillEffectRules.combineModifiers(classModifiers, { "STEADY_SWING", "DEEP_POCKETS" }, EFFECTS)
		expect(combined[Enums.ClassModifier.MINING_SPEED]).toBeCloseTo(1.32, 5)
		expect(combined[Enums.ClassModifier.BACKPACK_CAPACITY]).toBeCloseTo(1.1, 5)
		expect(combined[Enums.ClassModifier.MOVE_SPEED]).toBe(1.0)
		expect(classModifiers[Enums.ClassModifier.BACKPACK_CAPACITY]).toBeNil()
	end)

	it("ignores a skill with no modifiers and one the effects do not know", function()
		local combined = SkillEffectRules.combineModifiers({}, { "MOTHER_LODE", "NOT_A_SKILL" }, EFFECTS)
		expect(next(combined)).toBeNil()
	end)
end)

describe("SkillEffectRules.param", function()
	it("reads a number and falls back for an unknown skill or key", function()
		expect(SkillEffectRules.param(EFFECTS, "MOTHER_LODE", "EVERY_NTH_BREAK", 3)).toBe(10)
		expect(SkillEffectRules.param(EFFECTS, "MOTHER_LODE", "OTHER", 3)).toBe(3)
		expect(SkillEffectRules.param(EFFECTS, "NOT_A_SKILL", "EVERY_NTH_BREAK", 3)).toBe(3)
	end)
end)

describe("SkillEffectRules.isNthBreak", function()
	it("pays on every nth break and never on a zero count", function()
		expect(SkillEffectRules.isNthBreak(10, 10)).toBe(true)
		expect(SkillEffectRules.isNthBreak(20, 10)).toBe(true)
		expect(SkillEffectRules.isNthBreak(9, 10)).toBe(false)
		expect(SkillEffectRules.isNthBreak(0, 10)).toBe(false)
		expect(SkillEffectRules.isNthBreak(5, 0)).toBe(false)
	end)
end)

describe("SkillEffectRules.headshotMultiplier", function()
	it("keeps a weapon's own multiple, grants the Headhunter's to a holder, and none otherwise", function()
		expect(SkillEffectRules.headshotMultiplier(2, true, 1.25)).toBe(2)
		expect(SkillEffectRules.headshotMultiplier(1, true, 1.25)).toBe(1.25)
		expect(SkillEffectRules.headshotMultiplier(1, false, 1.25)).toBe(1)
	end)
end)

describe("SkillEffectRules.fireRateMultiplier", function()
	it("speeds a holder up only below the health share", function()
		expect(SkillEffectRules.fireRateMultiplier(20, 100, true, 0.25, 1.25)).toBe(1.25)
		expect(SkillEffectRules.fireRateMultiplier(25, 100, true, 0.25, 1.25)).toBe(1)
		expect(SkillEffectRules.fireRateMultiplier(20, 100, false, 0.25, 1.25)).toBe(1)
		expect(SkillEffectRules.fireRateMultiplier(20, 0, true, 0.25, 1.25)).toBe(1)
	end)
end)

describe("SkillEffectRules.donationCredit", function()
	it("counts the paid Iron up by the multiple, rounded, and never past what is left", function()
		expect(SkillEffectRules.donationCredit(10, 1.25, 100)).toBe(13)
		expect(SkillEffectRules.donationCredit(10, 1.25, 11)).toBe(11)
		expect(SkillEffectRules.donationCredit(0, 1.25, 11)).toBe(0)
	end)
end)
