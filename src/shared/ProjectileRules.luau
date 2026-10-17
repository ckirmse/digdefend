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

return ProjectileRules
