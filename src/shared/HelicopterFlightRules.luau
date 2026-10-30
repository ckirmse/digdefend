--!strict

-- Pure flight paths for the helicopters (M75): where a helicopter is, and
-- which way it points, at a moment of its approach to a pad or its
-- departure from one. The departure is a straight rise then a cubic
-- Bezier away along the heading, and the approach is that same path flown
-- backwards (designer, 2026-10-27: it comes in the way it leaves), both
-- sampled by time against a config (GameData/Control/Helicopter,
-- published to the clients as GameMetadata JSON), so every client draws
-- the same flight from the one server start time and a late viewer lands
-- on the right frame. The approach comes in nose down, turns hovering to
-- the pad's facing and sinks straight onto the pad flaring nose-up; the
-- departure lifts straight up, turning hovering from the pad's facing to
-- the heading on the way (a half turn on the lobby pads, so two helicopters
-- facing each other leave away from each other, designer 2026-10-30; the
-- lean banked into the turn before, which never showed since every heading
-- was the facing), then climbs away nose-first, at full speed within
-- DEPARTURE_RAMP_SEC of leaning forward. ClientHelicopterManager renders
-- the poses.
local HttpService = game:GetService("HttpService")

local HelicopterFlightRules = {}

export type Config = {
	APPROACH_SEC: number,
	APPROACH_NOSE_DOWN_DEGREES: number,
	APPROACH_FLARE_DEGREES: number,
	-- the first share of the descent over which the nose comes round
	-- toward the pad's own facing (it flew the run-in nose-first; the turn
	-- was over the run-in's end before, which looked too early, 2026-10-27)
	APPROACH_TURN_IN_SHARE: number,
	-- the last share of the approach spent sinking straight down the
	-- departure's lift onto the pad
	APPROACH_DESCENT_SHARE: number,
	DEPARTURE_SEC: number,
	-- straight up this far, taking this long, before the lean forward
	DEPARTURE_LIFT_HEIGHT_STUDS: number,
	DEPARTURE_LIFT_SEC: number,
	-- the lean is at full speed this long after it begins, and holds it
	DEPARTURE_RAMP_SEC: number,
	DEPARTURE_DISTANCE_STUDS: number,
	DEPARTURE_HEIGHT_STUDS: number,
	DEPARTURE_NOSE_DOWN_DEGREES: number,
}

-- what a client flies with when no config has reached it
HelicopterFlightRules.DEFAULT_CONFIG = {
	APPROACH_SEC = 30,
	APPROACH_NOSE_DOWN_DEGREES = 12,
	APPROACH_FLARE_DEGREES = 8,
	APPROACH_TURN_IN_SHARE = 0.6,
	APPROACH_DESCENT_SHARE = 0.3,
	DEPARTURE_SEC = 20.4,
	DEPARTURE_LIFT_HEIGHT_STUDS = 30,
	DEPARTURE_LIFT_SEC = 6,
	DEPARTURE_RAMP_SEC = 10,
	DEPARTURE_DISTANCE_STUDS = 1960,
	DEPARTURE_HEIGHT_STUDS = 350,
	DEPARTURE_NOSE_DOWN_DEGREES = 10,
} :: Config

-- the lift's pace at lift-off as a share of its average
local DEPARTURE_START_PACE = 0.6
-- the lean and the run-in are paced by distance along their curve, not
-- by the curve's own parameter (whose speed swells along it), so a held
-- pace is a held speed in studs: the curve is measured at this many
-- points each sample
local ARC_SAMPLES = 48
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

-- a run-in that slows steadily to a stop over the pad: twice the average
-- pace at the far end, none at the top of the lift (paced by distance,
-- so it is a true deceleration rather than a stall short of the pad)
function HelicopterFlightRules.easeOutQuad(share: number): number
	local t = clamp01(share)
	return 1 - (1 - t) * (1 - t)
end

-- the curve's parameter at a share of its length: the cubic Bezier is
-- measured at ARC_SAMPLES points and the share is found between them
function HelicopterFlightRules.parameterAtLengthShare(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, lengthShare: number): number
	local share = clamp01(lengthShare)
	local lengths: { number } = {}
	lengths[1] = 0
	local previous = p0
	for sample = 1, ARC_SAMPLES do
		local point = HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, sample / ARC_SAMPLES)
		lengths[sample + 1] = lengths[sample] + (point - previous).Magnitude
		previous = point
	end
	local total = lengths[ARC_SAMPLES + 1]
	if total < TINY then
		return share
	end
	local target = share * total
	for sample = 1, ARC_SAMPLES do
		local from = lengths[sample]
		local to = lengths[sample + 1]
		if target <= to then
			local within = if to - from < TINY then 0 else (target - from) / (to - from)
			return (sample - 1 + within) / ARC_SAMPLES
		end
	end
	return 1
end

-- a lift-off that is already moving: a start slope well above zero,
-- quickening to the end (a pure quadratic sat still for its first
-- seconds, 2026-10-27)
function HelicopterFlightRules.easeInSoft(share: number): number
	local t = clamp01(share)
	return t * (DEPARTURE_START_PACE + (1 - DEPARTURE_START_PACE) * t)
end

