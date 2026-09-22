--!strict

-- Pure rules for the day and night loop (GDD "Wave Cycle", "Adjusting for
-- Different Player Counts"), M28: when a day ends, which picture the
-- clock shows, how full the bar is, how the crew size is sampled (only
-- ever down), and the words of the day-start message. The server
-- (RunCycleManager) decides with these from server time; the client
-- (ClientRunCycleManager) draws the same clock from the published times.
local Enums = require(script.Parent.Enums)

local RunCycleRules = {}

-- the share of the day still to run, 1 at dawn and 0 at dusk's end
function RunCycleRules.dayShareLeft(dayStartTime: number, dayEndTime: number, now: number): number
	local length = dayEndTime - dayStartTime
	if length <= 0 then
		return 0
	end
	return math.clamp((dayEndTime - now) / length, 0, 1)
end

-- which of the clock's three pictures shows: day while the crew lands
-- and through a day until its last duskShare, which is dusk; night for
-- a night and for a run that is over
function RunCycleRules.clockPhase(runState: number, dayShareLeft: number, duskShare: number): number
	if runState == Enums.RunState.WAITING then
		return Enums.ClockPhase.DAY
	end
	if runState ~= Enums.RunState.DAY then
		return Enums.ClockPhase.NIGHT
	end
	if dayShareLeft <= duskShare then
		return Enums.ClockPhase.DUSK
	end
	return Enums.ClockPhase.DAY
end

-- the crew size that scales the run: the live count, capped by the last
-- sample so it only ever goes down, and never below one
function RunCycleRules.sampleScalingCount(previousCount: number?, liveCount: number, maxCount: number): number
	local count = math.clamp(liveCount, 1, maxCount)
	if previousCount then
		count = math.min(count, previousCount)
	end
	return count
end

-- a multiplier table indexed by crew size; the last entry covers any bigger crew
function RunCycleRules.multiplierFor(multipliersByCount: { number }, count: number): number
	local index = math.clamp(math.floor(count), 1, #multipliersByCount)
	return multipliersByCount[index] or 1
end

function RunCycleRules.dayStartMessage(format: string, day: number, crewCount: number, oreMultiplier: number, uraniumMultiplier: number): string
	return string.format(format, day, crewCount, oreMultiplier, uraniumMultiplier)
end

-- whether a night has run its placeholder course: the spawn window plus
-- the placeholder length, or never when the placeholder is 0 (M29: only
-- the enemies end a night)
function RunCycleRules.isNightOver(nightStartTime: number, now: number, spawnSec: number, placeholderSec: number): boolean
	if placeholderSec <= 0 then
		return false
	end
	return now - nightStartTime >= spawnSec + placeholderSec
end

-- the day number the clock shows: 1 while the crew is still landing
function RunCycleRules.shownDay(day: number): number
	return math.max(math.floor(day), 1)
end

-- which two looks the sky is between and how far along (Enums.SkyStage,
-- 0 to 1): the DAY stage runs day start into day end over the day (the
-- crew landing sits at its start); a night opens with the DUSK stage,
-- day end into night start over duskTransitionSec, then the NIGHT stage
-- runs night start into night end over the spawn window and holds the
-- end until the wave is done (and after the run); the DAWN stage, the
-- stretch before a day's start, runs night end back to day start
function RunCycleRules.skyStage(runState: number, phaseStartTime: number, phaseEndTime: number, now: number, dawnTransitionSec: number, duskTransitionSec: number, spawnSec: number): (number, number)
	if runState == Enums.RunState.WAITING then
		return Enums.SkyStage.DAY, 0
	end
	if runState ~= Enums.RunState.DAY then
		local elapsed = now - phaseStartTime
		if elapsed < duskTransitionSec then
			return Enums.SkyStage.DUSK, math.clamp(elapsed / duskTransitionSec, 0, 1)
		end
		if spawnSec <= 0 then
			return Enums.SkyStage.NIGHT, 1
		end
		return Enums.SkyStage.NIGHT, math.clamp((elapsed - duskTransitionSec) / spawnSec, 0, 1)
	end
	if now < phaseStartTime then
		if dawnTransitionSec <= 0 then
			return Enums.SkyStage.DAWN, 1
		end
		return Enums.SkyStage.DAWN, 1 - math.clamp((phaseStartTime - now) / dawnTransitionSec, 0, 1)
	end
	return Enums.SkyStage.DAY, 1 - RunCycleRules.dayShareLeft(phaseStartTime, phaseEndTime, now)
end

-- the hour between two hours, turning forward only (wrapping at 24), so
-- morning to night crosses noon and night to morning crosses midnight
function RunCycleRules.clockTimeBetween(fromClockTime: number, toClockTime: number, share: number): number
	local forward = (toClockTime - fromClockTime) % 24
	return (fromClockTime + forward * math.clamp(share, 0, 1)) % 24
end

function RunCycleRules.isRunOver(runState: number): boolean
	return runState == Enums.RunState.WON or runState == Enums.RunState.LOST
end

return RunCycleRules
