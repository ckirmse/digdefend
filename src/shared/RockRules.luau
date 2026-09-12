--!strict

-- Pure rules behind mine generation (GDD "The weight kernel" and
-- "Difficulty"): the weights kernel that both hardness and tierBias compress
-- through, the difficulty transform, and validation of the global rock table.
-- Tuning (spread, difficulty values, hardness shift) is passed in from
-- GameData/Rocks/Weights and GameData/Control/Difficulty so this module stays
-- free of GameData and unit testable.
local Enums = require(script.Parent.Enums)
local Validate = require(script.Parent.Validate)

local RockRules = {}

export type RockDefinition = {
	kind: number,
	hp: number?,
	resource: number?,
	tier: number?,
	yield: number?,
	clusterRadiusMin: number?,
	clusterRadiusMax: number?,
}

export type RockTable = {
	FILLER_ORDER: { number },
	RESOURCE_TIERS: { [number]: { number } },
	ROCKS: { [number]: RockDefinition },
}

local FILLER_SHAPE = {
	kind = { type = "enum", name = "RockKind" },
	hp = "positiveNumber",
}

local RESOURCE_SHAPE = {
	kind = { type = "enum", name = "RockKind" },
	hp = "positiveNumber",
	resource = { type = "enum", name = "RawResource" },
	tier = "positiveInteger",
	yield = "positiveNumber",
	clusterRadiusMin = "nonnegativeInteger",
	clusterRadiusMax = "nonnegativeInteger",
}

local STRUCTURAL_SHAPE = {
	kind = { type = "enum", name = "RockKind" },
}

local REMAINDER_TIE_EPSILON = 1e-9

-- Triangular kernel centred on `center` over categories 1..count, normalised
-- to sum to 1. spread is the half-width: a category further than spread from
-- the center gets zero weight.
function RockRules.weights(center: number, count: number, spread: number): { number }
	local raw = table.create(count, 0)
	local total = 0
	for index = 1, count do
		local weight = math.max(0, 1 - math.abs(index - center) / spread)
		raw[index] = weight
		total += weight
	end
	if total <= 0 then
		-- only reachable with a center far outside 1..count; fall back to the
		-- nearest category rather than dividing by zero
		local nearest = math.clamp(math.round(center), 1, count)
		raw[nearest] = 1
		total = 1
	end
	for index = 1, count do
		raw[index] /= total
	end
	return raw
end

-- Returns the clamped center and whether clamping happened, so the generator
-- can warn naming the parameter and chamber (GDD "Validation").
function RockRules.clampCenter(value: number, minCenter: number, maxCenter: number): (number, boolean)
	local clamped = math.clamp(value, minCenter, maxCenter)
	return clamped, clamped ~= value
end

