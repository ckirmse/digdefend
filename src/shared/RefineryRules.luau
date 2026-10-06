--!strict

-- Pure rules for the Refinery (GDD "Refining Ore", "Resources"): which
-- refined resource each ore becomes and at what rate, and the party-scaled
-- Uranium rescue target. Tuning is passed in from GameData so this stays
-- unit testable.
local Enums = require(script.Parent.Enums)

local RefineryRules = {}

export type Contents = { [number]: number }

-- the Enums.RefinedResource each Enums.RawResource refines into
local REFINED_BY_RAW: { [number]: number } = {
	[Enums.RawResource.IRON_ORE] = Enums.RefinedResource.IRON_BAR,
	[Enums.RawResource.GOLD_ORE] = Enums.RefinedResource.GOLD_BAR,
	[Enums.RawResource.URANIUM_ORE] = Enums.RefinedResource.URANIUM,
}
RefineryRules.REFINED_BY_RAW = REFINED_BY_RAW

-- refined units per ore; rates below one floor, so partial units are lost
function RefineryRules.convert(ore: Contents, rateByRaw: { [number]: number }): Contents
	local refined: Contents = {}
	for raw, amount in ore do
		local target = RefineryRules.REFINED_BY_RAW[raw]
		local rate = rateByRaw[raw]
		if not target or not rate or amount <= 0 then
			continue
		end
		local units = math.floor(amount * rate)
		if units > 0 then
			refined[target] = (refined[target] or 0) + units
		end
	end
	return refined
end

-- a scaled target is rounded to the nearest multiple of this (halves up,
-- decided 2026-09-25) so the radio reads 40, never 38; the generator
-- rounds its worst-case supply check the same way
RefineryRules.URANIUM_TARGET_STEP = 5

function RefineryRules.roundUraniumTarget(value: number): number
	local step = RefineryRules.URANIUM_TARGET_STEP
	return math.max(step, math.floor(value / step + 0.5) * step)
end

-- the mine's authored solo target scaled by the difficulty (M31) and the
-- party size, rounded to the nearest URANIUM_TARGET_STEP
function RefineryRules.uraniumTarget(baseTarget: number, playerCount: number, multiplierByPlayerCount: { number }, difficultyMultiplier: number?): number
	local clamped = math.clamp(math.floor(playerCount), 1, #multiplierByPlayerCount)
	return RefineryRules.roundUraniumTarget(baseTarget * multiplierByPlayerCount[clamped] * (difficultyMultiplier or 1))
end

return RefineryRules
