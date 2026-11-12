-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local GroupRewardRules = require(game:GetService("ReplicatedStorage").Shared.GroupRewardRules)

describe(
	"GroupRewardRules.canClaim",
	function()
		it(
			"lets only a group member who has not claimed yet claim",
			function()
				expect(GroupRewardRules.canClaim(true, false)).toBe(true)
				expect(GroupRewardRules.canClaim(false, false)).toBe(false)
				expect(GroupRewardRules.canClaim(true, true)).toBe(false)
				expect(GroupRewardRules.canClaim(false, true)).toBe(false)
			end
		)
	end
)
