--!strict

-- Pure flight paths for the helicopters (M75): where a helicopter is, and
-- which way it points, at a moment of its approach to a pad or its
-- departure from one. Both are a cubic Bezier through four points sampled
-- by time against a config (GameData/Control/Helicopter, published to the
-- clients as GameMetadata JSON), so every client draws the same flight
-- from the one server start time and a late viewer lands on the right
-- frame. The approach runs in level toward the pad, drops over it and
-- flares nose-up as it settles; the departure lifts, banks toward the
-- heading and climbs away. ClientHelicopterManager renders the poses.
local HttpService = game:GetService("HttpService")

local HelicopterFlightRules = {}

export type Config = {
	APPROACH_SEC: number,
	-- the point over the pad the approach drops from
	APPROACH_HOVER_HEIGHT_STUDS: number,
	-- how far along the straight run-in the path keeps its height, as a
	-- share of the flat distance to the pad
	APPROACH_RUN_IN_SHARE: number,
	APPROACH_NOSE_DOWN_DEGREES: number,
	APPROACH_FLARE_DEGREES: number,
	-- the last share of the run-in over which the nose comes round
	-- toward the pad's own facing
	APPROACH_TURN_IN_SHARE: number,
	-- the last share of the approach spent sinking straight down from the
	-- hover point onto the pad
	APPROACH_DESCENT_SHARE: number,
	DEPARTURE_SEC: number,
	-- straight up this far, taking this long, before the lean forward
	DEPARTURE_LIFT_HEIGHT_STUDS: number,
	DEPARTURE_LIFT_SEC: number,
	DEPARTURE_DISTANCE_STUDS: number,
	DEPARTURE_HEIGHT_STUDS: number,
	DEPARTURE_NOSE_DOWN_DEGREES: number,
	DEPARTURE_BANK_DEGREES: number,
}

-- what a client flies with when no config has reached it
HelicopterFlightRules.DEFAULT_CONFIG = {
	APPROACH_SEC = 20,
	APPROACH_HOVER_HEIGHT_STUDS = 40,
	APPROACH_RUN_IN_SHARE = 0.45,
	APPROACH_NOSE_DOWN_DEGREES = 12,
	APPROACH_FLARE_DEGREES = 8,
	APPROACH_TURN_IN_SHARE = 0.3,
	APPROACH_DESCENT_SHARE = 0.3,
	DEPARTURE_SEC = 24,
	DEPARTURE_LIFT_HEIGHT_STUDS = 30,
	DEPARTURE_LIFT_SEC = 6,
	DEPARTURE_DISTANCE_STUDS = 1400,
	DEPARTURE_HEIGHT_STUDS = 260,
	DEPARTURE_NOSE_DOWN_DEGREES = 10,
	DEPARTURE_BANK_DEGREES = 22,
} :: Config

-- the yaw blend of a departure runs over this stretch of the path
local DEPARTURE_TURN_START_SHARE = 0.05
local DEPARTURE_TURN_END_SHARE = 0.45
-- the run-in arrives over the pad from this share of the flat distance
-- back along its way, so it comes in level rather than dropping
local APPROACH_HOVER_LEAD_SHARE = 0.15
-- how much of the turn to the pad's facing the run-in makes; the descent
-- makes the rest
local APPROACH_RUN_IN_TURN_SHARE = 0.6
-- a quarter turn or more banks fully; less banks in proportion
local FULL_BANK_TURN_RADIANS = math.pi / 2
-- the departure's pace at lift-off as a share of its average
local DEPARTURE_START_PACE = 0.6
-- the run-in's pace at its start as a share of its average
local RUN_IN_START_PACE = 1.4
-- the lean forward keeps rising at first: its first control point sits
-- this share of the lift height above the lift's top
local DEPARTURE_LEAN_RISE_SHARE = 0.6
local TINY = 1e-4

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function smoothstep(share: number): number
	local t = clamp01(share)
	return t * t * (3 - 2 * t)
end

