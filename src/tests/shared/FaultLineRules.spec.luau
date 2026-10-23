-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local FaultLineRules = require(game:GetService("ReplicatedStorage").Shared.FaultLineRules)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function flatGround(_x: number, _z: number): number?
	return 0
end

local function body(id: string, x: number, y: number, z: number, isAirborne: boolean?): FaultLineRules.Body
	return {
		id = id,
		position = Vector3.new(x, y, z),
		size = Vector3.new(2, 4, 2),
		isAirborne = isAirborne == true,
	}
end

describe(
	"FaultLineRules",
	function()
		it(
			"flattens an aim and refuses a vertical one",
			function()
				local flat = FaultLineRules.flatDirection(Vector3.new(0, 0.5, 0.5).Unit) :: Vector3
				expect(flat.Y).toBe(0)
				expect(flat.Z).toBeCloseTo(1, 5)
				expect(FaultLineRules.flatDirection(Vector3.yAxis)).toBeNil()
			end
		)

		it(
			"samples the crack along the ground to its end",
			function()
				local heights = { [0] = 0, [4] = 1, [8] = 2 }
				local points = FaultLineRules.samplePoints(Vector3.new(0, 5, 0), Vector3.xAxis, 10, 4,
					function(x: number, _z: number): number?
						return heights[math.round(x)]
					end
				)
				expect(#points).toBe(4)
				expect(points[1]).toEqual(Vector3.new(0, 0, 0))
				expect(points[2]).toEqual(Vector3.new(4, 1, 0))
				expect(points[3]).toEqual(Vector3.new(8, 2, 0))
				-- off the known ground the last height holds, and the end is sampled
				expect(points[4]).toEqual(Vector3.new(10, 2, 0))
			end
		)

		it(
			"hits what stands on the line and nothing beside, behind, past, or above it",
			function()
				local bodies = {
					body("on", 10, 2, 1),
					body("edge", 20, 2, 3.9),
					body("beside", 20, 2, 6),
					body("behind", -4, 2, 0),
					body("past", 34, 2, 0),
					body("flyer", 10, 2, 0, true),
					body("roof", 10, 12, 0),
				}
				local hits = FaultLineRules.hitsAlong(Vector3.zero, Vector3.xAxis, 30, 6, bodies, flatGround, 3)
				expect(hits).toEqual({ "on", "edge" })
			end
		)
	end
)
