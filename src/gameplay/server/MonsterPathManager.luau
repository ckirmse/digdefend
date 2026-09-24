--!strict

-- The monsters' way to the Refinery (GDD "Setting Up Waves": Wave Area,
-- Pathfinding), M29. At run start one square grid of
-- GameData/Defenses/Placement CELL_SIZE_STUDS cells is laid over every
-- Camp.WaveAreas and Camp.CampArea part. Each cell inside an area gets its
-- ground height (a ray down) and is marked walkable unless something
-- solid that never moves stands on it (a box query above the ground, with
-- the walls, the gate, and the areas themselves left out). The Refinery's
-- cells are the goals. Barriers are the walls and the shut gate
-- (StructureManager) and every Tower and blocking Trap (PlacementManager);
-- their cells stay walkable but cost a ground monster BARRIER_COST_CELLS
-- to enter, which is how "go round if you can, break through if you
-- must" falls out of one Dijkstra pass (pure FlowField). A barrier change
-- only marks the ground field dirty; MonsterManager's tick recomputes it
-- at most every PATH_RECOMPUTE_MIN_SEC. The air field (every inside cell,
-- no barriers) is computed once. Nothing here is an instance except the
-- dev tool's debug view.
local Players = game:GetService("Players")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local FlowField = require("@game/ReplicatedStorage/Shared/FlowField")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local PlacementData = require("@game/ServerScriptService/GameData/Defenses/Placement")
local MapManager = require(script.Parent.MapManager)
local PlacementManager = require(script.Parent.PlacementManager)
local StructureManager = require(script.Parent.StructureManager)

local MonsterPathManager = {}
MonsterPathManager.__index = MonsterPathManager

export type MonsterPathManager = typeof(setmetatable(
	{} :: {
		grid: FlowField.Grid?,
		groundField: FlowField.Field?,
		airField: FlowField.Field?,
		goals: { number },
		refineryPosition: Vector3?,
		-- spawn number -> the spawn part's ground position
		spawnPositions: { [number]: Vector3 },
		isDirty: boolean,
		lastComputeTime: number,
		-- counts up on every grid or field change, so a cached route knows it is stale
		version: number,
		debugFolder: Folder?,
	},
	MonsterPathManager
))

-- a solid part this far above the ground blocks a cell; lower is floor
-- clutter a monster steps over
local OBSTACLE_CLEARANCE_STUDS = 1
local OBSTACLE_HEIGHT_STUDS = 5
-- the box query covers this share of a cell, so a wall that only grazes
-- a cell's edge leaves it open
local OBSTACLE_CELL_SHARE = 0.8
-- the ground is looked for from just above the area part's top face, so
-- a roof or a post's top is never mistaken for the floor
local GROUND_RAY_START_ABOVE_STUDS = 4
local GROUND_RAY_LENGTH_STUDS = 40
local DEBUG_FOLDER = "MonsterPathDebug"
local DEBUG_ARROW_EVERY_CELLS = 3

-- the flat footprint of every part directly under a folder
local function areaParts(camp: Instance, folderName: string): { BasePart }
	local parts = {}
	local folder = camp:FindFirstChild(folderName)
	for _, child in if folder then folder:GetChildren() else {} do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

local function isInsidePart(part: BasePart, x: number, z: number): boolean
	local localPosition = part.CFrame:PointToObjectSpace(Vector3.new(x, part.Position.Y, z))
	return math.abs(localPosition.X) <= part.Size.X / 2 and math.abs(localPosition.Z) <= part.Size.Z / 2
end

-- whether a cell centre is inside a box's flat footprint
local function isInsideBox(cframe: CFrame, size: Vector3, x: number, z: number): boolean
	local localPosition = cframe:PointToObjectSpace(Vector3.new(x, cframe.Position.Y, z))
	return math.abs(localPosition.X) <= size.X / 2 and math.abs(localPosition.Z) <= size.Z / 2
end

function MonsterPathManager:getGrid(): FlowField.Grid?
	return self.grid
end

function MonsterPathManager:getField(isAir: boolean): FlowField.Field?
	return if isAir then self.airField else self.groundField
end

function MonsterPathManager:getVersion(): number
	return self.version
end

function MonsterPathManager:getRefineryPosition(): Vector3?
	return self.refineryPosition
end

function MonsterPathManager:getSpawnPosition(spawnNumber: number): Vector3?
	return self.spawnPositions[spawnNumber]
end

function MonsterPathManager:getSpawnNumbers(): { number }
	local numbers = {}
	for spawnNumber in self.spawnPositions do
		table.insert(numbers, spawnNumber)
	end
	table.sort(numbers)
	return numbers
