--!strict

-- The monsters' shared way to the Refinery (GDD "Setting Up Waves":
-- Pathfinding), M29. Monsters never find their way one by one: the map's
-- Wave Areas and Camp Area are laid over one square grid, and a single
-- Dijkstra pass outward from the goal cells gives every cell the next cell
-- toward the goal, so a monster's step is one lookup however many there
-- are. Cells are `inside` an authored area or not; an inside cell is
-- `walkable` unless something that never moves stands on it (a store, the
-- Refinery); a walkable cell can also hold a barrier (a wall, the gate, a
-- Tower, a Trap), which a ground monster may enter only by breaking it, so
-- entering costs `barrierCost` more and monsters take any open way round
-- first. Air monsters use a field over every inside cell with no barriers.
-- Pure data, unit tested; MonsterPathManager builds the grid from the map.
local FlowField = {}

export type Grid = {
	-- world X and Z of the grid's low corner (column 1, row 1's outer corner)
	originX: number,
	originZ: number,
	columns: number,
	rows: number,
	cellSizeStuds: number,
	-- by cell index: inside a Wave Area or the Camp Area
	inside: { boolean },
	-- by cell index: inside and not permanently blocked
	walkable: { boolean },
	-- by cell index: the ground's height at the cell's centre
	heights: { number },
	-- cell index -> the barrier id standing there
	barriers: { [number]: string },
}

export type Field = {
	-- by cell index: the cost of the best way to a goal; math.huge when none
	costs: { number },
	-- by cell index: the next cell toward the goal; 0 at a goal or when unreachable
	nextIndex: { number },
}

export type ComputeOptions = {
	-- air: every inside cell is open and barriers do not count
	isAir: boolean,
	-- what entering a barrier cell adds, in cell steps
	barrierCost: number,
}

local DIAGONAL_STEP = math.sqrt(2)
local NEIGHBOR_OFFSETS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, DIAGONAL_STEP },
	{ 1, -1, DIAGONAL_STEP },
	{ -1, 1, DIAGONAL_STEP },
	{ -1, -1, DIAGONAL_STEP },
}

function FlowField.newGrid(originX: number, originZ: number, columns: number, rows: number, cellSizeStuds: number): Grid
	local count = columns * rows
	local inside = table.create(count, false)
	local walkable = table.create(count, false)
	local heights = table.create(count, 0)
	return {
		originX = originX,
		originZ = originZ,
		columns = columns,
		rows = rows,
		cellSizeStuds = cellSizeStuds,
		inside = inside,
		walkable = walkable,
		heights = heights,
		barriers = {},
	}
end

function FlowField.indexOf(grid: Grid, column: number, row: number): number
	return (row - 1) * grid.columns + column
end

function FlowField.cellOf(grid: Grid, index: number): (number, number)
	local zeroBased = index - 1
	return zeroBased % grid.columns + 1, zeroBased // grid.columns + 1
end

-- the cell under a world X and Z, or nil off the grid
function FlowField.indexAt(grid: Grid, x: number, z: number): number?
	local column = math.floor((x - grid.originX) / grid.cellSizeStuds) + 1
	local row = math.floor((z - grid.originZ) / grid.cellSizeStuds) + 1
	if column < 1 or column > grid.columns or row < 1 or row > grid.rows then
		return nil
	end
	return FlowField.indexOf(grid, column, row)
end

function FlowField.centerOf(grid: Grid, index: number): (number, number)
	local column, row = FlowField.cellOf(grid, index)
	return grid.originX + (column - 0.5) * grid.cellSizeStuds, grid.originZ + (row - 0.5) * grid.cellSizeStuds
end

function FlowField.isEnterable(grid: Grid, index: number, isAir: boolean): boolean
	return if isAir then grid.inside[index] else grid.walkable[index]
end

-- a binary min-heap of cell indices by cost, in two parallel arrays
local function heapPush(heapCosts: { number }, heapIndices: { number }, cost: number, index: number)
	local position = #heapCosts + 1
	heapCosts[position] = cost
	heapIndices[position] = index
	while position > 1 do
		local parent = position // 2
		if heapCosts[parent] <= cost then
			break
		end
		heapCosts[position], heapCosts[parent] = heapCosts[parent], heapCosts[position]
		heapIndices[position], heapIndices[parent] = heapIndices[parent], heapIndices[position]
		position = parent
	end
end

local function heapPop(heapCosts: { number }, heapIndices: { number }): (number, number)
	local topCost = heapCosts[1]
	local topIndex = heapIndices[1]
	local last = #heapCosts
	heapCosts[1] = heapCosts[last]
	heapIndices[1] = heapIndices[last]
	heapCosts[last] = nil
	heapIndices[last] = nil
	local count = last - 1
	local position = 1
	while true do
		local left = position * 2
		local right = left + 1
		local smallest = position
		if left <= count and heapCosts[left] < heapCosts[smallest] then
			smallest = left
		end
		if right <= count and heapCosts[right] < heapCosts[smallest] then
			smallest = right
		end
		if smallest == position then
			break
		end
		heapCosts[position], heapCosts[smallest] = heapCosts[smallest], heapCosts[position]
		heapIndices[position], heapIndices[smallest] = heapIndices[smallest], heapIndices[position]
		position = smallest
	end
	return topCost, topIndex
