-- One-time migration to the folder-per-map layout (GDD "Map authoring"):
-- moves the Workspace Camp folder to ServerStorage/Maps/DEADMANS_CANYON,
-- adds the Mine folder with its Entrance part if missing, and creates
-- FROSTBITE_PASS as a copy so both maps resolve. Safe to rerun: existing map
-- folders are left alone. Run in the gameplay place from the command bar or
-- the MCP execute_luau tool.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)

-- where the placeholder mine mouth goes on the flat canyon baseplate: west
-- of the pad, facing -X so the mine runs away from the camp
local ENTRANCE_POSITION = Vector3.new(-60, 0, 0)
local ENTRANCE_LOOK = Vector3.new(-1, 0, 0)

ChangeHistoryService:SetWaypoint("Before map setup")

local maps = ServerStorage:FindFirstChild(Constants.MAPS_FOLDER)
if not maps then
	maps = Instance.new("Folder")
	maps.Name = Constants.MAPS_FOLDER
	maps.Parent = ServerStorage
end

local function ensureMineEntrance(mapFolder)
	local mine = mapFolder:FindFirstChild(Constants.CAMP_MINE_FOLDER)
	if not mine then
		mine = Instance.new("Folder")
		mine.Name = Constants.CAMP_MINE_FOLDER
		mine.Parent = mapFolder
	end
	local entrance = mine:FindFirstChild(Constants.MINE_ENTRANCE_PART)
	if not entrance then
		entrance = Instance.new("Part")
		entrance.Name = Constants.MINE_ENTRANCE_PART
		entrance.Size = Vector3.new(4, 1, 4)
		entrance.Anchored = true
		entrance.CanCollide = false
		entrance.CanQuery = false
		entrance.Transparency = 0.6
		entrance.Color = Color3.fromRGB(255, 170, 0)
		entrance.CFrame = CFrame.lookAt(ENTRANCE_POSITION, ENTRANCE_POSITION + ENTRANCE_LOOK)
		entrance.Parent = mine
	end
end

local canyonName = Enums.getName(Enums.Map, Enums.Map.DEADMANS_CANYON)
local canyon = maps:FindFirstChild(canyonName)
if not canyon then
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if camp then
		camp.Name = canyonName
		camp.Parent = maps
		canyon = camp
		print("setup_maps: moved Workspace.Camp to " .. canyon:GetFullName())
	else
		canyon = Instance.new("Folder")
		canyon.Name = canyonName
		canyon.Parent = maps
		warn("setup_maps: no Workspace.Camp to move; created an empty " .. canyon:GetFullName())
	end
end
ensureMineEntrance(canyon)

local frostbiteName = Enums.getName(Enums.Map, Enums.Map.FROSTBITE_PASS)
if not maps:FindFirstChild(frostbiteName) then
	local frostbite = canyon:Clone()
	frostbite.Name = frostbiteName
	frostbite.Parent = maps
	print("setup_maps: created " .. frostbite:GetFullName() .. " as a placeholder copy of the canyon")
end

ChangeHistoryService:SetWaypoint("After map setup")
print("setup_maps: done; maps under " .. maps:GetFullName())
