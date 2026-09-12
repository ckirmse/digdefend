--!strict

-- The one module that maps the mine grid's local space (depth into the
-- mountain, height up, width across) into the world (GDD "Coordinate
-- model"). The origin is the centre of the entrance mouth at floor level and
-- the facing is the direction a player walks to enter, snapped to an axis so
-- blocks stay axis-aligned. Pure; the same math runs on server and client.
local Enums = require(script.Parent.Enums)

local MineSpace = {}

export type MineSpace = {
	origin: Vector3,
	forward: Vector3,
	widthAxis: Vector3,
	blockSize: number,
	-- grid width index that sits on the centreline (MineGrid.centrelineWidth)
	centrelineWidth: number,
	-- grid height index of the first chamber-floor row; the bedrock below it
	-- sits under the origin (MineGrid.floorHeight)
	floorHeight: number,
}

local FORWARD_BY_FACING: { [number]: Vector3 } = {
	[Enums.MineFacing.POSITIVE_X] = Vector3.new(1, 0, 0),
	[Enums.MineFacing.NEGATIVE_X] = Vector3.new(-1, 0, 0),
	[Enums.MineFacing.POSITIVE_Z] = Vector3.new(0, 0, 1),
	[Enums.MineFacing.NEGATIVE_Z] = Vector3.new(0, 0, -1),
}

function MineSpace.forwardForFacing(facing: number): Vector3
	local forward = FORWARD_BY_FACING[facing]
	if not forward then
		warn("MineSpace: unknown facing " .. tostring(facing) .. "; using +X")
		return FORWARD_BY_FACING[Enums.MineFacing.POSITIVE_X]
	end
	return forward
end

-- the dominant horizontal axis of a look vector, so a designer can rotate
-- the entrance part freely and still get an axis-aligned mine
function MineSpace.facingFromLookVector(lookVector: Vector3): number
	if math.abs(lookVector.X) >= math.abs(lookVector.Z) then
		return if lookVector.X >= 0 then Enums.MineFacing.POSITIVE_X else Enums.MineFacing.NEGATIVE_X
	end
	return if lookVector.Z >= 0 then Enums.MineFacing.POSITIVE_Z else Enums.MineFacing.NEGATIVE_Z
end

-- centre of the block at grid cell (depth, height, width)
function MineSpace.cellToWorld(space: MineSpace, depth: number, height: number, width: number): Vector3
	local size = space.blockSize
	return space.origin
		+ space.forward * ((depth + 0.5) * size)
		+ Vector3.new(0, (height - space.floorHeight + 0.5) * size, 0)
		+ space.widthAxis * ((width - space.centrelineWidth) * size)
end

-- the grid cell containing a world position; may be outside the grid
function MineSpace.worldToCell(space: MineSpace, position: Vector3): (number, number, number)
	local relative = position - space.origin
	local size = space.blockSize
	local depth = math.floor(relative:Dot(space.forward) / size)
	local height = math.floor(relative.Y / size) + space.floorHeight
	local width = math.floor(relative:Dot(space.widthAxis) / size + 0.5) + space.centrelineWidth
	return depth, height, width
end

function MineSpace.new(origin: Vector3, facing: number, centrelineWidth: number, floorHeight: number, blockSize: number): MineSpace
	local forward = MineSpace.forwardForFacing(facing)
	return {
		origin = origin,
		forward = forward,
		-- positive width is to the right of a player walking in
		widthAxis = forward:Cross(Vector3.yAxis),
		blockSize = blockSize,
		centrelineWidth = centrelineWidth,
		floorHeight = floorHeight,
	}
end

return MineSpace
