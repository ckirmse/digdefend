-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local StatusRules = require(game:GetService("ReplicatedStorage").Shared.StatusRules)

describe(
	"StatusRules slows",
	function()
		it(
			"takes the strongest active slow and never stacks",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applySlow(effects, 0.3, 5, 100)
				StatusRules.applySlow(effects, 0.5, 2, 100)
				expect(StatusRules.speedMultiplier(effects, 101)).toBeCloseTo(0.5, 5)
				expect(StatusRules.speedMultiplier(effects, 103)).toBeCloseTo(0.7, 5)
				expect(StatusRules.speedMultiplier(effects, 106)).toBe(1)
			end
		)
		it(
			"treats a stun as a full stop and ignores empty slows",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applySlow(effects, 0, 5, 0)
				StatusRules.applySlow(effects, 0.4, 0, 0)
				expect(#effects.slows).toBe(0)
				StatusRules.applyStun(effects, 1, 0)
				expect(StatusRules.isStunned(effects, 0.5)).toBe(true)
				expect(StatusRules.isStunned(effects, 1)).toBe(false)
			end
		)
		it(
			"clamps a share past one",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applySlow(effects, 1.5, 1, 0)
				expect(StatusRules.speedMultiplier(effects, 0)).toBe(0)
			end
		)
	end
)

describe(
	"StatusRules burns",
	function()
		it(
			"owes the rate over the stretch the burn was alive",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applyBurn(effects, 10, 2, 100)
				expect(StatusRules.burnDamage(effects, 100, 100.5)).toBeCloseTo(5, 5)
				expect(StatusRules.burnDamage(effects, 101.5, 103)).toBeCloseTo(5, 5)
				expect(StatusRules.burnDamage(effects, 102.5, 103)).toBe(0)
				expect(StatusRules.isBurning(effects, 101)).toBe(true)
				expect(StatusRules.isBurning(effects, 102)).toBe(false)
			end
		)
		it(
			"restarts the clock at the stronger rate",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applyBurn(effects, 10, 2, 100)
				StatusRules.applyBurn(effects, 4, 5, 101)
				expect(effects.burn.damagePerSec).toBe(10)
				expect(effects.burn.endTime).toBe(106)
				StatusRules.applyBurn(effects, 3, 1, 110)
				expect(effects.burn.damagePerSec).toBe(3)
			end
		)
	end
)

describe(
	"StatusRules.prune",
	function()
		it(
			"drops what ran out and says whether anything is left",
			function()
				local effects = StatusRules.newEffects()
				StatusRules.applySlow(effects, 0.5, 1, 0)
				StatusRules.applyBurn(effects, 1, 3, 0)
				expect(StatusRules.prune(effects, 2)).toBe(true)
				expect(#effects.slows).toBe(0)
				expect(StatusRules.prune(effects, 3)).toBe(false)
				expect(effects.burn).toBeNil()
			end
		)
	end
)

describe(
	"StatusRules.moveToward",
	function()
		it(
			"steps at the slowed speed and arrives exactly",
			function()
				local position, isArrived = StatusRules.moveToward(Vector3.zero, Vector3.new(10, 0, 0), 8, 0.5, 1)
				expect(position.X).toBeCloseTo(4, 5)
				expect(isArrived).toBe(false)
				position, isArrived = StatusRules.moveToward(position, Vector3.new(10, 0, 0), 8, 1, 1)
				expect(position.X).toBe(10)
				expect(isArrived).toBe(true)
			end
		)
		it(
			"stays put when stunned",
			function()
				local position, isArrived = StatusRules.moveToward(Vector3.zero, Vector3.new(10, 0, 0), 8, 0, 1)
				expect(position.X).toBe(0)
				expect(isArrived).toBe(false)
			end
		)
	end
)
