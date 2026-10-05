-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local RunStatsRules = require(game:GetService("ReplicatedStorage").Shared.RunStatsRules)

describe(
	"RunStatsRules",
	function()
		it(
			"ranks the highest number first",
			function()
				local values = { 10, 40, 25 }
				expect(RunStatsRules.rank(40, values)).toBe(1)
				expect(RunStatsRules.rank(25, values)).toBe(2)
				expect(RunStatsRules.rank(10, values)).toBe(3)
			end
		)
		it(
			"gives equal numbers the same place and skips the next",
			function()
				local values = { 30, 30, 5, 0 }
				expect(RunStatsRules.rank(30, values)).toBe(1)
				expect(RunStatsRules.rank(5, values)).toBe(3)
				expect(RunStatsRules.rank(0, values)).toBe(4)
			end
		)
		it(
			"ranks a solo player first",
			function()
				expect(RunStatsRules.rank(0, { 0 })).toBe(1)
			end
		)
		it(
			"writes a place as an ordinal",
			function()
				expect(RunStatsRules.ordinal(1)).toBe("1st")
				expect(RunStatsRules.ordinal(2)).toBe("2nd")
				expect(RunStatsRules.ordinal(3)).toBe("3rd")
				expect(RunStatsRules.ordinal(4)).toBe("4th")
				expect(RunStatsRules.ordinal(6)).toBe("6th")
				expect(RunStatsRules.ordinal(11)).toBe("11th")
				expect(RunStatsRules.ordinal(12)).toBe("12th")
				expect(RunStatsRules.ordinal(13)).toBe("13th")
				expect(RunStatsRules.ordinal(21)).toBe("21st")
			end
		)
	end
)
