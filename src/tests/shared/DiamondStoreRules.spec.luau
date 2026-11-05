-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DiamondStoreRules = require(game:GetService("ReplicatedStorage").Shared.DiamondStoreRules)
local DiamondPacksData = require(game:GetService("ServerScriptService").GameData.Store.DiamondPacks)

local function makePacks()
	return {
		{ id = "SMALL", diamonds = 100, productId = 0 },
		{ id = "MEDIUM", diamonds = 300, productId = 11 },
		{ id = "LARGE", diamonds = 700, productId = 12, banner = "Best value" },
	}
end

describe(
	"DiamondStoreRules.packForShortfall",
	function()
		local function makePublished()
			return DiamondStoreRules.publish(makePacks(), {})
		end

		it(
			"offers nothing when the player can afford the price",
			function()
				expect(DiamondStoreRules.packForShortfall(makePublished(), 100, 100)).toBe(nil)
			end
		)

		it(
			"offers the smallest on-sale pack that covers the shortfall",
			function()
				-- SMALL is not on sale, so a shortfall of 50 takes MEDIUM
				local pack = DiamondStoreRules.packForShortfall(makePublished(), 150, 100)
				expect(pack and pack.id).toBe("MEDIUM")
				local pack2 = DiamondStoreRules.packForShortfall(makePublished(), 500, 100)
				expect(pack2 and pack2.id).toBe("LARGE")
			end
		)

		it(
			"offers the largest on-sale pack when none covers the shortfall",
			function()
				local pack = DiamondStoreRules.packForShortfall(makePublished(), 5000, 0)
				expect(pack and pack.id).toBe("LARGE")
			end
		)

		it(
			"offers nothing when no pack is on sale",
			function()
				local published = DiamondStoreRules.publish({ { id = "SMALL", diamonds = 100, productId = 0 } }, {})
				expect(DiamondStoreRules.packForShortfall(published, 50, 0)).toBe(nil)
			end
		)
	end
)

describe(
	"DiamondStoreRules.validatePacks",
	function()
		it(
			"accepts a well-formed ascending list",
			function()
				expect(DiamondStoreRules.validatePacks(makePacks())).toEqual({})
			end
		)

		it(
			"accepts the shipped packs",
			function()
				expect(DiamondStoreRules.validatePacks(DiamondPacksData.PACKS)).toEqual({})
			end
		)

		it(
			"rejects an empty list",
			function()
				expect(#DiamondStoreRules.validatePacks({})).toBe(1)
			end
		)

		it(
			"rejects packs out of size order",
			function()
				local packs = makePacks()
				packs[2].diamonds = 50
				local problems = DiamondStoreRules.validatePacks(packs)
				expect(#problems).toBe(1)
				expect(problems[1]).toContain("pack 2")
			end
		)

		it(
			"rejects a duplicate id, a duplicate product id, and an empty banner",
			function()
				local packs = makePacks()
				packs[2].id = "SMALL"
				packs[3].productId = 11
				packs[3].banner = ""
				expect(#DiamondStoreRules.validatePacks(packs)).toBe(3)
			end
		)

		it(
			"allows several packs with no product yet",
			function()
				local packs = makePacks()
				packs[2].productId = 0
				expect(DiamondStoreRules.validatePacks(packs)).toEqual({})
			end
		)
	end
)

describe(
	"DiamondStoreRules.findPackByProductId",
	function()
		it(
			"finds a pack by its product and never matches the empty id",
			function()
				local packs = makePacks()
				expect(DiamondStoreRules.findPackByProductId(packs, 12).id).toBe("LARGE")
				expect(DiamondStoreRules.findPackByProductId(packs, 0)).toBeNil()
				expect(DiamondStoreRules.findPackByProductId(packs, 99)).toBeNil()
			end
		)
	end
)

describe(
	"DiamondStoreRules catalogue codec",
	function()
		it(
			"publishes prices by product id and round-trips through JSON in order",
			function()
				local published = DiamondStoreRules.publish(makePacks(), { [11] = 99, [12] = 199 })
				expect(published[1].priceRobux).toBe(0)
				expect(published[2].priceRobux).toBe(99)
				expect(published[3].banner).toBe("Best value")
				local decoded = DiamondStoreRules.decodeCatalogue(DiamondStoreRules.encodeCatalogue(published))
				expect(decoded).toEqual(published)
				expect(DiamondStoreRules.isOnSale(decoded[1])).toBe(false)
				expect(DiamondStoreRules.isOnSale(decoded[2])).toBe(true)
			end
		)

		it(
			"refuses an empty, broken, or mis-shaped string",
			function()
				expect(DiamondStoreRules.decodeCatalogue("")).toBeNil()
				expect(DiamondStoreRules.decodeCatalogue("not json")).toBeNil()
				expect(DiamondStoreRules.decodeCatalogue('[{"index":1}]')).toBeNil()
			end
		)
	end
)
