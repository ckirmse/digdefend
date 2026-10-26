--!strict

-- Pure rules for the Seam (GDD "Monster Types": Seam, M68): the face on a
-- block you must not hit. A Seam is a small set of rock cells, never a
-- body: it has no position of its own, so it is never a Damageable and no
-- weapon can touch it. It sleeps inside the rock until a neighbouring cell
-- is cleared and one of its faces meets the air; awake, it drifts a cell
-- at a time over the exposed rock around it and spreads onto neighbouring
-- stone, never ore. Everything here works on grid cells (depth into the
-- mountain, height up, width across) so the server's SeamManager and the
-- client's drawing share one set of answers; what counts as "stone" is a
-- predicate the caller passes, because the rock table lives in GameData
-- and this module must stay pure.
local LurkerRules = require(script.Parent.LurkerRules)
local MineGenerator = require(script.Parent.MineGenerator)

local SeamRules = {}

-- the same shape as LurkerRules.Cell, spelled out so a module that requires
-- only this one gets a whole type
export type Cell = {
	depth: number,
	height: number,
	width: number,
}

-- the six face neighbours
local NEIGHBOUR_STEPS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

-- how many random cells a placement draw tries before giving up on a face
local PLACEMENT_TRIES_PER_SEAM = 400

function SeamRules.cellKey(depth: number, height: number, width: number): string
	return `{depth}:{height}:{width}`
end

function SeamRules.isFaceNeighbour(a: Cell, b: Cell): boolean
	return math.abs(a.depth - b.depth) + math.abs(a.height - b.height) + math.abs(a.width - b.width) == 1
end

-- a rock cell (any rock, bedrock included) that has at least one face on air
function SeamRules.isExposedRock(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	if not LurkerRules.isInBounds(grid, depth, height, width) or LurkerRules.isAir(grid, depth, height, width) then
		return false
	end
	for _, step in NEIGHBOUR_STEPS do
		if LurkerRules.isAir(grid, depth + step[1], height + step[2], width + step[3]) then
			return true
		end
	end
	return false
end

-- a cell a Seam may lie on or move to: in the grid, rock the predicate
-- accepts (stone, never ore or bedrock), and not already held
function SeamRules.isHoldable(grid: MineGenerator.MineGrid, depth: number, height: number, width: number, isStone: (rock: number) -> boolean, occupied: { [string]: boolean }): boolean
	if not LurkerRules.isInBounds(grid, depth, height, width) then
		return false
	end
	local rock = MineGenerator.getCell(grid, depth, height, width)
	if rock == MineGenerator.AIR or not isStone(rock) then
		return false
	end
	return not occupied[SeamRules.cellKey(depth, height, width)]
end

-- the exposed stone cells a face could step or spread onto from a cell:
-- its rock neighbours that touch air and are free
function SeamRules.exposedHoldableNeighbours(grid: MineGenerator.MineGrid, cell: Cell, isStone: (rock: number) -> boolean, occupied: { [string]: boolean }): { Cell }
	local result = {}
	for _, step in NEIGHBOUR_STEPS do
		local depth, height, width = cell.depth + step[1], cell.height + step[2], cell.width + step[3]
		if SeamRules.isHoldable(grid, depth, height, width, isStone, occupied) and SeamRules.isExposedRock(grid, depth, height, width) then
			table.insert(result, { depth = depth, height = height, width = width })
		end
	end
	return result
end

-- draws count sleeping Seams from the seed: one buried stone cell each, at
-- or past minDepth, never touching a pocket (so a room's wall stays the
-- spiders' discovery), never two on neighbouring cells. Deterministic for
-- a seed, so every server of a mine seats the same faces. Fewer than count
-- when the tries run out
function SeamRules.pickSeamCells(grid: MineGenerator.MineGrid, count: number, random: Random, minDepth: number, isStone: (rock: number) -> boolean, pockets: { MineGenerator.Pocket }): { Cell }
	local picked: { Cell } = {}
	local occupied: { [string]: boolean } = {}
	if minDepth >= grid.depth or count <= 0 then
		return picked
	end
	for _ = 1, count do
		for _ = 1, PLACEMENT_TRIES_PER_SEAM do
			local depth = random:NextInteger(minDepth, grid.depth - 1)
			local height = random:NextInteger(0, grid.height - 1)
			local width = random:NextInteger(0, grid.width - 1)
			if not SeamRules.isHoldable(grid, depth, height, width, isStone, occupied) then
				continue
			end
			local isBesidePocket = false
			for _, pocket in pockets do
				if LurkerRules.isCellTouchingPocket(pocket, depth, height, width) then
					isBesidePocket = true
					break
				end
			end
			if isBesidePocket then
				continue
			end
			local isBesideSeam = false
			for _, step in NEIGHBOUR_STEPS do
				if occupied[SeamRules.cellKey(depth + step[1], height + step[2], width + step[3])] then
					isBesideSeam = true
					break
				end
			end
			if isBesideSeam then
				continue
			end
			local cell = { depth = depth, height = height, width = width }
			table.insert(picked, cell)
			occupied[SeamRules.cellKey(depth, height, width)] = true
			break
		end
	end
	return picked
end

-- a cleared cell wakes a sleeping Seam when it shares a face with one of
-- the Seam's cells: the face now meets the air
function SeamRules.isWokenBy(cells: { Cell }, clearedDepth: number, clearedHeight: number, clearedWidth: number): boolean
	local cleared = { depth = clearedDepth, height = clearedHeight, width = clearedWidth }
	for _, cell in cells do
		if SeamRules.isFaceNeighbour(cell, cleared) then
			return true
		end
	end
	return false
end

-- the index of the Seam cell a cleared cell was, or nil: dynamite (the
-- one thing that clears a Seam's block) takes that cell off the Seam
function SeamRules.indexOfCell(cells: { Cell }, depth: number, height: number, width: number): number?
	for index, cell in cells do
		if cell.depth == depth and cell.height == height and cell.width == width then
			return index
		end
	end
	return nil
end

-- the cells of a Seam as a flat array for the network: depth, height,
-- width, repeated
function SeamRules.encodeCells(cells: { Cell }): { number }
	local flat = table.create(#cells * 3)
	for _, cell in cells do
		table.insert(flat, cell.depth)
		table.insert(flat, cell.height)
		table.insert(flat, cell.width)
	end
	return flat
end

function SeamRules.decodeCells(flat: { number }): { Cell }
	local cells = {}
	for index = 1, #flat - 2, 3 do
		table.insert(cells, { depth = flat[index], height = flat[index + 1], width = flat[index + 2] })
	end
	return cells
end

return SeamRules