-- hardness -> { [rockName]: probability } over the filler rocks in table order
function RockRules.resolveHardnessWeights(hardness: number, fillerOrder: { number }, spread: number): { [number]: number }
	local weights = RockRules.weights(hardness, #fillerOrder, spread)
	local byRock = {}
	for index, rockName in fillerOrder do
		byRock[rockName] = weights[index]
	end
	return byRock
end

-- Splits an integer cluster count across tiers by tierBias. Largest-remainder
-- rounding so the parts always sum to exactly `count`.
function RockRules.resolveTierCounts(count: number, tierBias: number, tierCount: number, spread: number): { number }
	local weights = RockRules.weights(tierBias, tierCount, spread)
	local counts = table.create(tierCount, 0)
	local remainders: { { tier: number, remainder: number } } = {}
	local assigned = 0
	for tier = 1, tierCount do
		local exact = weights[tier] * count
		local whole = math.floor(exact)
		counts[tier] = whole
		assigned += whole
		table.insert(remainders, { tier = tier, remainder = exact - whole })
	end
	table.sort(
		remainders,
		function(a: { tier: number, remainder: number }, b: { tier: number, remainder: number })
			-- normalised weights carry float noise, so a 7.5 / 2.5 split must
			-- still count as a tie and go to the lower tier
			if math.abs(a.remainder - b.remainder) < REMAINDER_TIE_EPSILON then
				return a.tier < b.tier
			end
			return a.remainder > b.remainder
		end
	)
	local leftover = count - assigned
	for index = 1, leftover do
		local tier = remainders[index].tier
		counts[tier] += 1
	end
	return counts
end

-- Picks an index from a normalised weights array with the given Random. The
-- last non-zero weight absorbs floating-point slack so a roll never misses.
function RockRules.pickWeightedIndex(random: Random, weights: { number }): number
	local roll = random:NextNumber()
	local cumulative = 0
	local lastNonZero = 1
	for index, weight in weights do
		if weight <= 0 then
			continue
		end
		lastNonZero = index
		cumulative += weight
		if roll < cumulative then
			return index
		end
	end
	return lastNonZero
end

function RockRules.effectiveHardness(
	hardness: number,
	difficultyValue: number,
	hardnessShift: number,
	minCenter: number,
	maxCenter: number
): number
	return math.clamp(hardness + (difficultyValue - 1) * hardnessShift, minCenter, maxCenter)
end

-- round half up, so 15.5 clusters become 16 rather than rounding to even
function RockRules.effectiveVeinCount(baseCount: number, difficultyValue: number): number
	return math.floor(baseCount / difficultyValue + 0.5)
end

-- Validates the global rock table so a bad data edit fails loudly at startup
-- rather than as a silent hole in a mine. Returns (isValid, message).
function RockRules.validateRockTable(rockTable: any): (boolean, string?)
	if typeof(rockTable) ~= "table" then
		return false, "rock table is not a table"
	end
	if not Validate.isArray(rockTable.FILLER_ORDER) or #rockTable.FILLER_ORDER == 0 then
		return false, "FILLER_ORDER must be a non-empty array"
	end
	if typeof(rockTable.RESOURCE_TIERS) ~= "table" then
		return false, "RESOURCE_TIERS must be a table"
	end
	if typeof(rockTable.ROCKS) ~= "table" then
		return false, "ROCKS must be a table"
	end

	local rocks = rockTable.ROCKS
	for _, rockName in Enums.getAllValues(Enums.RockName) do
		local definition = rocks[rockName]
		local label = Enums.getName(Enums.RockName, rockName) or tostring(rockName)
		if definition == nil then
			return false, "ROCKS is missing " .. label
		end
		local shape
		if definition.kind == Enums.RockKind.FILLER then
			shape = FILLER_SHAPE
		elseif definition.kind == Enums.RockKind.RESOURCE then
			shape = RESOURCE_SHAPE
		elseif definition.kind == Enums.RockKind.BEDROCK or definition.kind == Enums.RockKind.GATE then
			shape = STRUCTURAL_SHAPE
		else
			return false, label .. " has unknown kind " .. tostring(definition.kind)
		end
		local isShapeValid, shapeMessage = Validate.isTableShape(definition, shape)
		if not isShapeValid then
			return false, label .. ": " .. tostring(shapeMessage)
		end
		if definition.kind == Enums.RockKind.RESOURCE and definition.clusterRadiusMax < definition.clusterRadiusMin then
			return false, label .. " cluster radius range is invalid"
		end
	end
	for rockName in rocks do
		if not Enums.isValidValue(Enums.RockName, rockName) then
			return false, "ROCKS has an entry that is not a RockName: " .. tostring(rockName)
		end
	end

	local previousHp = 0
	for index, rockName in rockTable.FILLER_ORDER do
		local definition = rocks[rockName]
		local label = Enums.getName(Enums.RockName, rockName) or tostring(rockName)
		if definition == nil or definition.kind ~= Enums.RockKind.FILLER then
			return false, "FILLER_ORDER entry " .. index .. " (" .. label .. ") is not a filler rock"
		end
		if definition.hp <= previousHp then
			return false, "FILLER_ORDER must be sorted by ascending hp; " .. label .. " breaks the order"
		end
		previousHp = definition.hp
	end

	for _, resource in Enums.getAllValues(Enums.RawResource) do
		local tiers = rockTable.RESOURCE_TIERS[resource]
		local resourceLabel = Enums.getName(Enums.RawResource, resource) or tostring(resource)
		if not Validate.isArray(tiers) or #tiers == 0 then
			return false, "RESOURCE_TIERS is missing " .. resourceLabel
		end
		for tier, rockName in tiers do
			local definition = rocks[rockName]
			local label = Enums.getName(Enums.RockName, rockName) or tostring(rockName)
			if definition == nil or definition.kind ~= Enums.RockKind.RESOURCE then
				return false, resourceLabel .. " tier " .. tier .. " (" .. label .. ") is not a resource rock"
			end
			if definition.resource ~= resource then
				return false, label .. " is listed under " .. resourceLabel .. " but yields another resource"
			end
			if definition.tier ~= tier then
				return false, label .. " is at tier position " .. tier .. " but declares tier " .. tostring(definition.tier)
			end
		end
	end

	return true, nil
end

return RockRules
