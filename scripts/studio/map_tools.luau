-- Designer map tools for Edit mode (GDD "Map authoring"). Set ACTION and
-- MAP_NAME below, then run from the command bar or the MCP execute_luau tool.
--
--   "load": moves ServerStorage/Maps/<MAP_NAME> into Workspace (keeping its
--           name) and, if the map has a TerrainSnapshot, clears the live
--           terrain and pastes the snapshot, so you can edit with everything
--           in place. Pressing Play with the folder still in Workspace uses
--           it as-is (MapManager warns), so an unsaved edit is never lost.
--   "save": if the map has a TerrainBounds part, snapshots the live terrain
--           inside it into the map's TerrainSnapshot; then moves the folder
--           back under ServerStorage/Maps. Maps without TerrainBounds are
--           plain folders and the terrain step is skipped. Any mine preview
--           is removed first so it never ends up inside a map.
--   "preview_mine": with the map in Workspace, generates its mine from
--           Mine.Entrance exactly as the server would and draws translucent
--           boxes for the bedrock envelope, each chamber, each corridor, and
--           each hand-placed rock into Workspace/MinePreview, so the camp can
--           be built around the real mine footprint. Rerun after moving the
--           entrance. The preview is only a guide; the server deletes it at run start.
--   "clear_preview": removes Workspace/MinePreview.
local ACTION = "load"
local MAP_NAME = "DEADMANS_CANYON"
local PREVIEW_SEED = 1

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local MineGenerator = require(ReplicatedStorage.Shared.MineGenerator)
local MineSpace = require(ReplicatedStorage.Shared.MineSpace)
local GameData = ServerScriptService.GameData
local MineRegistryData = require(GameData.Mines.Registry)
local GenerationData = require(GameData.Mines.Generation)
local RockDefinitionsData = require(GameData.Rocks.RockDefinitions)
local WeightsData = require(GameData.Rocks.Weights)
local DifficultyData = require(GameData.Control.Difficulty)
local StudioDefaultsData = require(GameData.Run.StudioDefaults)

local maps = ServerStorage:FindFirstChild(Constants.MAPS_FOLDER)
assert(maps, "ServerStorage has no " .. Constants.MAPS_FOLDER .. " folder; run setup_maps.luau first")

local terrain = workspace.Terrain

local function regionFor(bounds)
	local minCorner = terrain:WorldToCell(bounds.Position - bounds.Size / 2)
	local maxCorner = terrain:WorldToCell(bounds.Position + bounds.Size / 2)
	return Region3int16.new(
		Vector3int16.new(minCorner.X, minCorner.Y, minCorner.Z),
		Vector3int16.new(maxCorner.X, maxCorner.Y, maxCorner.Z)
	), minCorner
end

local function clearPreview()
	local previous = workspace:FindFirstChild(Constants.MINE_PREVIEW_FOLDER)
	if previous then
		previous:Destroy()
	end
end

local function addPreviewBox(folder: Folder, name: string, space, depthStart: number, depthCount: number, heightStart: number, heightCount: number, widthStart: number, widthCount: number, color: Color3, transparency: number, labelText: string?)
	local first = MineSpace.cellToWorld(space, depthStart, heightStart, widthStart)
	local last = MineSpace.cellToWorld(space, depthStart + depthCount - 1, heightStart + heightCount - 1, widthStart + widthCount - 1)
	local size = space.blockSize
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Transparency = transparency
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new((first + last) / 2)
	part.Size = Vector3.new(
		math.abs(space.forward.X) * depthCount * size + math.abs(space.widthAxis.X) * widthCount * size,
		heightCount * size,
		math.abs(space.forward.Z) * depthCount * size + math.abs(space.widthAxis.Z) * widthCount * size
	)
	local outline = Instance.new("SelectionBox")
	outline.Adornee = part
	outline.Color3 = color
	outline.LineThickness = 0.05
	outline.Parent = part
	if labelText then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(200, 40)
		billboard.AlwaysOnTop = true
		billboard.StudsOffsetWorldSpace = Vector3.new(0, heightCount * size / 2 + 2, 0)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Text = labelText
		label.Parent = billboard
		billboard.Parent = part
	end
	part.Parent = folder
	return part
