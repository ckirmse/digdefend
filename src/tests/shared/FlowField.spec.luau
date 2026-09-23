-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local FlowField = require(game:GetService("ReplicatedStorage").Shared.FlowField)

local GROUND = {
	isAir = false,
	barrierCost = 20,
}
local AIR = {
	isAir = true,
	barrierCost = 20,
}

-- a grid from rows of text: "." open, "#" blocked but inside, " " outside,
-- "B" a barrier on open ground, "G" a goal on open ground
local function gridFromRows(rows: { string }): (FlowField.Grid, { number })
	local grid = FlowField.newGrid(0, 0, #rows[1], #rows, 4)
	local goals = {}
	for row, text in rows do
		for column = 1, #text do
			local character = text:sub(column, column)
			local index = FlowField.indexOf(grid, column, row)
			grid.inside[index] = character ~= " "
			grid.walkable[index] = character == "." or character == "B" or character == "G"
			if character == "B" then
				grid.barriers[index] = `Barrier{column},{row}`
			elseif character == "G" then
				table.insert(goals, index)
			end
		end
	end
	return grid, goals
end

-- follows nextIndex from a cell to the goal, returning the cells walked
local function walk(grid: FlowField.Grid, field: FlowField.Field, column: number, row: number): { string }
	local cells = {}
	local index = FlowField.indexOf(grid, column, row)
	for _ = 1, 200 do
		local stepColumn, stepRow = FlowField.cellOf(grid, index)
		table.insert(cells, `{stepColumn},{stepRow}`)
		local nextIndex = field.nextIndex[index]
		if nextIndex == 0 then
			break
		end
		index = nextIndex
	end
	return cells
end

describe(
	"FlowField grid maths",
	function()
		it(
			"maps world positions to cells and back to centres",
			function()
				local grid = FlowField.newGrid(-10, 20, 5, 3, 4)
				expect(FlowField.indexAt(grid, -10, 20)).toBe(1)
				expect(FlowField.indexAt(grid, -6.5, 20)).toBe(1)
				expect(FlowField.indexAt(grid, -6, 24)).toBe(FlowField.indexOf(grid, 2, 2))
				expect(FlowField.indexAt(grid, 10, 20)).toBe(nil)
				expect(FlowField.indexAt(grid, 0, 19.9)).toBe(nil)
				local x, z = FlowField.centerOf(grid, FlowField.indexOf(grid, 3, 2))
				expect(x).toBe(0)
				expect(z).toBe(26)
				local column, row = FlowField.cellOf(grid, FlowField.indexOf(grid, 4, 3))
				expect(column).toBe(4)
				expect(row).toBe(3)
			end
		)
	end
)

describe(
	"FlowField.compute",
	function()
		it(
			"leads every open cell to the goal, walking round a block",
			function()
				local grid, goals = gridFromRows({
					"G....",
					"###..",
					".....",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				local path = walk(grid, field, 1, 3)
				expect(path[#path]).toBe("1,1")
				for _, cell in path do
					expect(cell == "1,2" or cell == "2,2" or cell == "3,2").toBe(false)
				end
				expect(field.costs[FlowField.indexOf(grid, 1, 1)]).toBe(0)
			end
		)
		it(
			"never cuts the corner of a blocked cell",
			function()
				local grid, goals = gridFromRows({
					"G#",
					"..",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				-- the diagonal from 2,2 to 1,1 would clip 2,1
				expect(walk(grid, field, 2, 2)).toEqual({ "2,2", "1,2", "1,1" })
			end
		)
		it(
			"takes a longer open way round rather than breaking a barrier",
			function()
				local grid, goals = gridFromRows({
					"G.....",
					"BB.###",
					"......",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				local path = walk(grid, field, 1, 3)
				expect(table.find(path, "1,2")).toBe(nil)
				expect(table.find(path, "3,2")).never.toBe(nil)
			end
		)
		it(
			"goes through a barrier when there is no other way",
			function()
				local grid, goals = gridFromRows({
					"G..",
					"B##",
					"...",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				local path = walk(grid, field, 3, 3)
				expect(table.find(path, "1,2")).never.toBe(nil)
				expect(path[#path]).toBe("1,1")
				expect(field.costs[FlowField.indexOf(grid, 1, 3)]).toBeGreaterThan(20)
			end
		)
		it(
			"never slips diagonally between barrier cells",
			function()
				-- a wall laid on the diagonal: without the rule, 3,3 to 2,2
				-- would pass between 3,2 and 2,3 for free
				local grid, goals = gridFromRows({
					"G..B",
					"..B.",
					".B..",
					"B...",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				expect(field.costs[FlowField.indexOf(grid, 4, 4)]).toBeGreaterThan(20)
				local path = walk(grid, field, 4, 4)
				expect(path[#path]).toBe("1,1")
			end
		)
		it(
			"leaves cells with no way at all unreachable",
			function()
				local grid, goals = gridFromRows({
					"G.#.",
					"..#.",
				})
				local field = FlowField.compute(grid, goals, GROUND)
				local index = FlowField.indexOf(grid, 4, 1)
				expect(field.costs[index]).toBe(math.huge)
				expect(field.nextIndex[index]).toBe(0)
			end
		)
		it(
			"lets air cross blocked and barrier cells but never leave the areas",
			function()
				local grid, goals = gridFromRows({
					"G##. ",
					"BB#. ",
					"...  ",
				})
				local field = FlowField.compute(grid, goals, AIR)
				expect(walk(grid, field, 4, 1)).toEqual({ "4,1", "3,1", "2,1", "1,1" })
				expect(field.costs[FlowField.indexOf(grid, 5, 1)]).toBe(math.huge)
			end
		)
	end
)

describe(
	"FlowField.isLineClear",
	function()
		it(
			"passes over open ground and stops at blocks, barriers, and the edge",
			function()
				local grid = gridFromRows({
					".....",
					"..#B.",
					".....",
				})
				-- along the top row, cell centres at z 2
				expect(FlowField.isLineClear(grid, 2, 2, 18, 2, false)).toBe(true)
				-- across the middle row: the block at column 3
				expect(FlowField.isLineClear(grid, 2, 6, 18, 6, false)).toBe(false)
				-- the barrier at column 4 stops the ground but not the air
				expect(FlowField.isLineClear(grid, 14, 2, 14, 10, false)).toBe(false)
				expect(FlowField.isLineClear(grid, 14, 2, 14, 10, true)).toBe(true)
				expect(FlowField.isLineClear(grid, 2, 2, 40, 2, true)).toBe(false)
			end
		)
	end
)

describe(
	"FlowField.nearestEnterable",
	function()
		it(
			"finds the closest open cell from off the grid or a blocked cell",
			function()
				local grid = gridFromRows({
					"###",
					"#..",
					"###",
				})
				local index = FlowField.nearestEnterable(grid, 2, 2, false, 3)
				expect(index).toBe(FlowField.indexOf(grid, 2, 2))
				local fromOutside = FlowField.nearestEnterable(grid, 40, 6, false, 20)
				expect(fromOutside).toBe(FlowField.indexOf(grid, 3, 2))
				expect(FlowField.nearestEnterable(gridFromRows({ "##" }), 0, 0, false, 5)).toBe(nil)
			end
		)
	end
)