-- a run-in that slows toward the pad but never stalls short of it: the
-- pace starts above the average and ends below it (a pure ease-out had
-- it hovering over the pad for the last third of the run-in, 2026-10-27)
function HelicopterFlightRules.easeOutSoft(share: number): number
	local t = clamp01(share)
	return t * (RUN_IN_START_PACE - (RUN_IN_START_PACE - 1) * t)
end

-- a lift-off that is already moving: a start slope well above zero,
-- quickening to the end (a pure quadratic sat still for its first
-- seconds, 2026-10-27)
function HelicopterFlightRules.easeInSoft(share: number): number
	local t = clamp01(share)
	return t * (DEPARTURE_START_PACE + (1 - DEPARTURE_START_PACE) * t)
end

function HelicopterFlightRules.cubicBezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- the derivative with respect to t: the direction of travel (unscaled)
function HelicopterFlightRules.cubicBezierTangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
end

function HelicopterFlightRules.flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- the yaw whose CFrame.Angles(0, yaw, 0).LookVector is the flat direction
function HelicopterFlightRules.yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

function HelicopterFlightRules.yawOfCFrame(cframe: CFrame): number
	return HelicopterFlightRules.yawOf(cframe.LookVector)
end

-- the signed shortest turn from one yaw to another, in (-pi, pi]
function HelicopterFlightRules.angleDifference(fromYaw: number, toYaw: number): number
	local difference = (toYaw - fromYaw) % (2 * math.pi)
	if difference > math.pi then
		difference -= 2 * math.pi
	end
	return difference
end

function HelicopterFlightRules.lerpAngle(fromYaw: number, toYaw: number, share: number): number
	return fromYaw + HelicopterFlightRules.angleDifference(fromYaw, toYaw) * clamp01(share)
end

-- yaw first, then pitch in the turned frame, then roll about the nose
function HelicopterFlightRules.pose(position: Vector3, yaw: number, pitch: number, roll: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, roll)
end

-- the flat unit direction from one point to another, or the fallback
-- when they share a location
function HelicopterFlightRules.flatDirection(fromPosition: Vector3, toPosition: Vector3, fallback: Vector3): Vector3
	local flat = HelicopterFlightRules.flatten(toPosition - fromPosition)
	if flat.Magnitude < TINY then
		local flatFallback = HelicopterFlightRules.flatten(fallback)
		return if flatFallback.Magnitude < TINY then Vector3.new(0, 0, -1) else flatFallback.Unit
	end
	return flat.Unit
end

function HelicopterFlightRules.approachShare(config: Config, elapsedSec: number): number
	return if config.APPROACH_SEC <= 0 then 1 else clamp01(elapsedSec / config.APPROACH_SEC)
end

function HelicopterFlightRules.isApproachDone(config: Config, elapsedSec: number): boolean
	return elapsedSec >= config.APPROACH_SEC
end

function HelicopterFlightRules.departureShare(config: Config, elapsedSec: number): number
	return if config.DEPARTURE_SEC <= 0 then 1 else clamp01(elapsedSec / config.DEPARTURE_SEC)
end

function HelicopterFlightRules.isDepartureDone(config: Config, elapsedSec: number): boolean
	return elapsedSec >= config.DEPARTURE_SEC
end

-- the four points of the run-in, from the start to the hover point over
-- the pad: it keeps its height along the first stretch, then sinks and
-- slows to arrive level over the pad from the side it came
function HelicopterFlightRules.approachPoints(startPosition: Vector3, padCFrame: CFrame, config: Config): (Vector3, Vector3, Vector3, Vector3)
	local padPosition = padCFrame.Position
	local direction = HelicopterFlightRules.flatDirection(startPosition, padPosition, padCFrame.LookVector)
	local flatDistance = HelicopterFlightRules.flatten(padPosition - startPosition).Magnitude
	local hover = padPosition + Vector3.new(0, config.APPROACH_HOVER_HEIGHT_STUDS, 0)
	local p0 = startPosition
	local p1 = startPosition + direction * (flatDistance * config.APPROACH_RUN_IN_SHARE)
	local p2 = hover - direction * (flatDistance * APPROACH_HOVER_LEAD_SHARE)
	return p0, p1, p2, hover