end

local function previewMine(mapFolder: Folder)
	local mapValue = Enums.getValueByName(Enums.Map, MAP_NAME)
	assert(mapValue, MAP_NAME .. " is not an Enums.Map key")
	local definition = MineRegistryData[mapValue]
	assert(definition, "no mine definition registered for " .. MAP_NAME)
	local mine = mapFolder:FindFirstChild(Constants.CAMP_MINE_FOLDER)
	local entrance = if mine then mine:FindFirstChild(Constants.MINE_ENTRANCE_PART) else nil
	assert(entrance and entrance:IsA("BasePart"), MAP_NAME .. " has no " .. Constants.CAMP_MINE_FOLDER .. "." .. Constants.MINE_ENTRANCE_PART .. " part")
	local origin = entrance.Position
	local facing = MineSpace.facingFromLookVector(entrance.CFrame.LookVector)

	-- mirrors MineManager:buildConfig; kept inline so Edit mode never loads
	-- the gameplay managers
	local difficulty = StudioDefaultsData.DIFFICULTY
	local config = {
		rockTable = RockDefinitionsData,
		spread = WeightsData.SPREAD,
		minCenter = WeightsData.MIN_CENTER,
		maxCenter = WeightsData.MAX_CENTER,
		hardnessShift = DifficultyData.HARDNESS_SHIFT,
		difficultyValue = DifficultyData.DIFFICULTY_VALUE[difficulty],
		veinDivisor = DifficultyData.VEIN_DIVISOR[difficulty],
		pickaxeReachBlocks = GenerationData.PICKAXE_REACH_BLOCKS,
		isClimbingEnabled = GenerationData.IS_CLIMBING_ENABLED,
		maxPartyUraniumTargetMultiplier = GenerationData.MAX_PARTY_URANIUM_TARGET_MULTIPLIER,
	}
	local result, errors, warnings = MineGenerator.generate(definition, config, PREVIEW_SEED)
	for _, warning in warnings do
		warn("map_tools: " .. warning)
	end
	if not result then
		for _, err in errors do
			warn("map_tools: FATAL " .. err)
		end
		error("map_tools: mine generation failed; see warnings above")
	end
	local grid = result.grid
	local space = MineSpace.new(origin, facing, grid.centrelineWidth, grid.floorHeight, Constants.MINE_BLOCK_SIZE_STUDS)

	clearPreview()
	local folder = Instance.new("Folder")
	folder.Name = Constants.MINE_PREVIEW_FOLDER
	addPreviewBox(folder, "Bedrock", space, 0, grid.depth, 0, grid.height, 0, grid.width, Color3.fromRGB(120, 120, 120), 0.85, "Mine envelope " .. tostring(Enums.getName(Enums.MineFacing, facing)))
	for _, chamber in result.chambers do
		local label = "Chamber " .. chamber.index .. " (camp level " .. chamber.unlockCampLevel .. ")"
		addPreviewBox(folder, "Chamber" .. chamber.index, space, chamber.depthStart, chamber.depth, chamber.heightStart, chamber.height, chamber.widthStart, chamber.width, Color3.fromRGB(80, 160, 255), 0.7, label)
		if chamber.hasCorridor then
			addPreviewBox(folder, "Corridor" .. chamber.index, space, chamber.depthStart, chamber.depth, chamber.heightStart, chamber.corridorHeight, chamber.corridorWidthStart, chamber.corridorWidth, Color3.fromRGB(255, 200, 60), 0.5, nil)
		end
		local centreline = chamber.corridorWidthStart + math.floor((chamber.corridorWidth - 1) / 2)
		for entryIndex, entry in chamber.handPlaced do
			local rockName = Enums.getName(Enums.RockName, entry.rock) or tostring(entry.rock)
			addPreviewBox(folder, "HandPlaced" .. chamber.index .. "_" .. entryIndex, space, chamber.depthStart + entry.depth, 1, chamber.heightStart + entry.height, 1, centreline + entry.widthOffset, 1, Color3.fromRGB(255, 80, 200), 0.2, rockName)
		end
	end
	folder.Parent = workspace
	print(MineGenerator.formatReport(result.report))
	print("map_tools: mine preview for " .. MAP_NAME .. " drawn in Workspace/" .. Constants.MINE_PREVIEW_FOLDER .. " from " .. entrance:GetFullName() .. "; envelope " .. grid.depth .. " deep x " .. grid.height .. " high x " .. grid.width .. " wide blocks")