end

-- the ground under a flat position, or nil off the grid
function MonsterPathManager:getGroundHeight(x: number, z: number): number?
	local grid = self.grid
	if not grid then
		return nil
	end
	local index = FlowField.indexAt(grid, x, z)
	if not index or not grid.inside[index] then
		return nil
	end
	return grid.heights[index]
end

function MonsterPathManager:markDirty()
	self.isDirty = true
end

-- the cells a box's footprint covers, by testing each cell centre in its
-- flat bounds
function MonsterPathManager:cellsUnderBox(cframe: CFrame, size: Vector3): { number }
	local grid = self.grid
	if not grid then
		return {}
	end
	local cells = {}
	local halfDiagonal = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	local center = cframe.Position
	local minColumn = math.max(1, math.floor((center.X - halfDiagonal - grid.originX) / grid.cellSizeStuds) + 1)
	local maxColumn = math.min(grid.columns, math.floor((center.X + halfDiagonal - grid.originX) / grid.cellSizeStuds) + 1)
	local minRow = math.max(1, math.floor((center.Z - halfDiagonal - grid.originZ) / grid.cellSizeStuds) + 1)
	local maxRow = math.min(grid.rows, math.floor((center.Z + halfDiagonal - grid.originZ) / grid.cellSizeStuds) + 1)
	for row = minRow, maxRow do
		for column = minColumn, maxColumn do
			local index = FlowField.indexOf(grid, column, row)
			local x, z = FlowField.centerOf(grid, index)
			if isInsideBox(cframe, size, x, z) then
				table.insert(cells, index)
			end
		end
	end
	return cells
end

function MonsterPathManager:scanCells(grid: FlowField.Grid, areas: { BasePart }, excluded: { Instance })
	local rayParameters = RaycastParams.new()
	rayParameters.FilterType = Enum.RaycastFilterType.Exclude
	rayParameters.FilterDescendantsInstances = excluded
	rayParameters.RespectCanCollide = true
	local overlapParameters = OverlapParams.new()
	overlapParameters.FilterType = Enum.RaycastFilterType.Exclude
	overlapParameters.FilterDescendantsInstances = excluded
	overlapParameters.RespectCanCollide = true
	local boxSize = Vector3.new(grid.cellSizeStuds * OBSTACLE_CELL_SHARE, OBSTACLE_HEIGHT_STUDS, grid.cellSizeStuds * OBSTACLE_CELL_SHARE)
	for index = 1, grid.columns * grid.rows do
		local x, z = FlowField.centerOf(grid, index)
		local containing: BasePart? = nil
		for _, area in areas do
			if isInsidePart(area, x, z) then
				containing = area
				break
			end
		end
		if not containing then
			continue
		end
		grid.inside[index] = true
		local topY = containing.Position.Y + containing.Size.Y / 2
		local hit = workspace:Raycast(Vector3.new(x, topY + GROUND_RAY_START_ABOVE_STUDS, z), Vector3.new(0, -GROUND_RAY_LENGTH_STUDS, 0), rayParameters)
		local groundY = if hit then hit.Position.Y else topY
		grid.heights[index] = groundY
		local boxCenter = CFrame.new(x, groundY + OBSTACLE_CLEARANCE_STUDS + OBSTACLE_HEIGHT_STUDS / 2, z)
		grid.walkable[index] = #workspace:GetPartBoundsInBox(boxCenter, boxSize, overlapParameters) == 0
	end
end

