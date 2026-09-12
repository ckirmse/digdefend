-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local MiningRules = require(game:GetService("ReplicatedStorage").Shared.MiningRules)

-- mirrors GameData/Mining/PickAxe and GameData/Control/PartyScaling
local DAMAGE_BY_LEVEL = { 5, 12, 25, 50 }
local ORE_YIELD_BY_COUNT = { 1.0, 1.15, 1.3, 1.45, 1.6, 1.75 }

describe(
	"MiningRules.damageForLevel",
	function()
		it(
			"reads the level's damage and clamps out-of-range levels",
			function()
				expect(MiningRules.damageForLevel(DAMAGE_BY_LEVEL, 1)).toBe(5)
				expect(MiningRules.damageForLevel(DAMAGE_BY_LEVEL, 4)).toBe(50)
				expect(MiningRules.damageForLevel(DAMAGE_BY_LEVEL, 0)).toBe(5)
				expect(MiningRules.damageForLevel(DAMAGE_BY_LEVEL, 9)).toBe(50)
				expect(MiningRules.damageForLevel(DAMAGE_BY_LEVEL, 2.7)).toBe(12)
			end
		)
	end
)

describe(
	"MiningRules hit checks",
	function()
		it(
			"accepts a block within reach plus tolerance and rejects one beyond",
			function()
				local player = Vector3.new(0, 0, 0)
				expect(MiningRules.isWithinReach(player, Vector3.new(12, 0, 0), 12, 4)).toBe(true)
				expect(MiningRules.isWithinReach(player, Vector3.new(16, 0, 0), 12, 4)).toBe(true)
				expect(MiningRules.isWithinReach(player, Vector3.new(16.5, 0, 0), 12, 4)).toBe(false)
			end
		)

		it(
			"enforces the cooldown from the last hit",
			function()
				expect(MiningRules.canHit(nil, 100, 0.4)).toBe(true)
				expect(MiningRules.canHit(100, 100.3, 0.4)).toBe(false)
				expect(MiningRules.canHit(100, 100.4, 0.4)).toBe(true)
			end
		)
	end
)

describe(
	"MiningRules.crackStage",
	function()
		it(
			"follows the GDD thresholds of 60% and 30%",
			function()
				expect(MiningRules.crackStage(100, 100)).toBe(0)
				expect(MiningRules.crackStage(61, 100)).toBe(0)
				expect(MiningRules.crackStage(60, 100)).toBe(1)
				expect(MiningRules.crackStage(31, 100)).toBe(1)
				expect(MiningRules.crackStage(30, 100)).toBe(2)
				expect(MiningRules.crackStage(1, 100)).toBe(2)
				expect(MiningRules.crackStage(5, 0)).toBe(0)
			end
		)
	end
)

describe(
	"MiningRules tool slots codec",
	function()
		it(
			"round-trips a slot list and drops anything that is not a tool",
			function()
				local slots = { Enums.ToolKind.PICK_AXE, Enums.ToolKind.WEAPON }
				expect(MiningRules.decodeToolSlots(MiningRules.encodeToolSlots(slots))).toEqual(slots)
				expect(MiningRules.decodeToolSlots(MiningRules.encodeToolSlots({}))).toEqual({})
				expect(MiningRules.decodeToolSlots("[1, 99, \"x\"]")).toEqual({ Enums.ToolKind.PICK_AXE })
				expect(MiningRules.decodeToolSlots(nil)).toEqual({})
				expect(MiningRules.decodeToolSlots("not json")).toEqual({})
			end
		)
	end
)

describe(
	"MiningRules party yield",
	function()
		it(
			"looks up the multiplier by party size and clamps",
			function()
				expect(MiningRules.getOreYieldMultiplier(ORE_YIELD_BY_COUNT, 1)).toBe(1.0)
				expect(MiningRules.getOreYieldMultiplier(ORE_YIELD_BY_COUNT, 4)).toBe(1.45)
				expect(MiningRules.getOreYieldMultiplier(ORE_YIELD_BY_COUNT, 6)).toBe(1.75)
				expect(MiningRules.getOreYieldMultiplier(ORE_YIELD_BY_COUNT, 0)).toBe(1.0)
				expect(MiningRules.getOreYieldMultiplier(ORE_YIELD_BY_COUNT, 12)).toBe(1.75)
			end
		)

		it(
			"scales only Iron and Gold",
			function()
				expect(MiningRules.isYieldScaledByParty(Enums.RawResource.IRON_ORE)).toBe(true)
				expect(MiningRules.isYieldScaledByParty(Enums.RawResource.GOLD_ORE)).toBe(true)
				expect(MiningRules.isYieldScaledByParty(Enums.RawResource.CRYSTAL)).toBe(false)
				expect(MiningRules.isYieldScaledByParty(Enums.RawResource.URANIUM_ORE)).toBe(false)
			end
		)
	end
)
