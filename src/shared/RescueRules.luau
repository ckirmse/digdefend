--!strict

-- Pure rules for the rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31:
-- when the radio may be used, which night the final wave is, when the
-- landed helicopter leaves, who wins, and whether a win counts toward a
-- player's own progression. RescueManager runs the flow with these.
local RescueRules = {}

-- the radio works once the crew has refined the target; a target of 0
-- means the run has no mine to win with
function RescueRules.isTargetReached(uraniumTotal: number, uraniumTarget: number): boolean
	return uraniumTarget > 0 and uraniumTotal >= uraniumTarget
end

-- the final wave is the night after the current day's, so it is always a
-- step up from whatever the crew last faced
function RescueRules.finalWaveNight(day: number): number
	return math.max(math.floor(day), 1) + 1
end

-- the helicopter leaves once everyone still standing is aboard, or
-- timeoutSec after landing with at least one aboard; with nobody aboard it
-- waits (decided 2026-09-24)
function RescueRules.shouldDepart(aboardCount: number, livingCount: number, landedTime: number, now: number, timeoutSec: number): boolean
	if aboardCount <= 0 then
		return false
	end
	return aboardCount >= livingCount or now - landedTime >= timeoutSec
end

-- a completion counts only for a player who already holds every
-- prerequisite themselves: a player carried through Nightmare by a friend
-- does not unlock Nightmare (GDD "Progression on completion")
function RescueRules.canRecordCompletion(hasCompletion: (completionKey: string) -> boolean, requirementKeys: { string }): boolean
	for _, key in requirementKeys do
		if not hasCompletion(key) then
			return false
		end
	end
	return true
end

-- the winning line: everyone, or the names of those who made it
function RescueRules.wonMessage(aboardNames: { string }, crewCount: number, allFormat: string, someFormat: string): string
	if #aboardNames >= crewCount then
		return allFormat
	end
	return string.format(someFormat, table.concat(aboardNames, ", "))
end

return RescueRules
