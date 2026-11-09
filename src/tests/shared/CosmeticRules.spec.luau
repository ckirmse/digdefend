-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CosmeticRules = require(game:GetService("ReplicatedStorage").Shared.CosmeticRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local function makeCatalogue()
	return {
		ZEBRA_PICK = { SLOT = Enums.CosmeticSlot.PICK_AXE, NAME = "Zebra Pick", TEMPLATE = "ZEBRA_PICK", REVEAL_SCALE = 1.5, RARITY = Enums.Rarity.RARE },
		APPLE_PACK = { SLOT = Enums.CosmeticSlot.JET_PACK, NAME = "Apple Pack", TEMPLATE = "APPLE_PACK", RARITY = Enums.Rarity.COMMON },
	}
end

describe(
	"CosmeticRules.validateCatalogue",
	function()
		it(
			"accepts a well-formed catalogue",
			function()
				expect(CosmeticRules.validateCatalogue(makeCatalogue())).toEqual({})
			end
		)

		it(
			"names a bad slot, a missing name, a bad reveal scale, and a missing rarity",
			function()
				local catalogue = makeCatalogue()
				catalogue.ZEBRA_PICK.SLOT = 99
				catalogue.APPLE_PACK.NAME = ""
				catalogue.APPLE_PACK.REVEAL_SCALE = 0
				catalogue.ZEBRA_PICK.RARITY = nil
				local problems = CosmeticRules.validateCatalogue(catalogue)
				expect(#problems).toBe(4)
			end
		)
	end
)

describe(
	"CosmeticRules.publish and the codec",
	function()
		it(
			"lists entries by id with the reveal scale defaulted",
			function()
				local published = CosmeticRules.publish(makeCatalogue())
				expect(published[1].id).toBe("APPLE_PACK")
				expect(published[1].revealScale).toBe(1)
				expect(published[2].id).toBe("ZEBRA_PICK")
				expect(published[2].revealScale).toBe(1.5)
			end
		)

		it(
			"round-trips through JSON",
			function()
				local published = CosmeticRules.publish(makeCatalogue())
				local decoded = CosmeticRules.decodeCatalogue(CosmeticRules.encodeCatalogue(published))
				expect(decoded).toEqual(published)
				expect(CosmeticRules.findEntry(decoded, "ZEBRA_PICK").name).toBe("Zebra Pick")
				expect(CosmeticRules.findEntry(decoded, "NOPE")).toBe(nil)
			end
		)

		it(
			"rejects a malformed string",
			function()
				expect(CosmeticRules.decodeCatalogue("")).toBe(nil)
				expect(CosmeticRules.decodeCatalogue("[{\"id\":1}]")).toBe(nil)
			end
		)
	end
)

describe(
	"CosmeticRules.isSkinForSlot",
	function()
		it(
			"takes the stock art on any slot and a catalogue skin on its own slot only",
			function()
				local catalogue = makeCatalogue()
				expect(CosmeticRules.isSkinForSlot(catalogue, "DEFAULT", Enums.CosmeticSlot.PICK_AXE, "DEFAULT")).toBe(true)
				expect(CosmeticRules.isSkinForSlot(catalogue, "DEFAULT", Enums.CosmeticSlot.PICK_AXE, "ZEBRA_PICK")).toBe(true)
				expect(CosmeticRules.isSkinForSlot(catalogue, "DEFAULT", Enums.CosmeticSlot.JET_PACK, "ZEBRA_PICK")).toBe(false)
				expect(CosmeticRules.isSkinForSlot(catalogue, "DEFAULT", Enums.CosmeticSlot.PICK_AXE, "NOPE")).toBe(false)
			end
		)
	end
)
