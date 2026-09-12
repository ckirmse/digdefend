-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local MineSpace = require(game:GetService("ReplicatedStorage").Shared.MineSpace)

local BLOCK = 4
local ORIGIN = Vector3.new(-60, 0, 10)

local function expectVector(actual: Vector3, expected: Vector3)
	expect(actual.X).toBeCloseTo(expected.X, 6)
	expect(actual.Y).toBeCloseTo(expected.Y, 6)
	expect(actual.Z).toBeCloseTo(expected.Z, 6)
end

describe(
	"MineSpace.facingFromLookVector",
	function()
		it(
			"snaps to the dominant horizontal axis",
			function()
				expect(MineSpace.facingFromLookVector(Vector3.new(-0.9, 0.2, 0.3))).toBe(Enums.MineFacing.NEGATIVE_X)
				expect(MineSpace.facingFromLookVector(Vector3.new(0.2, 0, 0.9))).toBe(Enums.MineFacing.POSITIVE_Z)
				expect(MineSpace.facingFromLookVector(Vector3.new(1, 0, 0))).toBe(Enums.MineFacing.POSITIVE_X)
				expect(MineSpace.facingFromLookVector(Vector3.new(0, 0, -1))).toBe(Enums.MineFacing.NEGATIVE_Z)
			end
		)
	end
)

describe(
	"MineSpace.cellToWorld",
	function()
		it(
			"puts the chamber floor row on the origin height and the mouth at the origin",
			function()
				-- centreline width 12, one bedrock floor row, facing -X
				local space = MineSpace.new(ORIGIN, Enums.MineFacing.NEGATIVE_X, 12, 1, BLOCK)
				-- first depth row, chamber floor row, centreline: half a block in, half a block up
				expectVector(MineSpace.cellToWorld(space, 0, 1, 12), ORIGIN + Vector3.new(-2, 2, 0))
				-- the bedrock floor row sits under the origin
				expectVector(MineSpace.cellToWorld(space, 0, 0, 12), ORIGIN + Vector3.new(-2, -2, 0))
				-- ten blocks in and two blocks up
				expectVector(MineSpace.cellToWorld(space, 10, 3, 12), ORIGIN + Vector3.new(-42, 10, 0))
			end
		)

		it(
			"lays width across the facing so a mine facing +Z spreads along X",
			function()
				local space = MineSpace.new(ORIGIN, Enums.MineFacing.POSITIVE_Z, 5, 1, BLOCK)
				local centre = MineSpace.cellToWorld(space, 0, 1, 5)
				local right = MineSpace.cellToWorld(space, 0, 1, 6)
				expect(right.Z).toBeCloseTo(centre.Z, 6)
				expect(math.abs(right.X - centre.X)).toBeCloseTo(BLOCK, 6)
			end
		)
	end
)

describe(
	"MineSpace.worldToCell",
	function()
		it(
			"inverts cellToWorld at block centres and across each block",
			function()
				for _, facing in Enums.getAllValues(Enums.MineFacing) do
					local space = MineSpace.new(ORIGIN, facing, 12, 1, BLOCK)
					for _, cell in { { 0, 0, 0 }, { 7, 3, 12 }, { 100, 17, 25 }, { 3, 1, 0 } } do
						local centre = MineSpace.cellToWorld(space, cell[1], cell[2], cell[3])
						local depth, height, width = MineSpace.worldToCell(space, centre)
						expect({ depth, height, width }).toEqual(cell)
						-- anywhere inside the block maps to the same cell
						local nudged = centre + space.forward * 1.9 + Vector3.new(0, -1.9, 0) + space.widthAxis * -1.9
						depth, height, width = MineSpace.worldToCell(space, nudged)
						expect({ depth, height, width }).toEqual(cell)
					end
				end
			end
		)

		it(
			"returns out-of-grid cells for positions outside the mine",
			function()
				local space = MineSpace.new(ORIGIN, Enums.MineFacing.NEGATIVE_X, 12, 1, BLOCK)
				local depth = MineSpace.worldToCell(space, ORIGIN + Vector3.new(20, 0, 0))
				expect(depth).toBeLessThan(0)
			end
		)
	end
)
