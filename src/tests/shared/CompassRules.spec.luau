-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CompassRules = require(game:GetService("ReplicatedStorage").Shared.CompassRules)

local ORIGIN = Vector3.new(0, 0, 0)
local UP = Vector3.new(0, 1, 0)
-- Roblox's default facing: forward is -Z, so +X is to the right
local LOOK_FORWARD = Vector3.new(0, 0, -1)

describe(
	"CompassRules.flatForward",
	function()
		it(
			"flattens a level or tilted look onto the ground",
			function()
				local x, z = CompassRules.flatForward(LOOK_FORWARD, UP)
				expect(x).toBeCloseTo(0, 5)
				expect(z).toBeCloseTo(-1, 5)
				local tiltedX, tiltedZ = CompassRules.flatForward(Vector3.new(3, -4, 0).Unit, UP)
				expect(tiltedX).toBeCloseTo(1, 5)
				expect(tiltedZ).toBeCloseTo(0, 5)
			end
		)
		it(
			"uses the top of the screen when looking straight down or up",
			function()
				local downX, downZ = CompassRules.flatForward(Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))
				expect(downX).toBeCloseTo(0, 5)
				expect(downZ).toBeCloseTo(-1, 5)
				local upX, upZ = CompassRules.flatForward(Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
				expect(upX).toBeCloseTo(0, 5)
				expect(upZ).toBeCloseTo(-1, 5)
			end
		)
	end
)

describe(
	"CompassRules.relativeYawDegrees",
	function()
		it(
			"is 0 ahead, positive right, negative left, 180 behind",
			function()
				expect(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(0, 0, -10))).toBeCloseTo(0, 5)
				expect(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(10, 0, 0))).toBeCloseTo(90, 5)
				expect(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(-10, 0, 0))).toBeCloseTo(-90, 5)
				expect(math.abs(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(0, 0, 10)))).toBeCloseTo(180, 5)
			end
		)
		it(
			"ignores height and treats the viewer's own spot as ahead",
			function()
				expect(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(10, 50, -10))).toBeCloseTo(45, 5)
				expect(CompassRules.relativeYawDegrees(0, -1, ORIGIN, Vector3.new(0, 30, 0))).toBe(0)
			end
		)
	end
)

describe(
	"CompassRules.barShare",
	function()
		it(
			"runs left end to right end across the field of view",
			function()
				expect(CompassRules.barShare(0, 120, false)).toBeCloseTo(0.5, 5)
				expect(CompassRules.barShare(-60, 120, false)).toBeCloseTo(0, 5)
				expect(CompassRules.barShare(60, 120, false)).toBeCloseTo(1, 5)
				expect(CompassRules.barShare(30, 120, false)).toBeCloseTo(0.75, 5)
			end
		)
		it(
			"hides an unpinned marker outside the view and pins the rest to the nearer end",
			function()
				expect(CompassRules.barShare(61, 120, false)).toBe(nil)
				expect(CompassRules.barShare(-170, 120, false)).toBe(nil)
				expect(CompassRules.barShare(61, 120, true)).toBe(1)
				expect(CompassRules.barShare(-170, 120, true)).toBe(0)
			end
		)
	end
)

describe(
	"CompassRules.dotScale",
	function()
		it(
			"is full size up close and shrinks evenly to the smallest",
			function()
				expect(CompassRules.dotScale(10, 40, 300, 0.5)).toBe(1)
				expect(CompassRules.dotScale(40, 40, 300, 0.5)).toBe(1)
				expect(CompassRules.dotScale(170, 40, 300, 0.5)).toBeCloseTo(0.75, 5)
				expect(CompassRules.dotScale(300, 40, 300, 0.5)).toBeCloseTo(0.5, 5)
				expect(CompassRules.dotScale(5000, 40, 300, 0.5)).toBeCloseTo(0.5, 5)
			end
		)
		it(
			"stays full size when the distances are not a range",
			function()
				expect(CompassRules.dotScale(500, 40, 40, 0.5)).toBe(1)
			end
		)
	end
)

describe(
	"CompassRules.verticalHint",
	function()
		it(
			"points up or down only past the threshold",
			function()
				expect(CompassRules.verticalHint(9, 8)).toBe(CompassRules.VERTICAL_HINT_UP)
				expect(CompassRules.verticalHint(-9, 8)).toBe(CompassRules.VERTICAL_HINT_DOWN)
				expect(CompassRules.verticalHint(8, 8)).toBe(CompassRules.VERTICAL_HINT_NONE)
				expect(CompassRules.verticalHint(-3, 8)).toBe(CompassRules.VERTICAL_HINT_NONE)
			end
		)
	end
)

describe(
	"CompassRules.lowestFreeIndex",
	function()
		it(
			"takes the lowest colour nobody holds",
			function()
				expect(CompassRules.lowestFreeIndex({}, 6)).toBe(1)
				expect(CompassRules.lowestFreeIndex({ [1] = true, [2] = true }, 6)).toBe(3)
				expect(CompassRules.lowestFreeIndex({ [1] = true, [3] = true }, 6)).toBe(2)
			end
		)
		it(
			"shares from the start when every colour is taken",
			function()
				expect(CompassRules.lowestFreeIndex({ [1] = true, [2] = true }, 2)).toBe(1)
			end
		)
	end
)
