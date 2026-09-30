-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local PathAreaRules = require(game:GetService("ReplicatedStorage").Shared.PathAreaRules)

-- Deadman's Canyon: the camp centred at (48, 0), Zone1 x 114..349, z -106..94,
-- inside a Wave Area z -128..120 that runs on to x 601
local ZONE = { centerX = 231.5, centerZ = -6, halfX = 117.5, halfZ = 100 }
local CAMP_X = 48
local CAMP_Z = 0

describe(
	"PathAreaRules",
	function()
		it(
			"reads the approach axis from the zone's offset from the camp",
			function()
				expect(PathAreaRules.approachIsX(ZONE, CAMP_X, CAMP_Z)).toBe(true)
				expect(PathAreaRules.approachIsX({ centerX = 48, centerZ = 200, halfX = 100, halfZ = 50 }, CAMP_X, CAMP_Z)).toBe(false)
			end
		)

		it(
			"closes the strip beside the zone and leaves the zone and the far approach open",
			function()
				-- inside the zone
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 200, 0)).toBe(false)
				-- beside it, in the Wave Area strip outside its width
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 200, -118)).toBe(true)
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 200, 110)).toBe(true)
				-- beyond it toward the spawns: open, whatever the width
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 500, -118)).toBe(false)
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 500, 0)).toBe(false)
				-- the camp side of the zone is not beside it either
				expect(PathAreaRules.isBesideZone(ZONE, CAMP_X, CAMP_Z, 100, -118)).toBe(false)
			end
		)

		it(
			"mirrors the rule for a zone approached along Z",
			function()
				local zone = { centerX = 48, centerZ = 200, halfX = 100, halfZ = 50 }
				expect(PathAreaRules.isBesideZone(zone, CAMP_X, CAMP_Z, 160, 200)).toBe(true)
				expect(PathAreaRules.isBesideZone(zone, CAMP_X, CAMP_Z, 160, 400)).toBe(false)
				expect(PathAreaRules.isBesideZone(zone, CAMP_X, CAMP_Z, 48, 200)).toBe(false)
			end
		)

		it(
			"checks every zone",
			function()
				local zones = { ZONE, { centerX = 48, centerZ = 200, halfX = 100, halfZ = 50 } }
				expect(PathAreaRules.isBesideAnyZone(zones, CAMP_X, CAMP_Z, 200, -118)).toBe(true)
				expect(PathAreaRules.isBesideAnyZone(zones, CAMP_X, CAMP_Z, 160, 200)).toBe(true)
				expect(PathAreaRules.isBesideAnyZone(zones, CAMP_X, CAMP_Z, 500, 0)).toBe(false)
				expect(PathAreaRules.isBesideAnyZone({}, CAMP_X, CAMP_Z, 200, -118)).toBe(false)
			end
		)
	end
)
