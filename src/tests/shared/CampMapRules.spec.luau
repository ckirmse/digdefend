-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CampMapRules = require(game:GetService("ReplicatedStorage").Shared.CampMapRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local Band = Enums.StructureHealthBand

-- a camp whose gate lies down positive X from the Refinery
local function gateEastFrame()
	return CampMapRules.makeFrame(Vector3.new(10, 0, 20), Vector3.new(50, 0, 20))
end

describe(
	"CampMapRules.healthBand",
	function()
		it(
			"is white only at full health",
			function()
				expect(CampMapRules.healthBand(100, 100, false)).toBe(Band.FULL)
				expect(CampMapRules.healthBand(99, 100, false)).toBe(Band.HIGH)
			end
		)
		it(
			"steps down through yellow, orange, and red at 60% and 30%",
			function()
				expect(CampMapRules.healthBand(61, 100, false)).toBe(Band.HIGH)
				expect(CampMapRules.healthBand(60, 100, false)).toBe(Band.MID)
				expect(CampMapRules.healthBand(31, 100, false)).toBe(Band.MID)
				expect(CampMapRules.healthBand(30, 100, false)).toBe(Band.LOW)
				expect(CampMapRules.healthBand(1, 100, false)).toBe(Band.LOW)
			end
		)
		it(
			"is destroyed at zero, when rubble, or with no max",
			function()
				expect(CampMapRules.healthBand(0, 100, false)).toBe(Band.DESTROYED)
				expect(CampMapRules.healthBand(50, 100, true)).toBe(Band.DESTROYED)
				expect(CampMapRules.healthBand(5, 0, false)).toBe(Band.DESTROYED)
			end
		)
	end
)

describe(
	"CampMapRules frame",
	function()
		it(
			"points the top of the map from the Refinery toward the gate",
			function()
				local frame = gateEastFrame()
				expect(frame.forwardX).toBeCloseTo(1, 6)
				expect(frame.forwardZ).toBeCloseTo(0, 6)
				-- the gate sits straight up the map, the Refinery at the origin
				local u, v = CampMapRules.toMap(frame, 50, 20)
				expect(u).toBeCloseTo(0, 6)
				expect(v).toBeCloseTo(40, 6)
				local originU, originV = CampMapRules.toMap(frame, 10, 20)
				expect(originU).toBeCloseTo(0, 6)
				expect(originV).toBeCloseTo(0, 6)
			end
		)
		it(
			"puts a point to the right of the line on the right of the map",
			function()
				local frame = gateEastFrame()
				-- facing +X, the right hand points down +Z
				local u, v = CampMapRules.toMap(frame, 10, 25)
				expect(u).toBeCloseTo(5, 6)
				expect(v).toBeCloseTo(0, 6)
			end
		)
		it(
			"falls back to the engine's forward when the two spots coincide",
			function()
				local frame = CampMapRules.makeFrame(Vector3.new(1, 0, 1), Vector3.new(1, 5, 1))
				expect(frame.forwardX).toBe(0)
				expect(frame.forwardZ).toBe(-1)
			end
		)
	end
)

describe(
	"CampMapRules layout",
	function()
		it(
			"fits the longer side into the square inside the margin and centres the camp",
			function()
				local layout = CampMapRules.layoutFor({ { u = -10, v = 0 }, { u = 30, v = 20 } }, 0.1)
				expect(layout.centerU).toBe(10)
				expect(layout.centerV).toBe(10)
				-- 40 studs across fill the 0.8 inside the margins
				expect(layout.scale).toBeCloseTo(0.02, 9)
				local x, y = CampMapRules.toScreen(layout, 30, 20)
				expect(x).toBeCloseTo(0.9, 9)
				-- up the map is up the screen: 10 studs above the centre is 0.2 up
				expect(y).toBeCloseTo(0.3, 9)
				local centerX, centerY = CampMapRules.toScreen(layout, 10, 10)
				expect(centerX).toBeCloseTo(0.5, 9)
				expect(centerY).toBeCloseTo(0.5, 9)
			end
		)
		it(
			"copes with no points and a single point",
			function()
				expect(CampMapRules.layoutFor({}, 0.1).scale).toBe(1)
				local single = CampMapRules.layoutFor({ { u = 3, v = 4 } }, 0.1)
				expect(single.centerU).toBe(3)
				expect(single.scale).toBe(1)
			end
		)
		it(
			"knows what falls outside the square",
			function()
				expect(CampMapRules.isOnScreen(0.5, 0.5)).toBe(true)
				expect(CampMapRules.isOnScreen(1.01, 0.5)).toBe(false)
				expect(CampMapRules.isOnScreen(0.5, -0.1)).toBe(false)
			end
		)
	end
)

describe(
	"CampMapRules structures",
	function()
		it(
			"gives a box its four ground corners in map coordinates",
			function()
				local frame = gateEastFrame()
				-- a 8 by 2 box centred 20 studs toward the gate, unrotated
				local corners = CampMapRules.boxCorners(frame, CFrame.new(30, 3, 20), Vector3.new(8, 6, 2))
				expect(#corners).toBe(4)
				local minU = math.huge
				local maxV = -math.huge
				for _, corner in corners do
					minU = math.min(minU, corner.u)
					maxV = math.max(maxV, corner.v)
				end
				-- the box's 2 studs of Z run across the map, its 8 of X up it
				expect(minU).toBeCloseTo(-1, 6)
				expect(maxV).toBeCloseTo(24, 6)
			end
		)
		it(
			"turns a structure so its right vector lies along its drawn width",
			function()
				local frame = gateEastFrame()
				-- a right vector along the map's right needs no turn
				expect(CampMapRules.rotationDegrees(frame, Vector3.new(0, 0, 1))).toBeCloseTo(0, 6)
				-- a right vector up the map turns the frame a quarter counter-clockwise
				expect(CampMapRules.rotationDegrees(frame, Vector3.new(1, 0, 0))).toBeCloseTo(-90, 6)
			end
		)
	end
)
