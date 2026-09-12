--!strict

-- Pure mine generator (GDD "Randomized Mine Creation"). Turns a mine
-- definition plus difficulty and seed into a grid of RockName integers in the
-- mine's local space (depth into the mountain, height up, width across), and
-- a report the designer can read. World placement is not this module's job.
-- Tuning and the rock table are passed in as a config so the module stays
-- free of GameData and unit testable; the server assembles the config from
-- GameData/Rocks, GameData/Control/Difficulty, and GameData/Mines/Generation.
local Enums = require(script.Parent.Enums)
local RockRules = require(script.Parent.RockRules)

local MineGenerator = {}

MineGenerator.AIR = 0
MineGenerator.CORRIDOR_HEIGHT_FULL = "full"

-- seeds drawn for a nil-seed run stay well inside Random's integer range
local MAX_DRAWN_SEED = 2 ^ 31 - 1
-- keeps chamber sub-seeds apart so editing one chamber never reshuffles another
local CHAMBER_SEED_STRIDE = 1000003

export type HandPlaced = {
	rock: number,
	depth: number,
	height: number,
	widthOffset: number,
	cluster: number?,
}

export type ChamberDefinition = {
	depth: number?,
	height: number?,
	width: number?,
	hardness: number?,
	tierBias: number?,
	iron: number?,
	gold: number?,
	crystal: number?,
	uranium: number?,
	corridorWidth: number?,
	corridorHeight: (number | string)?,
	handPlaced: { HandPlaced }?,
}

export type BedrockOverrides = {
	front: number?,
	far: number?,
	floor: number?,
	ceiling: number?,
	side: number?,
	divider: number?,
}

export type MineDefinition = {
	mineId: string,
	seed: number?,
	origin: Vector3,
	facing: number,
	startingCampLevel: number,
	bedrockThickness: number,
	bedrockOverrides: BedrockOverrides?,
	veinCorridorClearance: number,
	uraniumTarget: number,
	defaultChamberHeight: number,
	defaultChamberWidth: number,
	chambers: { ChamberDefinition },
}

export type GeneratorConfig = {
	rockTable: RockRules.RockTable,
	spread: number,
	minCenter: number,
	maxCenter: number,
	hardnessShift: number,
	difficultyValue: number,
	veinDivisor: number,
	pickaxeReachBlocks: number,
	isClimbingEnabled: boolean,
	maxPartyUraniumTargetMultiplier: number,
}

-- a chamber after inheritance and difficulty, in grid coordinates (0-based)
export type ResolvedChamber = {
	index: number,
	unlockCampLevel: number,
	hasCorridor: boolean,
	depth: number,
	height: number,
	width: number,
	hardness: number,
	tierBias: number,
	veins: { [number]: number },
	corridorWidth: number,
	corridorHeight: number,
	handPlaced: { HandPlaced },
	depthStart: number,
	heightStart: number,
	widthStart: number,
	corridorWidthStart: number,
}

export type MineGrid = {
	depth: number,
	height: number,
	width: number,
	cells: { number },
}

export type ChamberReport = {
	index: number,
	diggableVolume: number,
	reachableShare: number,
	requestedOre: { [number]: number },
	placedOre: { [number]: number },
	placedHp: number,
	-- uranium rocks in this and every earlier chamber, so the designer can
	-- see the progression toward uraniumTarget
	uraniumSoFar: number,
}

export type Report = {
	seed: number,
	gridDepth: number,
	gridHeight: number,
	gridWidth: number,
	chambers: { ChamberReport },
}

export type GenerateResult = {
	grid: MineGrid,
	chambers: { ResolvedChamber },
	report: Report,
}

type Box = {
	depthStart: number,
	depthEnd: number,
	heightStart: number,
	heightEnd: number,
	widthStart: number,
	widthEnd: number,
}

type Bedrock = {
	front: number,
	far: number,
	floor: number,
	ceiling: number,
	side: number,
	divider: number,
}

local RESOURCE_FIELDS = {
	{ field = "iron", resource = Enums.RawResource.IRON_ORE },
	{ field = "gold", resource = Enums.RawResource.GOLD_ORE },
	{ field = "crystal", resource = Enums.RawResource.CRYSTAL },
	{ field = "uranium", resource = Enums.RawResource.URANIUM_ORE },
}

