-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CosmeticLoadoutSchema = require(game:GetService("ReplicatedStorage").Shared.CosmeticLoadoutSchema)

local DEFAULT_COSMETICS = { HELMET = "HARD_HAT", PICK_AXE = "DEFAULT" }

describe(
	"CosmeticLoadoutSchema.getDefault",
	function()
		it(
			"is a fresh copy of the default skins",
			function()
				local loadout = CosmeticLoadoutSchema.getDefault(DEFAULT_COSMETICS)
				expect(loadout).toEqual(DEFAULT_COSMETICS)
				expect(loadout).never.toBe(DEFAULT_COSMETICS)
			end
		)
	end
)

describe(
	"CosmeticLoadoutSchema.validate",
	function()
		it(
			"passes a good loadout through with no repairs",
			function()
				local repairs = {}
				local loadout = { HELMET = "lamp", PICK_AXE = "ZEBRA_PICK", JET_PACK = "DEFAULT" }
				expect(CosmeticLoadoutSchema.validate(loadout, DEFAULT_COSMETICS, "cosmetics.", repairs)).toBe(loadout)
				expect(repairs).toEqual({})
			end
		)

		it(
			"drops unknown slots and blanks, fills missing defaults",
			function()
				local repairs = {}
				local loadout = CosmeticLoadoutSchema.validate({ BOGUS = "x", HELMET = "", JET_PACK = 4 }, DEFAULT_COSMETICS, "cosmetics.", repairs)
				expect(loadout).toEqual({ HELMET = "HARD_HAT", PICK_AXE = "DEFAULT" })
				expect(#repairs).toBe(5)
			end
		)

		it(
			"replaces a non-table with the defaults",
			function()
				local repairs = {}
				expect(CosmeticLoadoutSchema.validate(7, DEFAULT_COSMETICS, "cosmetics.", repairs)).toEqual(DEFAULT_COSMETICS)
				expect(repairs).toEqual({ "cosmetics.reset" })
			end
		)
	end
)

describe(
	"CosmeticLoadoutSchema codecs",
	function()
		it(
			"round-trips a loadout and reads garbage as empty",
			function()
				local loadout = { HELMET = "lamp" }
				expect(CosmeticLoadoutSchema.decode(CosmeticLoadoutSchema.encode(loadout))).toEqual(loadout)
				expect(CosmeticLoadoutSchema.decode(nil)).toEqual({})
				expect(CosmeticLoadoutSchema.decode("not json")).toEqual({})
				expect(CosmeticLoadoutSchema.decode("[1,2]")).toEqual({})
			end
		)
	end
)
