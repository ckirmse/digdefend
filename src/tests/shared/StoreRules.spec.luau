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
	-- level N+1 needs Camp Level N, the GameData/Camp/Level default
	requiredCampLevelByLevel = { 1, 1, 2, 3, 4 },
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
			"offers level 2 as a plain buy at camp level 1",
			function()
				local offer = StoreRules.getUpgradeOffer(TRACK, 1, 1)
				expect(offer.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(offer.level).toBe(2)
				expect(offer.price).toBe(15)
			end
		)
		it(
			"locks level N+1 until camp level N",
			function()
				local locked = StoreRules.getUpgradeOffer(TRACK, 2, 1)
				expect(locked.status).toBe(Enums.StoreOffer.LOCKED)
				expect(locked.level).toBe(3)
				expect(locked.requiredCampLevel).toBe(2)
				local open = StoreRules.getUpgradeOffer(TRACK, 2, 2)
				expect(open.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(open.price).toBe(40)
			end
		)
		it(
			"reads the gate from the track's table, not a formula",
			function()
				local loose = {
					priceByLevel = { 0, 15, 40, 100 },
					requiredCampLevelByLevel = { 1, 1, 1, 3 },
				}
				expect(StoreRules.getUpgradeOffer(loose, 2, 1).status).toBe(Enums.StoreOffer.AVAILABLE)
				local gated = StoreRules.getUpgradeOffer(loose, 3, 2)
				expect(gated.status).toBe(Enums.StoreOffer.LOCKED)
				expect(gated.requiredCampLevel).toBe(3)
			end
		)
		it(
			"never gates a level the table does not mention",
			function()
				local short = {
					priceByLevel = { 0, 15, 40 },
					requiredCampLevelByLevel = {},
				}
				expect(StoreRules.getUpgradeOffer(short, 2, 1).status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(StoreRules.requiredCampLevel(short, 3)).toBe(1)
			end
		)
		it(
			"is maxed past the last price",
			function()
				local offer = StoreRules.getUpgradeOffer(TRACK, 5, 9)
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
				local offer = StoreRules.getOffer(CATALOG, Enums.StoreItem.TORCH, 1, 1)
				expect(offer.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(offer.price).toBe(5)
				expect(StoreRules.nameText(Enums.StoreItem.TORCH, offer)).toBe("Torch")
			end
		)
		it(
			"returns nil for an item the catalogue lacks",
			function()
				expect(StoreRules.getOffer(CATALOG, Enums.StoreItem.BOOTS, 1, 1)).toBe(nil)
			end
		)
		it(
			"names the next level and the maxed state",
			function()
				expect(StoreRules.nameText(Enums.StoreItem.PICK_AXE, StoreRules.getUpgradeOffer(TRACK, 1, 1))).toBe("Pick Axe 2")
				expect(StoreRules.nameText(Enums.StoreItem.PICK_AXE, StoreRules.getUpgradeOffer(TRACK, 5, 1))).toBe(StoreRules.MAXED_TEXT)
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
				expect(decoded.upgrades[Enums.StoreItem.PICK_AXE].requiredCampLevelByLevel[3]).toBe(2)
				expect(decoded.consumables[Enums.StoreItem.TORCH].amount).toBe(4)
				expect(decoded.consumables[Enums.StoreItem.TORCH].tool).toBe(Enums.ToolKind.TORCH)
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

describe(
	"StoreRules.requiredCampLevelForOffer",
	function()
		it(
			"names the level for any upgrade offer and nothing for the rest",
			function()
				expect(StoreRules.requiredCampLevelForOffer(StoreRules.getUpgradeOffer(TRACK, 1, 1))).toBe(1)
				expect(StoreRules.requiredCampLevelForOffer(StoreRules.getUpgradeOffer(TRACK, 2, 1))).toBe(2)
				expect(StoreRules.requiredCampLevelForOffer(StoreRules.getUpgradeOffer(TRACK, 5, 1))).toBe(nil)
				expect(StoreRules.requiredCampLevelForOffer(StoreRules.getConsumableOffer({ tool = 3, price = 5, amount = 4 }))).toBe(nil)
			end
		)
	end
)