local INHERITED_FIELDS = {
	"depth",
	"height",
	"width",
	"hardness",
	"tierBias",
	"iron",
	"gold",
	"crystal",
	"uranium",
	"corridorWidth",
	"corridorHeight",
}

local REQUIRED_FIRST_CHAMBER_FIELDS = { "depth", "corridorWidth", "corridorHeight" }

function MineGenerator.cellIndex(grid: MineGrid, depth: number, height: number, width: number): number
	return (depth * grid.height + height) * grid.width + width + 1
end

function MineGenerator.getCell(grid: MineGrid, depth: number, height: number, width: number): number
	return grid.cells[MineGenerator.cellIndex(grid, depth, height, width)]
end

local function setCell(grid: MineGrid, depth: number, height: number, width: number, rock: number)
	grid.cells[MineGenerator.cellIndex(grid, depth, height, width)] = rock
end

local function isInBox(box: Box, depth: number, height: number, width: number): boolean
	return depth >= box.depthStart
		and depth <= box.depthEnd
		and height >= box.heightStart
		and height <= box.heightEnd
		and width >= box.widthStart
		and width <= box.widthEnd
end

local function expandBox(box: Box, amount: number): Box
	return {
		depthStart = box.depthStart - amount,
		depthEnd = box.depthEnd + amount,
		heightStart = box.heightStart - amount,
		heightEnd = box.heightEnd + amount,
		widthStart = box.widthStart - amount,
		widthEnd = box.widthEnd + amount,
	}
end

local function chamberBox(chamber: ResolvedChamber): Box
	return {
		depthStart = chamber.depthStart,
		depthEnd = chamber.depthStart + chamber.depth - 1,
		heightStart = chamber.heightStart,
		heightEnd = chamber.heightStart + chamber.height - 1,
		widthStart = chamber.widthStart,
		widthEnd = chamber.widthStart + chamber.width - 1,
	}
end

-- the corridor volume inside the chamber itself (not the divider it leads into)
local function corridorBox(chamber: ResolvedChamber): Box
	return {
		depthStart = chamber.depthStart,
		depthEnd = chamber.depthStart + chamber.depth - 1,
		heightStart = chamber.heightStart,
		heightEnd = chamber.heightStart + chamber.corridorHeight - 1,
		widthStart = chamber.corridorWidthStart,
		widthEnd = chamber.corridorWidthStart + chamber.corridorWidth - 1,
	}
end

-- number of cells in a discrete sphere of the given radius
function MineGenerator.clusterCellCount(radius: number): number
	local count = 0
	for dd = -radius, radius do
		for dh = -radius, radius do
			for dw = -radius, radius do
				if dd * dd + dh * dh + dw * dw <= radius * radius then
					count += 1
				end
			end
		end
	end
	return count
end

local function resolveBedrock(definition: MineDefinition): Bedrock
	local base = definition.bedrockThickness
	local overrides: BedrockOverrides = definition.bedrockOverrides or {}
	return {
		front = overrides.front or base,
		far = overrides.far or base,
		floor = overrides.floor or base,
		ceiling = overrides.ceiling or base,
		side = overrides.side or base,
		divider = overrides.divider or base,
	}
end

-- a span of `size` blocks centred on `centreline`; an even size leans one
-- block toward positive width (GDD "Corridors")
local function centredSpanStart(centreline: number, size: number): number
	return centreline - math.floor((size - 1) / 2)
end

local function chamberLabel(index: number): string
	return "chamber " .. index
end