end

-- where the helicopter is on its way in, elapsedSec after the approach
-- began: the run-in to the hover point over the pad takes the first part
-- of APPROACH_SEC and the straight descent onto the pad the last
-- APPROACH_DESCENT_SHARE of it, flaring nose-up as it settles; at and
-- after APPROACH_SEC it sits on the pad in the pad's facing
function HelicopterFlightRules.approachPose(startPosition: Vector3, padCFrame: CFrame, config: Config, elapsedSec: number): CFrame
	local share = HelicopterFlightRules.approachShare(config, elapsedSec)
	local padYaw = HelicopterFlightRules.yawOfCFrame(padCFrame)
	if share >= 1 then
		return HelicopterFlightRules.pose(padCFrame.Position, padYaw, 0, 0)
	end
	local p0, p1, p2, p3 = HelicopterFlightRules.approachPoints(startPosition, padCFrame, config)
	local runInShare = math.max(1 - config.APPROACH_DESCENT_SHARE, TINY)
	if share < runInShare then
		local t = HelicopterFlightRules.easeOutSoft(share / runInShare)
		local position = HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, t)
		local tangent = HelicopterFlightRules.cubicBezierTangent(p0, p1, p2, p3, t)
		local flatTangent = HelicopterFlightRules.flatten(tangent)
		-- the run-in's own pace is the reference: nose down in proportion to it
		local referenceSpeed = (p1 - p0).Magnitude * 3
		local speedShare = if referenceSpeed < TINY then 0 else clamp01(flatTangent.Magnitude / referenceSpeed)
		local flightYaw = if flatTangent.Magnitude < TINY then padYaw else HelicopterFlightRules.yawOf(flatTangent.Unit)
		-- the nose starts coming round to the pad's facing over the end of
		-- the run-in, so the descent finishes the turn
		local turnInShare = math.max(config.APPROACH_TURN_IN_SHARE, TINY)
		local settle = smoothstep((t - (1 - turnInShare)) / turnInShare) * APPROACH_RUN_IN_TURN_SHARE
		local yaw = HelicopterFlightRules.lerpAngle(flightYaw, padYaw, settle)
		local pitch = math.rad(-config.APPROACH_NOSE_DOWN_DEGREES) * speedShare
		return HelicopterFlightRules.pose(position, yaw, pitch, 0)
	end
	local descentShare = (share - runInShare) / math.max(config.APPROACH_DESCENT_SHARE, TINY)
	local sink = smoothstep(descentShare)
	local position = p3:Lerp(padCFrame.Position, sink)
	-- the heading the run-in ended on, finished off to the pad's facing
	local runInEnd = HelicopterFlightRules.flatten(HelicopterFlightRules.cubicBezierTangent(p0, p1, p2, p3, 1))
	local endYaw = if runInEnd.Magnitude < TINY then padYaw else HelicopterFlightRules.yawOf(runInEnd.Unit)
	local yaw = HelicopterFlightRules.lerpAngle(HelicopterFlightRules.lerpAngle(endYaw, padYaw, APPROACH_RUN_IN_TURN_SHARE), padYaw, smoothstep(descentShare))
	local pitch = math.rad(config.APPROACH_FLARE_DEGREES) * math.sin(math.pi * descentShare)
	return HelicopterFlightRules.pose(position, yaw, pitch, 0)
end

