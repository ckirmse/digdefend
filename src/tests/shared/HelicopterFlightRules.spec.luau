-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local HelicopterFlightRules = require(game:GetService("ReplicatedStorage").Shared.HelicopterFlightRules)

local CONFIG = HelicopterFlightRules.DEFAULT_CONFIG
-- a pad at the origin facing -Z (Roblox's forward), and a way out to +X
local PAD = CFrame.new(0, 10, 0)
local HEADING = Vector3.new(1, 0, 0)

local function expectVectorClose(actual: Vector3, expected: Vector3, digits: number?)
	expect(actual.X).toBeCloseTo(expected.X, digits or 3)
	expect(actual.Y).toBeCloseTo(expected.Y, digits or 3)
	expect(actual.Z).toBeCloseTo(expected.Z, digits or 3)
end

describe(
	"HelicopterFlightRules angles",
	function()
		it(
			"turns a flat direction into the yaw that looks along it",
			function()
				local direction = Vector3.new(1, 0, -1).Unit
				local yaw = HelicopterFlightRules.yawOf(direction)
				expectVectorClose(CFrame.Angles(0, yaw, 0).LookVector, direction)
			end
		)
		it(
			"takes the shortest way round between two yaws",
			function()
				expect(HelicopterFlightRules.angleDifference(math.rad(170), math.rad(-170))).toBeCloseTo(math.rad(20), 5)
				expect(HelicopterFlightRules.angleDifference(math.rad(-170), math.rad(170))).toBeCloseTo(math.rad(-20), 5)
				expect(HelicopterFlightRules.lerpAngle(math.rad(170), math.rad(-170), 0.5)).toBeCloseTo(math.rad(180), 5)
			end
		)
		it(
			"falls back when two points share a location",
			function()
				local direction = HelicopterFlightRules.flatDirection(Vector3.zero, Vector3.new(0, 9, 0), Vector3.new(0, 0, 1))
				expectVectorClose(direction, Vector3.new(0, 0, 1))
			end
		)
	end
)

describe(
	"HelicopterFlightRules.approachPose",
	function()
		it(
			"starts at the far end of the departure and ends on the pad in its facing",
			function()
				local start = HelicopterFlightRules.approachStart(PAD, HEADING, CONFIG)
				expectVectorClose(start, HelicopterFlightRules.departurePose(PAD, HEADING, CONFIG, CONFIG.DEPARTURE_SEC).Position)
				local first = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, 0)
				expectVectorClose(first.Position, start)
				local last = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, CONFIG.APPROACH_SEC)
				expectVectorClose(last.Position, PAD.Position)
				expectVectorClose(last.LookVector, PAD.LookVector)
				expectVectorClose(last.UpVector, Vector3.new(0, 1, 0))
				expect(HelicopterFlightRules.isApproachDone(CONFIG, CONFIG.APPROACH_SEC)).toBe(true)
				expect(HelicopterFlightRules.isApproachDone(CONFIG, CONFIG.APPROACH_SEC - 1)).toBe(false)
			end
		)
		it(
			"flies in nose down toward the pad and never below it",
			function()
				local early = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, 1)
				local toPad = HelicopterFlightRules.flatten(PAD.Position - early.Position).Unit
				local flatLook = HelicopterFlightRules.flatten(early.LookVector).Unit
				expect(flatLook:Dot(toPad)).toBeGreaterThan(0.95)
				-- nose down: the look dips below level
				expect(early.LookVector.Y).toBeLessThan(0)
				for step = 0, 40 do
					local pose = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, CONFIG.APPROACH_SEC * step / 40)
					expect(pose.Position.Y).toBeGreaterThanOrEqual(PAD.Position.Y - 0.001)
				end
			end
		)
		it(
			"keeps moving toward the pad the whole way",
			function()
				local lastDistance = math.huge
				for step = 0, 40 do
					local pose = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, CONFIG.APPROACH_SEC * step / 40)
					local distance = (pose.Position - PAD.Position).Magnitude
					expect(distance).toBeLessThanOrEqual(lastDistance + 0.001)
					lastDistance = distance
				end
			end
		)
		it(
			"is over the pad at the lift height still nose-first when the descent begins, turns to the pad's way on the way down, and flares",
			function()
				local runInSec = CONFIG.APPROACH_SEC * (1 - CONFIG.APPROACH_DESCENT_SHARE)
				local top = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, runInSec)
				expectVectorClose(top.Position, PAD.Position + Vector3.new(0, CONFIG.DEPARTURE_LIFT_HEIGHT_STUDS, 0), 2)
				expect(HelicopterFlightRules.flatten(top.LookVector).Unit:Dot(-HEADING)).toBeGreaterThan(0.99)
				local descentSec = CONFIG.APPROACH_SEC - runInSec
				local turned = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, runInSec + descentSec * CONFIG.APPROACH_TURN_IN_SHARE)
				expectVectorClose(HelicopterFlightRules.flatten(turned.LookVector).Unit, PAD.LookVector, 2)
				local halfway = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, CONFIG.APPROACH_SEC * 0.5)
				expect((halfway.Position - PAD.Position).Magnitude).toBeGreaterThan(CONFIG.DEPARTURE_LIFT_HEIGHT_STUDS + 20)
				-- the flare: nose up partway down, straight over the pad
				local settling = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, runInSec + (CONFIG.APPROACH_SEC - runInSec) * 0.5)
				expect(settling.LookVector.Y).toBeGreaterThan(0)
				expect(settling.Position.X).toBeCloseTo(PAD.Position.X, 3)
				expect(settling.Position.Z).toBeCloseTo(PAD.Position.Z, 3)
			end
		)
		it(
			"comes back up its own facing nose-first and turns about over the pad to land",
			function()
				-- the rescue's way: the pad's own facing is the way out, so it
				-- flies in facing the pad and ends facing the pad's way
				local early = HelicopterFlightRules.approachPose(PAD, PAD.LookVector, CONFIG, 1)
				local flatLook = HelicopterFlightRules.flatten(early.LookVector).Unit
				expect(flatLook:Dot(PAD.LookVector)).toBeLessThan(-0.99)
				expect(early.Position.X).toBeCloseTo(PAD.Position.X, 3)
				local runInSec = CONFIG.APPROACH_SEC * (1 - CONFIG.APPROACH_DESCENT_SHARE)
				local top = HelicopterFlightRules.approachPose(PAD, PAD.LookVector, CONFIG, runInSec)
				expect(HelicopterFlightRules.flatten(top.LookVector).Unit:Dot(PAD.LookVector)).toBeLessThan(-0.99)
				local descentSec = CONFIG.APPROACH_SEC - runInSec
				local turned = HelicopterFlightRules.approachPose(PAD, PAD.LookVector, CONFIG, runInSec + descentSec * CONFIG.APPROACH_TURN_IN_SHARE)
				expectVectorClose(HelicopterFlightRules.flatten(turned.LookVector).Unit, PAD.LookVector, 2)
			end
		)
		it(
			"flies the departure path backwards and banks into the turn to the pad's facing",
			function()
				-- every approach position lies on the departure's lean
				local p0, p1, p2, p3 = HelicopterFlightRules.departurePoints(PAD, HEADING, CONFIG)
				local runInSec = CONFIG.APPROACH_SEC * (1 - CONFIG.APPROACH_DESCENT_SHARE)
				for step = 0, 20 do
					local pose = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, runInSec * step / 20)
					local nearest = math.huge
					-- the curve is some 2000 studs long, so the samples sit a stud apart
					for sample = 0, 2000 do
						nearest = math.min(nearest, (HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, sample / 2000) - pose.Position).Magnitude)
					end
					expect(nearest).toBeLessThan(1)
				end
				-- level and nose-first the whole run-in: the turn waits for the descent
				for step = 0, 100 do
					local pose = HelicopterFlightRules.approachPose(PAD, HEADING, CONFIG, runInSec * step / 100)
					expect(pose.RightVector.Y).toBeCloseTo(0, 5)
					expect(HelicopterFlightRules.flatten(pose.LookVector).Unit:Dot(-HEADING)).toBeGreaterThan(0.95)
				end
			end
		)
	end
)

