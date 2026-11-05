-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local SkillRules = require(game:GetService("ReplicatedStorage").Shared.SkillRules)

local PRICING = {
	skillPriceDiamonds = 10,
	isFirstSkillRollFree = true,
	maxSkillSlots = 3,
}

local CATALOGUE = {
	GOLD_DIGGER = { family = Enums.SkillFamily.DIGGING, rarity = Enums.Rarity.COMMON, name = "Gold Digger", description = "Gold" },
	STEADY_SWING = { family = Enums.SkillFamily.DIGGING, rarity = Enums.Rarity.RARE, name = "Steady Swing", description = "Swing" },
	BIG_BANG = { family = Enums.SkillFamily.DEMOLITION, rarity = Enums.Rarity.LEGENDARY, name = "Big Bang", description = "Bang" },
}

describe(
	"SkillRules.rollSkill and skillRollPrice",
	function()
		it(
			"draws a catalogue skill with its rarity, nothing from an empty catalogue",
			function()
				local offer = SkillRules.rollSkill(Random.new(1), CATALOGUE)
				expect(CATALOGUE[offer.skillId]).never.toBeNil()
				expect(offer.rarity).toBe(CATALOGUE[offer.skillId].rarity)
				expect(SkillRules.rollSkill(Random.new(1), {})).toBeNil()
			end
		)

		it(
			"is repeatable for one seed",
			function()
				expect(SkillRules.rollSkill(Random.new(7), CATALOGUE)).toEqual(SkillRules.rollSkill(Random.new(7), CATALOGUE))
			end
		)

		it(
			"charges nothing for the roll into an empty slot when the first roll is free",
			function()
				expect(SkillRules.skillRollPrice(PRICING, true)).toBe(0)
				expect(SkillRules.skillRollPrice(PRICING, false)).toBe(10)
				local paid = table.clone(PRICING)
				paid.isFirstSkillRollFree = false
				expect(SkillRules.skillRollPrice(paid, true)).toBe(10)
			end
		)
	end
)

describe(
	"SkillRules odds",
	function()
		it(
			"shares the catalogue by rarity, every rarity listed in order",
			function()
				local odds = SkillRules.skillRarityOdds(CATALOGUE)
				expect(#odds).toBe(Enums.getCount(Enums.Rarity))
				expect(odds[1].rarity).toBe(Enums.Rarity.COMMON)
				expect(odds[1].percent).toBeCloseTo(100 / 3, 5)
				expect(odds[2].percent).toBe(0)
				expect(odds[5].rarity).toBe(Enums.Rarity.LEGENDARY)
				expect(SkillRules.isOddsTotalExact(odds)).toBe(false)
				expect(SkillRules.isOddsTotalExact(SkillRules.skillRarityOdds({ A = CATALOGUE.GOLD_DIGGER, B = CATALOGUE.BIG_BANG }))).toBe(true)
			end
		)

		it(
			"prints shares whole or to one decimal",
			function()
				expect(SkillRules.percentText(50)).toBe("50%")
				expect(SkillRules.percentText(100 / 3)).toBe("33.3%")
				expect(SkillRules.percentText(0)).toBe("0%")
			end
		)
	end
)

describe(
	"SkillRules.cosmeticItemOrder",
	function()
		it(
			"puts the equipped item first, the pinned one last, the rest by name",
			function()
				local names = { a = "Zebra", b = "Apple", c = "Mango", d = "None" }
				local ordered = SkillRules.cosmeticItemOrder({ "a", "b", "c", "d" }, "c", function(id)
					return names[id]
				end, "d")
				expect(ordered).toEqual({ "c", "b", "a", "d" })
			end
		)
	end
)

describe(
	"SkillRules codecs",
	function()
		it(
			"round-trips the pricing and rejects garbage",
			function()
				expect(SkillRules.decodeRerollPricing(SkillRules.encodeRerollPricing(PRICING))).toEqual(PRICING)
				expect(SkillRules.decodeRerollPricing("")).toBeNil()
				expect(SkillRules.decodeRerollPricing("{}")).toBeNil()
			end
		)

		it(
			"round-trips the skill catalogue and fills missing fields",
			function()
				expect(SkillRules.decodeSkillCatalogue(SkillRules.encodeSkillCatalogue(CATALOGUE))).toEqual(CATALOGUE)
				local sparse = SkillRules.decodeSkillCatalogue("{\"X\":{\"name\":\"X\"}}")
				expect(sparse.X).toEqual({ family = 0, rarity = 0, name = "X", description = "" })
				expect(SkillRules.decodeSkillCatalogue(nil)).toEqual({})
			end
		)

		it(
			"round-trips the hat catalogue",
			function()
				local hats = { HARD_HAT = { name = "Hard Hat", assetId = 123 } }
				expect(SkillRules.decodeHatCatalogue(SkillRules.encodeHatCatalogue(hats))).toEqual(hats)
				expect(SkillRules.decodeHatCatalogue("[1]")).toEqual({})
			end
		)
	end
)
