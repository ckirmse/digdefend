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

describe(
	"ProjectileRules.lobToward",
	function()
		it(
			"lands on a level target within reach at the fixed elevation",
			function()
				local origin = Vector3.new(0, 5, 0)
				local target = Vector3.new(0, 5, 100)
				local lob = ProjectileRules.lobToward(origin, target, 60, 60, 140)
				expect(lob.isReached).toBe(true)
				near(math.deg(math.asin(lob.unitDirection.Y)), 60, 1e-3)
				local flight = { origin = origin, unitDirection = lob.unitDirection, speedStudsPerSec = lob.speedStudsPerSec, gravityStudsPerSec2 = 60 }
				local landing = ProjectileRules.positionAt(flight, lob.flightSec)
				near(landing.X, target.X, 1e-2)
				near(landing.Y, target.Y, 1e-2)
				near(landing.Z, target.Z, 1e-2)
			end
		)

		it(
			"lands on a target below and above the gun",
			function()
				for _, height in { -20, 15 } do
					local origin = Vector3.new(10, 5, -4)
					local target = Vector3.new(60, 5 + height, 80)
					local lob = ProjectileRules.lobToward(origin, target, 60, 60, 140)
					expect(lob.isReached).toBe(true)
					local flight = { origin = origin, unitDirection = lob.unitDirection, speedStudsPerSec = lob.speedStudsPerSec, gravityStudsPerSec2 = 60 }
					local landing = ProjectileRules.positionAt(flight, lob.flightSec)
					near((landing - target).Magnitude, 0, 1e-2)
				end
			end
		)

		it(
			"falls short at the top speed when the target is past its reach",
			function()
				local origin = Vector3.new(0, 5, 0)
				local target = Vector3.new(0, 5, 1000)
				local lob = ProjectileRules.lobToward(origin, target, 60, 60, 140)
				expect(lob.isReached).toBe(false)
				near(lob.speedStudsPerSec, 140)
				near(lob.landing.Z, ProjectileRules.levelRangeStuds(140, 60, 60), 1e-2)
				near(lob.landing.Y, 5)
				local flight = { origin = origin, unitDirection = lob.unitDirection, speedStudsPerSec = 140, gravityStudsPerSec2 = 60 }
				near((ProjectileRules.positionAt(flight, lob.flightSec) - lob.landing).Magnitude, 0, 1e-2)
			end
		)

		it(
			"raises a falling shot so it lands on the aim point",
			function()
				local origin = Vector3.new(0, 16, 0)
				local target = Vector3.new(120, 2, 40)
				local aim = ProjectileRules.aimToward(origin, target, 30, 160)
				expect(aim.isReached).toBe(true)
				near(aim.unitDirection.Magnitude, 1)
				-- above the straight line, never a high mortar lob
				local straight = (target - origin).Unit
				expect(aim.unitDirection.Y > straight.Y).toBe(true)
				expect(aim.unitDirection.Y < 0.5).toBe(true)
				local flight = { origin = origin, unitDirection = aim.unitDirection, speedStudsPerSec = 160, gravityStudsPerSec2 = 30 }
				near((ProjectileRules.positionAt(flight, aim.flightSec) - target).Magnitude, 0, 1e-2)
				-- past the reach it is a straight shot that falls short
				local far = ProjectileRules.aimToward(origin, Vector3.new(5000, 2, 0), 30, 160)
				expect(far.isReached).toBe(false)
				near(far.unitDirection.X, (Vector3.new(5000, 2, 0) - origin).Unit.X)
				-- no gravity: the straight line is the answer
				local flat = ProjectileRules.aimToward(origin, target, 0, 160)
				expect(flat.isReached).toBe(true)
				near(flat.unitDirection.Y, straight.Y)
			end
		)

		it(
			"flies a returning projectile out, turns it, and brings it home",
			function()
				local flight = { origin = Vector3.new(0, 5, 0), unitDirection = Vector3.zAxis, speedStudsPerSec = 100, gravityStudsPerSec2 = 0 }
				local out = ProjectileRules.returningAt(flight, 0.5, 120)
				expect(out.isReturning).toBe(false)
				expect(out.isDone).toBe(false)
				near(out.position.Z, 50)
				expect(out.unitDirection).toEqual(Vector3.zAxis)
				local turn = ProjectileRules.returningAt(flight, 1.2, 120)
				near(turn.position.Z, 120)
				expect(turn.isReturning).toBe(false)
				local back = ProjectileRules.returningAt(flight, 1.7, 120)
				expect(back.isReturning).toBe(true)
				expect(back.isDone).toBe(false)
				near(back.position.Z, 70)
				expect(back.unitDirection).toEqual(-Vector3.zAxis)
				local home = ProjectileRules.returningAt(flight, 2.4, 120)
				expect(home.isDone).toBe(true)
				near((home.position - flight.origin).Magnitude, 0)
				local late = ProjectileRules.returningAt(flight, 9, 120)
				expect(late.isDone).toBe(true)
				near((late.position - flight.origin).Magnitude, 0)
			end
		)

		it(
			"fires up the elevation at a target under the gun",
			function()
				local origin = Vector3.new(0, 5, 0)
				local lob = ProjectileRules.lobToward(origin, origin, 60, 60, 140)
				near(lob.unitDirection.Magnitude, 1)
				near(math.deg(math.asin(lob.unitDirection.Y)), 60, 1e-3)
				expect(lob.landing).toEqual(origin)
			end
		)
	end
)
