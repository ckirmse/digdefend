-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local GadgetRules = require(game:GetService("ReplicatedStorage").Shared.GadgetRules)

local function makeCatalog(): GadgetRules.Catalog
	return {
		pricesByKind = {
			[Enums.GadgetKind.AUTO_TURRET] = { 30, 60, 120, 240 },
		},
	}
end

describe(
	"GadgetRules offers",
	function()
		it(
			"only a gadget with prices is upgradable, to one level past its prices",
			function()
				local catalog = makeCatalog()
				expect(GadgetRules.isUpgradable(catalog, Enums.GadgetKind.AUTO_TURRET)).toBe(true)
				expect(GadgetRules.isUpgradable(catalog, Enums.GadgetKind.MEDKIT)).toBe(false)
				expect(GadgetRules.levelCap(catalog, Enums.GadgetKind.AUTO_TURRET)).toBe(5)
				expect(GadgetRules.levelCap(catalog, Enums.GadgetKind.MEDKIT)).toBe(1)
			end
		)

		it(
			"offers the next level at its price and MAX at the cap or for a fixed gadget",
			function()
				local catalog = makeCatalog()
				local first = GadgetRules.getUpgradeOffer(catalog, Enums.GadgetKind.AUTO_TURRET, 1)
				expect(first.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(first.level).toBe(2)
				expect(first.price).toBe(30)
				local last = GadgetRules.getUpgradeOffer(catalog, Enums.GadgetKind.AUTO_TURRET, 4)
				expect(last.level).toBe(5)
				expect(last.price).toBe(240)
				expect(GadgetRules.getUpgradeOffer(catalog, Enums.GadgetKind.AUTO_TURRET, 5).status).toBe(Enums.StoreOffer.MAXED)
				expect(GadgetRules.getUpgradeOffer(catalog, Enums.GadgetKind.MEDKIT, 1).status).toBe(Enums.StoreOffer.MAXED)
				expect(GadgetRules.canAfford(30, 30)).toBe(true)
				expect(GadgetRules.canAfford(29, 30)).toBe(false)
			end
		)

		it(
			"reads a stats row by level and holds the level inside the table",
			function()
				local stats = { { DAMAGE = 8 }, { DAMAGE = 10 }, { DAMAGE = 13 } }
				expect(GadgetRules.statsFor(stats, 1).DAMAGE).toBe(8)
				expect(GadgetRules.statsFor(stats, 2).DAMAGE).toBe(10)
				expect(GadgetRules.statsFor(stats, 9).DAMAGE).toBe(13)
				expect(GadgetRules.statsFor(stats, 0).DAMAGE).toBe(8)
			end
		)

		it(
			"round-trips the catalogue through JSON and refuses junk",
			function()
				local catalog = makeCatalog()
				local decoded = GadgetRules.decodeCatalog(GadgetRules.encodeCatalog(catalog))
				expect(decoded).never.toBeNil()
				expect((decoded :: GadgetRules.Catalog).pricesByKind[Enums.GadgetKind.AUTO_TURRET]).toEqual({ 30, 60, 120, 240 })
				expect(GadgetRules.decodeCatalog("")).toBeNil()
				expect(GadgetRules.decodeCatalog(42)).toBeNil()
				expect(GadgetRules.decodeCatalog("not json")).toBeNil()
			end
		)
	end
)
