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
--           plain folders and the terrain step is skipped.
local ACTION = "load"
local MAP_NAME = "DEADMANS_CANYON"

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

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
else
	error("map_tools: ACTION must be \"load\" or \"save\"")
end
