--!strict

-- Read-only questions about a mine grid that both server and client ask.
-- Pure; the grid type is MineGenerator.MineGrid.
local Enums = require(script.Parent.Enums)
local MineGenerator = require(script.Parent.MineGenerator)

local MineGridQuery = {}

local NEIGHBOUR_OFFSETS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

function MineGridQuery.isInBounds(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	return depth >= 0
		and depth < grid.depth
		and height >= 0
		and height < grid.height
		and width >= 0
		and width < grid.width
end

-- Out of bounds counts as air only in front of the grid, so the mountain's
-- face (the wall with the mouth in it) renders; its top, sides, floor, and
-- far end count as solid, because nobody can see them from inside and a
-- map's placeholder mountain geometry covers them from outside.
function MineGridQuery.getCellOrAir(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): number
	if depth < 0 then
		return MineGenerator.AIR
	end
	if not MineGridQuery.isInBounds(grid, depth, height, width) then
		return Enums.RockName.BEDROCK
	end
	return MineGenerator.getCell(grid, depth, height, width)
end

-- a solid cell with at least one air face is the only kind worth rendering;
-- everything buried behind it is invisible until digging exposes it
function MineGridQuery.isExposed(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	if MineGridQuery.getCellOrAir(grid, depth, height, width) == MineGenerator.AIR then
		return false
	end
	for _, offset in NEIGHBOUR_OFFSETS do
		if MineGridQuery.getCellOrAir(grid, depth + offset[1], height + offset[2], width + offset[3]) == MineGenerator.AIR then
			return true
		end
	end
	return false
end

function MineGridQuery.countExposed(grid: MineGenerator.MineGrid): number
	local count = 0
	for depth = 0, grid.depth - 1 do
		for height = 0, grid.height - 1 do
			for width = 0, grid.width - 1 do
				if MineGridQuery.isExposed(grid, depth, height, width) then
					count += 1
				end
			end
		end
	end
	return count
end

return MineGridQuery