-- how far along the lean's length (0 to 1) it is at a share of its time:
-- the pace rises from a standstill to full over the ramp (rampShare of
-- the lean's time) and holds full speed to the end, the full pace being
-- whatever makes the whole lean fit (designer, 2026-10-27: a steady
-- build-up to full speed, then held)
function HelicopterFlightRules.leanProgress(share: number, rampShare: number): number
	local s = clamp01(share)
	local r = math.clamp(rampShare, TINY, 1)
	local fullPace = 1 / (1 - r / 2)
	if s < r then
		return fullPace * s * s / (2 * r)
	end
	return fullPace * (r / 2 + s - r)
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

-- where an approach to the pad begins: the far end of the departure
-- along the heading, since it flies that path backwards
function HelicopterFlightRules.approachStart(padCFrame: CFrame, heading: Vector3, config: Config): Vector3
	local _, _, _, farEnd = HelicopterFlightRules.departurePoints(padCFrame, heading, config)
	return farEnd
end

-- where the helicopter is on its way in, elapsedSec after the approach
-- began: the departure's lean flown backwards from its far end to the
-- top of the lift takes the first part of APPROACH_SEC, nose-first and
-- nose down with its pace; then the straight descent down the lift onto
-- the pad takes the last APPROACH_DESCENT_SHARE, the nose coming round
-- to the pad's facing over its first APPROACH_TURN_IN_SHARE and flaring
-- nose-up as it settles; at and after APPROACH_SEC it sits on the pad in
-- the pad's facing
function HelicopterFlightRules.approachPose(padCFrame: CFrame, heading: Vector3, config: Config, elapsedSec: number): CFrame
	local share = HelicopterFlightRules.approachShare(config, elapsedSec)
	local padYaw = HelicopterFlightRules.yawOfCFrame(padCFrame)
	if share >= 1 then
		return HelicopterFlightRules.pose(padCFrame.Position, padYaw, 0, 0)
	end
	local p0, p1, p2, p3 = HelicopterFlightRules.departurePoints(padCFrame, heading, config)
	local runInShare = math.max(1 - config.APPROACH_DESCENT_SHARE, TINY)
	if share < runInShare then
		local flown = HelicopterFlightRules.easeOutQuad(share / runInShare)
		local t = HelicopterFlightRules.parameterAtLengthShare(p0, p1, p2, p3, 1 - flown)
		local position = HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, t)
		-- backwards along the curve: the travel is against its tangent
		local travel = -HelicopterFlightRules.cubicBezierTangent(p0, p1, p2, p3, t)
		local flatTravel = HelicopterFlightRules.flatten(travel)
		-- the pace at the far end is the reference: nose down in proportion
		local referenceSpeed = (p3 - p2).Magnitude * 3
		local speedShare = if referenceSpeed < TINY then 0 else clamp01(flatTravel.Magnitude / referenceSpeed)
		local inboundYaw = HelicopterFlightRules.yawOf(HelicopterFlightRules.flatDirection(p3, p0, padCFrame.LookVector))
		local flightYaw = if flatTravel.Magnitude < TINY then inboundYaw else HelicopterFlightRules.yawOf(flatTravel.Unit)
		local pitch = math.rad(-config.APPROACH_NOSE_DOWN_DEGREES) * speedShare
		return HelicopterFlightRules.pose(position, flightYaw, pitch, 0)
	end
	local descentShare = (share - runInShare) / math.max(config.APPROACH_DESCENT_SHARE, TINY)
	local sink = smoothstep(descentShare)
	local position = p0:Lerp(padCFrame.Position, sink)
	-- a hovering turn from the way it came in to the pad's facing, over
	-- the descent's first part
	local inboundYaw = HelicopterFlightRules.yawOf(HelicopterFlightRules.flatDirection(p3, p0, padCFrame.LookVector))
	local turn = smoothstep(descentShare / math.max(config.APPROACH_TURN_IN_SHARE, TINY))
	local yaw = HelicopterFlightRules.lerpAngle(inboundYaw, padYaw, turn)
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
-- the heading while it banks into the turn and dips as it picks up speed,
-- at full speed DEPARTURE_RAMP_SEC into the lean
function HelicopterFlightRules.departurePose(padCFrame: CFrame, heading: Vector3, config: Config, elapsedSec: number): CFrame
	local padYaw = HelicopterFlightRules.yawOfCFrame(padCFrame)
	local headingYaw = HelicopterFlightRules.yawOf(HelicopterFlightRules.flatDirection(Vector3.zero, HelicopterFlightRules.flatten(heading), padCFrame.LookVector))
	local liftSec = math.max(config.DEPARTURE_LIFT_SEC, 0)
	if elapsedSec < liftSec then
		-- a hovering turn from the pad's facing to the heading over the
		-- whole lift, so the lean leaves nose-first (the approach's descent
		-- turns the same way, back again)
		local liftShare = elapsedSec / liftSec
		local rise = HelicopterFlightRules.easeInSoft(liftShare)
		local position = padCFrame.Position + Vector3.new(0, config.DEPARTURE_LIFT_HEIGHT_STUDS * rise, 0)
		local yaw = HelicopterFlightRules.lerpAngle(padYaw, headingYaw, smoothstep(liftShare))
		return HelicopterFlightRules.pose(position, yaw, 0, 0)
	end
	local leanSec = math.max(config.DEPARTURE_SEC - liftSec, TINY)
	local share = clamp01((elapsedSec - liftSec) / leanSec)
	local p0, p1, p2, p3 = HelicopterFlightRules.departurePoints(padCFrame, heading, config)
	local t = HelicopterFlightRules.parameterAtLengthShare(p0, p1, p2, p3, HelicopterFlightRules.leanProgress(share, config.DEPARTURE_RAMP_SEC / leanSec))
	local position = HelicopterFlightRules.cubicBezier(p0, p1, p2, p3, t)
	local pitch = math.rad(-config.DEPARTURE_NOSE_DOWN_DEGREES) * smoothstep(t / 0.5)
	return HelicopterFlightRules.pose(position, headingYaw, pitch, 0)
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
