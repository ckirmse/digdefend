-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local BuildCameraRules = require(game:GetService("ReplicatedStorage").Shared.BuildCameraRules)
local PlacementRules = require(game:GetService("ReplicatedStorage").Shared.PlacementRules)

local ORIGIN = Vector3.new(0, 0, 0)

describe(
	"BuildCameraRules.flatDirection",
	function()
		it(
			"points along the ground from one position to the other",
			function()
				local x, z = BuildCameraRules.flatDirection(ORIGIN, Vector3.new(30, 50, 40), 0, -1)
				expect(x).toBeCloseTo(0.6, 5)
				expect(z).toBeCloseTo(0.8, 5)
			end
		)
		it(
			"falls back when the two share a location",
			function()
				local x, z = BuildCameraRules.flatDirection(ORIGIN, Vector3.new(0, 9, 0), 0, -1)
				expect(x).toBe(0)
				expect(z).toBe(-1)
			end
		)
	end
)

describe(
	"BuildCameraRules.snapToGridAxis",
	function()
		it(
			"turns a direction to the grid's nearest axis",
			function()
				local grid = PlacementRules.measureZone(CFrame.new(100, 0, 0), Vector3.new(40, 2, 20), 4)
				local x, z = BuildCameraRules.snapToGridAxis(grid, 0.995, -0.0996)
				expect(x).toBeCloseTo(1, 5)
				expect(z).toBeCloseTo(0, 5)
				local backX, backZ = BuildCameraRules.snapToGridAxis(grid, -0.2, 0.98)
				expect(backX).toBeCloseTo(0, 5)
				expect(backZ).toBeCloseTo(1, 5)
			end
		)
		it(
			"follows a grid that is itself turned",
			function()
				local grid = PlacementRules.measureZone(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(40, 2, 40), 4)
				local x, z = BuildCameraRules.snapToGridAxis(grid, 1, 0)
				-- both nearest axes are 45 degrees off; either is a unit diagonal
				expect(math.abs(x)).toBeCloseTo(math.sqrt(0.5), 4)
				expect(math.abs(z)).toBeCloseTo(math.sqrt(0.5), 4)
			end
		)
	end
)

describe(
	"BuildCameraRules.cameraCFrame",
	function()
		it(
			"sits the distance away, behind and above the focus, looking at it",
			function()
				local focus = Vector3.new(10, 2, -5)
				local cframe = BuildCameraRules.cameraCFrame(focus, 0, -1, 60, 100)
				expect((cframe.Position - focus).Magnitude).toBeCloseTo(100, 3)
				-- forward is -Z, so behind is +Z; sin 60 up, cos 60 back
				expect(cframe.Position.X).toBeCloseTo(10, 3)
				expect(cframe.Position.Y).toBeCloseTo(2 + 100 * math.sin(math.rad(60)), 3)
				expect(cframe.Position.Z).toBeCloseTo(-5 + 50, 3)
				expect(cframe.LookVector:Dot((focus - cframe.Position).Unit)).toBeCloseTo(1, 4)
			end
		)
		it(
			"keeps forward up the screen even near straight down",
			function()
				local cframe = BuildCameraRules.cameraCFrame(ORIGIN, 1, 0, 90, 80)
				expect(cframe.UpVector.X > 0.9).toBe(true)
				expect(cframe.Position.Y > 79).toBe(true)
			end
		)
	end
)

describe(
	"BuildCameraRules.pointOnPlane",
	function()
		it(
			"finds where a downward ray meets the surface",
			function()
				local point = BuildCameraRules.pointOnPlane(Vector3.new(0, 100, 0), Vector3.new(0.6, -0.8, 0), 20)
				expect(point.X).toBeCloseTo(60, 4)
				expect(point.Y).toBeCloseTo(20, 4)
				expect(point.Z).toBeCloseTo(0, 4)
			end
		)
		it(
			"is nil for a level ray or one pointing away",
			function()
				expect(BuildCameraRules.pointOnPlane(Vector3.new(0, 100, 0), Vector3.new(1, 0, 0), 20)).toBe(nil)
				expect(BuildCameraRules.pointOnPlane(Vector3.new(0, 100, 0), Vector3.new(0, 1, 0), 20)).toBe(nil)
			end
		)
	end
)

describe(
	"BuildCameraRules pan and zoom",
	function()
		it(
			"covers more ground per pixel the further out it is",
			function()
				local near = BuildCameraRules.studsPerPixel(100, 70, 1000)
				expect(near).toBeCloseTo(2 * 100 * math.tan(math.rad(35)) / 1000, 6)
				expect(BuildCameraRules.studsPerPixel(200, 70, 1000)).toBeCloseTo(near * 2, 6)
				expect(BuildCameraRules.studsPerPixel(100, 70, 0)).toBe(0)
			end
		)
		it(
			"pans right and forward in the camera's own directions",
			function()
				-- forward -Z puts right at +X
				local right = BuildCameraRules.panFocus(ORIGIN, 0, -1, 5, 0)
				expect(right.X).toBeCloseTo(5, 5)
				expect(right.Z).toBeCloseTo(0, 5)
				local forward = BuildCameraRules.panFocus(ORIGIN, 0, -1, 0, 5)
				expect(forward.X).toBeCloseTo(0, 5)
				expect(forward.Z).toBeCloseTo(-5, 5)
				-- forward +X puts right at +Z
				local turned = BuildCameraRules.panFocus(ORIGIN, 1, 0, 5, 0)
				expect(turned.X).toBeCloseTo(0, 5)
				expect(turned.Z).toBeCloseTo(5, 5)
			end
		)
		it(
			"zooms by a share per step inside the limits",
			function()
				expect(BuildCameraRules.zoomDistance(100, 1, 0.1, 50, 300)).toBeCloseTo(90, 5)
				expect(BuildCameraRules.zoomDistance(100, -1, 0.1, 50, 300)).toBeCloseTo(100 / 0.9, 5)
				expect(BuildCameraRules.zoomDistance(55, 3, 0.1, 50, 300)).toBe(50)
				expect(BuildCameraRules.zoomDistance(290, -3, 0.1, 50, 300)).toBe(300)
			end
		)
	end
)

describe(
	"BuildCameraRules.clampFocus",
	function()
		it(
			"keeps the focus on the zone's rectangle and surface",
			function()
				-- a 40 x 20 stud zone whose top face is at y = 1
				local grid = PlacementRules.measureZone(CFrame.new(100, 0, 0), Vector3.new(40, 2, 20), 4)
				local inside = BuildCameraRules.clampFocus(grid, Vector3.new(110, 50, 5))
				expect(inside.X).toBeCloseTo(110, 4)
				expect(inside.Y).toBeCloseTo(1, 4)
				expect(inside.Z).toBeCloseTo(5, 4)
				local outside = BuildCameraRules.clampFocus(grid, Vector3.new(500, 0, -500))
				expect(outside.X).toBeCloseTo(120, 4)
				expect(outside.Z).toBeCloseTo(-10, 4)
			end
		)
	end
)
