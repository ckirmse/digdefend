-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DynamiteRules = require(game:GetService("ReplicatedStorage").Shared.DynamiteRules)

describe(
	"DynamiteRules.cellsInBlast",
	function()
		it(
			"covers the 3x3x3 cube for a radius of one block",
			function()
				local cells = DynamiteRules.cellsInBlast(5, 5, 5, 1, 20, 20, 20)
				expect(#cells).toBe(27)
			end
		)
		it(
			"clips at the grid edges",
			function()
				local cells = DynamiteRules.cellsInBlast(0, 0, 0, 1, 20, 20, 20)
				expect(#cells).toBe(8)
				local far = DynamiteRules.cellsInBlast(19, 19, 19, 1, 20, 20, 20)
				expect(#far).toBe(8)
			end
		)
		it(
			"is just the centre cell at radius zero",
			function()
				local cells = DynamiteRules.cellsInBlast(3, 4, 5, 0, 20, 20, 20)
				expect(#cells).toBe(1)
				expect(cells[1].depth).toBe(3)
				expect(cells[1].height).toBe(4)
				expect(cells[1].width).toBe(5)
			end
		)
	end
)
