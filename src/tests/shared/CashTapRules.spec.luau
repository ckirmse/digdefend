-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CashTapRules = require(game:GetService("ReplicatedStorage").Shared.CashTapRules)

local CASH_BY_NIGHT = {
	[1] = 5,
	[3] = 10,
	[5] = 15,
}

describe(
	"CashTapRules",
	function()
		it(
			"counts nights survived as the dawns reached",
			function()
				expect(CashTapRules.nightsSurvived(0)).toBe(0)
				expect(CashTapRules.nightsSurvived(1)).toBe(0)
				expect(CashTapRules.nightsSurvived(2)).toBe(1)
				expect(CashTapRules.nightsSurvived(16)).toBe(15)
			end
		)
		it(
			"pays a milestone at the dawn after its night",
			function()
				local cash, paidNight = CashTapRules.unpaidMilestoneCash(CASH_BY_NIGHT, 0, 1)
				expect(cash).toBe(5)
				expect(paidNight).toBe(1)
			end
		)
		it(
			"pays nothing for a night with no milestone but remembers it",
			function()
				local cash, paidNight = CashTapRules.unpaidMilestoneCash(CASH_BY_NIGHT, 1, 2)
				expect(cash).toBe(0)
				expect(paidNight).toBe(2)
			end
		)
		it(
			"never pays a night twice when a day starts over",
			function()
				local cash, paidNight = CashTapRules.unpaidMilestoneCash(CASH_BY_NIGHT, 3, 3)
				expect(cash).toBe(0)
				expect(paidNight).toBe(3)
			end
		)
		it(
			"pays every milestone passed since the last one paid",
			function()
				local cash, paidNight = CashTapRules.unpaidMilestoneCash(CASH_BY_NIGHT, 1, 5)
				expect(cash).toBe(25)
				expect(paidNight).toBe(5)
			end
		)
	end
)