describe(
	"HelicopterFlightRules.departurePose",
	function()
		local heading = Vector3.new(1, 0, 0)
		it(
			"lifts off the pad and ends the distance away along the heading",
			function()
				local first = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, 0)
				expectVectorClose(first.Position, PAD.Position)
				expectVectorClose(first.LookVector, PAD.LookVector)
				local last = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_SEC)
				expectVectorClose(last.Position, PAD.Position + heading * CONFIG.DEPARTURE_DISTANCE_STUDS + Vector3.new(0, CONFIG.DEPARTURE_HEIGHT_STUDS, 0))
				local flatLook = HelicopterFlightRules.flatten(last.LookVector).Unit
				expect(flatLook:Dot(heading)).toBeGreaterThan(0.999)
				expect(HelicopterFlightRules.isDepartureDone(CONFIG, CONFIG.DEPARTURE_SEC)).toBe(true)
			end
		)
		it(
			"rises straight up to the lift height, level, then leans away, and never sinks",
			function()
				for step = 1, 5 do
					local rising = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC * step / 6)
					expect(rising.Position.X).toBeCloseTo(PAD.Position.X, 5)
					expect(rising.Position.Z).toBeCloseTo(PAD.Position.Z, 5)
					expect(rising.Position.Y).toBeGreaterThan(PAD.Position.Y)
					-- level while it turns
					expect(rising.RightVector.Y).toBeCloseTo(0, 5)
					expect(rising.LookVector.Y).toBeCloseTo(0, 5)
				end
				local top = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC)
				expectVectorClose(top.Position, PAD.Position + Vector3.new(0, CONFIG.DEPARTURE_LIFT_HEIGHT_STUDS, 0))
				-- the nose has come round to the heading by the top of the lift
				expectVectorClose(top.LookVector, heading)
				local leaning = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC + 3)
				expect(leaning.Position.X).toBeGreaterThan(PAD.Position.X + 1)
				expect(leaning.Position.Y).toBeGreaterThan(top.Position.Y)
				-- the lean is at full speed DEPARTURE_RAMP_SEC in and holds it:
				-- its progress runs 0 to 1, rises through the ramp, then is a
				-- straight line
				local leanSec = CONFIG.DEPARTURE_SEC - CONFIG.DEPARTURE_LIFT_SEC
				local rampShare = CONFIG.DEPARTURE_RAMP_SEC / leanSec
				expect(HelicopterFlightRules.leanProgress(0, rampShare)).toBeCloseTo(0, 5)
				expect(HelicopterFlightRules.leanProgress(1, rampShare)).toBeCloseTo(1, 5)
				local function pace(share: number): number
					return (HelicopterFlightRules.leanProgress(share + 0.001, rampShare) - HelicopterFlightRules.leanProgress(share, rampShare)) / 0.001
				end
				expect(pace(0)).toBeLessThan(pace(rampShare * 0.5))
				expect(pace(rampShare * 0.5)).toBeLessThan(pace(rampShare))
				expect(pace(rampShare + 0.01)).toBeCloseTo(pace(0.95), 3)
				expect(pace(0.95)).toBeGreaterThan(1)
				-- a ramp with no room is a straight line
				expect(HelicopterFlightRules.leanProgress(0.5, 0)).toBeCloseTo(0.5, 3)
				-- and in studs: after the ramp every half second covers the same ground
				local function studsOver(fromSec: number): number
					local a = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC + fromSec).Position
					local b = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC + fromSec + 0.5).Position
					return (b - a).Magnitude
				end
				local held = studsOver(CONFIG.DEPARTURE_RAMP_SEC + 0.5)
				expect(studsOver(leanSec - 1)).toBeCloseTo(held, -1)
				expect(studsOver(CONFIG.DEPARTURE_RAMP_SEC * 0.25)).toBeLessThan(held * 0.6)
				-- off the ground within a few seconds, not sat there
				local soon = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, 4)
				expect(soon.Position.Y - PAD.Position.Y).toBeGreaterThan(8)
				local lastHeight = -math.huge
				for step = 0, 40 do
					local pose = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_SEC * step / 40)
					expect(pose.Position.Y).toBeGreaterThanOrEqual(lastHeight - 0.001)
					lastHeight = pose.Position.Y
				end
			end
		)
		it(
			"turns about over the pad during the lift and flies the lean nose-first without banking",
			function()
				-- a half turn: the pad faces -Z, the heading is +Z (the lobby's
				-- departure, so two helicopters facing each other part)
				local back = Vector3.new(0, 0, 1)
				local start = HelicopterFlightRules.departurePose(PAD, back, CONFIG, 0)
				expectVectorClose(start.LookVector, PAD.LookVector)
				local halfway = HelicopterFlightRules.departurePose(PAD, back, CONFIG, CONFIG.DEPARTURE_LIFT_SEC * 0.5)
				expect(math.abs(halfway.LookVector.Z)).toBeLessThan(0.1)
				expectVectorClose(halfway.Position, PAD.Position + Vector3.new(0, halfway.Position.Y - PAD.Position.Y, 0))
				local top = HelicopterFlightRules.departurePose(PAD, back, CONFIG, CONFIG.DEPARTURE_LIFT_SEC)
				expectVectorClose(top.LookVector, back)
				-- from there it flies away the way it faces, level
				for step = 0, 10 do
					local pose = HelicopterFlightRules.departurePose(PAD, back, CONFIG, CONFIG.DEPARTURE_LIFT_SEC + (CONFIG.DEPARTURE_SEC - CONFIG.DEPARTURE_LIFT_SEC) * step / 10)
					expect(pose.RightVector.Y).toBeCloseTo(0, 5)
					expect(HelicopterFlightRules.flatten(pose.LookVector).Unit:Dot(back)).toBeGreaterThan(0.999)
				end
				local last = HelicopterFlightRules.departurePose(PAD, back, CONFIG, CONFIG.DEPARTURE_SEC)
				expect(last.Position.Z).toBeGreaterThan(PAD.Position.Z + CONFIG.DEPARTURE_DISTANCE_STUDS * 0.99)
				-- a heading that is the facing never turns at all
				local straight = HelicopterFlightRules.departurePose(PAD, PAD.LookVector, CONFIG, CONFIG.DEPARTURE_LIFT_SEC * 0.5)
				expectVectorClose(straight.LookVector, PAD.LookVector)
			end
		)
	end
)

