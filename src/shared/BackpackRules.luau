--!strict

-- Pure rules for the backpack (GDD "Collecting Ore", "Backpack"): capacity by
-- level, what a broken rock yields for a party of a given size, and how ore
-- fits into a backpack with overflow. Contents are a resource -> ore count
-- table; capacity is counted in ore units, so the HUD's "taken/total" is
-- total ore over capacity.
local Attributes = require(script.Parent.Attributes)
local Enums = require(script.Parent.Enums)
local MiningRules = require(script.Parent.MiningRules)

local BackpackRules = {}

export type Contents = { [number]: number }

-- CurrentPlayer attribute carrying each resource's count
local ATTRIBUTE_BY_RESOURCE: { [number]: string } = {
	[Enums.RawResource.IRON_ORE] = Attributes.BACKPACK_IRON_ORE,
	[Enums.RawResource.GOLD_ORE] = Attributes.BACKPACK_GOLD_ORE,
	[Enums.RawResource.CRYSTAL] = Attributes.BACKPACK_CRYSTAL,
	[Enums.RawResource.URANIUM_ORE] = Attributes.BACKPACK_URANIUM_ORE,
}

function BackpackRules.attributeForResource(resource: number): string?
	return ATTRIBUTE_BY_RESOURCE[resource]
end

function BackpackRules.capacityForLevel(capacityByLevel: { number }, level: number): number
	local clamped = math.clamp(math.floor(level), 1, #capacityByLevel)
	return capacityByLevel[clamped]
end

-- ore a broken rock gives the breaker: Iron and Gold scale with party size
-- (rounded half up), the shared resources never do
function BackpackRules.yieldForBreak(baseYield: number, resource: number, playerCount: number, multiplierByPlayerCount: { number }): number
	if not MiningRules.isYieldScaledByParty(resource) then
		return baseYield
	end
	local multiplier = MiningRules.getOreYieldMultiplier(multiplierByPlayerCount, playerCount)
	return math.floor(baseYield * multiplier + 0.5)
end

function BackpackRules.getTotal(contents: Contents): number
	local total = 0
	for _, amount in contents do
		total += amount
	end
	return total
end

function BackpackRules.isFull(contents: Contents, capacity: number): boolean
	return BackpackRules.getTotal(contents) >= capacity
end

-- adds what fits and returns (added, overflow); contents is mutated
function BackpackRules.add(contents: Contents, capacity: number, resource: number, amount: number): (number, number)
	local room = math.max(0, capacity - BackpackRules.getTotal(contents))
	local added = math.min(room, math.max(0, math.floor(amount)))
	if added > 0 then
		contents[resource] = (contents[resource] or 0) + added
	end
	return added, amount - added
end

-- removes everything and returns what was carried (the refinery's input at M20)
function BackpackRules.takeAll(contents: Contents): Contents
	local taken = table.clone(contents)
	table.clear(contents)
	return taken
end

return BackpackRules