end

-- Dijkstra outward from the goals. A monster at a cell steps to its
-- nextIndex; the cost counts cell steps (a diagonal is root two) plus
-- barrierCost for every barrier cell entered on the way. A diagonal step
-- never cuts the corner of a cell it could not enter
function FlowField.compute(grid: Grid, goals: { number }, options: ComputeOptions): Field
	local count = grid.columns * grid.rows
	local costs = table.create(count, math.huge)
	local nextIndex = table.create(count, 0)
	local heapCosts: { number } = {}
	local heapIndices: { number } = {}
	local isAir = options.isAir
	for _, goal in goals do
		if goal >= 1 and goal <= count and costs[goal] > 0 then
			costs[goal] = 0
			heapPush(heapCosts, heapIndices, 0, goal)
		end
	end
	local columns = grid.columns
	local rows = grid.rows
	while #heapCosts > 0 do
		local cost, index = heapPop(heapCosts, heapIndices)
		if cost > costs[index] then
			continue
		end
		-- a monster reaching this cell from a neighbour pays to enter it
		local enterCost = if not isAir and grid.barriers[index] then options.barrierCost else 0
		local column, row = FlowField.cellOf(grid, index)
		for _, offset in NEIGHBOR_OFFSETS do
			local neighborColumn = column + offset[1]
			local neighborRow = row + offset[2]
			if neighborColumn < 1 or neighborColumn > columns or neighborRow < 1 or neighborRow > rows then
				continue
			end
			local neighbor = (neighborRow - 1) * columns + neighborColumn
			if not FlowField.isEnterable(grid, neighbor, isAir) then
				continue
			end
			local isDiagonal = offset[1] ~= 0 and offset[2] ~= 0
			if isDiagonal then
				-- a ground monster may not slip between two barrier cells
				-- either, or a wall one cell thick would leak on the diagonal
				local sideA = (row - 1) * columns + neighborColumn
				local sideB = (neighborRow - 1) * columns + column
				if not FlowField.isEnterable(grid, sideA, isAir) or not FlowField.isEnterable(grid, sideB, isAir) then
					continue
				end
				if not isAir and (grid.barriers[sideA] or grid.barriers[sideB]) then
					continue
				end
			end
			local candidate = cost + offset[3] + enterCost
			if candidate < costs[neighbor] then
				costs[neighbor] = candidate
				nextIndex[neighbor] = index
				heapPush(heapCosts, heapIndices, candidate, neighbor)
			end
		end
	end
	return {
		costs = costs,
		nextIndex = nextIndex,
	}
end

-- whether a straight walk between two flat points stays on cells the
-- monster may enter, never crossing a barrier (for the ground), sampled
-- every half cell
function FlowField.isLineClear(grid: Grid, fromX: number, fromZ: number, toX: number, toZ: number, isAir: boolean): boolean
	local deltaX = toX - fromX
	local deltaZ = toZ - fromZ
	local steps = math.max(1, math.ceil(math.sqrt(deltaX * deltaX + deltaZ * deltaZ) / (grid.cellSizeStuds / 2)))
	for step = 1, steps do
		local share = step / steps
		local index = FlowField.indexAt(grid, fromX + deltaX * share, fromZ + deltaZ * share)
		if not index or not FlowField.isEnterable(grid, index, isAir) then
			return false
		end
		if not isAir and grid.barriers[index] then
			return false
		end
	end
	return true
end

-- the nearest cell a monster may stand on, searching outward ring by ring
-- up to maxRings; a monster pushed off the grid walks back to it
function FlowField.nearestEnterable(grid: Grid, x: number, z: number, isAir: boolean, maxRings: number): number?
	local column = math.clamp(math.floor((x - grid.originX) / grid.cellSizeStuds) + 1, 1, grid.columns)
	local row = math.clamp(math.floor((z - grid.originZ) / grid.cellSizeStuds) + 1, 1, grid.rows)
	for ring = 0, maxRings do
		local best: number? = nil
		local bestDistance = math.huge
		for rowOffset = -ring, ring do
			for columnOffset = -ring, ring do
				if math.max(math.abs(rowOffset), math.abs(columnOffset)) ~= ring then
					continue
				end
				local candidateColumn = column + columnOffset
				local candidateRow = row + rowOffset
				if candidateColumn < 1 or candidateColumn > grid.columns or candidateRow < 1 or candidateRow > grid.rows then
					continue
				end
				local index = FlowField.indexOf(grid, candidateColumn, candidateRow)
				if not FlowField.isEnterable(grid, index, isAir) then
					continue
				end
				local centerX, centerZ = FlowField.centerOf(grid, index)
				local distance = (centerX - x) ^ 2 + (centerZ - z) ^ 2
				if distance < bestDistance then
					best = index
					bestDistance = distance
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

return FlowField
