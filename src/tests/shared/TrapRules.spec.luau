-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local TrapRules = require(game:GetService("ReplicatedStorage").Shared.TrapRules)

local TARGET_SIZE = Vector3.new(4, 6, 2)
-- an 8 by 8 trap centred at the origin
local TRAP_CFRAME = CFrame.new(0, 0, 0)
local TRAP_SIZE = Vector3.new(8, 1, 8)

describe(
	"TrapRules.isTouching",
	function()
		it(
			"overlaps from above, ignoring height",
			function()
				expect(TrapRules.isTouching(Vector3.new(0, 30, 0), TARGET_SIZE, TRAP_CFRAME, TRAP_SIZE)).toBe(true)
				expect(TrapRules.isTouching(Vector3.new(5.5, 0, 0), TARGET_SIZE, TRAP_CFRAME, TRAP_SIZE)).toBe(true)
				expect(TrapRules.isTouching(Vector3.new(6.5, 0, 0), TARGET_SIZE, TRAP_CFRAME, TRAP_SIZE)).toBe(false)
				expect(TrapRules.isTouching(Vector3.new(5.5, 0, 5.5), TARGET_SIZE, TRAP_CFRAME, TRAP_SIZE)).toBe(false)
			end
		)
		it(
			"follows the trap's rotation",
			function()
				local turned = CFrame.Angles(0, math.rad(90), 0)
				local longTrap = Vector3.new(16, 1, 4)
				expect(TrapRules.isTouching(Vector3.new(0, 0, 7), TARGET_SIZE, turned, longTrap)).toBe(true)
				expect(TrapRules.isTouching(Vector3.new(7, 0, 0), TARGET_SIZE, turned, longTrap)).toBe(false)
			end
		)
	end
)

describe(
	"TrapRules.findBlocker",
	function()
		it(
			"names the barrier the target stands on",
			function()
				local barriers = {
					{ id = "a", cframe = CFrame.new(20, 0, 0), size = TRAP_SIZE },
					{ id = "b", cframe = TRAP_CFRAME, size = TRAP_SIZE },
				}
				expect(TrapRules.findBlocker(Vector3.new(1, 0, 1), TARGET_SIZE, barriers)).toBe("b")
				expect(TrapRules.findBlocker(Vector3.new(40, 0, 0), TARGET_SIZE, barriers)).toBeNil()
			end
		)
	end
)

describe(
	"TrapRules.targetsWithin",
	function()
		it(
			"lists targets inside the radius",
			function()
				local ids = TrapRules.targetsWithin(Vector3.zero, 10, {
					{ id = "in", position = Vector3.new(6, 0, 6) },
					{ id = "out", position = Vector3.new(8, 0, 8) },
				})
				expect(ids).toEqual({ "in" })
			end
		)
	end
)

describe(
	"TrapRules.spikeState",
	function()
		it(
			"runs Down, Up, Recharging, Down",
			function()
				expect(TrapRules.spikeState(nil, 1, 3, 50)).toBe(Enums.TrapState.DOWN)
				expect(TrapRules.spikeState(100, 1, 3, 100.5)).toBe(Enums.TrapState.UP)
				expect(TrapRules.spikeState(100, 1, 3, 102)).toBe(Enums.TrapState.RECHARGING)
				expect(TrapRules.spikeState(100, 1, 3, 104)).toBe(Enums.TrapState.DOWN)
			end
		)
	end
)
