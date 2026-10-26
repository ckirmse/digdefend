--!strict

-- Pure rules for the Drag (GDD "Monster Types": Drag, M68): the chase. A
-- Drag floats through the mine's open air, cell to cell, six ways, with no
-- gravity and no need of a surface: any air cell is a step. It hunts one
-- player, its waker, and when it has no path to them it follows the trail
-- of cells they passed through, newest first, so a corner never loses it
-- and only distance does. Everything here works on grid cells (depth into
-- the mountain, height up, width across) so the server's DragManager and
-- a test share one set of answers. Nothing here touches instances.
local LurkerRules = require(script.Parent.LurkerRules)
local MineGenerator = require(script.Parent.MineGenerator)

local DragRules = {}

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

function DragRules.isSameCell(a: Cell, b: Cell): boolean
	return a.depth == b.depth and a.height == b.height and a.width == b.width
end

-- a breadth-first search over air cells, at most maxCells cells visited
-- from the start, every step costing the same: the cells to float through,
-- nearest first, without the start; nil when the goal is further than the
-- cap, in rock, or sealed off
function DragRules.findAirPath(grid: MineGenerator.MineGrid, from: Cell, to: Cell, maxCells: number): { Cell }?
	if not LurkerRules.isAir(grid, from.depth, from.height, from.width) or not LurkerRules.isAir(grid, to.depth, to.height, to.width) then
		return nil
	end
	if DragRules.isSameCell(from, to) then
		return {}
	end
	local startIndex = MineGenerator.cellIndex(grid, from.depth, from.height, from.width)
	local goalIndex = MineGenerator.cellIndex(grid, to.depth, to.height, to.width)
	local cameFrom: { [number]: number } = { [startIndex] = startIndex }
	local queue = { startIndex }
	local head = 1
	local visited = 0
	while head <= #queue do
		local index = queue[head]
		head += 1
		visited += 1
		if visited > maxCells then
			return nil
		end
		local cell = LurkerRules.cellOfIndex(grid, index)
		for _, step in NEIGHBOUR_STEPS do
			local depth, height, width = cell.depth + step[1], cell.height + step[2], cell.width + step[3]
			if not LurkerRules.isAir(grid, depth, height, width) then
				continue
			end
			local nextIndex = MineGenerator.cellIndex(grid, depth, height, width)
			if cameFrom[nextIndex] then
				continue
			end
			cameFrom[nextIndex] = index
			if nextIndex == goalIndex then
				return LurkerRules.tracePath(grid, cameFrom, startIndex, goalIndex)
			end
			table.insert(queue, nextIndex)
		end
	end
	return nil
end

-- the victim's trail: their recent cells, newest last, each kept once in a
-- row and the oldest dropped past maxCells
function DragRules.pushTrail(trail: { Cell }, cell: Cell, maxCells: number)
	local last = trail[#trail]
	if last and DragRules.isSameCell(last, cell) then
		return
	end
	table.insert(trail, cell)
	while #trail > maxCells do
		table.remove(trail, 1)
	end
end

-- where to float next: a path to the victim's own cell when one is within
-- the cap, else to the newest trail cell one reaches, else nothing (hold
-- where it is). The trail is read newest first so a long way round is
-- never preferred to the victim's last known cell
function DragRules.pickChasePath(grid: MineGenerator.MineGrid, from: Cell, victim: Cell?, trail: { Cell }, maxCells: number): { Cell }?
	if victim then
		local direct = DragRules.findAirPath(grid, from, victim, maxCells)
		if direct then
			return direct
		end
	end
	for index = #trail, 1, -1 do
		local path = DragRules.findAirPath(grid, from, trail[index], maxCells)
		if path and #path > 0 then
			return path
		end
	end
	return nil
end

-- the sleepers' pockets: countPerZone pockets in every zone from
-- minZoneIndex down, among those no lurker holds, drawn from the seed
-- zone by zone (designer, 2026-10-26: one in each deep zone rather than a
-- handful wherever the draw fell), as a set of indices into pockets
function DragRules.pickDragPockets(pockets: { MineGenerator.Pocket }, countPerZone: number, random: Random, minZoneIndex: number, heldIndices: { [number]: boolean }): { [number]: boolean }
	local eligibleByZone: { [number]: { number } } = {}
	local zones: { number } = {}
	for index, pocket in pockets do
		if pocket.zoneIndex >= minZoneIndex and not heldIndices[index] then
			local list = eligibleByZone[pocket.zoneIndex]
			if not list then
				list = {}
				eligibleByZone[pocket.zoneIndex] = list
				table.insert(zones, pocket.zoneIndex)
			end
			table.insert(list, index)
		end
	end
	-- zones in order, so the seed draws the same rooms whatever order the
	-- pockets were listed in
	table.sort(zones)
	local picked: { [number]: boolean } = {}
	for _, zoneIndex in zones do
		local eligible = eligibleByZone[zoneIndex]
		random:Shuffle(eligible)
		for position = 1, math.min(countPerZone, #eligible) do
			picked[eligible[position]] = true
		end
	end
	return picked
end

-- how many air cells up from the floor a floater centres itself in: a
-- passage two tall carries it on the seam, and a taller space keeps it
-- at that same height off the floor rather than its mid-height, so it
-- stays near the ground (designer, 2026-10-26)
DragRules.HOVER_CELLS = 2

-- the height a floater hangs at over a cell: the middle of the bottom
-- HOVER_CELLS air cells of the open column the cell sits in (the air
-- stacked below and above it, joined), as a height index that may fall
-- between rows; a one-cell passage is its own centre (designer,
-- 2026-10-26: the cell centres put it in the floor or the ceiling of every
-- passage, and the column's middle floated it to the roof of a room)
function DragRules.columnCentreHeight(grid: MineGenerator.MineGrid, cell: Cell): number
	local lowest = cell.height
	while LurkerRules.isAir(grid, cell.depth, lowest - 1, cell.width) do
		lowest -= 1
	end
	local highest = cell.height
	while LurkerRules.isAir(grid, cell.depth, highest + 1, cell.width) do
		highest += 1
	end
	local span = math.min(highest - lowest + 1, DragRules.HOVER_CELLS)
	return lowest + (span - 1) / 2
end

-- the cell a sleeper floats up in: the room's middle
function DragRules.pocketCentreCell(pocket: MineGenerator.Pocket): Cell
	return { depth = pocket.depth, height = pocket.height, width = pocket.width }
end

return DragRules
