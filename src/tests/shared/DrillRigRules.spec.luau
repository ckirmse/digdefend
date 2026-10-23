-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DrillRigRules = require(game:GetService("ReplicatedStorage").Shared.DrillRigRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local IRON = Enums.RawResource.IRON_ORE
local GOLD = Enums.RawResource.GOLD_ORE
local SHARES = {
	{ RESOURCE = IRON, SHARE = 0.75 },
	{ RESOURCE = GOLD, SHARE = 0.25 },
}

describe(
	"DrillRigRules.accumulate",
	function()
		it(
			"splits a minute's yield by the shares",
			function()
				local stock = DrillRigRules.accumulate({}, 4, SHARES, 60, 20)
				expect(stock[IRON]).toBeCloseTo(3, 6)
				expect(stock[GOLD]).toBeCloseTo(1, 6)
				expect(DrillRigRules.total(stock)).toBeCloseTo(4, 6)
			end
		)

		it(
			"stops at the cap and adds nothing to a full rig",
			function()
				local stock = DrillRigRules.accumulate({ [IRON] = 18 }, 4, SHARES, 600, 20)
				expect(DrillRigRules.total(stock)).toBeCloseTo(20, 6)
				local still = DrillRigRules.accumulate(stock, 4, SHARES, 60, 20)
				expect(DrillRigRules.total(still)).toBeCloseTo(20, 6)
			end
		)

		it(
			"leaves the stock alone for no time, no yield, or no shares",
			function()
				expect(DrillRigRules.total(DrillRigRules.accumulate({}, 4, SHARES, 0, 20))).toBe(0)
				expect(DrillRigRules.total(DrillRigRules.accumulate({}, 0, SHARES, 60, 20))).toBe(0)
				expect(DrillRigRules.total(DrillRigRules.accumulate({}, 4, {}, 60, 20))).toBe(0)
			end
		)
	end
)

describe(
	"DrillRigRules stock units",
	function()
		it(
			"hands out whole units and keeps the fraction",
			function()
				local stock = { [IRON] = 2.6, [GOLD] = 0.4 }
				expect(DrillRigRules.wholeUnits(stock)).toEqual({ [IRON] = 2 })
				local after = DrillRigRules.take(stock, IRON, 2)
				expect(after[IRON]).toBeCloseTo(0.6, 6)
				expect(DrillRigRules.take(after, IRON, 5)[IRON]).toBe(0)
			end
		)

		it(
			"round-trips the whole units through the attribute",
			function()
				local stock = { [IRON] = 2.6, [GOLD] = 3 }
				local decoded = DrillRigRules.decodeStock(DrillRigRules.encodeStock(stock))
				expect(decoded).toEqual({ [IRON] = 2, [GOLD] = 3 })
				expect(DrillRigRules.decodeStock("")).toEqual({})
				expect(DrillRigRules.decodeStock("not json")).toEqual({})
				expect(DrillRigRules.decodeStock([=[[{"resource": 99, "amount": 1}]]=])).toEqual({})
			end
		)
	end
)
