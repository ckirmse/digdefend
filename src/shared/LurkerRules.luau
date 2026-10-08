--!strict

-- Pure rules for the pocket lurkers (GDD "Pocket lurkers", M62): which
-- pockets hold one, when an opened wall wakes it, where it clings, what it
-- can see, and how it finds a player. Everything works on the mine grid's
-- cells (depth into the mountain, height up, width across), never on
-- world positions, so the server's LurkerManager and the client's drawing
-- share one set of answers. A lurker crawls surfaces: an air cell is
-- walkable only when it touches rock (designer, 2026-10-08: never a float
-- through open air), it moves cell to cell six ways with no gravity, and
-- it prefers cells with a floor, climbing a wall only when the route
-- needs it (a climb step costs CLIMB_EXTRA_COST more). Nothing here
-- touches instances.
local MineGenerator = require(script.Parent.MineGenerator)

local LurkerRules = {}

export type Cell = {
	depth: number,
	height: number,
	width: number,
}

-- the six neighbours, in the order a search tries them
local NEIGHBOUR_STEPS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

-- where a lurker prefers to cling, as the direction from the cell into
-- the rock: the floor first (it reads as standing), then the walls, then
-- the ceiling; the normal returned points the other way, into the air
local CLING_ORDER = {
	{ 0, -1, 0 },
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
	{ 0, 1, 0 },
}

-- how far apart the samples along a sight line are, in cells; under one
-- so a line cannot skip a corner cell
local SIGHT_STEP_CELLS = 0.4

