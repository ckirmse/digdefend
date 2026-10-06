--!strict

-- Pure rules for the Camp Map (GDD "HUD", M33): the overhead drawing of the
-- camp's walls, gate, and Refinery shown at night. The map is fixed
-- north-up with the top where the monsters come from, so its frame is the
-- line from the Refinery to the gate; every world position is turned into
-- map coordinates through that frame, the whole camp is fitted into the
-- square, and each structure's health picks one of a few plain colour bands.
-- Nothing here touches an instance, so it is unit testable.
local Enums = require(script.Parent.Enums)

local CampMapRules = {}

-- where a structure's health falls in the bands (GDD "HUD", decided
-- 2026-10-06): white at full, yellow down to just over 60%, orange down
-- to just over 30%, red while anything is left, black once destroyed
CampMapRules.HIGH_MIN_SHARE = 0.6
CampMapRules.MID_MIN_SHARE = 0.3

-- a camp whose Refinery and gate sit on the same spot has no direction;
-- the map then points down negative Z, the engine's forward
local DEFAULT_FORWARD_X = 0
local DEFAULT_FORWARD_Z = -1
local MIN_DIRECTION_STUDS = 0.01

-- the camp's frame on the ground: an origin and the unit direction the
-- top of the map points, with the matching right-hand direction
export type Frame = {
	originX: number,
	originZ: number,
	forwardX: number,
	forwardZ: number,
	rightX: number,
	rightZ: number,
}

-- how map coordinates (studs along the frame's right and forward) fit the
-- unit square: the point drawn at its centre and the square's share per stud
export type Layout = {
	centerU: number,
	centerV: number,
	scale: number,
}

export type MapPoint = {
	u: number,
	v: number,
}

function CampMapRules.healthBand(hp: number, maxHp: number, isDestroyed: boolean): number
	if isDestroyed or maxHp <= 0 or hp <= 0 then
		return Enums.StructureHealthBand.DESTROYED
	end
	local share = hp / maxHp
	if share >= 1 then
		return Enums.StructureHealthBand.FULL
	elseif share > CampMapRules.HIGH_MIN_SHARE then
		return Enums.StructureHealthBand.HIGH
	elseif share > CampMapRules.MID_MIN_SHARE then
		return Enums.StructureHealthBand.MID
	end
	return Enums.StructureHealthBand.LOW
end

-- the frame from the Refinery toward the gate: the gate side is where the
-- monsters come from, so it is the top of the map
function CampMapRules.makeFrame(refineryPosition: Vector3, gatePosition: Vector3): Frame
	local deltaX = gatePosition.X - refineryPosition.X
	local deltaZ = gatePosition.Z - refineryPosition.Z
	local length = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
	local forwardX = DEFAULT_FORWARD_X
	local forwardZ = DEFAULT_FORWARD_Z
	if length >= MIN_DIRECTION_STUDS then
		forwardX = deltaX / length
		forwardZ = deltaZ / length
	end
	-- the right-hand direction on the ground, so a camp seen from above
	-- reads the way a player standing at the Refinery facing the gate sees it
	return {
		originX = refineryPosition.X,
		originZ = refineryPosition.Z,
		forwardX = forwardX,
		forwardZ = forwardZ,
		rightX = -forwardZ,
		rightZ = forwardX,
	}
end

-- a world location in map coordinates: u along the frame's right, v along
-- its forward (up the map), both in studs from the origin
function CampMapRules.toMap(frame: Frame, worldX: number, worldZ: number): (number, number)
	local deltaX = worldX - frame.originX
	local deltaZ = worldZ - frame.originZ
	return deltaX * frame.rightX + deltaZ * frame.rightZ, deltaX * frame.forwardX + deltaZ * frame.forwardZ
end

-- a world direction in map coordinates (no origin)
function CampMapRules.directionToMap(frame: Frame, directionX: number, directionZ: number): (number, number)
	return directionX * frame.rightX + directionZ * frame.rightZ, directionX * frame.forwardX + directionZ * frame.forwardZ
end

-- the four ground corners of a structure's bounding box, in map coordinates
function CampMapRules.boxCorners(frame: Frame, boundsCFrame: CFrame, boundsSize: Vector3): { MapPoint }
	local corners = {}
	local halfX = boundsSize.X / 2
	local halfZ = boundsSize.Z / 2
	for _, signs in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local corner = boundsCFrame * Vector3.new(signs[1] * halfX, 0, signs[2] * halfZ)
		local u, v = CampMapRules.toMap(frame, corner.X, corner.Z)
		table.insert(corners, { u = u, v = v })
	end
	return corners
end

-- fits every point into the unit square with a margin on each side,
-- keeping the camp's proportions: the longer side sets the scale
function CampMapRules.layoutFor(points: { MapPoint }, marginShare: number): Layout
	local minU = math.huge
	local maxU = -math.huge
	local minV = math.huge
	local maxV = -math.huge
	for _, point in points do
		minU = math.min(minU, point.u)
		maxU = math.max(maxU, point.u)
		minV = math.min(minV, point.v)
		maxV = math.max(maxV, point.v)
	end
	if #points == 0 then
		return { centerU = 0, centerV = 0, scale = 1 }
	end
	local extent = math.max(maxU - minU, maxV - minV)
	local usable = math.max(1 - 2 * marginShare, 0)
	local scale = if extent > 0 then usable / extent else 1
	return {
		centerU = (minU + maxU) / 2,
		centerV = (minV + maxV) / 2,
		scale = scale,
	}
end

-- map coordinates to the unit square: x right, y down, the map's forward
-- pointing up the screen
function CampMapRules.toScreen(layout: Layout, u: number, v: number): (number, number)
	return 0.5 + (u - layout.centerU) * layout.scale, 0.5 - (v - layout.centerV) * layout.scale
end

function CampMapRules.isOnScreen(x: number, y: number): boolean
	return x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- the clockwise screen rotation, in degrees, that turns a frame drawn
-- along the screen's x axis to lie along a structure's own right vector
function CampMapRules.rotationDegrees(frame: Frame, rightVector: Vector3): number
	local u, v = CampMapRules.directionToMap(frame, rightVector.X, rightVector.Z)
	-- screen y runs down while map v runs up, so v flips
	return math.deg(math.atan2(-v, u))
end

return CampMapRules
