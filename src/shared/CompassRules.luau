--!strict

-- Pure rules for the Compass (GDD "Compass"): where a marker sits on the
-- locator bar given where the camera looks, how big a player's dot is at a
-- distance, whether a marker is above or below, and which dot colour a
-- joining player takes. Tuning is passed in from GameData so this stays
-- unit testable.
local CompassRules = {}

-- a look flatter than this (straight up or down) has no usable heading
local MIN_FLAT_LOOK = 0.05

CompassRules.VERTICAL_HINT_NONE = 0
CompassRules.VERTICAL_HINT_UP = 1
CompassRules.VERTICAL_HINT_DOWN = -1

-- the camera's heading on the ground as a unit (x, z). Looking straight
-- down the look vector has no heading, but the top of the screen still
-- points somewhere: the camera's up vector (its opposite when looking up)
function CompassRules.flatForward(lookVector: Vector3, upVector: Vector3): (number, number)
	local x = lookVector.X
	local z = lookVector.Z
	if math.sqrt(x * x + z * z) < MIN_FLAT_LOOK then
		local sign = if lookVector.Y < 0 then 1 else -1
		x = upVector.X * sign
		z = upVector.Z * sign
	end
	local length = math.sqrt(x * x + z * z)
	if length <= 0 then
		return 0, -1
	end
	return x / length, z / length
end

-- how far the target is off straight ahead, in degrees: 0 ahead, positive
-- to the right, negative to the left, 180 behind. A target at the viewer's
-- own location is straight ahead
function CompassRules.relativeYawDegrees(forwardX: number, forwardZ: number, fromPosition: Vector3, toPosition: Vector3): number
	local deltaX = toPosition.X - fromPosition.X
	local deltaZ = toPosition.Z - fromPosition.Z
	if deltaX == 0 and deltaZ == 0 then
		return 0
	end
	local cross = forwardX * deltaZ - forwardZ * deltaX
	local dot = forwardX * deltaX + forwardZ * deltaZ
	return math.deg(math.atan2(cross, dot))
end

-- where along the bar a marker sits, 0 (left end) to 1 (right end); nil
-- when it is outside the field of view and not pinned. A pinned marker
-- waits at the nearer end instead
function CompassRules.barShare(relativeYawDegrees: number, fieldOfViewDegrees: number, isPinned: boolean): number?
	local half = fieldOfViewDegrees / 2
	if math.abs(relativeYawDegrees) > half then
		if not isPinned then
			return nil
		end
		return if relativeYawDegrees < 0 then 0 else 1
	end
	return 0.5 + relativeYawDegrees / fieldOfViewDegrees
end

-- a dot's size as a share of full: 1 at or inside fullSizeStuds, shrinking
-- evenly to smallestScale at smallestStuds and beyond
function CompassRules.dotScale(distanceStuds: number, fullSizeStuds: number, smallestStuds: number, smallestScale: number): number
	if distanceStuds <= fullSizeStuds or smallestStuds <= fullSizeStuds then
		return 1
	end
	local share = math.clamp((distanceStuds - fullSizeStuds) / (smallestStuds - fullSizeStuds), 0, 1)
	return 1 + (smallestScale - 1) * share
end

-- the arrow a marker carries: up when the target is more than the
-- threshold above the viewer, down when below, none when about level
function CompassRules.verticalHint(deltaY: number, thresholdStuds: number): number
	if deltaY > thresholdStuds then
		return CompassRules.VERTICAL_HINT_UP
	elseif deltaY < -thresholdStuds then
		return CompassRules.VERTICAL_HINT_DOWN
	end
	return CompassRules.VERTICAL_HINT_NONE
end

-- the dot colour a joining player takes: the lowest index nobody holds,
-- so a colour freed by a leaver is reused and nobody else's ever changes.
-- A crew larger than the palette shares from the start again
function CompassRules.lowestFreeIndex(takenIndexes: { [number]: boolean }, colorCount: number): number
	for index = 1, colorCount do
		if not takenIndexes[index] then
			return index
		end
	end
	return 1
end

return CompassRules