function MonsterPathManager:buildGrid(camp: Instance)
	local areas = areaParts(camp, Constants.CAMP_WAVE_AREAS_FOLDER)
	for _, part in areaParts(camp, Constants.CAMP_CAMP_AREA_FOLDER) do
		table.insert(areas, part)
	end
	if #areas == 0 then
		warn(`MonsterPathManager: {camp:GetFullName()} has no {Constants.CAMP_WAVE_AREAS_FOLDER} or {Constants.CAMP_CAMP_AREA_FOLDER} parts; monsters have nowhere to walk`)
		return
	end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, area in areas do
		local half = area.Size / 2
		for _, corner in { Vector3.new(half.X, 0, half.Z), Vector3.new(-half.X, 0, half.Z), Vector3.new(half.X, 0, -half.Z), Vector3.new(-half.X, 0, -half.Z) } do
			local world = area.CFrame:PointToWorldSpace(corner)
			minX = math.min(minX, world.X)
			maxX = math.max(maxX, world.X)
			minZ = math.min(minZ, world.Z)
			maxZ = math.max(maxZ, world.Z)
		end
	end
	local cellSize = PlacementData.CELL_SIZE_STUDS
	local originX = math.floor(minX / cellSize) * cellSize
	local originZ = math.floor(minZ / cellSize) * cellSize
	local columns = math.ceil((maxX - originX) / cellSize)
	local rows = math.ceil((maxZ - originZ) / cellSize)
	local grid = FlowField.newGrid(originX, originZ, columns, rows, cellSize)

	-- the marker parts are the designer's guides and never show in play
	local excluded: { Instance } = {}
	for _, folderName in { Constants.CAMP_WAVE_AREAS_FOLDER, Constants.CAMP_CAMP_AREA_FOLDER, Constants.CAMP_MONSTER_SPAWNS_FOLDER } do
		local folder = camp:FindFirstChild(folderName)
		if folder then
			table.insert(excluded, folder)
			for _, descendant in folder:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				end
			end
		end
	end
	-- the walls and the gate are barriers, set apart from what never moves
	for _, name in { Constants.CAMP_WALLS_FOLDER, Constants.CAMP_GATE_MODEL } do
		local child = camp:FindFirstChild(name)
		if child then
			table.insert(excluded, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	self:scanCells(grid, areas, excluded)
	self.grid = grid

	-- the Refinery's cells are the goals, open so the field reaches them
	self.goals = {}
	for _, box in StructureManager:getStructureBoxes() do
		if box.kind ~= Enums.StructureKind.REFINERY then
			continue
		end
		self.refineryPosition = box.cframe.Position
		local expanded = box.size + Vector3.new(cellSize * 2, 0, cellSize * 2)
		for _, index in self:cellsUnderBox(box.cframe, expanded) do
			grid.inside[index] = true
			grid.walkable[index] = true
			table.insert(self.goals, index)
		end
	end
	if #self.goals == 0 then
		warn("MonsterPathManager: the Refinery is not on the monster grid; monsters will not find it")
	end
	self.airField = FlowField.compute(grid, self.goals, {
		isAir = true,
		barrierCost = BehaviorData.BARRIER_COST_CELLS,
	})
	local walkableCount = 0
	local insideCount = 0
	for index = 1, columns * rows do
		if grid.inside[index] then
			insideCount += 1
		end
		if grid.walkable[index] then
			walkableCount += 1
		end
	end
	print(`[MonsterPathManager] grid {columns} x {rows} cells of {cellSize} studs: {insideCount} inside the areas, {walkableCount} walkable, {#self.goals} goal cells`)
end

function MonsterPathManager:readSpawns(camp: Instance)
	self.spawnPositions = {}
	local folder = camp:FindFirstChild(Constants.CAMP_MONSTER_SPAWNS_FOLDER)
	for _, child in if folder then folder:GetChildren() else {} do
		local spawnNumber = tonumber(child.Name)
		if child:IsA("BasePart") and spawnNumber then
			self.spawnPositions[spawnNumber] = child.Position - Vector3.new(0, child.Size.Y / 2, 0)
		end
	end
	if next(self.spawnPositions) == nil then
		warn(`MonsterPathManager: {camp:GetFullName()} has no numbered {Constants.CAMP_MONSTER_SPAWNS_FOLDER} parts; waves cannot spawn`)
	end
end

-- the barriers now standing: the walls and a shut gate, every Tower, and
-- every Trap that blocks
function MonsterPathManager:refreshBarriers()
	local grid = self.grid
	if not grid then
		return
	end
	grid.barriers = {}
	local isGateOpen = StructureManager:isGateOpenNow()
	for _, box in StructureManager:getStructureBoxes() do
		if box.isDestroyed or box.kind == Enums.StructureKind.REFINERY then
			continue
		end
		if box.kind == Enums.StructureKind.GATE and isGateOpen then
			continue
		end
		for _, index in self:cellsUnderBox(box.cframe, box.size) do
			grid.barriers[index] = box.id
		end
	end
	local catalog = PlacementManager:getCatalog()
	for _, placement in PlacementManager:getPlacements() do
		local isBarrier = placement.placementKind == Enums.PlacementKind.TOWER
		if placement.placementKind == Enums.PlacementKind.TRAP then
			local trap = catalog.traps[placement.typeKind]
			isBarrier = trap ~= nil and trap.BEHAVIOR == Enums.TrapBehavior.BARRIER
		end
		if not isBarrier then
			continue
		end
		for _, index in self:cellsUnderBox(placement.shadow.CFrame, placement.shadow.Size) do
			grid.barriers[index] = placement.id
		end
	end
end

function MonsterPathManager:recompute(now: number)
	local grid = self.grid
	if not grid then
		return
	end
	self:refreshBarriers()
	self.groundField = FlowField.compute(grid, self.goals, {
		isAir = false,
		barrierCost = BehaviorData.BARRIER_COST_CELLS,
	})
	self.isDirty = false
	self.lastComputeTime = now
	self.version += 1
	if self.debugFolder then
		self:drawDebug()
	end
end

function MonsterPathManager:recomputeIfNeeded(now: number)
	if self.isDirty and now - self.lastComputeTime >= BehaviorData.PATH_RECOMPUTE_MIN_SEC then
		self:recompute(now)
	end
end

-- the dev tool's view: red where nothing may walk, orange barriers, and an
-- arrow every few cells pointing along the ground field
function MonsterPathManager:drawDebug()
	local previous = self.debugFolder
	if previous then
		previous:Destroy()
	end
	local grid = self.grid
	local field = self.groundField
	local folder = Instance.new("Folder")
	folder.Name = DEBUG_FOLDER
	self.debugFolder = folder
	if not grid or not field then
		folder.Parent = workspace
		return
	end
	local cellSize = grid.cellSizeStuds
	for index = 1, grid.columns * grid.rows do
		if not grid.inside[index] then
			continue
		end
		local column, row = FlowField.cellOf(grid, index)
		local x, z = FlowField.centerOf(grid, index)
		local y = grid.heights[index] + 0.3
		local color: Color3? = nil
		if not grid.walkable[index] then
			color = Color3.fromRGB(220, 50, 50)
		elseif grid.barriers[index] then
			color = Color3.fromRGB(240, 150, 40)
		elseif field.costs[index] == math.huge then
			color = Color3.fromRGB(90, 90, 90)
		end
		if color then
			local tile = Instance.new("Part")
			tile.Anchored = true
			tile.CanCollide = false
			tile.CanQuery = false
			tile.CanTouch = false
			tile.CastShadow = false
			tile.Material = Enum.Material.Neon
			tile.Transparency = 0.5
			tile.Color = color
			tile.Size = Vector3.new(cellSize * 0.9, 0.2, cellSize * 0.9)
			tile.CFrame = CFrame.new(x, y, z)
			tile.Parent = folder
		elseif column % DEBUG_ARROW_EVERY_CELLS == 0 and row % DEBUG_ARROW_EVERY_CELLS == 0 and field.nextIndex[index] ~= 0 then
			local nextX, nextZ = FlowField.centerOf(grid, field.nextIndex[index])
			local arrow = Instance.new("WedgePart")
			arrow.Anchored = true
			arrow.CanCollide = false
			arrow.CanQuery = false
			arrow.CanTouch = false
			arrow.CastShadow = false
			arrow.Material = Enum.Material.Neon
			arrow.Color = Color3.fromRGB(80, 220, 120)
			arrow.Size = Vector3.new(1, 0.4, 2.5)
			local from = Vector3.new(x, y, z)
			arrow.CFrame = CFrame.lookAt(from, Vector3.new(nextX, y, nextZ))
			arrow.Parent = folder
		end
	end
	folder.Parent = workspace
end

function MonsterPathManager:setDebugVisible(isVisible: boolean)
	if isVisible then
		self:drawDebug()
		return
	end
	local folder = self.debugFolder
	if folder then
		folder:Destroy()
	end
	self.debugFolder = nil
end

function MonsterPathManager:isDebugVisible(): boolean
	return self.debugFolder ~= nil
end

-- a run (or a dev-tool restart) reads the fresh camp. Runs after the
-- structures and placements have reset, so the walls stand and no
-- Tower is left from the last run
function MonsterPathManager:onRunStarted()
	self.grid = nil
	self.groundField = nil
	self.airField = nil
	self.goals = {}
	self.refineryPosition = nil
	self.spawnPositions = {}
	local camp = MapManager:getCamp()
	if not camp then
		warn("MonsterPathManager: no camp is loaded; monsters have nowhere to walk")
		return
	end
	self:buildGrid(camp)
	self:readSpawns(camp)
	self:recompute(workspace:GetServerTimeNow())
end

function MonsterPathManager:init()
	StructureManager:subscribeBarriersChanged(
		function()
			self:markDirty()
		end
	)
	PlacementManager:subscribePlacementsChanged(
		function()
			self:markDirty()
		end
	)
end

function MonsterPathManager.new(): MonsterPathManager
	local self = setmetatable({}, MonsterPathManager) :: MonsterPathManager
	self.grid = nil
	self.groundField = nil
	self.airField = nil
	self.goals = {}
	self.refineryPosition = nil
	self.spawnPositions = {}
	self.isDirty = false
	self.lastComputeTime = 0
	self.version = 0
	self.debugFolder = nil
	return self
end

return MonsterPathManager.new()
