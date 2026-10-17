-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local ProjectileRules = require(game:GetService("ReplicatedStorage").Shared.ProjectileRules)

local function near(actual, expected, tolerance)
	expect(math.abs(actual - expected)).toBeLessThanOrEqual(tolerance or 1e-4)
end

describe(
	"ProjectileRules.positionAt",
	function()
		it(
			"flies straight with no gravity",
			function()
				local flight = { origin = Vector3.new(0, 10, 0), unitDirection = Vector3.zAxis, speedStudsPerSec = 50, gravityStudsPerSec2 = 0 }
				local position = ProjectileRules.positionAt(flight, 2)
				expect(position).toEqual(Vector3.new(0, 10, 100))
				expect(ProjectileRules.headingAt(flight, 2)).toEqual(Vector3.zAxis)
			end
		)

		it(
			"falls under gravity and the heading tips down",
			function()
				local flight = { origin = Vector3.zero, unitDirection = Vector3.zAxis, speedStudsPerSec = 50, gravityStudsPerSec2 = 20 }
				local position = ProjectileRules.positionAt(flight, 2)
				near(position.Z, 100)
				near(position.Y, -40)
				local heading = ProjectileRules.headingAt(flight, 2)
				expect(heading.Y).toBeLessThan(0)
				near(heading.Magnitude, 1)
			end
		)
	end
)

describe(
	"ProjectileRules.turnToward",
	function()
		it(
			"snaps to the target when it is within the turn and limits the turn otherwise",
			function()
				local snapped = ProjectileRules.turnToward(Vector3.zAxis, Vector3.zero, Vector3.new(1, 0, 10), 90)
				near((snapped - Vector3.new(1, 0, 10).Unit).Magnitude, 0)
				local limited = ProjectileRules.turnToward(Vector3.zAxis, Vector3.zero, Vector3.new(10, 0, 0), 10)
				near(math.deg(math.acos(limited:Dot(Vector3.zAxis))), 10, 1e-3)
				near(limited.Magnitude, 1)
			end
		)

		it(
			"turns away from a target straight behind rather than freezing",
			function()
				local turned = ProjectileRules.turnToward(Vector3.zAxis, Vector3.zero, Vector3.new(0, 0, -10), 15)
				expect(turned:Dot(Vector3.zAxis)).toBeLessThan(1)
				near(turned.Magnitude, 1)
			end
		)

		it(
			"leaves the direction alone with no turn or a target on top of it",
			function()
				expect(ProjectileRules.turnToward(Vector3.zAxis, Vector3.zero, Vector3.new(10, 0, 0), 0)).toEqual(Vector3.zAxis)
				expect(ProjectileRules.turnToward(Vector3.zAxis, Vector3.zero, Vector3.zero, 30)).toEqual(Vector3.zAxis)
			end
		)
	end
)

describe(
	"ProjectileRules.levelRangeStuds",
	function()
		it(
			"is the ballistic range on level ground, unbounded without gravity",
			function()
				near(ProjectileRules.levelRangeStuds(100, 50, 45), 200, 1e-3)
				expect(ProjectileRules.levelRangeStuds(100, 0, 45)).toBe(math.huge)
			end
		)
	end
)
