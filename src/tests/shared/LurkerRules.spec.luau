-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MineGenerator = require(game:GetService("ReplicatedStorage").Shared.MineGenerator)
local LurkerRules = require(game:GetService("ReplicatedStorage").Shared.LurkerRules)

local ROCK = 1

-- a small solid grid with air carved where the test wants it
local function makeGrid(depth: number, height: number, width: number)
	local grid = {
		depth = depth,
		height = height,
		width = width,
		centrelineWidth = math.floor(width / 2),
		floorHeight = 1,
		cells = table.create(depth * height * width, ROCK),
	}
	return grid
end

local function carve(grid, depth: number, height: number, width: number)
	grid.cells[MineGenerator.cellIndex(grid, depth, height, width)] = MineGenerator.AIR
end

local function cell(depth: number, height: number, width: number)
	return { depth = depth, height = height, width = width }
end

describe(
	"LurkerRules",
	function()
		it(
			"picks a fixed count of pockets from the eligible zones, the same for the same seed",
			function()
				expect(LurkerRules.lurkerCount(1, 10, 2, 20)).toBe(10)
				expect(LurkerRules.lurkerCount(3, 10, 2, 20)).toBe(14)
				expect(LurkerRules.lurkerCount(6, 10, 2, 20)).toBe(20)
				expect(LurkerRules.lurkerCount(9, 10, 2, 20)).toBe(20)
				local pockets = {}
				for index = 1, 200 do
					pockets[index] = { zoneIndex = if index > 100 then 4 else 1, depth = index, height = 2, width = 2, radius = 1 }
				end
				local first = LurkerRules.pickLurkerPockets(pockets, 10, Random.new(7), 4)
				local second = LurkerRules.pickLurkerPockets(pockets, 10, Random.new(7), 4)
				local count = 0
				for index in first do
					count += 1
					expect(index).toBeGreaterThan(100)
					expect(second[index]).toBe(true)
				end
				expect(count).toBe(10)
				expect(next(LurkerRules.pickLurkerPockets(pockets, 0, Random.new(7)))).toBeNil()
				-- a mine with fewer eligible pockets than asked gives what it has
				local few = 0
				for _ in LurkerRules.pickLurkerPockets(pockets, 500, Random.new(7), 4) do
					few += 1
				end
				expect(few).toBe(100)
			end
		)
		it(
			"wakes on a block within one cell of the pocket's room",
			function()
				-- a radius 2 room: depths 9 to 12, rows 4 to 6, widths 4 to 7
				local pocket = { zoneIndex = 1, depth = 10, height = 5, width = 5, radius = 2 }
				expect(LurkerRules.isCellTouchingPocket(pocket, 13, 5, 5)).toBe(true)
				expect(LurkerRules.isCellTouchingPocket(pocket, 14, 5, 5)).toBe(false)
				expect(LurkerRules.isCellTouchingPocket(pocket, 12, 7, 5)).toBe(true)
				expect(LurkerRules.isCellTouchingPocket(pocket, 12, 8, 7)).toBe(false)
			end
		)
		it(
			"wakes only when the broken block opens into the pocket's air",
			function()
				local grid = makeGrid(20, 12, 12)
				-- a radius 1 room: one row, 2 by 2, from the centre cell outward
				local pocket = { zoneIndex = 1, depth = 10, height = 5, width = 5, radius = 1 }
				for depth = 10, 11 do
					for width = 5, 6 do
						carve(grid, depth, 5, width)
					end
				end
				-- the block in front of the pocket's air, broken: it opens
				carve(grid, 12, 5, 5)
				expect(LurkerRules.isCellOpeningPocket(grid, pocket, 12, 5, 5)).toBe(true)
				-- a block touching the room only at a corner, broken: still sealed
				carve(grid, 12, 6, 7)
				expect(LurkerRules.isCellTouchingPocket(pocket, 12, 6, 7)).toBe(true)
				expect(LurkerRules.isCellOpeningPocket(grid, pocket, 12, 6, 7)).toBe(false)
			end
		)
		it(
			"clings to the floor first, then a wall, then the ceiling, and floats free of none",
			function()
				local grid = makeGrid(5, 5, 5)
				carve(grid, 2, 2, 2)
				-- boxed in on every side: the floor wins
				local dd, dh, dw = LurkerRules.clingDirection(grid, 2, 2, 2)
				expect(dd).toBe(0)
				expect(dh).toBe(-1)
				expect(dw).toBe(0)
				carve(grid, 2, 1, 2)
				dd, dh, dw = LurkerRules.clingDirection(grid, 2, 2, 2)
				expect(dd).toBe(1)
				-- open a 3x3x3 room: the centre touches nothing
				for depth = 1, 3 do
					for height = 1, 3 do
						for width = 1, 3 do
							carve(grid, depth, height, width)
						end
					end
				end
				expect(LurkerRules.clingDirection(grid, 2, 2, 2)).toBeNil()
				-- the grid's edge counts as rock
				expect(LurkerRules.isSolid(grid, -1, 2, 2)).toBe(true)
			end
		)
		it(
			"rests on a pocket's floor",
			function()
				local grid = makeGrid(9, 9, 9)
				for depth = 3, 5 do
					for height = 3, 5 do
						for width = 3, 5 do
							carve(grid, depth, height, width)
						end
					end
				end
				-- a radius 1 room is one row: the cube's lowest, where the floor is
				local resting = LurkerRules.findRestingCell(grid, { zoneIndex = 1, depth = 4, height = 3, width = 4, radius = 1 })
				expect(resting.height).toBe(3)
				expect(LurkerRules.hasFloor(grid, resting.depth, resting.height, resting.width)).toBe(true)
			end
		)
		it(
			"rests on a room's floor, never in a pit, and can walk out of where it rests",
			function()
				-- a pocket as the generator carves it: a 4 by 4 room three rows
				-- tall on a flat floor, its top row stepped in
				local grid = makeGrid(14, 14, 14)
				local pocket = { zoneIndex = 1, depth = 7, height = 7, width = 7, radius = 2 }
				local bounds = MineGenerator.pocketBounds(pocket)
				expect(bounds.heightStart).toBe(6)
				expect(bounds.heightEnd).toBe(8)
				for depth = bounds.depthStart, bounds.depthEnd do
					for height = bounds.heightStart, bounds.heightEnd do
						for width = bounds.widthStart, bounds.widthEnd do
							if MineGenerator.isCellInPocket(pocket, depth, height, width) then
								carve(grid, depth, height, width)
							end
						end
					end
				end
				-- woken by a block on one wall, it starts on the floor cell farthest
				-- from that block: the opposite corner of the room
				local far = LurkerRules.findRestingCell(grid, pocket, cell(4, 7, 5))
				expect(far.height).toBe(6)
				expect(far.depth).toBe(9)
				expect(far.width).toBe(9)
				expect(LurkerRules.isWalkableFloor(grid, far.depth, far.height, far.width)).toBe(true)
				-- the top row's corners stay rock: the ceiling domes
				expect(MineGenerator.isCellInPocket(pocket, 6, 8, 6)).toBe(false)
				expect(MineGenerator.isCellInPocket(pocket, 7, 8, 7)).toBe(true)
				expect(MineGenerator.pocketCellCount(2)).toBe(36)
				expect(MineGenerator.pocketCellCount(1)).toBe(4)
				-- a one-cell pit would not be a place to rest
				local pitGrid = makeGrid(5, 5, 5)
				carve(pitGrid, 2, 1, 2)
				carve(pitGrid, 2, 2, 2)
				expect(LurkerRules.isWalkableFloor(pitGrid, 2, 1, 2)).toBe(false)
				local resting = LurkerRules.findRestingCell(grid, pocket)
				expect(resting.height).toBe(6)
				expect(LurkerRules.isWalkableFloor(grid, resting.depth, resting.height, resting.width)).toBe(true)
				-- from there a route reaches the far side of the room along its floor
				local path = LurkerRules.findPath(grid, resting, cell(8, 6, 7), 20)
				expect(path).never.toBeNil()
				-- a goal in the room's open middle snaps to the first cell under it that touches rock
				local snapped = LurkerRules.surfaceCellBelow(grid, cell(7, 7, 8), 6) :: LurkerRules.Cell
				expect(snapped.height).toBe(6)
				expect(LurkerRules.surfaceCellBelow(grid, cell(7, 12, 7), 6)).toBeNil()
				-- a goal in open air that no surface cell can enter is reached by stopping beside it
				local beside = LurkerRules.findPath(grid, resting, cell(7, 7, 7), 20) :: { LurkerRules.Cell }
				expect(beside).never.toBeNil()
				local last = beside[#beside]
				expect(math.abs(last.depth - 7) + math.abs(last.height - 7) + math.abs(last.width - 7)).toBe(1)
			end
		)
		it(
			"stands only on cells that touch rock",
			function()
				local grid = makeGrid(9, 9, 9)
				for depth = 2, 6 do
					for height = 2, 6 do
						for width = 2, 6 do
							carve(grid, depth, height, width)
						end
					end
				end
				expect(LurkerRules.isSurface(grid, 4, 4, 4)).toBe(false)
				expect(LurkerRules.isSurface(grid, 2, 4, 4)).toBe(true)
				expect(LurkerRules.isSurface(grid, 4, 2, 4)).toBe(true)
				expect(LurkerRules.hasFloor(grid, 4, 2, 4)).toBe(true)
				expect(LurkerRules.hasFloor(grid, 2, 4, 4)).toBe(false)
				-- a route across the room goes round the walls, never through the middle
				local path = LurkerRules.findPath(grid, cell(2, 2, 2), cell(6, 2, 6), 20) :: { LurkerRules.Cell }
				expect(path).never.toBeNil()
				for _, step in path do
					expect(LurkerRules.isSurface(grid, step.depth, step.height, step.width)).toBe(true)
				end
				expect(LurkerRules.findPath(grid, cell(2, 2, 2), cell(4, 4, 4), 20)).toBeNil()
				-- drifting from a floor cell stays on the floor
				for _ = 1, 10 do
					local neighbour = LurkerRules.randomAirNeighbour(grid, cell(3, 2, 3), Random.new(_)) :: LurkerRules.Cell
					expect(LurkerRules.hasFloor(grid, neighbour.depth, neighbour.height, neighbour.width)).toBe(true)
				end
			end
		)
		it(
			"leaps a one-cell gap of open air, never two cells in a row",
			function()
				-- a floor corridor along depth with one cell in the middle hollowed
				-- out on every side, so that cell touches no rock
				local grid = makeGrid(9, 6, 7)
				for depth = 1, 7 do
					carve(grid, depth, 2, 3)
				end
				carve(grid, 4, 1, 3)
				carve(grid, 4, 3, 3)
				carve(grid, 4, 2, 2)
				carve(grid, 4, 2, 4)
				expect(LurkerRules.isSurface(grid, 4, 2, 3)).toBe(false)
				local path = LurkerRules.findPath(grid, cell(1, 2, 3), cell(7, 2, 3), 20) :: { LurkerRules.Cell }
				expect(path).never.toBeNil()
				expect(#path).toBe(6)
				local wasOpenAir = false
				for _, step in path do
					local isOpenAir = not LurkerRules.isSurface(grid, step.depth, step.height, step.width)
					expect(wasOpenAir and isOpenAir).toBe(false)
					wasOpenAir = isOpenAir
				end
				-- a goal in open air is reached beside it only from a cell on rock
				local beside = LurkerRules.findPath(grid, cell(1, 2, 3), cell(4, 2, 3), 20) :: { LurkerRules.Cell }
				expect(beside).never.toBeNil()
				local last = beside[#beside]
				expect(LurkerRules.isSurface(grid, last.depth, last.height, last.width)).toBe(true)
			end
		)
		it(
			"takes the floor over a climb of the same length",
			function()
				-- a 2-high tunnel: floor row 2, head row 3; both rows reach the end
				local grid = makeGrid(12, 6, 5)
				for depth = 1, 8 do
					carve(grid, depth, 2, 2)
					carve(grid, depth, 3, 2)
				end
				local path = LurkerRules.findPath(grid, cell(1, 3, 2), cell(8, 3, 2), 20) :: { LurkerRules.Cell }
				expect(path).never.toBeNil()
				-- it drops to the floor, walks it, and climbs for the last cell
				local floorSteps = 0
				for _, step in path do
					if step.height == 2 then
						floorSteps += 1
					end
				end
				expect(floorSteps).toBeGreaterThanOrEqual(6)
				expect(path[#path].height).toBe(3)
			end
		)
		it(
			"sees down a straight tunnel and not round a corner",
			function()
				local grid = makeGrid(12, 5, 5)
				for depth = 1, 8 do
					carve(grid, depth, 2, 2)
				end
				for width = 2, 4 do
					carve(grid, 8, 2, width)
				end
				expect(LurkerRules.hasLineOfSight(grid, cell(1, 2, 2), cell(8, 2, 2))).toBe(true)
				expect(LurkerRules.hasLineOfSight(grid, cell(1, 2, 2), cell(8, 2, 4))).toBe(false)
				expect(LurkerRules.hasLineOfSight(grid, cell(1, 2, 2), cell(1, 2, 2))).toBe(true)
				expect(LurkerRules.hasLineOfSight(grid, cell(1, 2, 2), cell(10, 2, 2))).toBe(false)
			end
		)
		it(
			"finds the way round a corner within the cap and gives up past it",
			function()
				local grid = makeGrid(12, 5, 5)
				for depth = 1, 8 do
					carve(grid, depth, 2, 2)
				end
				for width = 2, 4 do
					carve(grid, 8, 2, width)
				end
				local path = LurkerRules.findPath(grid, cell(1, 2, 2), cell(8, 2, 4), 12) :: { LurkerRules.Cell }
				expect(path).never.toBeNil()
				expect(#path).toBe(9)
				expect(path[1].depth).toBe(2)
				expect(path[#path].width).toBe(4)
				expect(LurkerRules.findPath(grid, cell(1, 2, 2), cell(8, 2, 4), 5)).toBeNil()
				-- a goal inside rock is unreachable, and the start is a path of nothing
				expect(LurkerRules.findPath(grid, cell(1, 2, 2), cell(1, 1, 2), 12)).toBeNil()
				expect(#(LurkerRules.findPath(grid, cell(1, 2, 2), cell(1, 2, 2), 12) :: { LurkerRules.Cell })).toBe(0)
			end
		)
		it(
			"drifts only into air and reads a cell back from its index",
			function()
				local grid = makeGrid(6, 6, 6)
				carve(grid, 2, 2, 2)
				expect(LurkerRules.randomAirNeighbour(grid, cell(2, 2, 2), Random.new(1))).toBeNil()
				carve(grid, 3, 2, 2)
				local neighbour = LurkerRules.randomAirNeighbour(grid, cell(2, 2, 2), Random.new(1)) :: LurkerRules.Cell
				expect(neighbour.depth).toBe(3)
				local index = MineGenerator.cellIndex(grid, 4, 5, 1)
				local back = LurkerRules.cellOfIndex(grid, index)
				expect(back.depth).toBe(4)
				expect(back.height).toBe(5)
				expect(back.width).toBe(1)
			end
		)
	end
)
