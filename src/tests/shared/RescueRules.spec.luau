-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local RescueRules = require(game:GetService("ReplicatedStorage").Shared.RescueRules)

describe(
	"RescueRules",
	function()
		it(
			"lets the radio work only once the target is refined",
			function()
				expect(RescueRules.isTargetReached(19, 20)).toBe(false)
				expect(RescueRules.isTargetReached(20, 20)).toBe(true)
				expect(RescueRules.isTargetReached(5, 0)).toBe(false)
			end
		)
		it(
			"makes the final wave the night after the current day",
			function()
				expect(RescueRules.finalWaveNight(1)).toBe(2)
				expect(RescueRules.finalWaveNight(7)).toBe(8)
				expect(RescueRules.finalWaveNight(0)).toBe(2)
			end
		)
		it(
			"leaves with everyone aboard, or after the timeout with someone aboard, never empty",
			function()
				expect(RescueRules.shouldDepart(0, 3, 100, 200, 30)).toBe(false)
				expect(RescueRules.shouldDepart(3, 3, 100, 101, 30)).toBe(true)
				expect(RescueRules.shouldDepart(1, 3, 100, 120, 30)).toBe(false)
				expect(RescueRules.shouldDepart(1, 3, 100, 130, 30)).toBe(true)
				expect(RescueRules.shouldDepart(2, 1, 100, 101, 30)).toBe(true)
			end
		)
		it(
			"records a completion only when every prerequisite is held",
			function()
				local held = { ["DEADMANS_CANYON/NORMAL"] = true }
				local function hasCompletion(key: string): boolean
					return held[key] == true
				end
				expect(RescueRules.canRecordCompletion(hasCompletion, {})).toBe(true)
				expect(RescueRules.canRecordCompletion(hasCompletion, { "DEADMANS_CANYON/NORMAL" })).toBe(true)
				expect(RescueRules.canRecordCompletion(hasCompletion, { "DEADMANS_CANYON/HARD" })).toBe(false)
				expect(RescueRules.canRecordCompletion(hasCompletion, { "DEADMANS_CANYON/NORMAL", "DEADMANS_CANYON/HARD" })).toBe(false)
			end
		)
		it(
			"names who made it unless everyone did",
			function()
				expect(RescueRules.wonMessage({ "Ann", "Bo" }, 2, "All out", "%s made it out")).toBe("All out")
				expect(RescueRules.wonMessage({ "Ann" }, 2, "All out", "%s made it out")).toBe("Ann made it out")
			end
		)
	end
)