-- Step 2 of the pipeline plus the parts of step 3 that must pass before
-- anything else makes sense. Returns resolved chambers (without grid
-- positions yet) or fatal errors.
local function resolveChambers(definition: MineDefinition, config: GeneratorConfig, warnings: { string }): ({ ResolvedChamber }?, { string })
	local errors = {}
	local resolved: { ResolvedChamber } = {}
	local previous: { [string]: any } = {
		height = definition.defaultChamberHeight,
		width = definition.defaultChamberWidth,
		hardness = 1.0,
		tierBias = 1.0,
		iron = 0,
		gold = 0,
		crystal = 0,
		uranium = 0,
	}

	for index, chamberDefinition in definition.chambers do
		local label = chamberLabel(index)
		local values: { [string]: any } = {}
		for _, field in INHERITED_FIELDS do
			local value = (chamberDefinition :: any)[field]
			if value == nil then
				value = previous[field]
			end
			values[field] = value
		end
		if index == 1 then
			for _, field in REQUIRED_FIRST_CHAMBER_FIELDS do
				if values[field] == nil then
					table.insert(errors, label .. ": " .. field .. " is required on the first chamber")
				end
			end
		end
		if #errors > 0 then
			return nil, errors
		end
		previous = values

		for _, field in { "depth", "height", "width" } do
			if typeof(values[field]) ~= "number" or values[field] < 1 then
				table.insert(errors, label .. ": " .. field .. " must be at least 1 (got " .. tostring(values[field]) .. ")")
			end
		end
		if typeof(values.corridorWidth) ~= "number" or values.corridorWidth < 1 then
			table.insert(errors, label .. ": corridorWidth must be at least 1 (got " .. tostring(values.corridorWidth) .. ")")
		elseif typeof(values.width) == "number" and values.corridorWidth >= values.width then
			table.insert(errors, label .. ": corridorWidth (" .. values.corridorWidth .. ") must be less than width (" .. values.width .. "), or no rock is left to mine")
		end

		local hardness, wasHardnessClamped = RockRules.clampCenter(values.hardness, config.minCenter, config.maxCenter)
		if wasHardnessClamped then
			table.insert(warnings, label .. ": hardness " .. values.hardness .. " is outside " .. config.minCenter .. "-" .. config.maxCenter .. "; clamped to " .. hardness)
		end
		local tierBias, wasTierBiasClamped = RockRules.clampCenter(values.tierBias, config.minCenter, config.maxCenter)
		if wasTierBiasClamped then
			table.insert(warnings, label .. ": tierBias " .. values.tierBias .. " is outside " .. config.minCenter .. "-" .. config.maxCenter .. "; clamped to " .. tierBias)
		end
		hardness = RockRules.effectiveHardness(hardness, config.difficultyValue, config.hardnessShift, config.minCenter, config.maxCenter)

		local veins = {}
		for _, entry in RESOURCE_FIELDS do
			local baseCount = values[entry.field]
			if typeof(baseCount) ~= "number" or baseCount < 0 then
				table.insert(errors, label .. ": " .. entry.field .. " must be a non-negative number (got " .. tostring(baseCount) .. ")")
				baseCount = 0
			end
			if entry.resource == Enums.RawResource.URANIUM_ORE then
				veins[entry.resource] = baseCount
			else
				veins[entry.resource] = RockRules.effectiveVeinCount(baseCount, config.veinDivisor)
			end
		end

		local corridorHeight = values.corridorHeight
		local height = values.height
		local hasCorridor = index < #definition.chambers
		if corridorHeight == MineGenerator.CORRIDOR_HEIGHT_FULL then
			corridorHeight = height
		elseif typeof(corridorHeight) ~= "number" or corridorHeight < 1 then
			table.insert(errors, label .. ": corridorHeight must be a positive number or \"full\" (got " .. tostring(corridorHeight) .. ")")
			corridorHeight = 1
		elseif typeof(height) == "number" and corridorHeight > height then
			-- the last chamber has no corridor, so its inherited value is not worth a warning
			if hasCorridor then
				table.insert(warnings, label .. ": corridorHeight " .. corridorHeight .. " exceeds height " .. height .. "; clamped to full")
			end
			corridorHeight = height
		elseif hasCorridor and typeof(height) == "number" and corridorHeight > config.pickaxeReachBlocks and corridorHeight < height and not config.isClimbingEnabled then
			table.insert(warnings, label .. ": corridorHeight " .. corridorHeight .. " is above pickaxe reach (" .. config.pickaxeReachBlocks .. ") but below full, with no climbing mechanic enabled")
		end

		table.insert(resolved, {
			index = index,
			unlockCampLevel = index,
			hasCorridor = hasCorridor,
			depth = values.depth,
			height = height,
			width = values.width,
			hardness = hardness,
			tierBias = tierBias,
			veins = veins,
			corridorWidth = values.corridorWidth,
			corridorHeight = corridorHeight,
			handPlaced = chamberDefinition.handPlaced or {},
			depthStart = 0,
			heightStart = 0,
			widthStart = 0,
			corridorWidthStart = 0,
		})
	end

	if #errors > 0 then
		return nil, errors
	end
	return resolved, errors
