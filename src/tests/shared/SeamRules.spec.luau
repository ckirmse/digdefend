-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MineGenerator = require(game:GetService("ReplicatedStorage").Shared.MineGenerator)
local SeamRules = require(game:GetService("ReplicatedStorage").Shared.SeamRules)

local STONE = 1
local ORE = 2

local function isStone(rock: number): boolean
	return rock == STONE
end

local function makeGrid(depth: number, height: number, width: number)
	return {
		depth = depth,
		height = height,
		width = width,
		centrelineWidth = math.floor(width / 2),
		floorHeight = 1,
		cells = table.create(depth * height * width, STONE),
	}
end

local function setCell(grid, depth: number, height: number, width: number, value: number)
	grid.cells[MineGenerator.cellIndex(grid, depth, height, width)] = value
end

local function carve(grid, depth: number, height: number, width: number)
	setCell(grid, depth, height, width, MineGenerator.AIR)
end

local function cell(depth: number, height: number, width: number)
	return { depth = depth, height = height, width = width }
end

describe(
	"SeamRules",
	function()
		it(
			"calls a rock cell exposed only when a face meets air",
			function()
				local grid = makeGrid(5, 5, 5)
				expect(SeamRules.isExposedRock(grid, 2, 2, 2)).toBe(false)
				carve(grid, 3, 2, 2)
				expect(SeamRules.isExposedRock(grid, 2, 2, 2)).toBe(true)
				-- air itself is never exposed rock
				expect(SeamRules.isExposedRock(grid, 3, 2, 2)).toBe(false)
				-- the grid's edge is not air
				expect(SeamRules.isExposedRock(grid, 0, 0, 0)).toBe(false)
			end
		)

		it(
			"holds stone only, never ore, air, or a held cell",
			function()
				local grid = makeGrid(3, 3, 3)
				setCell(grid, 1, 1, 1, ORE)
				carve(grid, 1, 1, 2)
				local occupied = { [SeamRules.cellKey(0, 0, 0)] = true }
				expect(SeamRules.isHoldable(grid, 1, 1, 1, isStone, occupied)).toBe(false)
				expect(SeamRules.isHoldable(grid, 1, 1, 2, isStone, occupied)).toBe(false)
				expect(SeamRules.isHoldable(grid, 0, 0, 0, isStone, occupied)).toBe(false)
				expect(SeamRules.isHoldable(grid, 2, 2, 2, isStone, occupied)).toBe(true)
				expect(SeamRules.isHoldable(grid, 3, 0, 0, isStone, occupied)).toBe(false)
			end
		)

		it(
			"seats the asked count of sleeping seams from the seed, past the minimum depth, apart, and away from pockets",
			function()
				local grid = makeGrid(20, 6, 8)
				local pockets = {
					{ zoneIndex = 1, depth = 15, height = 2, width = 4, radius = 2 },
				}
				local first = SeamRules.pickSeamCells(grid, 6, Random.new(7), 10, isStone, pockets)
				local second = SeamRules.pickSeamCells(grid, 6, Random.new(7), 10, isStone, pockets)
				expect(#first).toBe(6)
				expect(#second).toBe(6)
				for index, cellA in first do
					expect(cellA.depth).toBe(second[index].depth)
					expect(cellA.height).toBe(second[index].height)
					expect(cellA.width).toBe(second[index].width)
					expect(cellA.depth >= 10).toBe(true)
					expect(SeamRules.isHoldable(grid, cellA.depth, cellA.height, cellA.width, isStone, {})).toBe(true)
					-- never on a pocket's wall
					local bounds = MineGenerator.pocketBounds(pockets[1])
					local isTouching = cellA.depth >= bounds.depthStart - 1 and cellA.depth <= bounds.depthEnd + 1 and cellA.height >= bounds.heightStart - 1 and cellA.height <= bounds.heightEnd + 1 and cellA.width >= bounds.widthStart - 1 and cellA.width <= bounds.widthEnd + 1
					expect(isTouching).toBe(false)
					for otherIndex, cellB in first do
						if otherIndex ~= index then
							expect(SeamRules.isFaceNeighbour(cellA, cellB)).toBe(false)
						end
					end
				end
				local different = SeamRules.pickSeamCells(grid, 6, Random.new(8), 10, isStone, pockets)
				local isSame = true
				for index, cellA in first do
					if cellA.depth ~= different[index].depth or cellA.height ~= different[index].height or cellA.width ~= different[index].width then
						isSame = false
					end
				end
				expect(isSame).toBe(false)
				-- a minimum depth past the grid seats nothing
				expect(#SeamRules.pickSeamCells(grid, 6, Random.new(7), 20, isStone, pockets)).toBe(0)
			end
		)

		it(
			"wakes on a cleared face neighbour only, and finds the cleared cell on the seam",
			function()
				local cells = { cell(5, 2, 3), cell(6, 2, 3) }
				expect(SeamRules.isWokenBy(cells, 4, 2, 3)).toBe(true)
				expect(SeamRules.isWokenBy(cells, 6, 3, 3)).toBe(true)
				-- a corner touch is not a face
				expect(SeamRules.isWokenBy(cells, 4, 3, 3)).toBe(false)
				expect(SeamRules.isWokenBy(cells, 9, 9, 9)).toBe(false)
				expect(SeamRules.indexOfCell(cells, 6, 2, 3)).toBe(2)
				expect(SeamRules.indexOfCell(cells, 7, 2, 3)).toBe(nil)
			end
		)

		it(
			"round-trips cells through the flat network list",
			function()
				local cells = { cell(1, 2, 3), cell(10, 0, 7) }
				local flat = SeamRules.encodeCells(cells)
				expect(#flat).toBe(6)
				local back = SeamRules.decodeCells(flat)
				expect(#back).toBe(2)
				expect(back[2].depth).toBe(10)
				expect(back[2].height).toBe(0)
				expect(back[2].width).toBe(7)
				expect(#SeamRules.decodeCells({})).toBe(0)
			end
		)
	end
)
