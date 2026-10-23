--!strict

-- Pure rules for anything a weapon or a post lobs or launches (M64, the
-- class posts of 2026-10-16): where a projectile is after a stretch of
-- flight, straight or pulled down by gravity, and how a homing one bends
-- toward its target. The server (ProjectileManager) flies the truth
-- segment by segment with these; every client flies its own copy from
-- the launch message with the same maths, so the two agree without a
-- position ever travelling over the network.
local ProjectileRules = {}

-- a projectile's motion at launch: everything the client needs to draw it
export type Flight = {
	origin: Vector3,
	unitDirection: Vector3,
	speedStudsPerSec: number,
	-- 0 for a straight flight
	gravityStudsPerSec2: number,
}

-- velocity after flying for elapsedSec: the launch velocity plus the fall
function ProjectileRules.velocityAt(flight: Flight, elapsedSec: number): Vector3
	return flight.unitDirection * flight.speedStudsPerSec - Vector3.new(0, flight.gravityStudsPerSec2 * elapsedSec, 0)
end

-- the position after flying for elapsedSec from the origin
function ProjectileRules.positionAt(flight: Flight, elapsedSec: number): Vector3
	return flight.origin + flight.unitDirection * flight.speedStudsPerSec * elapsedSec - Vector3.new(0, 0.5 * flight.gravityStudsPerSec2 * elapsedSec * elapsedSec, 0)
end

-- the way the nose points in flight: along the velocity, or the launch
-- direction for a stopped one
function ProjectileRules.headingAt(flight: Flight, elapsedSec: number): Vector3
	local velocity = ProjectileRules.velocityAt(flight, elapsedSec)
	return if velocity.Magnitude > 1e-6 then velocity.Unit else flight.unitDirection
end

-- a homing step: the direction turned toward the target by at most
-- maxTurnDegrees; a target at the origin leaves the direction alone
function ProjectileRules.turnToward(unitDirection: Vector3, position: Vector3, targetPosition: Vector3, maxTurnDegrees: number): Vector3
	local toTarget = targetPosition - position
	if toTarget.Magnitude < 1e-6 or maxTurnDegrees <= 0 then
		return unitDirection
	end
	local wanted = toTarget.Unit
	local cosAngle = math.clamp(unitDirection:Dot(wanted), -1, 1)
	local angle = math.acos(cosAngle)
	local maxTurn = math.rad(maxTurnDegrees)
	if angle <= maxTurn then
		return wanted
	end
	local axis = unitDirection:Cross(wanted)
	if axis.Magnitude < 1e-6 then
		-- straight behind: any sideways turn will do
		axis = if math.abs(unitDirection.Y) < 0.9 then unitDirection:Cross(Vector3.yAxis) else unitDirection:Cross(Vector3.xAxis)
	end
	return CFrame.fromAxisAngle(axis.Unit, maxTurn):VectorToWorldSpace(unitDirection).Unit
end

-- how far a lob at this speed and angle lands from its origin on level
-- ground, for a range check that means something to a gunner
function ProjectileRules.levelRangeStuds(speedStudsPerSec: number, gravityStudsPerSec2: number, pitchDegrees: number): number
	if gravityStudsPerSec2 <= 0 then
		return math.huge
	end
	local pitch = math.rad(pitchDegrees)
	return speedStudsPerSec * speedStudsPerSec * math.sin(2 * pitch) / gravityStudsPerSec2
end

-- a lob at a fixed elevation (the TNT Launcher, 2026-10-20): the speed
-- that lands a shell from origin on target is solved from
-- v^2 = g d^2 / (2 cos^2(a) (d tan(a) - h)), so the gunner aims at a spot
-- and the arc is the gun's. A spot past the top speed's reach gets the
-- top speed instead and lands short, on the target's own level, and
-- isReached says so; the flight time is for a range that fits the arc
export type Lob = {
	unitDirection: Vector3,
	speedStudsPerSec: number,
	landing: Vector3,
	flightSec: number,
	isReached: boolean,
}

