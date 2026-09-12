--!strict

-- Loads the run's map (GDD "Map authoring"): every map is a Folder under
-- ServerStorage/Maps named by its Enums.Map key, cloned into Workspace as
-- Camp when the run starts, so only the active map exists in memory. A map
-- folder left in Workspace by the designer's "Load map for editing" tool is
-- used as-is with a warning, so an unsaved edit still plays. Terrain is
-- optional: a map with a TerrainSnapshot region gets it pasted at load.
local ServerStorage = game:GetService("ServerStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local GameplayMapManager = require(script.Parent.GameplayMapManager)

local MapManager = {}
MapManager.__index = MapManager

export type MapManager = typeof(setmetatable(
	{} :: {
		map: number?,
		camp: Folder?,
	},
	MapManager
))

function MapManager:getCamp(): Folder?
	return self.camp
end

function MapManager:getMap(): number?
	return self.map
end

-- the mine's origin and facing, read from the entrance part the designer placed
function MapManager:getMineEntrance(): (Vector3?, number?)
	local camp = self.camp
	local mine = if camp then camp:FindFirstChild(Constants.CAMP_MINE_FOLDER) else nil
	local entrance = if mine then mine:FindFirstChild(Constants.MINE_ENTRANCE_PART) else nil
	if not entrance or not entrance:IsA("BasePart") then
		return nil, nil
	end
	return entrance.Position, MineSpace.facingFromLookVector(entrance.CFrame.LookVector)
end

function MapManager:findSource(mapName: string): (Instance?, boolean)
	local unsaved = workspace:FindFirstChild(mapName)
	if unsaved and unsaved:IsA("Folder") then
		return unsaved, true
	end
	local maps = ServerStorage:FindFirstChild(Constants.MAPS_FOLDER)
	local source = if maps then maps:FindFirstChild(mapName) else nil
	if source and source:IsA("Folder") then
		return source, false
	end
	return nil, false
end

function MapManager:pasteTerrain(source: Instance)
	local region = source:FindFirstChild(Constants.MAP_TERRAIN_REGION)
	local bounds = source:FindFirstChild(Constants.MAP_TERRAIN_BOUNDS_PART)
	if not region or not region:IsA("TerrainRegion") then
		return
	end
	if not bounds or not bounds:IsA("BasePart") then
		warn(`MapManager: {source:GetFullName()} has a terrain snapshot but no {Constants.MAP_TERRAIN_BOUNDS_PART} part; terrain skipped`)
		return
	end
	local terrain = workspace.Terrain
	terrain:Clear()
	local corner = terrain:WorldToCell(bounds.Position - bounds.Size / 2)
	terrain:PasteRegion(region, corner, true)
end

function MapManager:loadMap(map: number): boolean
	local mapName = Enums.getName(Enums.Map, map) or tostring(map)
	local source, isUnsaved = self:findSource(mapName)
	if not source then
		warn(`MapManager: no map folder named {mapName} under ServerStorage.{Constants.MAPS_FOLDER} or Workspace`)
		return false
	end

	local previous = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if previous then
		previous:Destroy()
	end

	local camp: Folder
	if isUnsaved then
		warn(`MapManager: using the unsaved {mapName} folder found in Workspace (run the Save map tool before publishing)`)
		camp = source :: Folder
	else
		camp = source:Clone() :: Folder
		-- the snapshot stays with the source; the live terrain is pasted below
		local regionCopy = camp:FindFirstChild(Constants.MAP_TERRAIN_REGION)
		if regionCopy then
			regionCopy:Destroy()
		end
		self:pasteTerrain(source)
	end
	camp.Name = Constants.CAMP_FOLDER
	camp.Parent = workspace

	self.map = map
	self.camp = camp
	GameplayMapManager:checkCamp(camp, mapName)
	print(`[MapManager] loaded map {mapName}`)
	return true
end

function MapManager:init()
end

function MapManager.new(): MapManager
	local self = setmetatable({}, MapManager) :: MapManager
	self.map = nil
	self.camp = nil
	return self
end

return MapManager.new()
