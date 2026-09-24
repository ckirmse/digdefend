--!strict

-- Pure rules for the Refinery (GDD "Refining Ore", "Resources", "Camp
-- Level"): which refined resource each ore becomes and at what rate, how
-- Diamonds fill the shared Camp Level like an XP bar, and the party-scaled
-- Uranium rescue target. Tuning is passed in from GameData so this stays
-- unit testable.
local Enums = require(script.Parent.Enums)

local RefineryRules = {}

export type Contents = { [number]: number }

-- the Enums.RefinedResource each Enums.RawResource refines into
local REFINED_BY_RAW: { [number]: number } = {
	[Enums.RawResource.IRON_ORE] = Enums.RefinedResource.IRON_BAR,
	[Enums.RawResource.GOLD_ORE] = Enums.RefinedResource.GOLD_BAR,
	[Enums.RawResource.CRYSTAL] = Enums.RefinedResource.DIAMOND,
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

-- Diamonds needed to go from `level` to the next one; nil at the top level
function RefineryRules.diamondsRequired(requiredByLevel: { number }, level: number): number?
	return requiredByLevel[math.floor(level)]
end

-- Adds Diamonds to the shared pool and rolls over full bars into levels, so
-- the pool always reads as progress toward the next level. Returns the new
-- level, the remaining pool, and how many levels were gained.
function RefineryRules.applyDiamonds(level: number, pool: number, added: number, requiredByLevel: { number }): (number, number, number)
	local newLevel = level
	local newPool = pool + math.max(0, math.floor(added))
	local gained = 0
	while true do
		local required = RefineryRules.diamondsRequired(requiredByLevel, newLevel)
		if required == nil or newPool < required then
			break
		end
		newPool -= required
		newLevel += 1
		gained += 1
	end
	if RefineryRules.diamondsRequired(requiredByLevel, newLevel) == nil then
		-- at the top there is nothing to progress toward
		newPool = 0
	end
	return newLevel, newPool, gained
end

-- the mine's authored solo target scaled by the difficulty (M31) and the
-- party size, rounded half up
function RefineryRules.uraniumTarget(baseTarget: number, playerCount: number, multiplierByPlayerCount: { number }, difficultyMultiplier: number?): number
	local clamped = math.clamp(math.floor(playerCount), 1, #multiplierByPlayerCount)
	return math.floor(baseTarget * multiplierByPlayerCount[clamped] * (difficultyMultiplier or 1) + 0.5)
end

return RefineryRules
