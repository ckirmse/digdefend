-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CharacterRules = require(game:GetService("ReplicatedStorage").Shared.CharacterRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local PRICING = {
	diamondPriceBySlot = { [2] = 300 },
	robuxProductId = 12345,
	maxCharacters = 4,
}

describe(
	"CharacterRules.nextSlotOffer",
	function()
		it(
			"offers the second slot for Diamonds, later slots for Robux, nothing at the cap",
			function()
				expect(CharacterRules.nextSlotOffer(1, PRICING)).toEqual({ slot = 2, currency = Enums.SlotCurrency.DIAMONDS, diamonds = 300 })
				expect(CharacterRules.nextSlotOffer(2, PRICING)).toEqual({ slot = 3, currency = Enums.SlotCurrency.ROBUX, productId = 12345 })
				expect(CharacterRules.nextSlotOffer(3, PRICING)).toEqual({ slot = 4, currency = Enums.SlotCurrency.ROBUX, productId = 12345 })
				expect(CharacterRules.nextSlotOffer(4, PRICING)).toBeNil()
				expect(CharacterRules.nextSlotOffer(9, PRICING)).toBeNil()
			end
		)

		it(
			"never offers the first slot, which every player already has",
			function()
				expect(CharacterRules.nextSlotOffer(0, PRICING)).toBeNil()
			end
		)

		it(
			"passes a missing product through as 0 so the menu can say the slot is coming",
			function()
				local offer = CharacterRules.nextSlotOffer(2, { diamondPriceBySlot = { [2] = 300 }, robuxProductId = 0, maxCharacters = 5 })
				expect(offer.productId).toBe(0)
			end
		)
	end
)

describe(
	"CharacterRules pricing codec",
	function()
		it(
			"round-trips the pricing with numeric slot keys",
			function()
				local decoded = CharacterRules.decodePricing(CharacterRules.encodePricing(PRICING))
				expect(decoded).toEqual(PRICING)
			end
		)

		it(
			"returns nil for garbage",
			function()
				expect(CharacterRules.decodePricing("")).toBeNil()
				expect(CharacterRules.decodePricing(nil)).toBeNil()
				expect(CharacterRules.decodePricing("nope")).toBeNil()
				expect(CharacterRules.decodePricing("{}")).toBeNil()
			end
		)
	end
)

local REROLL_PRICING = {
	gearPriceDiamonds = 10,
	skillPriceDiamonds = 10,
	isFirstSkillRollFree = true,
	minStars = 1,
	maxStars = 5,
	bonusPerStar = 0.05,
	skillSlotUnlockNights = { 0, 15, 50 },
	rankPointsByRarity = { 1, 2, 3, 4, 5 },
	rankBaselinePoints = 3,
	rankBands = { { minRank = 1, rarity = 1 }, { minRank = 8, rarity = 2 }, { minRank = 18, rarity = 3 } },
}

local CATALOGUE = {
	A = { family = 1, rarity = 1, name = "A", description = "a" },
	B = { family = 1, rarity = 2, name = "B", description = "b" },
	C = { family = 2, rarity = 3, name = "C", description = "c" },
	D = { family = 2, rarity = 4, name = "D", description = "d" },
}

describe(
	"CharacterRules rolls",
	function()
		it(
			"rolls stars inside the bounds",
			function()
				local random = Random.new(7)
				local seen = {}
				for _ = 1, 200 do
					local stars = CharacterRules.rollStars(random, REROLL_PRICING)
					expect(stars >= 1 and stars <= 5).toBe(true)
					seen[stars] = true
				end
				for stars = 1, 5 do
					expect(seen[stars]).toBe(true)
				end
			end
		)

		it(
			"rolls a gear kind and stars together, every kind of the slot reachable",
			function()
				local random = Random.new(11)
				local seenKinds = {}
				for _ = 1, 300 do
					local offer = CharacterRules.rollGear(random, Enums.GearSlot.TOWER_1, REROLL_PRICING)
					expect(Enums.isValidValue(Enums.TowerKind, offer.kind)).toBe(true)
					expect(offer.stars >= 1 and offer.stars <= 5).toBe(true)
					seenKinds[offer.kind] = true
				end
				for _, kind in Enums.getAllValues(Enums.TowerKind) do
					expect(seenKinds[kind]).toBe(true)
				end
				-- the weapon roll draws from every weapon kind (five since the class weapons of 2026-10-16)
				expect(Enums.isValidValue(Enums.WeaponKind, CharacterRules.rollGear(random, Enums.GearSlot.WEAPON, REROLL_PRICING).kind)).toBe(true)
				expect(CharacterRules.rollGear(random, 99, REROLL_PRICING)).toBeNil()
			end
		)

		it(
			"lists the gear odds by rarity, every rung a fifth",
			function()
				local odds = CharacterRules.gearRarityOdds(REROLL_PRICING)
				expect(#odds).toBe(5)
				for index, line in odds do
					expect(line.rarity).toBe(index)
					expect(line.percent).toBeCloseTo(20, 5)
				end
				expect(CharacterRules.isOddsTotalExact(odds)).toBe(true)
				local narrow = CharacterRules.gearRarityOdds({ minStars = 2, maxStars = 3 } :: any)
				expect(narrow[1].percent).toBe(0)
				expect(narrow[2].percent).toBe(50)
				expect(narrow[3].percent).toBe(50)
				expect(narrow[5].percent).toBe(0)
			end
		)

		it(
			"lists the skill odds by how many skills carry each rarity",
			function()
				local odds = CharacterRules.skillRarityOdds(CATALOGUE)
				expect(#odds).toBe(5)
				expect(odds[1].percent).toBe(25)
				expect(odds[4].percent).toBe(25)
				expect(odds[5].percent).toBe(0)
				expect(CharacterRules.isOddsTotalExact(odds)).toBe(true)
				local thirds = CharacterRules.skillRarityOdds({ A = CATALOGUE.A, B = CATALOGUE.B, C = CATALOGUE.C })
				expect(CharacterRules.isOddsTotalExact(thirds)).toBe(false)
				expect(CharacterRules.percentText(thirds[1].percent)).toBe("33.3%")
				expect(CharacterRules.percentText(25)).toBe("25%")
				expect(CharacterRules.skillRarityOdds({})[1].percent).toBe(0)
			end
		)

		it(
			"orders a cosmetics row equipped first, then by name",
			function()
				local names = { a = "Zed", b = "Alpha", c = "Mid", d = "Mid" }
				local nameOf = function(id)
					return names[id]
				end
				expect(CharacterRules.cosmeticItemOrder({ "a", "b", "c", "d" }, "c", nameOf)).toEqual({ "c", "b", "d", "a" })
				expect(CharacterRules.cosmeticItemOrder({ "a", "b" }, nil, nameOf)).toEqual({ "b", "a" })
				expect(CharacterRules.cosmeticItemOrder({ "a", "b" }, "zz", nameOf)).toEqual({ "b", "a" })
				expect(CharacterRules.cosmeticItemOrder({}, "a", nameOf)).toEqual({})
				expect(CharacterRules.cosmeticItemOrder({ "a", "b", "c" }, "c", nameOf, "c")).toEqual({ "b", "a", "c" })
				expect(CharacterRules.cosmeticItemOrder({ "a", "b", "c" }, "a", nameOf, "c")).toEqual({ "a", "b", "c" })
			end
		)

		it(
			"describes the kind odds",
			function()
				expect(CharacterRules.describeKindOdds(Enums.GearSlot.WEAPON)).toBe("Each of the 5 kinds has a 20% chance")
				expect(CharacterRules.describeKindOdds(Enums.GearSlot.POST)).toBe("Each of the 12 kinds has a 8% chance")
				expect(CharacterRules.describeKindOdds(Enums.GearSlot.TOWER_2)).toBe("Each of the 7 kinds has a 14% chance")
			end
		)

		it(
			"rolls one skill from the whole catalogue with its rarity, the current one included",
			function()
				local random = Random.new(3)
				local seen = {}
				for _ = 1, 200 do
					local offer = CharacterRules.rollSkill(random, CATALOGUE)
					expect(CATALOGUE[offer.skillId]).never.toBeNil()
					expect(offer.rarity).toBe(CATALOGUE[offer.skillId].rarity)
					seen[offer.skillId] = true
				end
				for id in CATALOGUE do
					expect(seen[id]).toBe(true)
				end
				expect(CharacterRules.rollSkill(random, {})).toBeNil()
			end
		)

		it(
			"makes the roll into an empty slot free only when the pricing says so",
			function()
				expect(CharacterRules.skillRollPrice(REROLL_PRICING, true)).toBe(0)
				expect(CharacterRules.skillRollPrice(REROLL_PRICING, false)).toBe(10)
				local paid = table.clone(REROLL_PRICING)
				paid.isFirstSkillRollFree = false
				expect(CharacterRules.skillRollPrice(paid, true)).toBe(10)
			end
		)

		it(
			"names stars as numerals and describes even odds",
			function()
				expect(CharacterRules.starNumeral(1)).toBe("I")
				expect(CharacterRules.starNumeral(4)).toBe("IV")
				expect(CharacterRules.starNumeral(9)).toBe("9")
				expect(CharacterRules.rarityForStars(1)).toBe(Enums.Rarity.COMMON)
				expect(CharacterRules.rarityForStars(4)).toBe(Enums.Rarity.EPIC)
				expect(CharacterRules.rarityForStars(9)).toBe(Enums.Rarity.LEGENDARY)
				expect(CharacterRules.rarityName(Enums.Rarity.EPIC)).toBe("Epic")
			end
		)

		it(
			"round-trips the reroll pricing and the skill catalogue",
			function()
				expect(CharacterRules.decodeRerollPricing(CharacterRules.encodeRerollPricing(REROLL_PRICING))).toEqual(REROLL_PRICING)
				expect(CharacterRules.decodeRerollPricing("")).toBeNil()
				expect(CharacterRules.decodeSkillCatalogue(CharacterRules.encodeSkillCatalogue(CATALOGUE))).toEqual(CATALOGUE)
				expect(CharacterRules.decodeSkillCatalogue(nil)).toEqual({})
				local hats = { RED_CAP = { name = "Red Baseball Cap", assetId = 1028606 } }
				expect(CharacterRules.decodeHatCatalogue(CharacterRules.encodeHatCatalogue(hats))).toEqual(hats)
				expect(CharacterRules.decodeHatCatalogue("junk")).toEqual({})
			end
		)
	end
)

describe(
	"CharacterRules.rankOf",
	function()
		it(
			"is 1 for a new character and scores every gear row and filled skill by rarity",
			function()
				local points = { 1, 2, 3, 4, 5 }
				expect(CharacterRules.rankOf({ 1, 1, 1, 1 }, {}, points, 3)).toBe(1)
				expect(CharacterRules.rankOf({ 3, 1, 5, 2 }, {}, points, 3)).toBe(8)
				expect(CharacterRules.rankOf({ 1, 1, 1, 1 }, { Enums.Rarity.COMMON }, points, 3)).toBe(2)
				expect(CharacterRules.rankOf({ 5, 5, 5, 5 }, { 5, 5, 5 }, points, 3)).toBe(32)
				expect(CharacterRules.rankOf({}, {}, points, 3)).toBe(1)
			end
		)

		it(
			"round-trips the points table through the pricing codec",
			function()
				local decoded = CharacterRules.decodeRerollPricing(CharacterRules.encodeRerollPricing(REROLL_PRICING))
				expect(decoded.rankPointsByRarity).toEqual({ 1, 2, 3, 4, 5 })
				expect(decoded.rankBaselinePoints).toBe(3)
				expect(CharacterRules.rankOfPricing({ 2, 1, 1, 1 }, {}, decoded)).toBe(2)
				expect(decoded.rankBands).toEqual(REROLL_PRICING.rankBands)
			end
		)

		it(
			"names the band a Rank falls in",
			function()
				local bands = REROLL_PRICING.rankBands
				expect(CharacterRules.rankBand(1, bands)).toBe(1)
				expect(CharacterRules.rankBand(7, bands)).toBe(1)
				expect(CharacterRules.rankBand(8, bands)).toBe(2)
				expect(CharacterRules.rankBand(99, bands)).toBe(3)
				expect(CharacterRules.rankText(9, bands)).toBe("Rank 9 - Uncommon")
			end
		)

		it(
			"rewards the top rungs more with a curved points table",
			function()
				local curved = { 1, 2, 4, 7, 11 }
				expect(CharacterRules.rankOf({ 1, 1, 1, 1 }, {}, curved, 3)).toBe(1)
				expect(CharacterRules.rankOf({ 5, 1, 1, 1 }, {}, curved, 3)).toBe(11)
				expect(CharacterRules.rankOf({ 5, 5, 5, 5 }, { 5, 5, 5 }, curved, 3)).toBe(74)
			end
		)

		it(
			"reads a record's gear rows",
			function()
				local record = {
					id = "a",
					name = "A",
					nightsSurvived = 0,
					gear = {
						WEAPON = { kind = "RIFLE", stars = 2 },
						POST = { kind = "MACHINE_GUN", stars = 1 },
						TOWER_1 = { kind = "SENTRY_GUN", stars = 4 },
						TOWER_2 = { kind = "FLAMETHROWER", stars = 1 },
					},
					skills = {},
					cosmetics = {},
				}
				expect(CharacterRules.rankOfRecord(record, { 1, 2, 3, 4, 5 }, 3)).toBe(5)
			end
		)
	end
)
