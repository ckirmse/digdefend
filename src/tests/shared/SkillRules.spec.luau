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
	freeRollIntervalSec = 86400,
	keepPriceDiamondsByRarity = { 10, 20, 40, 80, 160 },
}

local CATALOGUE = {
	GOLD_DIGGER = { family = Enums.SkillFamily.MINING, rarity = Enums.Rarity.COMMON, name = "Gold Digger", description = "Gold" },
	STEADY_SWING = { family = Enums.SkillFamily.MINING, rarity = Enums.Rarity.RARE, name = "Steady Swing", description = "Swing" },
	BIG_BANG = { family = Enums.SkillFamily.MINING, rarity = Enums.Rarity.LEGENDARY, name = "Big Bang", description = "Bang" },
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
	end
)

describe(
	"SkillRules free rolls",
	function()
		local DAY = 86400

		it(
			"lets a slot never rolled roll at once",
			function()
				local state = SkillRules.freeRollState(nil, 1000, DAY)
				expect(state.canRoll).toBe(true)
				expect(state.offer).toBeNil()
			end
		)

		it(
			"holds the offer and the wait until the interval has run",
			function()
				local freeRoll = { rollTime = 1000, skillId = "HANDY", rarity = Enums.Rarity.RARE }
				local state = SkillRules.freeRollState(freeRoll, 1000 + DAY - 1, DAY)
				expect(state.canRoll).toBe(false)
				expect(state.nextRollTime).toBe(1000 + DAY)
				expect(state.offer).toEqual({ skillId = "HANDY", rarity = Enums.Rarity.RARE })
			end
		)

		it(
			"waits with no offer once it was kept",
			function()
				local state = SkillRules.freeRollState({ rollTime = 1000 }, 2000, DAY)
				expect(state.canRoll).toBe(false)
				expect(state.offer).toBeNil()
			end
		)

		it(
			"lapses the offer when the next roll is due",
			function()
				local freeRoll = { rollTime = 1000, skillId = "HANDY", rarity = Enums.Rarity.RARE }
				local state = SkillRules.freeRollState(freeRoll, 1000 + DAY, DAY)
				expect(state.canRoll).toBe(true)
				expect(state.offer).toBeNil()
			end
		)

		it(
			"prices a kept offer by its rarity",
			function()
				expect(SkillRules.keepPrice(PRICING, Enums.Rarity.COMMON)).toBe(10)
				expect(SkillRules.keepPrice(PRICING, Enums.Rarity.LEGENDARY)).toBe(160)
			end
		)

		it(
			"writes a wait as hours, minutes, and seconds",
			function()
				expect(SkillRules.formatCountdown(7 * 3600 + 5 * 60 + 9)).toBe("07:05:09")
				expect(SkillRules.formatCountdown(0.2)).toBe("00:00:01")
				expect(SkillRules.formatCountdown(-5)).toBe("00:00:00")
			end
		)

		it(
			"carries the free roll numbers through the pricing codec",
			function()
				local decoded = SkillRules.decodeRerollPricing(SkillRules.encodeRerollPricing(PRICING))
				expect(decoded.freeRollIntervalSec).toBe(86400)
				expect(decoded.keepPriceDiamondsByRarity).toEqual({ 10, 20, 40, 80, 160 })
			end
		)
	end
)