-- the four points of the departure's second leg, from the top of the
-- straight lift along the heading: still rising as it leans forward,
-- then away and climbing
function HelicopterFlightRules.departurePoints(padCFrame: CFrame, heading: Vector3, config: Config): (Vector3, Vector3, Vector3, Vector3)
	local padPosition = padCFrame.Position
	local direction = HelicopterFlightRules.flatDirection(Vector3.zero, HelicopterFlightRules.flatten(heading), padCFrame.LookVector)
	local lift = Vector3.new(0, config.DEPARTURE_LIFT_HEIGHT_STUDS, 0)
	local p0 = padPosition + lift
	local p1 = p0 + lift * DEPARTURE_LEAN_RISE_SHARE
	local p2 = p0 + direction * (config.DEPARTURE_DISTANCE_STUDS * 0.3) + Vector3.new(0, (config.DEPARTURE_HEIGHT_STUDS - config.DEPARTURE_LIFT_HEIGHT_STUDS) * 0.3, 0)
	local p3 = padPosition + direction * config.DEPARTURE_DISTANCE_STUDS + Vector3.new(0, config.DEPARTURE_HEIGHT_STUDS, 0)
	return p0, p1, p2, p3
end

-- where the helicopter is on its way out, elapsedSec after lift-off: a
-- straight rise of DEPARTURE_LIFT_HEIGHT_STUDS over DEPARTURE_LIFT_SEC,
-- level and facing the pad's way (designer, 2026-10-27), then the lean
-- forward along the heading, the nose turning from the pad's facing to
-- the heading while it banks into the turn and dips as it picks up speed
function HelicopterFlightRules.departurePose(padCFrame: CFrame, heading: Vector3, config: Config, elapsedSec: number): CFrame
	local padYaw = HelicopterFlightRules.yawOfCFrame(padCFrame)
	local liftSec = math.max(config.DEPARTURE_LIFT_SEC, 0)
	if elapsedSec < liftSec then
		local rise = HelicopterFlightRules.easeInSoft(elapsedSec / liftSec)
		local position = padCFrame.Position + Vector3.new(0, config.DEPARTURE_LIFT_HEIGHT_STUDS * rise, 0)
		return HelicopterFlightRules.pose(position, padYaw, 0, 0)
	end
	local leanSec = math.max(config.DEPARTURE_SEC - liftSec, TINY)
	local share = clamp01((elapsedSec - liftSec) / leanSec)
	local t = HelicopterFlightRules.easeInSoft(share)
	local p0, p1, p2, p3 = HelicopterFlightRules.departurePoints(padCFrame, heading, config)
	local position = HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, t)
	local headingYaw = HelicopterFlightRules.yawOf(HelicopterFlightRules.flatDirection(Vector3.zero, HelicopterFlightRules.flatten(heading), padCFrame.LookVector))
	local turn = HelicopterFlightRules.angleDifference(padYaw, headingYaw)
	local turnShare = smoothstep((t - DEPARTURE_TURN_START_SHARE) / (DEPARTURE_TURN_END_SHARE - DEPARTURE_TURN_START_SHARE))
	local yaw = padYaw + turn * turnShare
	local bankStrength = clamp01(math.abs(turn) / FULL_BANK_TURN_RADIANS)
	-- a left turn (yaw growing) lifts the right side: positive roll
	local roll = math.sign(turn) * math.rad(config.DEPARTURE_BANK_DEGREES) * bankStrength * math.sin(math.pi * turnShare)
	local pitch = math.rad(-config.DEPARTURE_NOSE_DOWN_DEGREES) * smoothstep(t / 0.5)
	return HelicopterFlightRules.pose(position, yaw, pitch, roll)
end

function HelicopterFlightRules.encodeConfig(config: Config): string
	return HttpService:JSONEncode(config)
end

-- a config from the published JSON, every missing or odd field falling
-- back to the default so a client always has a whole flight
function HelicopterFlightRules.decodeConfig(json: any): Config
	local decoded: any = nil
	if typeof(json) == "string" and json ~= "" then
		local isSuccess, result = pcall(HttpService.JSONDecode, HttpService, json)
		if isSuccess and typeof(result) == "table" then
			decoded = result
		end
	end
	local config = table.clone(HelicopterFlightRules.DEFAULT_CONFIG)
	if decoded then
		for key, default in pairs(HelicopterFlightRules.DEFAULT_CONFIG :: any) do
			local value = decoded[key]
			if typeof(value) == "number" and typeof(default) == "number" then
				(config :: any)[key] = value
			end
		end
	end
	return config
end

return HelicopterFlightRules
