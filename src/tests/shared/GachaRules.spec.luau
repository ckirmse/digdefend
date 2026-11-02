-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GachaRules = require(game:GetService("ReplicatedStorage").Shared.GachaRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local CONFIG = {
	maxSkillSlots = 3,
	keysPerKeysResult = 1,
	keysPerCompleteClass = 2,
	keysPerDuplicateCosmetic = 1,
}

local function makePool()
	return {
		classKinds = { Enums.ClassKind.GUNNER, Enums.ClassKind.SNIPER },
		cosmeticIds = { "HARD_HAT", "LAMP" },
		classWeight = 60,
		cosmeticWeight = 30,
		keysWeight = 10,
	}
end

describe(
	"GachaRules.odds",
	function()
		it(
			"shares the weights out as fractions of one",
			function()
				local odds = GachaRules.odds(makePool())
				expect(odds.CLASS).toBeCloseTo(0.6, 5)
				expect(odds.COSMETIC).toBeCloseTo(0.3, 5)
				expect(odds.KEYS).toBeCloseTo(0.1, 5)
			end
		)

		it(
			"drops a kind with nothing to draw and gives its share to the rest",
			function()
				local pool = makePool()
				pool.cosmeticIds = {}
				local odds = GachaRules.odds(pool)
				expect(odds.COSMETIC).toBeNil()
				expect(odds.CLASS).toBeCloseTo(60 / 70, 5)
				expect(odds.KEYS).toBeCloseTo(10 / 70, 5)
			end
		)

		it(
			"is empty for a pool with nothing in it",
			function()
				expect(GachaRules.odds({ classKinds = {}, cosmeticIds = {}, classWeight = 1, cosmeticWeight = 1, keysWeight = 0 })).toEqual({})
			end
		)
	end
)

describe(
	"GachaRules.prizeList",
	function()
		it(
			"gives every entry its kind's share over the kind's count, most likely first",
			function()
				local prizes = GachaRules.prizeList(makePool())
				expect(#prizes).toBe(5)
				expect(prizes[1].kind).toBe(Enums.GachaResultKind.CLASS)
				expect(prizes[1].odds).toBeCloseTo(0.3, 5)
				expect(prizes[2].key).toBe("CLASS:3")
				expect(prizes[3].kind).toBe(Enums.GachaResultKind.COSMETIC)
				expect(prizes[3].odds).toBeCloseTo(0.15, 5)
				expect(prizes[5].key).toBe("KEYS")
				expect(prizes[5].odds).toBeCloseTo(0.1, 5)
				local total = 0
				for _, prize in prizes do
					total += prize.odds
				end
				expect(total).toBeCloseTo(1, 5)
			end
		)

		it(
			"leaves out a kind with nothing to draw",
			function()
				local pool = makePool()
				pool.cosmeticIds = {}
				local prizes = GachaRules.prizeList(pool)
				expect(#prizes).toBe(3)
				for _, prize in prizes do
					expect(prize.kind).never.toBe(Enums.GachaResultKind.COSMETIC)
				end
			end
		)
	end
)

describe(
	"GachaRules.formatOddsPercent",
	function()
		it(
			"shows more detail as the chance shrinks and trims trailing zeros",
			function()
				expect(GachaRules.formatOddsPercent(0.5)).toBe("50%")
				expect(GachaRules.formatOddsPercent(0.045)).toBe("4.5%")
				expect(GachaRules.formatOddsPercent(0.04)).toBe("4%")
				expect(GachaRules.formatOddsPercent(0.0005)).toBe("0.05%")
				expect(GachaRules.formatOddsPercent(0.001)).toBe("0.1%")
				expect(GachaRules.formatOddsPercent(1)).toBe("100%")
			end
		)
	end
)

describe(
	"GachaRules.draw",
	function()
		it(
			"only ever draws what the pool holds, at about the stated odds",
			function()
				local random = Random.new(7)
				local pool = makePool()
				local counts = { [Enums.GachaResultKind.CLASS] = 0, [Enums.GachaResultKind.COSMETIC] = 0, [Enums.GachaResultKind.KEYS] = 0 }
				for _ = 1, 3000 do
					local draw = GachaRules.draw(random, pool)
					counts[draw.kind] += 1
					if draw.kind == Enums.GachaResultKind.CLASS then
						expect(table.find(pool.classKinds, draw.classKind)).never.toBeNil()
					elseif draw.kind == Enums.GachaResultKind.COSMETIC then
						expect(table.find(pool.cosmeticIds, draw.cosmeticId)).never.toBeNil()
					end
				end
				expect(counts[Enums.GachaResultKind.CLASS] / 3000).toBeGreaterThan(0.5)
				expect(counts[Enums.GachaResultKind.CLASS] / 3000).toBeLessThan(0.7)
				expect(counts[Enums.GachaResultKind.KEYS] / 3000).toBeGreaterThan(0.05)
				expect(counts[Enums.GachaResultKind.KEYS] / 3000).toBeLessThan(0.15)
			end
		)

		it(
			"never draws a cosmetic when the catalogue is empty",
			function()
				local random = Random.new(3)
				local pool = makePool()
				pool.cosmeticIds = {}
				for _ = 1, 500 do
					expect(GachaRules.draw(random, pool).kind).never.toBe(Enums.GachaResultKind.COSMETIC)
				end
			end
		)

		it(
			"returns nil for an empty pool",
			function()
				expect(GachaRules.draw(Random.new(1), { classKinds = {}, cosmeticIds = {}, classWeight = 1, cosmeticWeight = 1, keysWeight = 0 })).toBeNil()
			end
		)

		it(
			"is reproducible from a seed",
			function()
				local first = GachaRules.draw(Random.new(42), makePool())
				local second = GachaRules.draw(Random.new(42), makePool())
				expect(first).toEqual(second)
			end
		)
	end
)

describe(
	"GachaRules.resolve",
	function()
		local classDraw = { kind = Enums.GachaResultKind.CLASS, classKind = Enums.ClassKind.GUNNER }

		it(
			"unlocks a class the player does not own, with no skill slots",
			function()
				local result = GachaRules.resolve(classDraw, { RECRUIT = 0 }, {}, CONFIG)
				expect(result.kind).toBe(Enums.GachaResultKind.CLASS)
				expect(result.classKind).toBe(Enums.ClassKind.GUNNER)
				expect(result.keys).toBe(0)
			end
		)

		it(
			"opens the skill slots of an owned class in order",
			function()
				for open = 0, 2 do
					local result = GachaRules.resolve(classDraw, { GUNNER = open }, {}, CONFIG)
					expect(result.kind).toBe(Enums.GachaResultKind.SKILL_SLOT)
					expect(result.skillSlot).toBe(open + 1)
					expect(result.classKind).toBe(Enums.ClassKind.GUNNER)
				end
			end
		)

		it(
			"pays Keys for a complete class and says which class was rolled",
			function()
				local result = GachaRules.resolve(classDraw, { GUNNER = 3 }, {}, CONFIG)
				expect(result.kind).toBe(Enums.GachaResultKind.KEYS)
				expect(result.keys).toBe(2)
				expect(result.convertedFromKind).toBe(Enums.GachaResultKind.CLASS)
				expect(result.convertedClassKind).toBe(Enums.ClassKind.GUNNER)
			end
		)

		it(
			"grants a new cosmetic and pays Keys for a duplicate",
			function()
				local draw = { kind = Enums.GachaResultKind.COSMETIC, cosmeticId = "LAMP" }
				local fresh = GachaRules.resolve(draw, {}, {}, CONFIG)
				expect(fresh.kind).toBe(Enums.GachaResultKind.COSMETIC)
				expect(fresh.cosmeticId).toBe("LAMP")
				local duplicate = GachaRules.resolve(draw, {}, { LAMP = true }, CONFIG)
				expect(duplicate.kind).toBe(Enums.GachaResultKind.KEYS)
				expect(duplicate.keys).toBe(1)
				expect(duplicate.convertedCosmeticId).toBe("LAMP")
			end
		)

		it(
			"pays Keys outright for a Keys draw",
			function()
				local result = GachaRules.resolve({ kind = Enums.GachaResultKind.KEYS }, {}, {}, CONFIG)
				expect(result.kind).toBe(Enums.GachaResultKind.KEYS)
				expect(result.keys).toBe(1)
				expect(result.convertedFromKind).toBeNil()
			end
		)
	end
)

describe(
	"GachaRules.applyResult",
	function()
		it(
			"takes a class from locked to complete in four rolls and pays Keys after",
			function()
				local progress = { RECRUIT = 0 }
				local owned = {}
				local draw = { kind = Enums.GachaResultKind.CLASS, classKind = Enums.ClassKind.SNIPER }
				local keys = 0
				for _ = 1, 5 do
					local result = GachaRules.resolve(draw, progress, owned, CONFIG)
					keys += GachaRules.applyResult(progress, owned, result)
				end
				expect(progress.SNIPER).toBe(3)
				expect(keys).toBe(2)
				expect(GachaRules.isClassOwned(progress, Enums.ClassKind.SNIPER)).toBe(true)
				expect(GachaRules.isClassOwned(progress, Enums.ClassKind.PYRO)).toBe(false)
				expect(GachaRules.openSkillSlots(progress, Enums.ClassKind.SNIPER, 3)).toBe(3)
				expect(GachaRules.openSkillSlots(progress, Enums.ClassKind.PYRO, 3)).toBe(0)
			end
		)

		it(
			"records a won cosmetic",
			function()
				local owned = {}
				GachaRules.applyResult({}, owned, { kind = Enums.GachaResultKind.COSMETIC, cosmeticId = "LAMP", keys = 0 })
				expect(owned.LAMP).toBe(true)
			end
		)

		it(
			"caps the open slot count at the maximum",
			function()
				expect(GachaRules.openSkillSlots({ GUNNER = 9 }, Enums.ClassKind.GUNNER, 3)).toBe(3)
			end
		)
	end
)

describe(
	"GachaRules.poolClassKinds",
	function()
		it(
			"leaves the excluded classes out and sorts the rest",
			function()
				local kinds = GachaRules.poolClassKinds({ 3, 1, 2 }, { 1 })
				expect(kinds).toEqual({ 2, 3 })
			end
		)
	end
)

describe(
	"GachaRules codecs",
	function()
		it(
			"round-trips the published config",
			function()
				local config = {
					rollPriceDiamonds = 100,
					directClassPriceDiamonds = 400,
					odds = { CLASS = 0.6, COSMETIC = 0.3, KEYS = 0.1 },
					poolClassKinds = { 2, 3, 4 },
					prizes = GachaRules.prizeList(makePool()),
					maxSkillSlots = 3,
				}
				local decoded = GachaRules.decodeConfig(GachaRules.encodeConfig(config))
				expect(#decoded.prizes).toBe(5)
				expect(decoded.prizes[1].classKind).toBe(Enums.ClassKind.GUNNER)
				expect(decoded.prizes[5].key).toBe("KEYS")
				expect(decoded.rollPriceDiamonds).toBe(100)
				expect(decoded.directClassPriceDiamonds).toBe(400)
				expect(decoded.odds.CLASS).toBeCloseTo(0.6, 5)
				expect(decoded.poolClassKinds).toEqual({ 2, 3, 4 })
				expect(decoded.maxSkillSlots).toBe(3)
			end
		)

		it(
			"returns nil for a missing or broken config",
			function()
				expect(GachaRules.decodeConfig(nil)).toBeNil()
				expect(GachaRules.decodeConfig("")).toBeNil()
				expect(GachaRules.decodeConfig("{not json")).toBeNil()
			end
		)

		it(
			"round-trips the progress map and the owned cosmetics",
			function()
				local progress = GachaRules.decodeProgress(GachaRules.encodeProgress({ RECRUIT = 0, GUNNER = 2 }))
				expect(progress).toEqual({ RECRUIT = 0, GUNNER = 2 })
				local owned = GachaRules.decodeOwnedCosmetics(GachaRules.encodeOwnedCosmetics({ LAMP = true, HARD_HAT = true }))
				expect(owned).toEqual({ LAMP = true, HARD_HAT = true })
				expect(GachaRules.decodeProgress(nil)).toEqual({})
				expect(GachaRules.decodeOwnedCosmetics("oops")).toEqual({})
			end
		)
	end
)
