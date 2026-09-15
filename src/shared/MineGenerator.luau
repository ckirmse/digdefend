--!strict

-- Pure mine generator (GDD "Randomized Mine Creation"). Turns a mine
-- definition plus difficulty and seed into a grid of RockName integers in the
-- mine's local space (depth into the mountain, height up, width across), and
-- a report the designer can read. World placement is not this module's job.
-- Tuning and the rock table are passed in as a config so the module stays
-- free of GameData and unit testable; the server assembles the config from
-- GameData/Rocks, GameData/Control/Difficulty, and GameData/Mines/Generation.
--
-- The mine is one open volume inside a bedrock shell (decided 2026-09-15,
-- replacing sealed chambers with gates): depth zones set how hard the rock
-- is and what it holds as players dig deeper, pockets are pre-carved caverns
-- to discover, and the only opening is the entrance tunnel at the mouth.
local Enums = require(script.Parent.Enums)
local RockRules = require(script.Parent.RockRules)

local MineGenerator = {}

MineGenerator.AIR = 0
-- wire symbol for "a filler block; roll its identity from the seed" (see
-- collapseFiller / expandFiller): filler is per-block noise that no codec
-- can compress, but it is a pure function of the zone seed, so clients
-- re-roll it instead of receiving it
MineGenerator.FILLER_PLACEHOLDER = 255

-- seeds drawn for a nil-seed run stay well inside Random's integer range
local MAX_DRAWN_SEED = 2 ^ 31 - 1
-- keeps zone sub-seeds apart so editing one zone never reshuffles another
local ZONE_SEED_STRIDE = 1000003

export type HandPlaced = {
	rock: number,
	depth: number,
	height: number,
	widthOffset: number,
	cluster: number?,
}

export type ZoneDefinition = {
	depth: number?,
	-- blocks up from the entrance floor line
	height: number?,
	-- blocks the zone extends below the entrance floor line (added
	-- 2026-09-15 so a mine goes down as well as up); inherited, default 0
	floorDrop: number?,
	width: number?,
	hardness: number?,
	tierBias: number?,
	iron: number?,
	gold: number?,
	crystal: number?,
	uranium: number?,
	pockets: number?,
	handPlaced: { HandPlaced }?,
}

export type BedrockOverrides = {
	front: number?,
	far: number?,
	floor: number?,
	ceiling: number?,
	side: number?,
}

