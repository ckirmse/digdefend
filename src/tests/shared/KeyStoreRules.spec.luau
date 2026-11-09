-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local KeyStoreRules = require(game:GetService("ReplicatedStorage").Shared.KeyStoreRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
-- the shipped catalogues are not required here: GameData/Cosmetics/Catalogue
-- uses the @game alias, which jest cannot resolve; KeyStoreManager:init
-- validates them at startup instead

local PLACEHOLDER = "rbxassetid://0"

local function makeSkins()
	return {
		ZEBRA_PICK = { SLOT = Enums.CosmeticSlot.PICK_AXE, NAME = "Zebra Pick", TEMPLATE = "ZEBRA_PICK", PRICE_KEYS = 30, RARITY = Enums.Rarity.EPIC },
		APPLE_PACK = { SLOT = Enums.CosmeticSlot.JET_PACK, NAME = "Apple Pack", TEMPLATE = "APPLE_PACK", PRICE_KEYS = 20, RARITY = Enums.Rarity.COMMON },
		ACORN_PICK = { SLOT = Enums.CosmeticSlot.PICK_AXE, NAME = "Acorn Pick", TEMPLATE = "ACORN_PICK", PRICE_KEYS = 10, RARITY = Enums.Rarity.RARE },
	}
end

local function makeEntries()
	return KeyStoreRules.build(makeSkins(), { ZEBRA_PICK = "rbxassetid://7" }, PLACEHOLDER)
end

describe(
	"KeyStoreRules.validate",
	function()
		it(
			"accepts a priced catalogue",
			function()
				expect(KeyStoreRules.validate(makeSkins())).toEqual({})
			end
		)

		it(
			"names a missing, zero, and fractional price",
			function()
				local skins = makeSkins()
				skins.ZEBRA_PICK.PRICE_KEYS = nil
				skins.APPLE_PACK.PRICE_KEYS = 0
				skins.ACORN_PICK.PRICE_KEYS = 2.5
				local problems = KeyStoreRules.validate(skins)
				expect(#problems).toBe(3)
				expect(problems[1]).toContain("ACORN_PICK")
				expect(problems[2]).toContain("APPLE_PACK")
				expect(problems[3]).toContain("ZEBRA_PICK")
			end
		)

		it(
			"names a missing and a bad rarity",
			function()
				local skins = makeSkins()
				skins.ACORN_PICK.RARITY = nil
				skins.APPLE_PACK.RARITY = 99
				local problems = KeyStoreRules.validate(skins)
				expect(#problems).toBe(2)
				expect(problems[1]).toContain("ACORN_PICK")
				expect(problems[2]).toContain("APPLE_PACK")
			end
		)

		it(
			"carries the rarity through build and the codec",
			function()
				local entries = KeyStoreRules.decode(KeyStoreRules.encode(makeEntries())) :: { KeyStoreRules.Entry }
				expect(KeyStoreRules.findEntry(entries, "ZEBRA_PICK").rarity).toBe(Enums.Rarity.EPIC)
				expect(KeyStoreRules.findEntry(entries, "ACORN_PICK").rarity).toBe(Enums.Rarity.RARE)
			end
		)
	end
)

describe(
	"KeyStoreRules.build",
	function()
		it(
			"lists every skin sorted by slot then name",
			function()
				local entries = makeEntries()
				local ids = {}
				for _, entry in entries do
					table.insert(ids, entry.id)
				end
				expect(ids).toEqual({ "ACORN_PICK", "ZEBRA_PICK", "APPLE_PACK" })
			end
		)

		it(
			"carries the price, the slot, and the pictures",
			function()
				local entries = makeEntries()
				local apple = KeyStoreRules.findEntry(entries, "APPLE_PACK")
				expect(apple and apple.slot).toBe(Enums.CosmeticSlot.JET_PACK)
				expect(apple and apple.priceKeys).toBe(20)
				local zebra = KeyStoreRules.findEntry(entries, "ZEBRA_PICK")
				expect(zebra and zebra.iconId).toBe("rbxassetid://7")
				local acorn = KeyStoreRules.findEntry(entries, "ACORN_PICK")
				expect(acorn and acorn.iconId).toBe(PLACEHOLDER)
			end
		)
	end
)

describe(
	"KeyStoreRules.buyRefusal",
	function()
		it(
			"allows a buy the Keys cover of an item not owned",
			function()
				expect(KeyStoreRules.buyRefusal(makeEntries(), {}, 30, "ZEBRA_PICK")).toBe(nil)
			end
		)

		it(
			"refuses an owned item, an unknown one, and a short balance",
			function()
				local entries = makeEntries()
				expect(KeyStoreRules.buyRefusal(entries, { ZEBRA_PICK = true }, 100, "ZEBRA_PICK")).toBe("owned")
				expect(KeyStoreRules.buyRefusal(entries, {}, 100, "NO_SUCH")).toBe("unknown")
				expect(KeyStoreRules.buyRefusal(entries, {}, 29, "ZEBRA_PICK")).toBe("short")
			end
		)
	end
)

describe(
	"KeyStoreRules codec",
	function()
		it(
			"round-trips the list",
			function()
				local entries = makeEntries()
				expect(KeyStoreRules.decode(KeyStoreRules.encode(entries))).toEqual(entries)
			end
		)

		it(
			"rejects an empty string and a malformed entry",
			function()
				expect(KeyStoreRules.decode("")).toBe(nil)
				expect(KeyStoreRules.decode(nil)).toBe(nil)
				expect(KeyStoreRules.decode('[{"id":"X"}]')).toBe(nil)
			end
		)
	end
)