end

local function validateMine(definition: MineDefinition, chambers: { ResolvedChamber }, config: GeneratorConfig): { string }
	local errors = {}
	if typeof(definition.mineId) ~= "string" or definition.mineId == "" then
		table.insert(errors, "mineId is required")
	end
	if not Enums.isValidValue(Enums.MineFacing, definition.facing) then
		table.insert(errors, "facing must be a MineFacing value (got " .. tostring(definition.facing) .. ")")
	end
	if typeof(definition.startingCampLevel) ~= "number" or definition.startingCampLevel < 1 then
		table.insert(errors, "startingCampLevel must be at least 1, or the run begins with nothing open")
	end
	if typeof(definition.bedrockThickness) ~= "number" or definition.bedrockThickness < 1 then
		table.insert(errors, "bedrockThickness must be at least 1")
	end
	if typeof(definition.veinCorridorClearance) ~= "number" or definition.veinCorridorClearance < 0 then
		table.insert(errors, "veinCorridorClearance must be a non-negative number")
	end
	if typeof(definition.uraniumTarget) ~= "number" or definition.uraniumTarget < 1 then
		table.insert(errors, "uraniumTarget must be at least 1")
	end

	local uraniumTotal = 0
	local uraniumBeforeLast = 0
	for _, chamber in chambers do
		uraniumTotal += chamber.veins[Enums.RawResource.URANIUM_ORE]
		if chamber.index < #chambers then
			uraniumBeforeLast += chamber.veins[Enums.RawResource.URANIUM_ORE]
		end
	end
	if typeof(definition.uraniumTarget) == "number" then
		local required = math.ceil(definition.uraniumTarget * config.maxPartyUraniumTargetMultiplier)
		if uraniumTotal < required then
			table.insert(errors, "uranium: " .. uraniumTotal .. " rocks authored across all chambers, but uraniumTarget " .. definition.uraniumTarget .. " x " .. config.maxPartyUraniumTargetMultiplier .. " for the largest party needs " .. required .. "; the run is unwinnable")
		end
		-- the last chamber must be required, so the run cannot finish before the final gate
		if uraniumBeforeLast >= definition.uraniumTarget then
			table.insert(errors, "uranium: chambers 1-" .. (#chambers - 1) .. " hold " .. uraniumBeforeLast .. " rocks, which already meets uraniumTarget " .. definition.uraniumTarget .. "; the last chamber must be required")
		end
	end
	return errors
end

-- Step 4: size the grid and place every chamber in it. All chambers share
-- the centreline; a narrower or shorter chamber simply gets thicker bedrock.
local function layoutGrid(definition: MineDefinition, chambers: { ResolvedChamber }, bedrock: Bedrock): MineGrid
	local sumDepth = 0
	local maxHeight = 0
	local maxWidth = 0
	for _, chamber in chambers do
		sumDepth += chamber.depth
		maxHeight = math.max(maxHeight, chamber.height)
		maxWidth = math.max(maxWidth, chamber.width)
	end
	local grid: MineGrid = {
		depth = bedrock.front + sumDepth + bedrock.divider * (#chambers - 1) + bedrock.far,
		height = maxHeight + bedrock.floor + bedrock.ceiling,
		width = maxWidth + bedrock.side * 2,
		cells = {},
	}
	local centreline = bedrock.side + math.floor((maxWidth - 1) / 2)
	local depthCursor = bedrock.front
	for _, chamber in chambers do
		chamber.depthStart = depthCursor
		chamber.heightStart = bedrock.floor
		chamber.widthStart = centredSpanStart(centreline, chamber.width)
		chamber.corridorWidthStart = centredSpanStart(centreline, chamber.corridorWidth)
		depthCursor += chamber.depth + bedrock.divider
	end
	return grid
end

-- Steps 5 and 6: everything is bedrock until carved; chamber interiors are
-- rolled against the hardness weights.
local function fillBedrockAndCarve(grid: MineGrid, chambers: { ResolvedChamber }, config: GeneratorConfig, chamberRandoms: { Random })
	grid.cells = table.create(grid.depth * grid.height * grid.width, Enums.RockName.BEDROCK)
	local fillerOrder = config.rockTable.FILLER_ORDER
	for _, chamber in chambers do
		local weights = RockRules.weights(chamber.hardness, #fillerOrder, config.spread)
		local random = chamberRandoms[chamber.index]
		local box = chamberBox(chamber)
		for depth = box.depthStart, box.depthEnd do
			for height = box.heightStart, box.heightEnd do
				for width = box.widthStart, box.widthEnd do
					setCell(grid, depth, height, width, fillerOrder[RockRules.pickWeightedIndex(random, weights)])
				end
			end
		end
	end
end

local function stampCluster(grid: MineGrid, bounds: Box, exclude: Box?, centerDepth: number, centerHeight: number, centerWidth: number, radius: number, rock: number)
	for depth = centerDepth - radius, centerDepth + radius do
		for height = centerHeight - radius, centerHeight + radius do
			for width = centerWidth - radius, centerWidth + radius do
				local dd = depth - centerDepth
				local dh = height - centerHeight
				local dw = width - centerWidth
				if dd * dd + dh * dh + dw * dw > radius * radius then
					continue
				end
				if not isInBox(bounds, depth, height, width) then
					continue
				end
				if exclude ~= nil and isInBox(exclude, depth, height, width) then
					continue
				end
				setCell(grid, depth, height, width, rock)
			end
		end
	end
end

-- Step 7: per chamber, per resource, split the count across tiers and drop
-- each cluster at a random position outside the corridor clearance zone.
local function stampVeins(grid: MineGrid, definition: MineDefinition, chambers: { ResolvedChamber }, config: GeneratorConfig, chamberRandoms: { Random }, warnings: { string })
	local rocks = config.rockTable.ROCKS
	for _, chamber in chambers do
		local random = chamberRandoms[chamber.index]
		local bounds = chamberBox(chamber)
		local exclude: Box? = nil
		if chamber.hasCorridor then
			exclude = expandBox(corridorBox(chamber), definition.veinCorridorClearance)
		end
		local hasFreeCell = false
		for depth = bounds.depthStart, bounds.depthEnd do
			for height = bounds.heightStart, bounds.heightEnd do
				for width = bounds.widthStart, bounds.widthEnd do
					if exclude == nil or not isInBox(exclude, depth, height, width) then
						hasFreeCell = true
					end
				end
			end
		end
		for _, entry in RESOURCE_FIELDS do
			local count = chamber.veins[entry.resource]
			if count == 0 then
				continue
			end
			if not hasFreeCell then
				table.insert(warnings, chamberLabel(chamber.index) .. ": veinCorridorClearance leaves no room for " .. entry.field .. " veins; none placed")
				break
			end
			local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
			local tierCounts
			if #tiers == 1 then
				tierCounts = { count }
			else
				tierCounts = RockRules.resolveTierCounts(count, chamber.tierBias, #tiers, config.spread)
			end
			-- uranium is the win condition, so it is always minable from a
			-- standing start (centers stay within pickaxe reach of the floor)
			-- and never lands on another uranium rock, so placed equals authored
			local maxCenterHeight = bounds.heightEnd
			if entry.resource == Enums.RawResource.URANIUM_ORE then
				maxCenterHeight = math.min(bounds.heightEnd, bounds.heightStart + config.pickaxeReachBlocks - 1)
			end
			for tier, tierCount in tierCounts do
				local rock = tiers[tier]
				local definitionOfRock = rocks[rock]
				for _ = 1, tierCount do
					local radius = random:NextInteger(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
					-- rejection sampling keeps the distribution uniform over the
					-- allowed volume; the free-cell check above guarantees it ends
					local centerDepth, centerHeight, centerWidth
					repeat
						centerDepth = random:NextInteger(bounds.depthStart, bounds.depthEnd)
						centerHeight = random:NextInteger(bounds.heightStart, maxCenterHeight)
						centerWidth = random:NextInteger(bounds.widthStart, bounds.widthEnd)
					until (exclude == nil or not isInBox(exclude, centerDepth, centerHeight, centerWidth))
						and (entry.resource ~= Enums.RawResource.URANIUM_ORE or MineGenerator.getCell(grid, centerDepth, centerHeight, centerWidth) ~= rock)
					stampCluster(grid, bounds, exclude, centerDepth, centerHeight, centerWidth, radius, rock)
				end
			end
		end
	end
end

-- Step 8: hand-placed rock wins over generated veins and ignores clearance.
local function stampHandPlaced(grid: MineGrid, chambers: { ResolvedChamber }, config: GeneratorConfig, chamberRandoms: { Random }, warnings: { string })
	local rocks = config.rockTable.ROCKS
	for _, chamber in chambers do
		local random = chamberRandoms[chamber.index]
		local bounds = chamberBox(chamber)
		local corridor = if chamber.hasCorridor then corridorBox(chamber) else nil
		local centreline = chamber.corridorWidthStart + math.floor((chamber.corridorWidth - 1) / 2)
		for entryIndex, entry in chamber.handPlaced do
			local label = chamberLabel(chamber.index) .. " handPlaced[" .. entryIndex .. "]"
			local definitionOfRock = rocks[entry.rock]
			if definitionOfRock == nil or definitionOfRock.kind ~= Enums.RockKind.RESOURCE then
				warn(label .. ": rock " .. tostring(entry.rock) .. " is not a resource rock; skipped")
				table.insert(warnings, label .. ": rock " .. tostring(entry.rock) .. " is not a resource rock; skipped")
				continue
			end
			local depth = chamber.depthStart + entry.depth
			local height = chamber.heightStart + entry.height
			local width = centreline + entry.widthOffset
			if not isInBox(bounds, depth, height, width) then
				table.insert(warnings, label .. ": falls outside the chamber bounds; clipped")
			elseif corridor ~= nil and isInBox(corridor, depth, height, width) then
				table.insert(warnings, label .. ": falls inside the corridor volume and will be carved away")
			end
			local radius = entry.cluster
			if radius == nil then
				radius = random:NextInteger(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
			end
			stampCluster(grid, bounds, nil, depth, height, width, radius :: number, entry.rock)
		end
	end
end

-- Steps 9 and 10: carve each corridor through its chamber and the divider
-- beyond it, then fill the divider crossing with gate blocks. Chamber 1's
-- corridor also opens the front face, which is the mine mouth.
local function carveCorridorsAndGates(grid: MineGrid, chambers: { ResolvedChamber }, bedrock: Bedrock)
	for chamberIndex, chamber in chambers do
		if not chamber.hasCorridor then
			continue
		end
		local box = corridorBox(chamber)
		local depthStart = box.depthStart
		if chamberIndex == 1 then
			depthStart = 0
		end
		local dividerStart = box.depthEnd + 1
		local dividerEnd = dividerStart + bedrock.divider - 1
		for depth = depthStart, dividerEnd do
			for height = box.heightStart, box.heightEnd do
				for width = box.widthStart, box.widthEnd do
					local rock = if depth >= dividerStart then Enums.RockName.GATE else MineGenerator.AIR
					setCell(grid, depth, height, width, rock)
				end
			end
		end
	end
end

local function emptyOreTotals(): { [number]: number }
	local totals = {}
	for _, resource in Enums.getAllValues(Enums.RawResource) do
		totals[resource] = 0
	end
	return totals
end

local function meanClusterCells(radiusMin: number, radiusMax: number): number
	local total = 0
	for radius = radiusMin, radiusMax do
		total += MineGenerator.clusterCellCount(radius)
	end
	return total / (radiusMax - radiusMin + 1)
end

-- expected ore from the authored counts alone: clusters x tier split x mean
-- cluster cells x yield, plus hand-placed rock, before overlap or corridor
-- carving
local function requestedOre(chamber: ResolvedChamber, config: GeneratorConfig): { [number]: number }
	local totals = emptyOreTotals()
	local rocks = config.rockTable.ROCKS
	for _, entry in chamber.handPlaced do
		local definitionOfRock = rocks[entry.rock]
		if definitionOfRock == nil or definitionOfRock.kind ~= Enums.RockKind.RESOURCE then
			continue
		end
		local cells
		if entry.cluster ~= nil then
			cells = MineGenerator.clusterCellCount(entry.cluster)
		else
			cells = meanClusterCells(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
		end
		totals[definitionOfRock.resource :: number] += cells * (definitionOfRock.yield :: number)
	end
	for _, entry in RESOURCE_FIELDS do
		local count = chamber.veins[entry.resource]
		local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
		local tierCounts
		if #tiers == 1 then
			tierCounts = { count }
		else
			tierCounts = RockRules.resolveTierCounts(count, chamber.tierBias, #tiers, config.spread)
		end
		for tier, tierCount in tierCounts do
			local definitionOfRock = rocks[tiers[tier]]
			local meanCells = meanClusterCells(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
			totals[entry.resource] += tierCount * meanCells * (definitionOfRock.yield :: number)
		end
	end
	return totals
end

-- Step 11: close the loop between what the designer authored and what the
-- grid actually holds.
local function buildReport(grid: MineGrid, chambers: { ResolvedChamber }, config: GeneratorConfig, seed: number): Report
	local rocks = config.rockTable.ROCKS
	local report: Report = {
		seed = seed,
		gridDepth = grid.depth,
		gridHeight = grid.height,
		gridWidth = grid.width,
		chambers = {},
	}
	local uraniumSoFar = 0
	for _, chamber in chambers do
		local box = chamberBox(chamber)
		local diggable = 0
		local reachable = 0
		local placedHp = 0
		local placed = emptyOreTotals()
		for depth = box.depthStart, box.depthEnd do
			for height = box.heightStart, box.heightEnd do
				for width = box.widthStart, box.widthEnd do
					local rock = MineGenerator.getCell(grid, depth, height, width)
					if rock == MineGenerator.AIR then
						continue
					end
					local definitionOfRock = rocks[rock]
					if definitionOfRock.kind ~= Enums.RockKind.FILLER and definitionOfRock.kind ~= Enums.RockKind.RESOURCE then
						continue
					end
					diggable += 1
					if height - chamber.heightStart < config.pickaxeReachBlocks then
						reachable += 1
					end
					placedHp += definitionOfRock.hp :: number
					if definitionOfRock.kind == Enums.RockKind.RESOURCE then
						placed[definitionOfRock.resource :: number] += definitionOfRock.yield :: number
					end
				end
			end
		end
		uraniumSoFar += placed[Enums.RawResource.URANIUM_ORE]
		table.insert(report.chambers, {
			index = chamber.index,
			diggableVolume = diggable,
			reachableShare = if diggable > 0 then reachable / diggable else 0,
			requestedOre = requestedOre(chamber, config),
			placedOre = placed,
			placedHp = placedHp,
			uraniumSoFar = uraniumSoFar,
		})
	end
	return report
end

function MineGenerator.deriveChamberSeed(seed: number, chamberIndex: number): number
	return seed + chamberIndex * CHAMBER_SEED_STRIDE
end

-- Runs the full pipeline. Returns (result, errors, warnings); result is nil
-- when errors is non-empty. `seed` overrides the definition's seed; when both
-- are nil a fresh seed is drawn and reported.
function MineGenerator.generate(definition: MineDefinition, config: GeneratorConfig, seed: number?): (GenerateResult?, { string }, { string })
	local warnings: { string } = {}
	if typeof(definition) ~= "table" or typeof(definition.chambers) ~= "table" or #definition.chambers == 0 then
		return nil, { "mine definition needs a non-empty chambers list" }, warnings
	end

	local chambers, errors = resolveChambers(definition, config, warnings)
	if chambers == nil then
		return nil, errors, warnings
	end
	errors = validateMine(definition, chambers, config)
	if #errors > 0 then
		return nil, errors, warnings
	end

	local resolvedSeed = seed or definition.seed
	if resolvedSeed == nil then
		resolvedSeed = Random.new():NextInteger(1, MAX_DRAWN_SEED)
	end
	local chamberRandoms: { Random } = {}
	for _, chamber in chambers do
		chamberRandoms[chamber.index] = Random.new(MineGenerator.deriveChamberSeed(resolvedSeed :: number, chamber.index))
	end

	local bedrock = resolveBedrock(definition)
	local grid = layoutGrid(definition, chambers, bedrock)
	fillBedrockAndCarve(grid, chambers, config, chamberRandoms)
	stampVeins(grid, definition, chambers, config, chamberRandoms, warnings)
	stampHandPlaced(grid, chambers, config, chamberRandoms, warnings)
	carveCorridorsAndGates(grid, chambers, bedrock)
	local report = buildReport(grid, chambers, config, resolvedSeed :: number)

	for _, chamberReport in report.chambers do
		if chamberReport.diggableVolume == 0 then
			table.insert(warnings, chamberLabel(chamberReport.index) .. ": bedrock and corridor leave no diggable volume")
		end
	end
	-- the authored counts passed validation; this checks what actually
	-- survived stamping and carving, so no seed can ship unwinnable
	local placedUranium = report.chambers[#report.chambers].uraniumSoFar
	local requiredUranium = math.ceil(definition.uraniumTarget * config.maxPartyUraniumTargetMultiplier)
	if placedUranium < requiredUranium then
		return nil, { "uranium: only " .. placedUranium .. " rocks survived generation with seed " .. (resolvedSeed :: number) .. ", but the largest party needs " .. requiredUranium .. "; the run is unwinnable" }, warnings
	end

	return { grid = grid, chambers = chambers, report = report }, errors, warnings
end

export type PreviewChamber = {
	index: number,
	requestedOre: { [number]: number },
	expectedHp: number,
}

-- The designer's balance sheet from the file alone: expected ore per chamber
-- and the HP a party must chew through, with no grid built. Filler HP is the
-- interior volume minus the corridor times the hardness-weighted mean HP;
-- vein HP is added on top (veins overwrite filler, so this slightly
-- overstates, which is the safe direction).
function MineGenerator.preview(definition: MineDefinition, config: GeneratorConfig): ({ PreviewChamber }?, { string }, { string })
	local warnings: { string } = {}
	if typeof(definition) ~= "table" or typeof(definition.chambers) ~= "table" or #definition.chambers == 0 then
		return nil, { "mine definition needs a non-empty chambers list" }, warnings
	end
	local chambers, errors = resolveChambers(definition, config, warnings)
	if chambers == nil then
		return nil, errors, warnings
	end
	errors = validateMine(definition, chambers, config)
	if #errors > 0 then
		return nil, errors, warnings
	end

	local rocks = config.rockTable.ROCKS
	local fillerOrder = config.rockTable.FILLER_ORDER
	local previews: { PreviewChamber } = {}
	for _, chamber in chambers do
		local weights = RockRules.weights(chamber.hardness, #fillerOrder, config.spread)
		local meanFillerHp = 0
		for index, rock in fillerOrder do
			meanFillerHp += weights[index] * (rocks[rock].hp :: number)
		end
		local volume = chamber.depth * chamber.height * chamber.width
		if chamber.hasCorridor then
			volume -= chamber.depth * chamber.corridorHeight * chamber.corridorWidth
		end
		local expectedHp = volume * meanFillerHp
		for _, entry in RESOURCE_FIELDS do
			local count = chamber.veins[entry.resource]
			local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
			local tierCounts
			if #tiers == 1 then
				tierCounts = { count }
			else
				tierCounts = RockRules.resolveTierCounts(count, chamber.tierBias, #tiers, config.spread)
			end
			for tier, tierCount in tierCounts do
				local definitionOfRock = rocks[tiers[tier]]
				local meanCells = meanClusterCells(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
				expectedHp += tierCount * meanCells * (definitionOfRock.hp :: number)
			end
		end
		table.insert(previews, {
			index = chamber.index,
			requestedOre = requestedOre(chamber, config),
			expectedHp = expectedHp,
		})
	end
	return previews, errors, warnings
end

-- One line per chamber for the Output window.
function MineGenerator.formatReport(report: Report): string
	local lines = {
		string.format("mine seed %d, grid %d x %d x %d (depth x height x width)", report.seed, report.gridDepth, report.gridHeight, report.gridWidth),
	}
	for _, chamber in report.chambers do
		local parts = {}
		for _, entry in RESOURCE_FIELDS do
			table.insert(parts, string.format("%s %d/%d", entry.field, chamber.placedOre[entry.resource], math.floor(chamber.requestedOre[entry.resource] + 0.5)))
		end
		table.insert(lines, string.format(
			"  chamber %d: diggable %d blocks, %d%% within reach, hp %d, ore placed/requested: %s, uranium so far %d",
			chamber.index,
			chamber.diggableVolume,
			math.floor(chamber.reachableShare * 100 + 0.5),
			chamber.placedHp,
			table.concat(parts, ", "),
			chamber.uraniumSoFar
		))
	end
	return table.concat(lines, "\n")
end

return MineGenerator