export type MineDefinition = {
	mineId: string,
	seed: number?,
	origin: Vector3,
	facing: number,
	bedrockThickness: number,
	bedrockOverrides: BedrockOverrides?,
	entranceWidth: number,
	entranceHeight: number,
	entranceDepth: number,
	veinEntranceClearance: number,
	pocketRadiusMin: number,
	pocketRadiusMax: number,
	uraniumTarget: number,
	defaultZoneHeight: number,
	defaultZoneWidth: number,
	zones: { ZoneDefinition },
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

-- a zone after inheritance and difficulty, in grid coordinates (0-based)
export type ResolvedZone = {
	index: number,
	depth: number,
	-- the whole vertical span: floorDrop rows below the floor line plus the
	-- authored height above it
	height: number,
	floorDrop: number,
	width: number,
	hardness: number,
	tierBias: number,
	veins: { [number]: number },
	pockets: number,
	handPlaced: { HandPlaced },
	depthStart: number,
	heightStart: number,
	widthStart: number,
	-- the resolved hardness kernel over the filler order, so a client can
	-- re-roll filler without RockRules or the rock table
	fillerWeights: { number },
}

-- what a client needs per zone to re-roll filler (a subset of ResolvedZone)
export type ZoneFill = {
	index: number,
	depthStart: number,
	depth: number,
	heightStart: number,
	height: number,
	widthStart: number,
	width: number,
	fillerWeights: { number },
}

export type MineGrid = {
	depth: number,
	height: number,
	width: number,
	-- width index on the mine centreline and height index of the first
	-- floor row; MineSpace needs both to place the grid in the world
	centrelineWidth: number,
	floorHeight: number,
	cells: { number },
}

export type ZoneReport = {
	index: number,
	diggableVolume: number,
	reachableShare: number,
	pocketVolume: number,
	requestedOre: { [number]: number },
	placedOre: { [number]: number },
	placedHp: number,
	-- uranium rocks in this and every shallower zone, so the designer can
	-- see the progression toward uraniumTarget
	uraniumSoFar: number,
}

export type Report = {
	seed: number,
	gridDepth: number,
	gridHeight: number,
	gridWidth: number,
	zones: { ZoneReport },
}

export type GenerateResult = {
	grid: MineGrid,
	zones: { ResolvedZone },
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
	"floorDrop",
	"width",
	"hardness",
	"tierBias",
	"iron",
	"gold",
	"crystal",
	"uranium",
	"pockets",
}

local REQUIRED_FIRST_ZONE_FIELDS = { "depth" }

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

local function zoneBox(zone: ResolvedZone): Box
	return {
		depthStart = zone.depthStart,
		depthEnd = zone.depthStart + zone.depth - 1,
		heightStart = zone.heightStart,
		heightEnd = zone.heightStart + zone.height - 1,
		widthStart = zone.widthStart,
		widthEnd = zone.widthStart + zone.width - 1,
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
	}
end

-- a span of `size` blocks centred on `centreline`; an even size leans one
-- block toward positive width (GDD "The entrance")
local function centredSpanStart(centreline: number, size: number): number
	return centreline - math.floor((size - 1) / 2)
end

local function zoneLabel(index: number): string
	return "zone " .. index
end

-- the entrance tunnel: through the front bedrock and entranceDepth blocks
-- into zone 1, centred on the centreline, up from the floor line
local function entranceBox(grid: MineGrid, definition: MineDefinition, bedrock: Bedrock): Box
	return {
		depthStart = 0,
		depthEnd = bedrock.front + definition.entranceDepth - 1,
		heightStart = grid.floorHeight,
		heightEnd = grid.floorHeight + definition.entranceHeight - 1,
		widthStart = centredSpanStart(grid.centrelineWidth, definition.entranceWidth),
		widthEnd = centredSpanStart(grid.centrelineWidth, definition.entranceWidth) + definition.entranceWidth - 1,
	}
end

-- Step 2 of the pipeline plus the parts of step 3 that must pass before
-- anything else makes sense. Returns resolved zones (without grid
-- positions yet) or fatal errors.
local function resolveZones(definition: MineDefinition, config: GeneratorConfig, warnings: { string }): ({ ResolvedZone }?, { string })
	local errors = {}
	local resolved: { ResolvedZone } = {}
	local previous: { [string]: any } = {
		height = definition.defaultZoneHeight,
		floorDrop = 0,
		width = definition.defaultZoneWidth,
		hardness = 1.0,
		tierBias = 1.0,
		iron = 0,
		gold = 0,
		crystal = 0,
		uranium = 0,
		pockets = 0,
	}

	for index, zoneDefinition in definition.zones do
		local label = zoneLabel(index)
		local values: { [string]: any } = {}
		for _, field in INHERITED_FIELDS do
			local value = (zoneDefinition :: any)[field]
			if value == nil then
				value = previous[field]
			end
			values[field] = value
		end
		if index == 1 then
			for _, field in REQUIRED_FIRST_ZONE_FIELDS do
				if values[field] == nil then
					table.insert(errors, label .. ": " .. field .. " is required on the first zone")
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
		if typeof(values.pockets) ~= "number" or values.pockets < 0 then
			table.insert(errors, label .. ": pockets must be a non-negative number (got " .. tostring(values.pockets) .. ")")
			values.pockets = 0
		end
		if typeof(values.floorDrop) ~= "number" or values.floorDrop < 0 or values.floorDrop % 1 ~= 0 then
			table.insert(errors, label .. ": floorDrop must be a non-negative whole number (got " .. tostring(values.floorDrop) .. ")")
			values.floorDrop = 0
		end

		-- hardness spans the stone tiers, tierBias the ore tiers
		local maxHardness = #config.rockTable.FILLER_ORDER
		local hardness, wasHardnessClamped = RockRules.clampCenter(values.hardness, config.minCenter, maxHardness)
		if wasHardnessClamped then
			table.insert(warnings, label .. ": hardness " .. values.hardness .. " is outside " .. config.minCenter .. "-" .. maxHardness .. "; clamped to " .. hardness)
		end
		local tierBias, wasTierBiasClamped = RockRules.clampCenter(values.tierBias, config.minCenter, config.maxCenter)
		if wasTierBiasClamped then
			table.insert(warnings, label .. ": tierBias " .. values.tierBias .. " is outside " .. config.minCenter .. "-" .. config.maxCenter .. "; clamped to " .. tierBias)
		end
		hardness = RockRules.effectiveHardness(hardness, config.difficultyValue, config.hardnessShift, config.minCenter, maxHardness)

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

		table.insert(resolved, {
			index = index,
			depth = values.depth,
			height = values.height + values.floorDrop,
			floorDrop = values.floorDrop,
			width = values.width,
			hardness = hardness,
			tierBias = tierBias,
			veins = veins,
			pockets = values.pockets,
			handPlaced = zoneDefinition.handPlaced or {},
			depthStart = 0,
			heightStart = 0,
			widthStart = 0,
			fillerWeights = {},
		})
	end

	if #errors > 0 then
		return nil, errors
	end
	return resolved, errors
end

local function validateMine(definition: MineDefinition, zones: { ResolvedZone }, config: GeneratorConfig, warnings: { string }): { string }
	local errors = {}
	if typeof(definition.mineId) ~= "string" or definition.mineId == "" then
		table.insert(errors, "mineId is required")
	end
	if not Enums.isValidValue(Enums.MineFacing, definition.facing) then
		table.insert(errors, "facing must be a MineFacing value (got " .. tostring(definition.facing) .. ")")
	end
	if typeof(definition.bedrockThickness) ~= "number" or definition.bedrockThickness < 1 then
		table.insert(errors, "bedrockThickness must be at least 1")
	end
	local firstZone = zones[1]
	if typeof(definition.entranceWidth) ~= "number" or definition.entranceWidth < 1 then
		table.insert(errors, "entranceWidth must be at least 1")
	elseif definition.entranceWidth > firstZone.width then
		table.insert(errors, "entranceWidth (" .. definition.entranceWidth .. ") must not exceed zone 1's width (" .. firstZone.width .. ")")
	end
	if typeof(definition.entranceHeight) ~= "number" or definition.entranceHeight < 1 then
		table.insert(errors, "entranceHeight must be at least 1")
	elseif definition.entranceHeight > firstZone.height - firstZone.floorDrop then
		table.insert(errors, "entranceHeight (" .. definition.entranceHeight .. ") must not exceed zone 1's height above the floor line (" .. (firstZone.height - firstZone.floorDrop) .. ")")
	elseif definition.entranceHeight > config.pickaxeReachBlocks and not config.isClimbingEnabled then
		table.insert(warnings, "entranceHeight " .. definition.entranceHeight .. " is above pickaxe reach (" .. config.pickaxeReachBlocks .. ") with no climbing mechanic enabled; its ceiling cannot be mined from the floor")
	end
	if typeof(definition.entranceDepth) ~= "number" or definition.entranceDepth < 0 then
		table.insert(errors, "entranceDepth must be a non-negative number")
	elseif definition.entranceDepth > firstZone.depth then
		table.insert(errors, "entranceDepth (" .. definition.entranceDepth .. ") must not exceed zone 1's depth (" .. firstZone.depth .. ")")
	end
	if typeof(definition.veinEntranceClearance) ~= "number" or definition.veinEntranceClearance < 0 then
		table.insert(errors, "veinEntranceClearance must be a non-negative number")
	end
	if typeof(definition.pocketRadiusMin) ~= "number" or definition.pocketRadiusMin < 0 then
		table.insert(errors, "pocketRadiusMin must be a non-negative number")
	end
	if typeof(definition.pocketRadiusMax) ~= "number" or definition.pocketRadiusMax < definition.pocketRadiusMin then
		table.insert(errors, "pocketRadiusMax must be at least pocketRadiusMin")
	end
	if typeof(definition.uraniumTarget) ~= "number" or definition.uraniumTarget < 1 then
		table.insert(errors, "uraniumTarget must be at least 1")
	end

	local uraniumTotal = 0
	for _, zone in zones do
		uraniumTotal += zone.veins[Enums.RawResource.URANIUM_ORE]
	end
	if typeof(definition.uraniumTarget) == "number" then
		local required = math.ceil(definition.uraniumTarget * config.maxPartyUraniumTargetMultiplier)
		if uraniumTotal < required then
			table.insert(errors, "uranium: " .. uraniumTotal .. " rocks authored across all zones, but uraniumTarget " .. definition.uraniumTarget .. " x " .. config.maxPartyUraniumTargetMultiplier .. " for the largest party needs " .. required .. "; the run is unwinnable")
		end
	end
	return errors
end

-- Step 4: size the grid and place every zone in it, one after another along
-- the depth axis. All zones share the centreline and the floor; a narrower
-- or shorter zone simply gets thicker bedrock around it.
local function layoutGrid(zones: { ResolvedZone }, bedrock: Bedrock): MineGrid
	local sumDepth = 0
	local maxHeight = 0
	local maxWidth = 0
	-- the floor line sits above the deepest drop; zones reach up and down from it
	local maxFloorDrop = 0
	for _, zone in zones do
		sumDepth += zone.depth
		maxHeight = math.max(maxHeight, zone.height - zone.floorDrop)
		maxFloorDrop = math.max(maxFloorDrop, zone.floorDrop)
		maxWidth = math.max(maxWidth, zone.width)
	end
	local floorLine = bedrock.floor + maxFloorDrop
	local centreline = bedrock.side + math.floor((maxWidth - 1) / 2)
	local grid: MineGrid = {
		depth = bedrock.front + sumDepth + bedrock.far,
		height = floorLine + maxHeight + bedrock.ceiling,
		width = maxWidth + bedrock.side * 2,
		centrelineWidth = centreline,
		floorHeight = floorLine,
		cells = {},
	}
	local depthCursor = bedrock.front
	for _, zone in zones do
		zone.depthStart = depthCursor
		zone.heightStart = floorLine - zone.floorDrop
		zone.widthStart = centredSpanStart(centreline, zone.width)
		depthCursor += zone.depth
	end
	return grid
end

-- Steps 5 and 6: everything is bedrock until carved; zone interiors are
-- rolled against the hardness weights.
-- Rolls filler for one zone from a fresh zone Random, writing a cell only
-- where `onlyPlaceholder` allows. Server generation and client
-- reconstruction both call this, in the same cell order, so the rolls line
-- up: the client's Random consumes exactly what the server's did.
function MineGenerator.rollFiller(grid: MineGrid, fill: ZoneFill, fillerOrder: { number }, random: Random, onlyPlaceholder: boolean)
	for depth = fill.depthStart, fill.depthStart + fill.depth - 1 do
		for height = fill.heightStart, fill.heightStart + fill.height - 1 do
			for width = fill.widthStart, fill.widthStart + fill.width - 1 do
				local rock = fillerOrder[RockRules.pickWeightedIndex(random, fill.fillerWeights)]
				if onlyPlaceholder and MineGenerator.getCell(grid, depth, height, width) ~= MineGenerator.FILLER_PLACEHOLDER then
					continue
				end
				setCell(grid, depth, height, width, rock)
			end
		end
	end
end

-- cells for the wire: every filler rock becomes FILLER_PLACEHOLDER so zone
-- interiors run-length encode to almost nothing
function MineGenerator.collapseFiller(cells: { number }, fillerOrder: { number }): { number }
	local isFiller: { [number]: boolean } = {}
	for _, rock in fillerOrder do
		isFiller[rock] = true
	end
	local collapsed = table.create(#cells, MineGenerator.AIR)
	for index, rock in cells do
		collapsed[index] = if isFiller[rock] then MineGenerator.FILLER_PLACEHOLDER else rock
	end
	return collapsed
end

-- the inverse of collapseFiller on a client: re-rolls every placeholder from
-- the zone seeds. Placeholders outside every zone (never expected) become
-- the first filler rock so the grid holds no wire symbols.
function MineGenerator.expandFiller(grid: MineGrid, fills: { ZoneFill }, seed: number, fillerOrder: { number })
	for _, fill in fills do
		local random = Random.new(MineGenerator.deriveZoneSeed(seed, fill.index))
		MineGenerator.rollFiller(grid, fill, fillerOrder, random, true)
	end
	for index, rock in grid.cells do
		if rock == MineGenerator.FILLER_PLACEHOLDER then
			grid.cells[index] = fillerOrder[1]
		end
	end
end

local function fillBedrockAndRock(grid: MineGrid, zones: { ResolvedZone }, config: GeneratorConfig, zoneRandoms: { Random })
	grid.cells = table.create(grid.depth * grid.height * grid.width, Enums.RockName.BEDROCK)
	local fillerOrder = config.rockTable.FILLER_ORDER
	for _, zone in zones do
		zone.fillerWeights = RockRules.weights(zone.hardness, #fillerOrder, config.spread)
		MineGenerator.rollFiller(grid, zone, fillerOrder, zoneRandoms[zone.index], false)
	end
end

-- writes a discrete sphere of `rock` inside `bounds`, skipping `exclude`
-- and, when `isSkippingAir`, any cell already carved
local function stampCluster(grid: MineGrid, bounds: Box, exclude: Box?, centerDepth: number, centerHeight: number, centerWidth: number, radius: number, rock: number, isSkippingAir: boolean)
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
				if isSkippingAir and MineGenerator.getCell(grid, depth, height, width) == MineGenerator.AIR then
					continue
				end
				setCell(grid, depth, height, width, rock)
			end
		end
	end
end

-- Step 7: pockets are carved before veins so ore lands around them, never
-- inside them, and every pocket wall is a discovery
local function carvePockets(grid: MineGrid, definition: MineDefinition, zones: { ResolvedZone }, zoneRandoms: { Random })
	for _, zone in zones do
		local random = zoneRandoms[zone.index]
		local bounds = zoneBox(zone)
		for _ = 1, zone.pockets do
			local radius = random:NextInteger(definition.pocketRadiusMin, definition.pocketRadiusMax)
			local centerDepth = random:NextInteger(bounds.depthStart, bounds.depthEnd)
			local centerHeight = random:NextInteger(bounds.heightStart, bounds.heightEnd)
			local centerWidth = random:NextInteger(bounds.widthStart, bounds.widthEnd)
			stampCluster(grid, bounds, nil, centerDepth, centerHeight, centerWidth, radius, MineGenerator.AIR, false)
		end
	end
end

-- Step 8: per zone, per resource, split the count across tiers and drop
-- each cluster at a random rock position outside the entrance clearance.
local function stampVeins(grid: MineGrid, zones: { ResolvedZone }, config: GeneratorConfig, zoneRandoms: { Random }, exclude: Box, warnings: { string })
	local rocks = config.rockTable.ROCKS
	for _, zone in zones do
		local random = zoneRandoms[zone.index]
		local bounds = zoneBox(zone)
		local hasFreeCell = false
		for depth = bounds.depthStart, bounds.depthEnd do
			for height = bounds.heightStart, bounds.heightEnd do
				for width = bounds.widthStart, bounds.widthEnd do
					if not isInBox(exclude, depth, height, width) and MineGenerator.getCell(grid, depth, height, width) ~= MineGenerator.AIR then
						hasFreeCell = true
					end
				end
			end
		end
		for _, entry in RESOURCE_FIELDS do
			local count = zone.veins[entry.resource]
			if count == 0 then
				continue
			end
			if not hasFreeCell then
				table.insert(warnings, zoneLabel(zone.index) .. ": entrance clearance and pockets leave no rock for " .. entry.field .. " veins; none placed")
				break
			end
			local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
			local tierCounts
			if #tiers == 1 then
				tierCounts = { count }
			else
				tierCounts = RockRules.resolveTierCounts(count, zone.tierBias, #tiers, config.spread)
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
					until not isInBox(exclude, centerDepth, centerHeight, centerWidth)
						and MineGenerator.getCell(grid, centerDepth, centerHeight, centerWidth) ~= MineGenerator.AIR
						and (entry.resource ~= Enums.RawResource.URANIUM_ORE or MineGenerator.getCell(grid, centerDepth, centerHeight, centerWidth) ~= rock)
					stampCluster(grid, bounds, exclude, centerDepth, centerHeight, centerWidth, radius, rock, true)
				end
			end
		end
	end
end

-- Step 9: hand-placed rock wins over generated veins and pockets, and
-- ignores the entrance clearance.
local function stampHandPlaced(grid: MineGrid, zones: { ResolvedZone }, config: GeneratorConfig, zoneRandoms: { Random }, entrance: Box, warnings: { string })
	local rocks = config.rockTable.ROCKS
	for _, zone in zones do
		local random = zoneRandoms[zone.index]
		local bounds = zoneBox(zone)
		for entryIndex, entry in zone.handPlaced do
			local label = zoneLabel(zone.index) .. " handPlaced[" .. entryIndex .. "]"
			local definitionOfRock = rocks[entry.rock]
			if definitionOfRock == nil or definitionOfRock.kind ~= Enums.RockKind.RESOURCE then
				warn(label .. ": rock " .. tostring(entry.rock) .. " is not a resource rock; skipped")
				table.insert(warnings, label .. ": rock " .. tostring(entry.rock) .. " is not a resource rock; skipped")
				continue
			end
			-- heights are authored from the entrance floor line, what a player
			-- walking in sees as ground level, not from the zone's lowest row
			local depth = zone.depthStart + entry.depth
			local height = grid.floorHeight + entry.height
			local width = grid.centrelineWidth + entry.widthOffset
			if not isInBox(bounds, depth, height, width) then
				table.insert(warnings, label .. ": falls outside the zone bounds; clipped")
			elseif isInBox(entrance, depth, height, width) then
				table.insert(warnings, label .. ": falls inside the entrance tunnel and will be carved away")
			end
			local radius = entry.cluster
			if radius == nil then
				radius = random:NextInteger(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
			end
			stampCluster(grid, bounds, nil, depth, height, width, radius :: number, entry.rock, false)
		end
	end
end

-- Step 10: the entrance tunnel, after veins and hand-placed rock so nothing
-- can plug the mouth. It is the only opening in the shell.
local function carveEntrance(grid: MineGrid, entrance: Box)
	for depth = entrance.depthStart, entrance.depthEnd do
		for height = entrance.heightStart, entrance.heightEnd do
			for width = entrance.widthStart, entrance.widthEnd do
				setCell(grid, depth, height, width, MineGenerator.AIR)
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
-- cluster cells x yield, plus hand-placed rock, before overlap or carving
local function requestedOre(zone: ResolvedZone, config: GeneratorConfig): { [number]: number }
	local totals = emptyOreTotals()
	local rocks = config.rockTable.ROCKS
	for _, entry in zone.handPlaced do
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
		local count = zone.veins[entry.resource]
		local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
		local tierCounts
		if #tiers == 1 then
			tierCounts = { count }
		else
			tierCounts = RockRules.resolveTierCounts(count, zone.tierBias, #tiers, config.spread)
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
local function buildReport(grid: MineGrid, zones: { ResolvedZone }, config: GeneratorConfig, seed: number): Report
	local rocks = config.rockTable.ROCKS
	local report: Report = {
		seed = seed,
		gridDepth = grid.depth,
		gridHeight = grid.height,
		gridWidth = grid.width,
		zones = {},
	}
	local uraniumSoFar = 0
	for _, zone in zones do
		local box = zoneBox(zone)
		local diggable = 0
		local reachable = 0
		local pocketVolume = 0
		local placedHp = 0
		local placed = emptyOreTotals()
		for depth = box.depthStart, box.depthEnd do
			for height = box.heightStart, box.heightEnd do
				for width = box.widthStart, box.widthEnd do
					local rock = MineGenerator.getCell(grid, depth, height, width)
					if rock == MineGenerator.AIR then
						pocketVolume += 1
						continue
					end
					local definitionOfRock = rocks[rock]
					if definitionOfRock.kind ~= Enums.RockKind.FILLER and definitionOfRock.kind ~= Enums.RockKind.RESOURCE then
						continue
					end
					diggable += 1
					if height - zone.heightStart < config.pickaxeReachBlocks then
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
		table.insert(report.zones, {
			index = zone.index,
			diggableVolume = diggable,
			reachableShare = if diggable > 0 then reachable / diggable else 0,
			pocketVolume = pocketVolume,
			requestedOre = requestedOre(zone, config),
			placedOre = placed,
			placedHp = placedHp,
			uraniumSoFar = uraniumSoFar,
		})
	end
	return report
end

function MineGenerator.deriveZoneSeed(seed: number, zoneIndex: number): number
	return seed + zoneIndex * ZONE_SEED_STRIDE
end

-- Runs the full pipeline. Returns (result, errors, warnings); result is nil
-- when errors is non-empty. `seed` overrides the definition's seed; when both
-- are nil a fresh seed is drawn and reported.
function MineGenerator.generate(definition: MineDefinition, config: GeneratorConfig, seed: number?): (GenerateResult?, { string }, { string })
	local warnings: { string } = {}
	if typeof(definition) ~= "table" or typeof(definition.zones) ~= "table" or #definition.zones == 0 then
		return nil, { "mine definition needs a non-empty zones list" }, warnings
	end

	local zones, errors = resolveZones(definition, config, warnings)
	if zones == nil then
		return nil, errors, warnings
	end
	errors = validateMine(definition, zones, config, warnings)
	if #errors > 0 then
		return nil, errors, warnings
	end

	local resolvedSeed = seed or definition.seed
	if resolvedSeed == nil then
		resolvedSeed = Random.new():NextInteger(1, MAX_DRAWN_SEED)
	end
	local zoneRandoms: { Random } = {}
	for _, zone in zones do
		zoneRandoms[zone.index] = Random.new(MineGenerator.deriveZoneSeed(resolvedSeed :: number, zone.index))
	end

	local bedrock = resolveBedrock(definition)
	local grid = layoutGrid(zones, bedrock)
	local entrance = entranceBox(grid, definition, bedrock)
	fillBedrockAndRock(grid, zones, config, zoneRandoms)
	carvePockets(grid, definition, zones, zoneRandoms)
	stampVeins(grid, zones, config, zoneRandoms, expandBox(entrance, definition.veinEntranceClearance), warnings)
	stampHandPlaced(grid, zones, config, zoneRandoms, entrance, warnings)
	carveEntrance(grid, entrance)
	local report = buildReport(grid, zones, config, resolvedSeed :: number)

	for _, zoneReport in report.zones do
		if zoneReport.diggableVolume == 0 then
			table.insert(warnings, zoneLabel(zoneReport.index) .. ": pockets and the entrance leave no diggable volume")
		end
	end
	-- the authored counts passed validation; this checks what actually
	-- survived stamping and carving, so no seed can ship unwinnable
	local placedUranium = report.zones[#report.zones].uraniumSoFar
	local requiredUranium = math.ceil(definition.uraniumTarget * config.maxPartyUraniumTargetMultiplier)
	if placedUranium < requiredUranium then
		return nil, { "uranium: only " .. placedUranium .. " rocks survived generation with seed " .. (resolvedSeed :: number) .. ", but the largest party needs " .. requiredUranium .. "; the run is unwinnable" }, warnings
	end

	return { grid = grid, zones = zones, report = report }, errors, warnings
end

export type PreviewZone = {
	index: number,
	requestedOre: { [number]: number },
	expectedHp: number,
}

-- The designer's balance sheet from the file alone: expected ore per zone
-- and the HP a party must chew through, with no grid built. Filler HP is the
-- zone volume minus the expected pocket volume times the hardness-weighted
-- mean HP; vein HP is added on top (veins overwrite filler, so this slightly
-- overstates, which is the safe direction).
function MineGenerator.preview(definition: MineDefinition, config: GeneratorConfig): ({ PreviewZone }?, { string }, { string })
	local warnings: { string } = {}
	if typeof(definition) ~= "table" or typeof(definition.zones) ~= "table" or #definition.zones == 0 then
		return nil, { "mine definition needs a non-empty zones list" }, warnings
	end
	local zones, errors = resolveZones(definition, config, warnings)
	if zones == nil then
		return nil, errors, warnings
	end
	errors = validateMine(definition, zones, config, warnings)
	if #errors > 0 then
		return nil, errors, warnings
	end

	local rocks = config.rockTable.ROCKS
	local fillerOrder = config.rockTable.FILLER_ORDER
	local meanPocketCells = meanClusterCells(definition.pocketRadiusMin, definition.pocketRadiusMax)
	local previews: { PreviewZone } = {}
	for _, zone in zones do
		local weights = RockRules.weights(zone.hardness, #fillerOrder, config.spread)
		local meanFillerHp = 0
		for index, rock in fillerOrder do
			meanFillerHp += weights[index] * (rocks[rock].hp :: number)
		end
		local volume = math.max(zone.depth * zone.height * zone.width - zone.pockets * meanPocketCells, 0)
		local expectedHp = volume * meanFillerHp
		for _, entry in RESOURCE_FIELDS do
			local count = zone.veins[entry.resource]
			local tiers = config.rockTable.RESOURCE_TIERS[entry.resource]
			local tierCounts
			if #tiers == 1 then
				tierCounts = { count }
			else
				tierCounts = RockRules.resolveTierCounts(count, zone.tierBias, #tiers, config.spread)
			end
			for tier, tierCount in tierCounts do
				local definitionOfRock = rocks[tiers[tier]]
				local meanCells = meanClusterCells(definitionOfRock.clusterRadiusMin :: number, definitionOfRock.clusterRadiusMax :: number)
				expectedHp += tierCount * meanCells * (definitionOfRock.hp :: number)
			end
		end
		table.insert(previews, {
			index = zone.index,
			requestedOre = requestedOre(zone, config),
			expectedHp = expectedHp,
		})
	end
	return previews, errors, warnings
end

-- One line per zone for the Output window.
function MineGenerator.formatReport(report: Report): string
	local lines = {
		string.format("mine seed %d, grid %d x %d x %d (depth x height x width)", report.seed, report.gridDepth, report.gridHeight, report.gridWidth),
	}
	for _, zone in report.zones do
		local parts = {}
		for _, entry in RESOURCE_FIELDS do
			table.insert(parts, string.format("%s %d/%d", entry.field, zone.placedOre[entry.resource], math.floor(zone.requestedOre[entry.resource] + 0.5)))
		end
		table.insert(lines, string.format(
			"  zone %d: diggable %d blocks, %d%% within reach, %d pocket cells, hp %d, ore placed/requested: %s, uranium so far %d",
			zone.index,
			zone.diggableVolume,
			math.floor(zone.reachableShare * 100 + 0.5),
			zone.pocketVolume,
			zone.placedHp,
			table.concat(parts, ", "),
			zone.uraniumSoFar
		))
	end
	return table.concat(lines, "\n")
end

return MineGenerator
