-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local ClassCatalogueRules = require(game:GetService("ReplicatedStorage").Shared.ClassCatalogueRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local ROSTER = {
	[Enums.ClassKind.RECRUIT] = { KIT = { WEAPON = 1, POST = 2, TOWER = 3, GADGET = 0 } },
	[Enums.ClassKind.GUNNER] = { KIT = { WEAPON = 5, POST = 6, TOWER = 7, GADGET = 8 } },
}

local DESCRIPTIONS = {
	BY_CLASS_KIND = { [Enums.ClassKind.GUNNER] = "Shoots things" },
	BY_KIT_SLOT = {
		[Enums.GearSlot.WEAPON] = { [5] = "A rifle" },
		[Enums.GearSlot.TOWER_1] = { [7] = "A tower" },
	},
	BY_GADGET_KIND = { [8] = "A gadget" },
}

describe(
	"ClassCatalogueRules.listedKinds",
	function()
		it(
			"lists every class but the excluded ones, in enum order",
			function()
				local kinds = ClassCatalogueRules.listedKinds({ Enums.ClassKind.MEDIC, Enums.ClassKind.HAULER })
				expect(#kinds).toBe(Enums.getCount(Enums.ClassKind) - 2)
				expect(kinds[1]).toBe(Enums.ClassKind.RECRUIT)
				expect(table.find(kinds, Enums.ClassKind.MEDIC)).toBeNil()
			end
		)
	end
)

describe(
	"ClassCatalogueRules.publish and the codec",
	function()
		it(
			"resolves the kit and its words, blank where none is written, skipping a class with no roster row",
			function()
				local catalogue = ClassCatalogueRules.publish(ROSTER, DESCRIPTIONS, { Enums.ClassKind.RECRUIT, Enums.ClassKind.GUNNER, Enums.ClassKind.SNIPER })
				expect(#catalogue).toBe(2)
				local gunner = ClassCatalogueRules.findEntry(catalogue, Enums.ClassKind.GUNNER)
				expect(gunner.description).toBe("Shoots things")
				expect(gunner.kit).toEqual({ weapon = 5, post = 6, tower = 7, gadget = 8 })
				expect(gunner.kitDescriptions).toEqual({ weapon = "A rifle", post = "", tower = "A tower", gadget = "A gadget" })
				local recruit = ClassCatalogueRules.findEntry(catalogue, Enums.ClassKind.RECRUIT)
				expect(recruit.description).toBe("")
				expect(recruit.kitDescriptions.gadget).toBe("")
			end
		)

		it(
			"sorts the menu's list as the class in play, the owned, then the locked, keeping the catalogue order within each",
			function()
				local catalogue = {
					{ kind = 1 },
					{ kind = 2 },
					{ kind = 3 },
					{ kind = 4 },
					{ kind = 5 },
				}
				local sorted = ClassCatalogueRules.sortForMenu(catalogue :: any, 4, { [1] = true, [4] = true, [5] = true })
				local kinds = {}
				for _, entry in sorted do
					table.insert(kinds, entry.kind)
				end
				expect(kinds).toEqual({ 4, 1, 5, 2, 3 })
				expect(#catalogue).toBe(5)
				expect(catalogue[1].kind).toBe(1)
				local noActive = ClassCatalogueRules.sortForMenu(catalogue :: any, nil, {})
				expect(noActive[1].kind).toBe(1)
			end
		)

		it(
			"round-trips through JSON and rejects garbage",
			function()
				local catalogue = ClassCatalogueRules.publish(ROSTER, DESCRIPTIONS, { Enums.ClassKind.RECRUIT, Enums.ClassKind.GUNNER })
				expect(ClassCatalogueRules.decode(ClassCatalogueRules.encode(catalogue))).toEqual(catalogue)
				expect(ClassCatalogueRules.decode("")).toEqual({})
				expect(ClassCatalogueRules.decode("[{\"kind\":999}]")).toEqual({})
				expect(ClassCatalogueRules.findEntry(catalogue, Enums.ClassKind.SNIPER)).toBeNil()
			end
		)
	end
)