describe(
	"HelicopterFlightRules.parameterAtLengthShare",
	function()
		it(
			"walks a straight curve evenly and a bent one by its length",
			function()
				local a, b = Vector3.zero, Vector3.new(100, 0, 0)
				expect(HelicopterFlightRules.parameterAtLengthShare(a, a:Lerp(b, 1 / 3), a:Lerp(b, 2 / 3), b, 0.25)).toBeCloseTo(0.25, 2)
				-- control points bunched at the start: half the length is well past t = 0.5
				local bunched = HelicopterFlightRules.parameterAtLengthShare(a, a, a, b, 0.5)
				expect(bunched).toBeGreaterThan(0.6)
				expect(HelicopterFlightRules.parameterAtLengthShare(a, a, a, b, 0)).toBeCloseTo(0, 5)
				expect(HelicopterFlightRules.parameterAtLengthShare(a, a, a, b, 1)).toBeCloseTo(1, 5)
			end
		)
	end
)

describe(
	"HelicopterFlightRules config codec",
	function()
		it(
			"falls back to the defaults for nothing, junk, and missing fields",
			function()
				expect(HelicopterFlightRules.decodeConfig(nil)).toEqual(CONFIG)
				expect(HelicopterFlightRules.decodeConfig("not json")).toEqual(CONFIG)
				local partial = HelicopterFlightRules.decodeConfig('{"APPROACH_SEC": 5, "DEPARTURE_SEC": "x"}')
				expect(partial.APPROACH_SEC).toBe(5)
				expect(partial.DEPARTURE_SEC).toBe(CONFIG.DEPARTURE_SEC)
			end
		)
		it(
			"round-trips a config",
			function()
				local config = table.clone(CONFIG)
				config.DEPARTURE_NOSE_DOWN_DEGREES = 33
				expect(HelicopterFlightRules.decodeConfig(HelicopterFlightRules.encodeConfig(config))).toEqual(config)
			end
		)
	end
)
