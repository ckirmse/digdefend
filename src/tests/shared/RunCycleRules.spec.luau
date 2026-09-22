-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local RunCycleRules = require(game:GetService("ReplicatedStorage").Shared.RunCycleRules)

describe(
	"RunCycleRules clock",
	function()
		it(
			"runs the bar from full at dawn to empty at night",
			function()
				expect(RunCycleRules.dayShareLeft(100, 400, 100)).toBe(1)
				expect(RunCycleRules.dayShareLeft(100, 400, 250)).toBeCloseTo(0.5, 5)
				expect(RunCycleRules.dayShareLeft(100, 400, 500)).toBe(0)
				-- a day whose start is still ahead (the dawn fade) reads full
				expect(RunCycleRules.dayShareLeft(100, 400, 98)).toBe(1)
				expect(RunCycleRules.dayShareLeft(100, 100, 100)).toBe(0)
			end
		)
		it(
			"shows day, then dusk in the last share, then night",
			function()
				expect(RunCycleRules.clockPhase(Enums.RunState.DAY, 0.5, 0.2)).toBe(Enums.ClockPhase.DAY)
				expect(RunCycleRules.clockPhase(Enums.RunState.DAY, 0.2, 0.2)).toBe(Enums.ClockPhase.DUSK)
				expect(RunCycleRules.clockPhase(Enums.RunState.NIGHT, 1, 0.2)).toBe(Enums.ClockPhase.NIGHT)
				expect(RunCycleRules.clockPhase(Enums.RunState.LOST, 1, 0.2)).toBe(Enums.ClockPhase.NIGHT)
				expect(RunCycleRules.clockPhase(Enums.RunState.WAITING, 1, 0.2)).toBe(Enums.ClockPhase.DAY)
				expect(RunCycleRules.shownDay(0)).toBe(1)
				expect(RunCycleRules.shownDay(3)).toBe(3)
			end
		)
	end
)

describe(
	"RunCycleRules scaling",
	function()
		it(
			"samples the live count but never goes up, and never below one",
			function()
				expect(RunCycleRules.sampleScalingCount(nil, 4, 6)).toBe(4)
				expect(RunCycleRules.sampleScalingCount(4, 6, 6)).toBe(4)
				expect(RunCycleRules.sampleScalingCount(4, 2, 6)).toBe(2)
				expect(RunCycleRules.sampleScalingCount(nil, 0, 6)).toBe(1)
				expect(RunCycleRules.sampleScalingCount(nil, 9, 6)).toBe(6)
			end
		)
		it(
			"reads the multiplier table and clamps to its ends",
			function()
				local table = { 1, 1.15, 1.3 }
				expect(RunCycleRules.multiplierFor(table, 2)).toBeCloseTo(1.15, 5)
				expect(RunCycleRules.multiplierFor(table, 9)).toBeCloseTo(1.3, 5)
				expect(RunCycleRules.multiplierFor(table, 0)).toBe(1)
			end
		)
		it(
			"words the day-start message",
			function()
				local message = RunCycleRules.dayStartMessage("Day %d. Crew of %d. Ore %.2fx, Uranium target %.2fx", 3, 4, 1.45, 1.15)
				expect(message).toBe("Day 3. Crew of 4. Ore 1.45x, Uranium target 1.15x")
			end
		)
	end
)

describe(
	"RunCycleRules sky",
	function()
		it(
			"runs day start into day end over the day",
			function()
				local stage, share = RunCycleRules.skyStage(Enums.RunState.WAITING, 100, 400, 50, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.DAY)
				expect(share).toBe(0)
				stage, share = RunCycleRules.skyStage(Enums.RunState.DAY, 100, 400, 250, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.DAY)
				expect(share).toBeCloseTo(0.5, 5)
				stage, share = RunCycleRules.skyStage(Enums.RunState.DAY, 100, 400, 400, 2, 2, 90)
				expect(share).toBe(1)
			end
		)
		it(
			"opens a night with the dusk blend, then night start into night end over the spawn window, and holds",
			function()
				local stage, share = RunCycleRules.skyStage(Enums.RunState.NIGHT, 500, 0, 500, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.DUSK)
				expect(share).toBe(0)
				stage, share = RunCycleRules.skyStage(Enums.RunState.NIGHT, 500, 0, 501, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.DUSK)
				expect(share).toBeCloseTo(0.5, 5)
				stage, share = RunCycleRules.skyStage(Enums.RunState.NIGHT, 500, 0, 502, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.NIGHT)
				expect(share).toBe(0)
				stage, share = RunCycleRules.skyStage(Enums.RunState.NIGHT, 500, 0, 547, 2, 2, 90)
				expect(share).toBeCloseTo(0.5, 5)
				stage, share = RunCycleRules.skyStage(Enums.RunState.NIGHT, 500, 0, 900, 2, 2, 90)
				expect(share).toBe(1)
				stage, share = RunCycleRules.skyStage(Enums.RunState.LOST, 500, 0, 503, 2, 2, 0)
				expect(stage).toBe(Enums.SkyStage.NIGHT)
				expect(share).toBe(1)
			end
		)
		it(
			"runs night end back to day start during the dawn stretch before the day starts",
			function()
				local stage, share = RunCycleRules.skyStage(Enums.RunState.DAY, 100, 400, 98, 2, 2, 90)
				expect(stage).toBe(Enums.SkyStage.DAWN)
				expect(share).toBe(0)
				stage, share = RunCycleRules.skyStage(Enums.RunState.DAY, 100, 400, 99, 2, 2, 90)
				expect(share).toBeCloseTo(0.5, 5)
				stage, share = RunCycleRules.skyStage(Enums.RunState.DAY, 100, 400, 99.9, 0, 2, 90)
				expect(share).toBe(1)
			end
		)
		it(
			"turns the clock forward between two hours, wrapping at midnight",
			function()
				expect(RunCycleRules.clockTimeBetween(8, 20, 0.5)).toBeCloseTo(14, 5)
				expect(RunCycleRules.clockTimeBetween(20, 8, 0.5)).toBeCloseTo(2, 5)
				expect(RunCycleRules.clockTimeBetween(20, 8, 1)).toBeCloseTo(8, 5)
				expect(RunCycleRules.clockTimeBetween(8, 20, 0)).toBe(8)
			end
		)
	end
)

describe(
	"RunCycleRules night",
	function()
		it(
			"ends a placeholder night after the spawn window plus the placeholder, never at zero",
			function()
				expect(RunCycleRules.isNightOver(100, 219, 90, 30)).toBe(false)
				expect(RunCycleRules.isNightOver(100, 220, 90, 30)).toBe(true)
				expect(RunCycleRules.isNightOver(100, 10000, 90, 0)).toBe(false)
			end
		)
		it(
			"knows a finished run",
			function()
				expect(RunCycleRules.isRunOver(Enums.RunState.DAY)).toBe(false)
				expect(RunCycleRules.isRunOver(Enums.RunState.LOST)).toBe(true)
				expect(RunCycleRules.isRunOver(Enums.RunState.WON)).toBe(true)
			end
		)
	end
)
