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

-- the sleepers' pockets: count pockets from the eligible zones that no
-- lurker holds, drawn from the seed, as a set of indices into pockets
function DragRules.pickDragPockets(pockets: { MineGenerator.Pocket }, count: number, random: Random, minZoneIndex: number, heldIndices: { [number]: boolean }): { [number]: boolean }
	local eligible: { number } = {}
	for index, pocket in pockets do
		if pocket.zoneIndex >= minZoneIndex and not heldIndices[index] then
			table.insert(eligible, index)
		end
	end
	random:Shuffle(eligible)
	local picked: { [number]: boolean } = {}
	for position = 1, math.min(count, #eligible) do
		picked[eligible[position]] = true
	end
	return picked
end

-- the cell a sleeper floats up in: the room's middle
function DragRules.pocketCentreCell(pocket: MineGenerator.Pocket): Cell
	return { depth = pocket.depth, height = pocket.height, width = pocket.width }
end

return DragRules
