-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local JetPackRules = require(game:GetService("ReplicatedStorage").Shared.JetPackRules)

-- mirrors GameData/Mining/JetPack
local BASE_FUEL_SEC = 1.5
local FUEL_PER_LEVEL_SEC = 0.5
local REFILL_RATE = 0.5

describe(
	"JetPackRules.maxFuelForLevel",
	function()
		it(
			"starts at the base and adds the step per level",
			function()
				expect(JetPackRules.maxFuelForLevel(BASE_FUEL_SEC, FUEL_PER_LEVEL_SEC, 1)).toBe(1.5)
				expect(JetPackRules.maxFuelForLevel(BASE_FUEL_SEC, FUEL_PER_LEVEL_SEC, 5)).toBe(3.5)
				expect(JetPackRules.maxFuelForLevel(BASE_FUEL_SEC, FUEL_PER_LEVEL_SEC, 0)).toBe(1.5)
			end
		)
	end
)

describe(
	"JetPackRules.step",
	function()
		it(
			"drains while burning, cuts out at empty, and locks",
			function()
				local tank = { fuelSec = 1, isBurning = true, isLocked = false }
				local fuel, isCutOut, isLocked = JetPackRules.step(tank, 0.4, 3, REFILL_RATE)
				expect(fuel).toBeCloseTo(0.6, 5)
				expect(isCutOut).toBe(false)
				expect(isLocked).toBe(false)
				tank.fuelSec = fuel
				fuel, isCutOut, isLocked = JetPackRules.step(tank, 1, 3, REFILL_RATE)
				expect(fuel).toBe(0)
				expect(isCutOut).toBe(true)
				expect(isLocked).toBe(true)
			end
		)
		it(
			"refills anywhere while not burning and unlocks only when full",
			function()
				local tank = { fuelSec = 0, isBurning = false, isLocked = true }
				local fuel, _, isLocked = JetPackRules.step(tank, 1, 3, REFILL_RATE)
				expect(fuel).toBe(0.5)
				expect(isLocked).toBe(true)
				tank.fuelSec = fuel
				fuel, _, isLocked = JetPackRules.step(tank, 5, 3, REFILL_RATE)
				expect(fuel).toBe(3)
				expect(isLocked).toBe(false)
			end
		)
		it(
			"only starts with fuel, unlocked, and while not already burning",
			function()
				expect(JetPackRules.canStart({ fuelSec = 0, isBurning = false, isLocked = false })).toBe(false)
				expect(JetPackRules.canStart({ fuelSec = 1, isBurning = true, isLocked = false })).toBe(false)
				expect(JetPackRules.canStart({ fuelSec = 2, isBurning = false, isLocked = true })).toBe(false)
				expect(JetPackRules.canStart({ fuelSec = 1, isBurning = false, isLocked = false })).toBe(true)
			end
		)
	end
)
