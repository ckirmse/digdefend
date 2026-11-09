-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GearLockerRules = require(game:GetService("ReplicatedStorage").Shared.GearLockerRules)
local CosmeticLoadoutSchema = require(game:GetService("ReplicatedStorage").Shared.CosmeticLoadoutSchema)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local STOCK_ICON = "rbxassetid://1"

local function makeEntries()
	return {
		{ id = "ACORN_PICK", slot = Enums.CosmeticSlot.PICK_AXE, name = "Acorn Pick", priceKeys = 10, iconId = "rbxassetid://2" },
		{ id = "ZEBRA_PICK", slot = Enums.CosmeticSlot.PICK_AXE, name = "Zebra Pick", priceKeys = 30, iconId = "rbxassetid://3" },
		{ id = "APPLE_PACK", slot = Enums.CosmeticSlot.JET_PACK, name = "Apple Pack", priceKeys = 20, iconId = "rbxassetid://4" },
	}
end

describe(
	"GearLockerRules.LOCKER_SLOTS",
	function()
		it(
			"lays out pick axes then jet packs",
			function()
				expect(GearLockerRules.LOCKER_SLOTS).toEqual({ Enums.CosmeticSlot.PICK_AXE, Enums.CosmeticSlot.JET_PACK })
			end
		)
	end
)

describe(
	"GearLockerRules.cardsForSlot",
	function()
		it(
			"puts the stock card first and marks it worn when the slot is empty",
			function()
				local cards = GearLockerRules.cardsForSlot(makeEntries(), {}, {}, Enums.CosmeticSlot.PICK_AXE, STOCK_ICON)
				expect(#cards).toBe(3)
				expect(cards[1].id).toBe(CosmeticLoadoutSchema.DEFAULT_SKIN_ID)
				expect(cards[1].name).toBe(GearLockerRules.DEFAULT_NAME)
				expect(cards[1].iconId).toBe(STOCK_ICON)
				expect(cards[1].isOwned).toBe(true)
				expect(cards[1].isEquipped).toBe(true)
				expect(cards[2].id).toBe("ACORN_PICK")
				expect(cards[3].id).toBe("ZEBRA_PICK")
			end
		)

		it(
			"marks ownership and the worn skin from the loadout",
			function()
				local cards = GearLockerRules.cardsForSlot(
					makeEntries(),
					{ ZEBRA_PICK = true },
					{ PICK_AXE = "ZEBRA_PICK" },
					Enums.CosmeticSlot.PICK_AXE,
					STOCK_ICON
				)
				expect(cards[1].isEquipped).toBe(false)
				expect(cards[2].isOwned).toBe(false)
				expect(cards[2].isEquipped).toBe(false)
				expect(cards[3].isOwned).toBe(true)
				expect(cards[3].isEquipped).toBe(true)
			end
		)

		it(
			"leaves other slots' items out",
			function()
				local cards = GearLockerRules.cardsForSlot(makeEntries(), {}, {}, Enums.CosmeticSlot.TOWER, STOCK_ICON)
				expect(#cards).toBe(1)
			end
		)
	end
)
