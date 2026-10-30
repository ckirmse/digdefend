--!strict

-- Pure rules for the Blockface (GDD "Monster Types": Blockface, M68): the face on a
-- block you must not hit. A Blockface is a small set of rock cells, never a
-- body: it has no position of its own, so it is never a Damageable and no
-- weapon can touch it. It sleeps inside the rock until a neighbouring cell
-- is cleared and one of its faces meets the air; awake, it drifts a cell
-- at a time over the exposed rock around it and spreads onto neighbouring
-- stone, never ore. Everything here works on grid cells (depth into the
-- mountain, height up, width across) so the server's BlockfaceManager and the
-- client's drawing share one set of answers; what counts as "stone" is a
-- predicate the caller passes, because the rock table lives in GameData
-- and this module must stay pure.
local LurkerRules = require(script.Parent.LurkerRules)
local MineGenerator = require(script.Parent.MineGenerator)

local BlockfaceRules = {}

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
local PLACEMENT_TRIES_PER_BLOCKFACE = 400

function BlockfaceRules.cellKey(depth: number, height: number, width: number): string
	return `{depth}:{height}:{width}`
end

function BlockfaceRules.isFaceNeighbour(a: Cell, b: Cell): boolean
	return math.abs(a.depth - b.depth) + math.abs(a.height - b.height) + math.abs(a.width - b.width) == 1
end

-- a rock cell (any rock, bedrock included) that has at least one face on air
function BlockfaceRules.isExposedRock(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
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

-- a cell a Blockface may lie on or move to: in the grid, rock the predicate
-- accepts (stone, never ore or bedrock), and not already held
function BlockfaceRules.isHoldable(grid: MineGenerator.MineGrid, depth: number, height: number, width: number, isStone: (rock: number) -> boolean, occupied: { [string]: boolean }): boolean
	if not LurkerRules.isInBounds(grid, depth, height, width) then
		return false
	end
	local rock = MineGenerator.getCell(grid, depth, height, width)
	if rock == MineGenerator.AIR or not isStone(rock) then
		return false
	end
	return not occupied[BlockfaceRules.cellKey(depth, height, width)]
end

-- draws count sleeping Blockfaces from the seed: one buried stone cell each, at
-- or past minDepth, never touching a pocket (so a room's wall stays the
-- spiders' discovery), never two on neighbouring cells. Deterministic for
-- a seed, so every server of a mine seats the same faces. Fewer than count
-- when the tries run out
function BlockfaceRules.pickBlockfaceCells(grid: MineGenerator.MineGrid, count: number, random: Random, minDepth: number, isStone: (rock: number) -> boolean, pockets: { MineGenerator.Pocket }): { Cell }
	local picked: { Cell } = {}
	local occupied: { [string]: boolean } = {}
	if minDepth >= grid.depth or count <= 0 then
		return picked
	end
	for _ = 1, count do
		for _ = 1, PLACEMENT_TRIES_PER_BLOCKFACE do
			local depth = random:NextInteger(minDepth, grid.depth - 1)
			local height = random:NextInteger(0, grid.height - 1)
			local width = random:NextInteger(0, grid.width - 1)
			if not BlockfaceRules.isHoldable(grid, depth, height, width, isStone, occupied) then
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
			local isBesideBlockface = false
			for _, step in NEIGHBOUR_STEPS do
				if occupied[BlockfaceRules.cellKey(depth + step[1], height + step[2], width + step[3])] then
					isBesideBlockface = true
					break
				end
			end
			if isBesideBlockface then
				continue
			end
			local cell = { depth = depth, height = height, width = width }
			table.insert(picked, cell)
			occupied[BlockfaceRules.cellKey(depth, height, width)] = true
			break
		end
	end
	return picked
end

-- a cleared cell wakes a sleeping Blockface when it shares a face with one of
-- the Blockface's cells: the face now meets the air
function BlockfaceRules.isWokenBy(cells: { Cell }, clearedDepth: number, clearedHeight: number, clearedWidth: number): boolean
	local cleared = { depth = clearedDepth, height = clearedHeight, width = clearedWidth }
	for _, cell in cells do
		if BlockfaceRules.isFaceNeighbour(cell, cleared) then
			return true
		end
	end
	return false
end

-- the index of the Blockface cell a cleared cell was, or nil: dynamite (the
-- one thing that clears a Blockface's block) takes that cell off the Blockface
function BlockfaceRules.indexOfCell(cells: { Cell }, depth: number, height: number, width: number): number?
	for index, cell in cells do
		if cell.depth == depth and cell.height == height and cell.width == width then
			return index
		end
	end
	return nil
end

-- the cells of a Blockface as a flat array for the network: depth, height,
-- width, repeated
function BlockfaceRules.encodeCells(cells: { Cell }): { number }
	local flat = table.create(#cells * 3)
	for _, cell in cells do
		table.insert(flat, cell.depth)
		table.insert(flat, cell.height)
		table.insert(flat, cell.width)
	end
	return flat
end

function BlockfaceRules.decodeCells(flat: { number }): { Cell }
	local cells = {}
	for index = 1, #flat - 2, 3 do
		table.insert(cells, { depth = flat[index], height = flat[index + 1], width = flat[index + 2] })
	end
	return cells
end

return BlockfaceRules