function ProjectileRules.lobToward(origin: Vector3, target: Vector3, angleDegrees: number, gravityStudsPerSec2: number, maxSpeedStudsPerSec: number): Lob
	local flat = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local distance = flat.Magnitude
	local height = target.Y - origin.Y
	local angle = math.rad(angleDegrees)
	local cosAngle = math.cos(angle)
	local sinAngle = math.sin(angle)
	local tanAngle = math.tan(angle)
	local flatUnit = if distance > 1e-6 then flat.Unit else Vector3.zAxis
	local unitDirection = flatUnit * cosAngle + Vector3.yAxis * sinAngle
	local drop = distance * tanAngle - height
	if distance > 1e-6 and drop > 0 then
		local speed = math.sqrt(gravityStudsPerSec2 * distance * distance / (2 * cosAngle * cosAngle * drop))
		if speed <= maxSpeedStudsPerSec then
			return {
				unitDirection = unitDirection,
				speedStudsPerSec = speed,
				landing = target,
				flightSec = distance / (speed * cosAngle),
				isReached = true,
			}
		end
	end
	-- the farthest landing on the target's level at the top speed:
	-- g d^2 - 2 v^2 cos^2(a) tan(a) d + 2 v^2 cos^2(a) h = 0, the far root
	local speedSquared = maxSpeedStudsPerSec * maxSpeedStudsPerSec
	local horizontalSquared = speedSquared * cosAngle * cosAngle
	local halfLinear = horizontalSquared * tanAngle
	local discriminant = halfLinear * halfLinear - 2 * gravityStudsPerSec2 * horizontalSquared * height
	local reach
	if discriminant >= 0 then
		reach = (halfLinear + math.sqrt(discriminant)) / gravityStudsPerSec2
	else
		-- too high to reach on its level: the level reach is the best guess
		reach = ProjectileRules.levelRangeStuds(maxSpeedStudsPerSec, gravityStudsPerSec2, angleDegrees)
	end
	reach = math.min(reach, distance)
	return {
		unitDirection = unitDirection,
		speedStudsPerSec = maxSpeedStudsPerSec,
		landing = Vector3.new(origin.X, target.Y, origin.Z) + flatUnit * reach,
		flightSec = reach / math.max(maxSpeedStudsPerSec * cosAngle, 1e-6),
		isReached = false,
	}
end

-- a falling shot at a fixed speed that still lands on the aim point (the
-- Fault Line Drill's bit, designer 2026-10-22: the arc should sag but
-- the drill land where the sight is): the low launch angle solved from
-- tan(a) = (v^2 - sqrt(v^4 - g (g d^2 + 2 h v^2))) / (g d), raised just
-- enough that gravity brings it back down onto the target. Past the
-- speed's reach (no real root) isReached is false and the direction is
-- the straight line, which lands short as a plain shot would
export type Aim = {
	unitDirection: Vector3,
	flightSec: number,
	isReached: boolean,
}

function ProjectileRules.aimToward(origin: Vector3, target: Vector3, gravityStudsPerSec2: number, speedStudsPerSec: number): Aim
	local offset = target - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local height = offset.Y
	local straight = if offset.Magnitude > 1e-6 then offset.Unit else Vector3.zAxis
	if gravityStudsPerSec2 <= 0 or speedStudsPerSec <= 0 or distance < 1e-6 then
		return {
			unitDirection = straight,
			flightSec = offset.Magnitude / math.max(speedStudsPerSec, 1e-6),
			isReached = gravityStudsPerSec2 <= 0,
		}
	end
	local speedSquared = speedStudsPerSec * speedStudsPerSec
	local discriminant = speedSquared * speedSquared - gravityStudsPerSec2 * (gravityStudsPerSec2 * distance * distance + 2 * height * speedSquared)
	if discriminant < 0 then
		return {
			unitDirection = straight,
			flightSec = offset.Magnitude / speedStudsPerSec,
			isReached = false,
		}
	end
	local angle = math.atan((speedSquared - math.sqrt(discriminant)) / (gravityStudsPerSec2 * distance))
	local flatUnit = flat.Unit
	return {
		unitDirection = flatUnit * math.cos(angle) + Vector3.yAxis * math.sin(angle),
		flightSec = distance / (speedStudsPerSec * math.cos(angle)),
		isReached = true,
	}
end

-- a boomerang's flight (the Prospector's thrown pick axe, 2026-10-22):
-- straight out along the launch direction for outStuds at the speed,
-- then straight back the same line to the origin, where it is done. No
-- gravity and nothing in the world turns it early, so every client can
-- fly it from the launch alone. isReturning is the leg it is on
export type ReturnLeg = {
	position: Vector3,
	unitDirection: Vector3,
	isReturning: boolean,
	isDone: boolean,
}

function ProjectileRules.returningAt(flight: Flight, elapsedSec: number, outStuds: number): ReturnLeg
	local travelled = flight.speedStudsPerSec * math.max(elapsedSec, 0)
	if travelled <= outStuds then
		return {
			position = flight.origin + flight.unitDirection * travelled,
			unitDirection = flight.unitDirection,
			isReturning = false,
			isDone = false,
		}
	end
	local back = math.min(travelled - outStuds, outStuds)
	return {
		position = flight.origin + flight.unitDirection * (outStuds - back),
		unitDirection = -flight.unitDirection,
		isReturning = true,
		isDone = back >= outStuds,
	}
end

return ProjectileRules
