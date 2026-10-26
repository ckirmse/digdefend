-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MineGenerator = require(game:GetService("ReplicatedStorage").Shared.MineGenerator)
local DragRules = require(game:GetService("ReplicatedStorage").Shared.DragRules)

local ROCK = 1

local function makeGrid(depth: number, height: number, width: number)
	return {
		depth = depth,
		height = height,
		width = width,
		centrelineWidth = math.floor(width / 2),
		floorHeight = 1,
		cells = table.create(depth * height * width, ROCK),
	}
end

local function carve(grid, depth: number, height: number, width: number)
	grid.cells[MineGenerator.cellIndex(grid, depth, height, width)] = MineGenerator.AIR
end

local function cell(depth: number, height: number, width: number)
	return { depth = depth, height = height, width = width }
end

describe(
	"DragRules",
	function()
		it(
			"floats through open air six ways, up and down included, and never through rock",
			function()
				local grid = makeGrid(6, 6, 6)
				-- a shaft up then a corridor along depth: no floor anywhere on the way
				for height = 1, 4 do
					carve(grid, 1, height, 1)
				end
				for depth = 1, 4 do
					carve(grid, depth, 4, 1)
				end
				local path = DragRules.findAirPath(grid, cell(1, 1, 1), cell(4, 4, 1), 64)
				expect(path).never.toBe(nil)
				expect(#path).toBe(6)
				expect(path[#path].depth).toBe(4)
				expect(path[#path].height).toBe(4)
				-- a goal in rock, or a start in rock, has no path
				expect(DragRules.findAirPath(grid, cell(1, 1, 1), cell(5, 5, 5), 64)).toBe(nil)
				expect(DragRules.findAirPath(grid, cell(0, 0, 0), cell(1, 1, 1), 64)).toBe(nil)
				-- the same cell is an empty path
				expect(#DragRules.findAirPath(grid, cell(1, 1, 1), cell(1, 1, 1), 64)).toBe(0)
			end
		)

		it(
			"gives up past the cap and finds the way when the cap allows",
			function()
				local grid = makeGrid(12, 3, 3)
				for depth = 0, 11 do
					carve(grid, depth, 1, 1)
				end
				expect(DragRules.findAirPath(grid, cell(0, 1, 1), cell(11, 1, 1), 4)).toBe(nil)
				local path = DragRules.findAirPath(grid, cell(0, 1, 1), cell(11, 1, 1), 64)
				expect(#path).toBe(11)
			end
		)

		it(
			"keeps a trail of distinct recent cells, newest last, dropping the oldest",
			function()
				local trail = {}
				DragRules.pushTrail(trail, cell(1, 1, 1), 3)
				DragRules.pushTrail(trail, cell(1, 1, 1), 3)
				DragRules.pushTrail(trail, cell(2, 1, 1), 3)
				DragRules.pushTrail(trail, cell(3, 1, 1), 3)
				DragRules.pushTrail(trail, cell(4, 1, 1), 3)
				expect(#trail).toBe(3)
				expect(trail[1].depth).toBe(2)
				expect(trail[3].depth).toBe(4)
			end
		)

		it(
			"chases the victim directly when it can, else the newest trail cell it can reach",
			function()
				local grid = makeGrid(12, 3, 3)
				for depth = 0, 11 do
					carve(grid, depth, 1, 1)
				end
				local trail = { cell(3, 1, 1), cell(5, 1, 1), cell(7, 1, 1) }
				-- the victim is within the cap: straight to them
				local direct = DragRules.pickChasePath(grid, cell(0, 1, 1), cell(4, 1, 1), trail, 64)
				expect(direct[#direct].depth).toBe(4)
				-- the victim is too far for the cap; the newest trail cell within it wins
				local viaTrail = DragRules.pickChasePath(grid, cell(0, 1, 1), cell(11, 1, 1), trail, 9)
				expect(viaTrail).never.toBe(nil)
				expect(viaTrail[#viaTrail].depth).toBe(7)
				-- nothing in reach: hold
				expect(DragRules.pickChasePath(grid, cell(0, 1, 1), cell(11, 1, 1), { cell(10, 1, 1) }, 3)).toBe(nil)
				-- no victim cell and an empty trail: hold
				expect(DragRules.pickChasePath(grid, cell(0, 1, 1), nil, {}, 64)).toBe(nil)
			end
		)

		it(
			"hangs at the middle of the bottom two air cells of a column, from any cell of it",
			function()
				local grid = makeGrid(3, 8, 3)
				-- a two-block passage at heights 1 and 2: the seam between them
				carve(grid, 1, 1, 1)
				carve(grid, 1, 2, 1)
				expect(DragRules.columnCentreHeight(grid, cell(1, 1, 1))).toBe(1.5)
				expect(DragRules.columnCentreHeight(grid, cell(1, 2, 1))).toBe(1.5)
				-- a shaft of five: the seam of its bottom two, from any cell of it
				for height = 1, 5 do
					carve(grid, 2, height, 1)
				end
				expect(DragRules.columnCentreHeight(grid, cell(2, 1, 1))).toBe(1.5)
				expect(DragRules.columnCentreHeight(grid, cell(2, 5, 1))).toBe(1.5)
				-- a single cell: its own centre
				carve(grid, 0, 4, 0)
				expect(DragRules.columnCentreHeight(grid, cell(0, 4, 0))).toBe(4)
			end
		)

		it(
			"picks one sleeper's pocket per deep zone among those the lurkers left free, the same for a seed",
			function()
				local pockets = {
					{ zoneIndex = 2, depth = 10, height = 2, width = 4, radius = 2 },
					{ zoneIndex = 5, depth = 60, height = 2, width = 4, radius = 2 },
					{ zoneIndex = 5, depth = 70, height = 2, width = 4, radius = 2 },
					{ zoneIndex = 6, depth = 100, height = 2, width = 4, radius = 2 },
					{ zoneIndex = 6, depth = 110, height = 2, width = 4, radius = 2 },
				}
				local picked = DragRules.pickDragPockets(pockets, 1, Random.new(3), 5, { [2] = true })
				local count = 0
				local zonesSeen = {}
				for index in picked do
					count += 1
					expect(index ~= 1 and index ~= 2).toBe(true)
					zonesSeen[pockets[index].zoneIndex] = true
				end
				-- one in zone 5 (the free one) and one in zone 6, never the shallow one
				expect(count).toBe(2)
				expect(zonesSeen[5]).toBe(true)
				expect(zonesSeen[6]).toBe(true)
				local again = DragRules.pickDragPockets(pockets, 1, Random.new(3), 5, { [2] = true })
				for index in picked do
					expect(again[index]).toBe(true)
				end
				local centre = DragRules.pocketCentreCell(pockets[2])
				expect(centre.depth).toBe(60)
			end
		)
	end
)
