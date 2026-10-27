-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local HelicopterFlightRules = require(game:GetService("ReplicatedStorage").Shared.HelicopterFlightRules)

local CONFIG = HelicopterFlightRules.DEFAULT_CONFIG
-- a pad at the origin facing -Z (Roblox's forward), and a start far out
-- to the +X side and high up
local PAD = CFrame.new(0, 10, 0)
local START = Vector3.new(400, 150, 100)

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
			"starts at the start and ends on the pad in its facing",
			function()
				local first = HelicopterFlightRules.approachPose(START, PAD, CONFIG, 0)
				expectVectorClose(first.Position, START)
				local last = HelicopterFlightRules.approachPose(START, PAD, CONFIG, CONFIG.APPROACH_SEC)
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
				local early = HelicopterFlightRules.approachPose(START, PAD, CONFIG, 1)
				local toPad = HelicopterFlightRules.flatten(PAD.Position - early.Position).Unit
				local flatLook = HelicopterFlightRules.flatten(early.LookVector).Unit
				expect(flatLook:Dot(toPad)).toBeGreaterThan(0.95)
				-- nose down: the look dips below level
				expect(early.LookVector.Y).toBeLessThan(0)
				for step = 0, 40 do
					local pose = HelicopterFlightRules.approachPose(START, PAD, CONFIG, CONFIG.APPROACH_SEC * step / 40)
					expect(pose.Position.Y).toBeGreaterThanOrEqual(PAD.Position.Y - 0.001)
				end
			end
		)
		it(
			"keeps moving toward the pad the whole way",
			function()
				local lastDistance = math.huge
				for step = 0, 40 do
					local pose = HelicopterFlightRules.approachPose(START, PAD, CONFIG, CONFIG.APPROACH_SEC * step / 40)
					local distance = (pose.Position - PAD.Position).Magnitude
					expect(distance).toBeLessThanOrEqual(lastDistance + 0.001)
					lastDistance = distance
				end
			end
		)
		it(
			"is over the pad at the hover height when the descent begins, and still well out at half time",
			function()
				local runInSec = CONFIG.APPROACH_SEC * (1 - CONFIG.APPROACH_DESCENT_SHARE)
				local hover = HelicopterFlightRules.approachPose(START, PAD, CONFIG, runInSec)
				expectVectorClose(hover.Position, PAD.Position + Vector3.new(0, CONFIG.APPROACH_HOVER_HEIGHT_STUDS, 0), 2)
				local halfway = HelicopterFlightRules.approachPose(START, PAD, CONFIG, CONFIG.APPROACH_SEC * 0.5)
				expect((halfway.Position - PAD.Position).Magnitude).toBeGreaterThan(CONFIG.APPROACH_HOVER_HEIGHT_STUDS + 20)
				-- the flare: nose up partway down
				local settling = HelicopterFlightRules.approachPose(START, PAD, CONFIG, runInSec + (CONFIG.APPROACH_SEC - runInSec) * 0.5)
				expect(settling.LookVector.Y).toBeGreaterThan(0)
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
					expectVectorClose(rising.LookVector, PAD.LookVector)
				end
				local top = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC)
				expectVectorClose(top.Position, PAD.Position + Vector3.new(0, CONFIG.DEPARTURE_LIFT_HEIGHT_STUDS, 0))
				local leaning = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_LIFT_SEC + 3)
				expect(leaning.Position.X).toBeGreaterThan(PAD.Position.X + 1)
				expect(leaning.Position.Y).toBeGreaterThan(top.Position.Y)
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
			"banks into the turn and not at all when the heading is its facing",
			function()
				local midway = HelicopterFlightRules.departurePose(PAD, heading, CONFIG, CONFIG.DEPARTURE_SEC * 0.5)
				-- the pad faces -Z and the heading is +X: a right turn, so the
				-- right side drops
				expect(midway.RightVector.Y).toBeLessThan(-0.05)
				local leftTurn = HelicopterFlightRules.departurePose(PAD, Vector3.new(-1, 0, 0), CONFIG, CONFIG.DEPARTURE_SEC * 0.5)
				expect(leftTurn.RightVector.Y).toBeGreaterThan(0.05)
				local straight = HelicopterFlightRules.departurePose(PAD, PAD.LookVector, CONFIG, CONFIG.DEPARTURE_SEC * 0.5)
				expect(straight.RightVector.Y).toBeCloseTo(0, 5)
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
				config.DEPARTURE_BANK_DEGREES = 33
				expect(HelicopterFlightRules.decodeConfig(HelicopterFlightRules.encodeConfig(config))).toEqual(config)
			end
		)
	end
)
