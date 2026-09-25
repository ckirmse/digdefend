-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local StructureRules = require(game:GetService("ReplicatedStorage").Shared.StructureRules)

-- mirrors GameData/Camp/Structures
local WALL = {
	MAX_HP_BY_TIER = { 200, 400, 800 },
}
local UPGRADE_IRON_TO_TIER = { 0, 150, 400 }
local CHUNK_HP = 10
local CHUNK_IRON = 4

describe(
	"StructureRules.maxHp",
	function()
		it(
			"reads the tier and clamps outside the table",
			function()
				expect(StructureRules.maxHp(WALL, 1)).toBe(200)
				expect(StructureRules.maxHp(WALL, 3)).toBe(800)
				expect(StructureRules.maxHp(WALL, 0)).toBe(200)
				expect(StructureRules.maxHp(WALL, 9)).toBe(800)
			end
		)
	end
)

describe(
	"StructureRules.repairChunk",
	function()
		it(
			"is nothing at full HP",
			function()
				local gained, cost = StructureRules.repairChunk(200, 200, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(0)
				expect(cost).toBe(0)
			end
		)
		it(
			"adds a whole chunk for the chunk price",
			function()
				local gained, cost = StructureRules.repairChunk(200, 100, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(10)
				expect(cost).toBe(4)
			end
		)
		it(
			"rebuilds from zero a chunk at a time",
			function()
				local gained, cost = StructureRules.repairChunk(200, 0, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(10)
				expect(cost).toBe(4)
			end
		)
		it(
			"charges a short last chunk its share, rounded up, never under 1",
			function()
				local gained, cost = StructureRules.repairChunk(200, 195, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(5)
				expect(cost).toBe(2)
				gained, cost = StructureRules.repairChunk(200, 197, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(3)
				expect(cost).toBe(2)
				gained, cost = StructureRules.repairChunk(200, 199, CHUNK_HP, CHUNK_IRON)
				expect(gained).toBe(1)
				expect(cost).toBe(1)
			end
		)
	end
)

describe(
	"StructureRules.isRebuilt",
	function()
		it(
			"needs the whole structure at a share of 1",
			function()
				expect(StructureRules.isRebuilt(190, 200, 1)).toBe(false)
				expect(StructureRules.isRebuilt(200, 200, 1)).toBe(true)
			end
		)
		it(
			"stands at the share, and on the first chunk at a share of 0",
			function()
				expect(StructureRules.isRebuilt(90, 200, 0.5)).toBe(false)
				expect(StructureRules.isRebuilt(100, 200, 0.5)).toBe(true)
				expect(StructureRules.isRebuilt(10, 200, 0)).toBe(true)
				expect(StructureRules.isRebuilt(0, 200, 0)).toBe(false)
			end
		)
	end
)

describe(
	"StructureRules.isWithinReach",
	function()
		local bounds = CFrame.new(100, 5, 0)
		local size = Vector3.new(6, 10, 22)
		it(
			"measures to the closest point of the bounds, not the centre",
			function()
				expect(StructureRules.isWithinReach(Vector3.new(90, 5, 10), bounds, size, 12, 0)).toBe(true)
				expect(StructureRules.isWithinReach(Vector3.new(80, 5, 10), bounds, size, 12, 0)).toBe(false)
				expect(StructureRules.isWithinReach(Vector3.new(80, 5, 10), bounds, size, 12, 6)).toBe(true)
			end
		)
		it(
			"counts a player inside the bounds as in reach",
			function()
				expect(StructureRules.isWithinReach(Vector3.new(100, 5, 0), bounds, size, 0, 0)).toBe(true)
			end
		)
	end
)

describe(
	"StructureRules.canSwing",
	function()
		it(
			"allows the first swing and refuses one inside the cooldown",
			function()
				-- quarters are exact in binary, so the boundary case is a real
				-- equality and not a rounding accident
				expect(StructureRules.canSwing(nil, 10, 0.25)).toBe(true)
				expect(StructureRules.canSwing(10, 10.125, 0.25)).toBe(false)
				expect(StructureRules.canSwing(10, 10.25, 0.25)).toBe(true)
			end
		)
	end
)

describe(
	"StructureRules.upgradeCost",
	function()
		it(
			"is the price of the next tier and nil at the top",
			function()
				expect(StructureRules.upgradeCost(UPGRADE_IRON_TO_TIER, 1)).toBe(150)
				expect(StructureRules.upgradeCost(UPGRADE_IRON_TO_TIER, 2)).toBe(400)
				expect(StructureRules.upgradeCost(UPGRADE_IRON_TO_TIER, 3)).toBeNil()
			end
		)
	end
)

describe(
	"StructureRules.hpAfterUpgrade",
	function()
		it(
			"keeps the share of HP, rounded up",
			function()
				expect(StructureRules.hpAfterUpgrade(200, 200, 400)).toBe(400)
				expect(StructureRules.hpAfterUpgrade(100, 200, 400)).toBe(200)
				expect(StructureRules.hpAfterUpgrade(1, 200, 300)).toBe(2)
			end
		)
		it(
			"leaves a destroyed structure destroyed",
			function()
				expect(StructureRules.hpAfterUpgrade(0, 200, 400)).toBe(0)
			end
		)
	end
)

describe(
	"StructureRules.donate",
	function()
		it(
			"moves a whole donation while the pool has room",
			function()
				local amount, isFilled = StructureRules.donate(0, 150, 10)
				expect(amount).toBe(10)
				expect(isFilled).toBe(false)
			end
		)
		it(
			"fills the pool exactly and never past it",
			function()
				local amount, isFilled = StructureRules.donate(140, 150, 10)
				expect(amount).toBe(10)
				expect(isFilled).toBe(true)
				amount, isFilled = StructureRules.donate(148, 150, 10)
				expect(amount).toBe(2)
				expect(isFilled).toBe(true)
			end
		)
		it(
			"moves nothing at the top tier",
			function()
				local amount, isFilled = StructureRules.donate(0, nil, 10)
				expect(amount).toBe(0)
				expect(isFilled).toBe(false)
			end
		)
	end
)

describe(
	"StructureRules.numberFromId",
	function()
		it(
			"reads the trailing number and gives nil without one",
			function()
				expect(StructureRules.numberFromId("Wall3")).toBe(3)
				expect(StructureRules.numberFromId("Wall12")).toBe(12)
				expect(StructureRules.numberFromId("Gate")).toBe(nil)
				expect(StructureRules.numberFromId("Refinery")).toBe(nil)
			end
		)
	end
)

describe(
	"StructureRules.distanceToBox",
	function()
		it(
			"is zero inside and the gap to the nearest face outside, in the box's own frame",
			function()
				local cframe = CFrame.new(10, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
				local size = Vector3.new(4, 2, 8)
				expect(StructureRules.distanceToBox(Vector3.new(10, 0, 0), cframe, size)).toBe(0)
				-- the box's Z axis (8 long) points along world X after the turn
				expect(StructureRules.distanceToBox(Vector3.new(20, 0, 0), cframe, size)).toBeCloseTo(6, 5)
				expect(StructureRules.distanceToBox(Vector3.new(10, 0, 5), cframe, size)).toBeCloseTo(3, 5)
			end
		)
	end
)

describe(
	"StructureRules.requiredCampLevel",
	function()
		it(
			"reads the table and never locks a tier past it",
			function()
				expect(StructureRules.requiredCampLevel({ 1, 2, 3 }, 2)).toBe(2)
				expect(StructureRules.requiredCampLevel({ 1, 2, 3 }, 7)).toBe(1)
			end
		)
	end
)