end

if ACTION == "load" then
	ChangeHistoryService:SetWaypoint("Before load map " .. MAP_NAME)
	local mapFolder = maps:FindFirstChild(MAP_NAME)
	assert(mapFolder, "no map folder named " .. MAP_NAME .. " under " .. maps:GetFullName())
	local unsaved = workspace:FindFirstChild(MAP_NAME)
	assert(not unsaved, MAP_NAME .. " is already in Workspace; save it first")
	local snapshot = mapFolder:FindFirstChild(Constants.MAP_TERRAIN_REGION)
	local bounds = mapFolder:FindFirstChild(Constants.MAP_TERRAIN_BOUNDS_PART)
	if snapshot and bounds then
		terrain:Clear()
		local _, corner = regionFor(bounds)
		terrain:PasteRegion(snapshot, corner, true)
		print("map_tools: pasted terrain snapshot for " .. MAP_NAME)
	end
	mapFolder.Parent = workspace
	ChangeHistoryService:SetWaypoint("After load map " .. MAP_NAME)
	print("map_tools: " .. MAP_NAME .. " is in Workspace for editing; run with ACTION = \"save\" when done")
elseif ACTION == "save" then
	ChangeHistoryService:SetWaypoint("Before save map " .. MAP_NAME)
	local mapFolder = workspace:FindFirstChild(MAP_NAME)
	assert(mapFolder, MAP_NAME .. " is not in Workspace; nothing to save")
	clearPreview()
	local bounds = mapFolder:FindFirstChild(Constants.MAP_TERRAIN_BOUNDS_PART)
	if bounds then
		local previous = mapFolder:FindFirstChild(Constants.MAP_TERRAIN_REGION)
		if previous then
			previous:Destroy()
		end
		local region = regionFor(bounds)
		local snapshot = terrain:CopyRegion(region)
		snapshot.Name = Constants.MAP_TERRAIN_REGION
		snapshot.Parent = mapFolder
		print("map_tools: saved terrain snapshot for " .. MAP_NAME)
	end
	mapFolder.Parent = maps
	ChangeHistoryService:SetWaypoint("After save map " .. MAP_NAME)
	print("map_tools: " .. MAP_NAME .. " saved back under " .. maps:GetFullName())
elseif ACTION == "preview_mine" then
	ChangeHistoryService:SetWaypoint("Before mine preview " .. MAP_NAME)
	local mapFolder = workspace:FindFirstChild(MAP_NAME)
	assert(mapFolder, MAP_NAME .. " is not in Workspace; run with ACTION = \"load\" first")
	previewMine(mapFolder)
	ChangeHistoryService:SetWaypoint("After mine preview " .. MAP_NAME)
elseif ACTION == "clear_preview" then
	ChangeHistoryService:SetWaypoint("Before clear mine preview")
	clearPreview()
	ChangeHistoryService:SetWaypoint("After clear mine preview")
	print("map_tools: mine preview cleared")
else
	error("map_tools: ACTION must be \"load\", \"save\", \"preview_mine\" or \"clear_preview\"")
end
