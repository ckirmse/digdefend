-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GiveCurrencyRules = require(game:GetService("ReplicatedStorage").Shared.GiveCurrencyRules)

describe(
	"GiveCurrencyRules",
	function()
		it(
			"steps an amount by the press and holds it between nothing and the balance",
			function()
				expect(GiveCurrencyRules.stepAmount(0, 10, 35)).toBe(10)
				expect(GiveCurrencyRules.stepAmount(30, 10, 35)).toBe(35)
				expect(GiveCurrencyRules.stepAmount(5, -10, 35)).toBe(0)
				expect(GiveCurrencyRules.stepAmount(0, 10, 0)).toBe(0)
			end
		)
		it(
			"reads a typed amount as a whole number inside the balance",
			function()
				expect(GiveCurrencyRules.parseAmount("25", 100)).toBe(25)
				expect(GiveCurrencyRules.parseAmount("25.9", 100)).toBe(25)
				expect(GiveCurrencyRules.parseAmount("250", 100)).toBe(100)
				expect(GiveCurrencyRules.parseAmount("-4", 100)).toBe(0)
				expect(GiveCurrencyRules.parseAmount("lots", 100)).toBe(0)
				expect(GiveCurrencyRules.parseAmount("", 100)).toBe(0)
			end
		)
		it(
			"refuses an empty gift and one the sender cannot cover",
			function()
				expect(GiveCurrencyRules.getRejection(0, 0, 50, 50)).toBe(GiveCurrencyRules.REJECT_NOTHING)
				expect(GiveCurrencyRules.getRejection(60, 0, 50, 50)).toBe(GiveCurrencyRules.REJECT_BALANCE)
				expect(GiveCurrencyRules.getRejection(0, 51, 50, 50)).toBe(GiveCurrencyRules.REJECT_BALANCE)
				expect(GiveCurrencyRules.getRejection(50, 0, 50, 50)).toBe(nil)
				expect(GiveCurrencyRules.getRejection(10, 20, 50, 50)).toBe(nil)
			end
		)
		it(
			"describes what was sent in words",
			function()
				expect(GiveCurrencyRules.describeAmounts(20, 0, "Gold Bar", "Iron Bar")).toBe("20 Gold Bars")
				expect(GiveCurrencyRules.describeAmounts(0, 1, "Gold Bar", "Iron Bar")).toBe("1 Iron Bar")
				expect(GiveCurrencyRules.describeAmounts(20, 10, "Gold Bar", "Iron Bar")).toBe("20 Gold Bars and 10 Iron Bars")
			end
		)
	end
)
