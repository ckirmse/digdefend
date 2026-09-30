--!strict

-- Pure maths for the Defense Table's overhead camera (GDD "Defense
-- Table"): where the camera sits for a point it looks at, where a screen
-- ray meets the build surface, how far a pan or a zoom moves it, and how
-- the looked-at point is kept over the Defensive Zone. Tuning is passed in
-- from GameData so this stays unit testable.
local PlacementRules = require(script.Parent.PlacementRules)

local BuildCameraRules = {}

-- the camera never looks flatter than this or quite straight down, where
-- "up the screen" would have no direction
local MIN_PITCH_DEGREES = 10
local MAX_PITCH_DEGREES = 89

-- the unit direction on the ground from one position toward another: the
-- way that is "up the screen" when the camera looks from the camp out over
-- the zone. The fallback serves when the two are at the same location
function BuildCameraRules.flatDirection(fromPosition: Vector3, toPosition: Vector3, fallbackX: number, fallbackZ: number): (number, number)
	local x = toPosition.X - fromPosition.X
	local z = toPosition.Z - fromPosition.Z
	local length = math.sqrt(x * x + z * z)
	if length < 0.001 then
		return fallbackX, fallbackZ
	end
	return x / length, z / length
end

-- a ground direction turned to the nearest of the grid's four axes, so the
-- cells run straight up and across the screen instead of a few degrees off
function BuildCameraRules.snapToGridAxis(grid: PlacementRules.Grid, directionX: number, directionZ: number): (number, number)
	local right = grid.cframe.RightVector
	local look = grid.cframe.LookVector
	local bestX, bestZ = directionX, directionZ
	local bestDot = -math.huge
	for _, axis in { right, -right, look, -look } do
		local dot = axis.X * directionX + axis.Z * directionZ
		if dot > bestDot then
			bestDot = dot
			bestX, bestZ = axis.X, axis.Z
		end
	end
	local length = math.sqrt(bestX * bestX + bestZ * bestZ)
	if length < 0.001 then
		return directionX, directionZ
	end
	return bestX / length, bestZ / length
end

-- the camera's pose: distanceStuds from the focus, raised by the pitch (90
-- would be straight down), behind it along the forward direction, looking
-- at it with forward up the screen
function BuildCameraRules.cameraCFrame(focus: Vector3, forwardX: number, forwardZ: number, pitchDegrees: number, distanceStuds: number): CFrame
	local pitch = math.rad(math.clamp(pitchDegrees, MIN_PITCH_DEGREES, MAX_PITCH_DEGREES))
	local flat = math.cos(pitch) * distanceStuds
	local position = focus + Vector3.new(-forwardX * flat, math.sin(pitch) * distanceStuds, -forwardZ * flat)
	return CFrame.lookAt(position, focus, Vector3.new(forwardX, 0, forwardZ))
end

-- where a ray meets the horizontal plane at planeY; nil when it runs level
-- with the plane or away from it
function BuildCameraRules.pointOnPlane(origin: Vector3, direction: Vector3, planeY: number): Vector3?
	if math.abs(direction.Y) < 0.0001 then
		return nil
	end
	local distance = (planeY - origin.Y) / direction.Y
	if distance <= 0 then
		return nil
	end
	return origin + direction * distance
end

-- how many studs on the build surface one screen pixel covers at the
-- middle of the view, so a drag moves the ground with the finger
function BuildCameraRules.studsPerPixel(distanceStuds: number, fieldOfViewDegrees: number, viewportHeightPx: number): number
	if viewportHeightPx <= 0 then
		return 0
	end
	return 2 * distanceStuds * math.tan(math.rad(fieldOfViewDegrees) / 2) / viewportHeightPx
end

-- the focus moved by an amount to the right and an amount forward (studs),
-- in the camera's own left-right and up-down
function BuildCameraRules.panFocus(focus: Vector3, forwardX: number, forwardZ: number, rightStuds: number, forwardStuds: number): Vector3
	return focus + Vector3.new(-forwardZ * rightStuds + forwardX * forwardStuds, 0, forwardX * rightStuds + forwardZ * forwardStuds)
end

-- the distance after zooming: each step in closes (or, negative, opens)
-- the distance by stepShare of itself, inside the limits
function BuildCameraRules.zoomDistance(distanceStuds: number, steps: number, stepShare: number, minStuds: number, maxStuds: number): number
	return math.clamp(distanceStuds * (1 - stepShare) ^ steps, minStuds, maxStuds)
end

-- the focus kept on the zone: inside its rectangle, on its surface
function BuildCameraRules.clampFocus(grid: PlacementRules.Grid, focus: Vector3): Vector3
	local halfWidth = grid.columns * grid.cellSizeStuds / 2
	local halfDepth = grid.rows * grid.cellSizeStuds / 2
	local localPoint = grid.cframe:PointToObjectSpace(focus)
	return grid.cframe:PointToWorldSpace(Vector3.new(math.clamp(localPoint.X, -halfWidth, halfWidth), 0, math.clamp(localPoint.Z, -halfDepth, halfDepth)))
end

return BuildCameraRules
