-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MineGenerator = require(game:GetService("ReplicatedStorage").Shared.MineGenerator)
local MineGridQuery = require(game:GetService("ReplicatedStorage").Shared.MineGridQuery)

-- a 5x5x5 grid of rock 18 with a single air cell in the middle
local function makeGrid()
	local grid = {
		depth = 5,
		height = 5,
		width = 5,
		centrelineWidth = 2,
		floorHeight = 1,
		cells = table.create(125, 18),
	}
	grid.cells[MineGenerator.cellIndex(grid, 2, 2, 2)] = MineGenerator.AIR
	return grid
end

describe(
	"MineGridQuery.isExposed",
	function()
		it(
			"exposes the six cells around an air pocket and nothing else inside",
			function()
				local grid = makeGrid()
				expect(MineGridQuery.isExposed(grid, 1, 2, 2)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 3, 2, 2)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 2, 1, 2)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 2, 3, 2)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 2, 2, 1)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 2, 2, 3)).toBe(true)
				-- diagonal neighbour of the pocket is buried
				expect(MineGridQuery.isExposed(grid, 1, 1, 1)).toBe(false)
				-- the air cell itself is not a block
				expect(MineGridQuery.isExposed(grid, 2, 2, 2)).toBe(false)
			end
		)

		it(
			"exposes only the front face of the grid's shell",
			function()
				local grid = makeGrid()
				expect(MineGridQuery.isExposed(grid, 0, 0, 0)).toBe(true)
				expect(MineGridQuery.isExposed(grid, 0, 4, 4)).toBe(true)
				-- far end, top, and side stay buried
				expect(MineGridQuery.isExposed(grid, 4, 2, 2)).toBe(false)
				expect(MineGridQuery.isExposed(grid, 2, 4, 2)).toBe(false)
				expect(MineGridQuery.isExposed(grid, 2, 2, 0)).toBe(false)
				expect(MineGridQuery.isExposed(grid, -1, 2, 2)).toBe(false)
			end
		)

		it(
			"counts the front face plus the pocket walls",
			function()
				-- the 5x5 front face plus the 6 cells around the pocket
				expect(MineGridQuery.countExposed(makeGrid())).toBe(25 + 6)
			end
		)
	end
)
