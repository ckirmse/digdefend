-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local StoreRules = require(game:GetService("ReplicatedStorage").Shared.StoreRules)

local TRACK = {
	priceByLevel = { 0, 15, 40, 100, 250 },
}
local CATALOG = {
	upgrades = {
		[Enums.StoreItem.PICK_AXE] = TRACK,
	},
	consumables = {
		[Enums.StoreItem.TORCH] = { tool = Enums.ToolKind.TORCH, price = 5, amount = 4 },
	},
}

describe(
	"StoreRules.getUpgradeOffer",
	function()
		it(
			"offers the next level at its price",
			function()
				local offer = StoreRules.getUpgradeOffer(TRACK, 1)
				expect(offer.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(offer.level).toBe(2)
				expect(offer.price).toBe(15)
			end
		)
		it(
			"climbs the track one level at a time",
			function()
				local third = StoreRules.getUpgradeOffer(TRACK, 2)
				expect(third.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(third.level).toBe(3)
				expect(third.price).toBe(40)
			end
		)
		it(
			"is maxed past the last price",
			function()
				local offer = StoreRules.getUpgradeOffer(TRACK, 5)
				expect(offer.status).toBe(Enums.StoreOffer.MAXED)
				expect(offer.level).toBe(nil)
			end
		)
	end
)

describe(
	"StoreRules.getOffer and text",
	function()
		it(
			"never locks or maxes a consumable",
			function()
				local offer = StoreRules.getOffer(CATALOG, Enums.StoreItem.TORCH, 1)
				expect(offer.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(offer.price).toBe(5)
				expect(StoreRules.nameText(Enums.StoreItem.TORCH, offer)).toBe("Torch")
			end
		)
		it(
			"returns nil for an item the catalogue lacks",
			function()
				expect(StoreRules.getOffer(CATALOG, Enums.StoreItem.BOOTS, 1)).toBe(nil)
			end
		)
		it(
			"names the next level and the maxed state",
			function()
				expect(StoreRules.nameText(Enums.StoreItem.PICK_AXE, StoreRules.getUpgradeOffer(TRACK, 1))).toBe("Pick Axe 2")
				expect(StoreRules.nameText(Enums.StoreItem.PICK_AXE, StoreRules.getUpgradeOffer(TRACK, 5))).toBe(StoreRules.MAXED_TEXT)
			end
		)
		it(
			"shows a single purchase by its bare name, then as owned",
			function()
				local single = {
					priceByLevel = { 0, 30 },
					startsUnowned = true,
				}
				expect(StoreRules.isSinglePurchase(single)).toBe(true)
				expect(StoreRules.isSinglePurchase(TRACK)).toBe(false)
				local offer = StoreRules.getUpgradeOffer(single, 1)
				expect(offer.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(offer.price).toBe(30)
				expect(StoreRules.nameText(Enums.StoreItem.COMPASS, offer)).toBe("Compass")
				local owned = StoreRules.getUpgradeOffer(single, 2)
				expect(owned.status).toBe(Enums.StoreOffer.MAXED)
				expect(StoreRules.nameText(Enums.StoreItem.COMPASS, owned)).toBe(StoreRules.OWNED_TEXT)
			end
		)
		it(
			"counts a track that starts unowned from its first buy",
			function()
				local bought = {
					priceByLevel = { 0, 90, 270, 800 },
					startsUnowned = true,
				}
				expect(StoreRules.isSinglePurchase(bought)).toBe(false)
				expect(StoreRules.nameText(Enums.StoreItem.GEIGER_COUNTER, StoreRules.getUpgradeOffer(bought, 1))).toBe("Geiger Counter")
				expect(StoreRules.nameText(Enums.StoreItem.GEIGER_COUNTER, StoreRules.getUpgradeOffer(bought, 2))).toBe("Geiger Counter 2")
				expect(StoreRules.nameText(Enums.StoreItem.GEIGER_COUNTER, StoreRules.getUpgradeOffer(bought, 3))).toBe("Geiger Counter 3")
				expect(StoreRules.nameText(Enums.StoreItem.GEIGER_COUNTER, StoreRules.getUpgradeOffer(bought, 4))).toBe(StoreRules.MAXED_TEXT)
				local decoded = StoreRules.decodeCatalog(StoreRules.encodeCatalog({
					upgrades = { [Enums.StoreItem.GEIGER_COUNTER] = bought },
					consumables = {},
				}))
				expect(decoded.upgrades[Enums.StoreItem.GEIGER_COUNTER].startsUnowned).toBe(true)
			end
		)
		it(
			"checks affordability",
			function()
				expect(StoreRules.canAfford(15, 15)).toBe(true)
				expect(StoreRules.canAfford(14, 15)).toBe(false)
			end
		)
		it(
			"builds the Studio stand name from the item key",
			function()
				expect(StoreRules.standNameForItem(Enums.StoreItem.PICK_AXE)).toBe("PickAxeStand")
				expect(StoreRules.standNameForItem(Enums.StoreItem.JET_PACK)).toBe("JetPackStand")
				expect(StoreRules.standNameForItem(Enums.StoreItem.TORCH)).toBe("TorchStand")
			end
		)
	end
)

describe(
	"StoreRules catalog codec",
	function()
		it(
			"round-trips numeric item keys through JSON",
			function()
				local decoded = StoreRules.decodeCatalog(StoreRules.encodeCatalog(CATALOG))
				expect(decoded.upgrades[Enums.StoreItem.PICK_AXE].priceByLevel[3]).toBe(40)
				expect(decoded.consumables[Enums.StoreItem.TORCH].amount).toBe(4)
				expect(decoded.consumables[Enums.StoreItem.TORCH].tool).toBe(Enums.ToolKind.TORCH)
			end
		)
		it(
			"keeps an item whose number does not follow the others",
			function()
				local sparse = {
					upgrades = {
						[Enums.StoreItem.PICK_AXE] = TRACK,
						[Enums.StoreItem.BOOTS] = TRACK,
						[Enums.StoreItem.COMPASS] = { priceByLevel = { 0, 30 } },
					},
					consumables = {},
				}
				local decoded = StoreRules.decodeCatalog(StoreRules.encodeCatalog(sparse))
				expect(decoded.upgrades[Enums.StoreItem.PICK_AXE].priceByLevel[2]).toBe(15)
				expect(decoded.upgrades[Enums.StoreItem.BOOTS].priceByLevel[2]).toBe(15)
				expect(decoded.upgrades[Enums.StoreItem.COMPASS].priceByLevel[2]).toBe(30)
			end
		)
		it(
			"returns nil for garbage",
			function()
				expect(StoreRules.decodeCatalog(nil)).toBe(nil)
				expect(StoreRules.decodeCatalog("not json")).toBe(nil)
			end
		)
	end
)