function LurkerRules.isInBounds(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	return depth >= 0 and depth < grid.depth and height >= 0 and height < grid.height and width >= 0 and width < grid.width
end

function LurkerRules.isAir(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	return LurkerRules.isInBounds(grid, depth, height, width) and MineGenerator.getCell(grid, depth, height, width) == MineGenerator.AIR
end

-- a rock, or the edge of the grid, which a lurker treats as rock too
function LurkerRules.isSolid(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	return not LurkerRules.isAir(grid, depth, height, width)
end

-- rock directly under the cell: where a lurker would rather be
function LurkerRules.hasFloor(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	return LurkerRules.isAir(grid, depth, height, width) and LurkerRules.isSolid(grid, depth, height - 1, width)
end

-- an air cell a lurker may stand in: one touching rock on any side
function LurkerRules.isSurface(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	if not LurkerRules.isAir(grid, depth, height, width) then
		return false
	end
	for _, step in NEIGHBOUR_STEPS do
		if LurkerRules.isSolid(grid, depth + step[1], height + step[2], width + step[3]) then
			return true
		end
	end
	return false
end

-- which pockets hold a lurker, by pocket index, drawn once per pocket
-- from the given stream so the same seed always picks the same pockets
-- how many lurkers a crew of this size meets: a base for one player and
-- a step per extra member, capped
function LurkerRules.lurkerCount(crewSize: number, baseCount: number, countPerExtraCrew: number, maxCount: number): number
	return math.clamp(baseCount + countPerExtraCrew * (math.max(crewSize, 1) - 1), 0, maxCount)
end

-- `count` pockets at random among those in a zone at or past minZoneIndex
-- (every pocket when nil), the same for the same seed; fewer when the mine
-- has fewer eligible pockets
function LurkerRules.pickLurkerPockets(pockets: { MineGenerator.Pocket }, count: number, random: Random, minZoneIndex: number?): { [number]: boolean }
	local eligible = {}
	for index, pocket in pockets do
		if minZoneIndex == nil or pocket.zoneIndex >= minZoneIndex then
			table.insert(eligible, index)
		end
	end
	random:Shuffle(eligible)
	local picked = {}
	for position = 1, math.min(count, #eligible) do
		picked[eligible[position]] = true
	end
	return picked
end

-- a broken block touches the pocket when it lies within one cell of the
-- carved room's box: the pocket's wall is that shell
function LurkerRules.isCellTouchingPocket(pocket: MineGenerator.Pocket, depth: number, height: number, width: number): boolean
	local bounds = MineGenerator.pocketBounds(pocket)
	return depth >= bounds.depthStart - 1
		and depth <= bounds.depthEnd + 1
		and height >= bounds.heightStart - 1
		and height <= bounds.heightEnd + 1
		and width >= bounds.widthStart - 1
		and width <= bounds.widthEnd + 1
end

function LurkerRules.isCellInPocket(pocket: MineGenerator.Pocket, depth: number, height: number, width: number): boolean
	return MineGenerator.isCellInPocket(pocket, depth, height, width)
end

-- a broken block opens the pocket when, now air, it shares a face with a
-- cell of the pocket's room: a block that only touched it at a corner
-- woke a lurker into a room with no way out (2026-10-08)
function LurkerRules.isCellOpeningPocket(grid: MineGenerator.MineGrid, pocket: MineGenerator.Pocket, depth: number, height: number, width: number): boolean
	if not LurkerRules.isCellTouchingPocket(pocket, depth, height, width) then
		return false
	end
	for _, step in NEIGHBOUR_STEPS do
		local nextDepth = depth + step[1]
		local nextHeight = height + step[2]
		local nextWidth = width + step[3]
		if LurkerRules.isCellInPocket(pocket, nextDepth, nextHeight, nextWidth) and LurkerRules.isAir(grid, nextDepth, nextHeight, nextWidth) then
			return true
		end
	end
	return false
end

-- the direction from an air cell into the rock it clings to, in grid
-- axes, or nil when the cell floats free of every face
function LurkerRules.clingDirection(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): (number?, number?, number?)
	for _, step in CLING_ORDER do
		if LurkerRules.isSolid(grid, depth + step[1], height + step[2], width + step[3]) then
			return step[1], step[2], step[3]
		end
	end
	return nil
end

-- a floor cell with a floor cell beside it: somewhere a lurker can both
-- stand and walk from. A sphere's lowest cell is a one-cell pit whose
-- only exit touches no rock, and a lurker resting there could never leave
-- it (2026-10-08)
function LurkerRules.isWalkableFloor(grid: MineGenerator.MineGrid, depth: number, height: number, width: number): boolean
	if not LurkerRules.hasFloor(grid, depth, height, width) then
		return false
	end
	for _, step in NEIGHBOUR_STEPS do
		if step[2] == 0 and LurkerRules.hasFloor(grid, depth + step[1], height, width + step[3]) then
			return true
		end
	end
	return false
end

-- the air cell a sleeping lurker starts on: the pocket's lowest floor cell
-- it can walk from (it stays on the ground unless a route climbs, designer
-- 2026-10-08), else any air cell on a face, else the centre. With awayFrom
-- (the block just broken) it is the such cell farthest from it, so a
-- woken spider starts across the room and the player has time to react
-- (designer, 2026-10-08)
function LurkerRules.findRestingCell(grid: MineGenerator.MineGrid, pocket: MineGenerator.Pocket, awayFrom: Cell?): Cell
	local best: Cell? = nil
	local bestDistance = -1
	local bestOnFace: Cell? = nil
	local bestOnFaceDistance = -1
	local bounds = MineGenerator.pocketBounds(pocket)
	for height = bounds.heightStart, bounds.heightEnd do
		for depth = bounds.depthStart, bounds.depthEnd do
			for width = bounds.widthStart, bounds.widthEnd do
				if not LurkerRules.isAir(grid, depth, height, width) then
					continue
				end
				local distance = if awayFrom then math.abs(depth - awayFrom.depth) + math.abs(height - awayFrom.height) + math.abs(width - awayFrom.width) else 0
				if distance > bestDistance and LurkerRules.isWalkableFloor(grid, depth, height, width) then
					best = { depth = depth, height = height, width = width }
					bestDistance = distance
				end
				if distance > bestOnFaceDistance and LurkerRules.clingDirection(grid, depth, height, width) ~= nil then
					bestOnFace = { depth = depth, height = height, width = width }
					bestOnFaceDistance = distance
				end
			end
		end
		if best and awayFrom == nil then
			break
		end
	end
	return best or bestOnFace or { depth = pocket.depth, height = pocket.height, width = pocket.width }
end

-- the nearest surface cell at or under a cell in open air (a player on a
-- jet pack, a dev spawn mid-room): the cell itself, else down through the
-- air up to maxDrop cells to the first that touches rock; nil in rock or
-- over a long fall
function LurkerRules.surfaceCellBelow(grid: MineGenerator.MineGrid, cell: Cell, maxDrop: number): Cell?
	for drop = 0, maxDrop do
		local height = cell.height - drop
		if not LurkerRules.isAir(grid, cell.depth, height, cell.width) then
			return nil
		end
		if LurkerRules.isSurface(grid, cell.depth, height, cell.width) then
			return { depth = cell.depth, height = height, width = cell.width }
		end
	end
	return nil
end

-- whether every cell along the straight line between two cell centres is
-- air (the end cells included), sampled finely enough to catch corners
function LurkerRules.hasLineOfSight(grid: MineGenerator.MineGrid, from: Cell, to: Cell): boolean
	local dd = to.depth - from.depth
	local dh = to.height - from.height
	local dw = to.width - from.width
	local length = math.sqrt(dd * dd + dh * dh + dw * dw)
	if length == 0 then
		return LurkerRules.isAir(grid, from.depth, from.height, from.width)
	end
	local steps = math.ceil(length / SIGHT_STEP_CELLS)
	for step = 0, steps do
		local share = step / steps
		local depth = math.floor(from.depth + dd * share + 0.5)
		local height = math.floor(from.height + dh * share + 0.5)
		local width = math.floor(from.width + dw * share + 0.5)
		if not LurkerRules.isAir(grid, depth, height, width) then
			return false
		end
	end
	return true
end

-- a step onto a cell with no floor (a wall or a ceiling) costs this much
-- more than a step along the ground, so a lurker climbs only where the
-- ground does not go
LurkerRules.CLIMB_EXTRA_COST = 2
-- a step onto a cell that touches no rock at all: a leap across a one-cell
-- gap, allowed only from a surface cell and never two in a row, so a
-- spider crosses the open cell where a wide tunnel meets a room's wall
-- (2026-10-08: one such cell sealed a spider in its room while the player
-- stood 30 studs away) but never floats through open air
LurkerRules.LEAP_EXTRA_COST = 4

-- a cheapest-first search over surface cells, six ways, at most maxCells
-- steps from the start: a ground step costs 1 and a climb step 1 plus
-- CLIMB_EXTRA_COST, so of two routes the one along the floor wins. The
-- cells to walk, nearest first, without the start; nil when the goal is
-- further than maxCells, in rock, or off every surface
function LurkerRules.findPath(grid: MineGenerator.MineGrid, from: Cell, to: Cell, maxCells: number): { Cell }?
	if from.depth == to.depth and from.height == to.height and from.width == to.width then
		return {}
	end
	if not LurkerRules.isAir(grid, to.depth, to.height, to.width) then
		return nil
	end
	-- a goal in open air (nothing to cling to) is reached by stopping on
	-- the surface cell beside it: a bite reaches across one cell
	local isGoalOpenAir = not LurkerRules.isSurface(grid, to.depth, to.height, to.width)
	local startIndex = MineGenerator.cellIndex(grid, from.depth, from.height, from.width)
	local goalIndex = MineGenerator.cellIndex(grid, to.depth, to.height, to.width)
	local cameFrom: { [number]: number } = { [startIndex] = startIndex }
	local stepsTo: { [number]: number } = { [startIndex] = 0 }
	-- costs are small whole numbers, so the queue is a bucket per cost
	local buckets: { [number]: { Cell } } = { [0] = { from } }
	local highestCost = 0
	local cost = 0
	while cost <= highestCost do
		local bucket = buckets[cost]
		if bucket then
			for _, cell in bucket do
				local cellIndex = MineGenerator.cellIndex(grid, cell.depth, cell.height, cell.width)
				local isCellSurface = LurkerRules.isSurface(grid, cell.depth, cell.height, cell.width)
				if isGoalOpenAir and isCellSurface and cellIndex ~= startIndex and math.abs(cell.depth - to.depth) + math.abs(cell.height - to.height) + math.abs(cell.width - to.width) == 1 then
					return LurkerRules.tracePath(grid, cameFrom, startIndex, cellIndex)
				end
				local steps = stepsTo[cellIndex]
				if steps >= maxCells then
					continue
				end
				for _, step in NEIGHBOUR_STEPS do
					local depth = cell.depth + step[1]
					local height = cell.height + step[2]
					local width = cell.width + step[3]
					local isNextSurface = LurkerRules.isSurface(grid, depth, height, width)
					if not isNextSurface and not (isCellSurface and LurkerRules.isAir(grid, depth, height, width)) then
						continue
					end
					local index = MineGenerator.cellIndex(grid, depth, height, width)
					if cameFrom[index] ~= nil then
						continue
					end
					cameFrom[index] = cellIndex
					stepsTo[index] = steps + 1
					if index == goalIndex then
						return LurkerRules.tracePath(grid, cameFrom, startIndex, goalIndex)
					end
					local stepCost = if not isNextSurface then 1 + LurkerRules.LEAP_EXTRA_COST elseif LurkerRules.hasFloor(grid, depth, height, width) then 1 else 1 + LurkerRules.CLIMB_EXTRA_COST
					local nextCost = cost + stepCost
					local nextBucket = buckets[nextCost]
					if not nextBucket then
						nextBucket = {}
						buckets[nextCost] = nextBucket
					end
					table.insert(nextBucket, { depth = depth, height = height, width = width })
					highestCost = math.max(highestCost, nextCost)
				end
			end
		end
		cost += 1
	end
	return nil
end

function LurkerRules.cellOfIndex(grid: MineGenerator.MineGrid, index: number): Cell
	local zeroBased = index - 1
	local width = zeroBased % grid.width
	local rest = (zeroBased - width) / grid.width
	local height = rest % grid.height
	local depth = (rest - height) / grid.height
	return { depth = depth, height = height, width = width }
end

function LurkerRules.tracePath(grid: MineGenerator.MineGrid, cameFrom: { [number]: number }, startIndex: number, goalIndex: number): { Cell }
	local reversed = {}
	local index = goalIndex
	while index ~= startIndex do
		table.insert(reversed, LurkerRules.cellOfIndex(grid, index))
		index = cameFrom[index]
	end
	local path = table.create(#reversed)
	for position = #reversed, 1, -1 do
		table.insert(path, reversed[position])
	end
	return path
end

-- a random surface neighbour to drift to, one with a floor when any has,
-- or nil when the cell is boxed in
function LurkerRules.randomAirNeighbour(grid: MineGenerator.MineGrid, cell: Cell, random: Random): Cell?
	local grounded = {}
	local climbing = {}
	for _, step in NEIGHBOUR_STEPS do
		local depth = cell.depth + step[1]
		local height = cell.height + step[2]
		local width = cell.width + step[3]
		if not LurkerRules.isSurface(grid, depth, height, width) then
			continue
		end
		local option = { depth = depth, height = height, width = width }
		if LurkerRules.hasFloor(grid, depth, height, width) then
			table.insert(grounded, option)
		else
			table.insert(climbing, option)
		end
	end
	local options = if #grounded > 0 then grounded else climbing
	if #options == 0 then
		return nil
	end
	return options[random:NextInteger(1, #options)]
end

return LurkerRules
