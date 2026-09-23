-- Adds the monster areas to the map that is loaded in Workspace (GDD
-- "Wave Area", "Wave Spawn Locations"), M29:
--   Camp.WaveAreas.Area1: the canyon floor from the camp wall out to the
--     spawns, wide enough to hold every Defensive Zone.
--   Camp.CampArea.Camp: the inside of the camp, wall line included, so
--     monsters that break through find their way to the Refinery.
--   Camp.MonsterSpawns.1 .. 3: small markers at the far end of the canyon.
-- Only each part's footprint matters (MonsterPathManager cuts all the
-- areas into one grid of GameData/Defenses/Placement CELL_SIZE_STUDS
-- cells); the designer moves, resizes, and duplicates them in the
-- Explorer afterwards, so an existing folder is left alone: delete it by
-- hand to have it rebuilt. Run in the gameplay place with the map loaded
-- (map_tools.luau "load"), then save the map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MAP_NAME = "DEADMANS_CANYON"
local AREA_THICKNESS_STUDS = 1
-- the top face floats a hair above the ground so the parts are visible
local LIFT_STUDS = 0.1
local WAVE_AREA_COLOR = Color3.fromRGB(200, 70, 60)
local CAMP_AREA_COLOR = Color3.fromRGB(80, 140, 220)
local SPAWN_COLOR = Color3.fromRGB(150, 40, 180)
local SPAWN_SIZE = Vector3.new(6, 1, 6)

-- world X/Z bounds, read off the canyon in Studio (the floor is y 0; the
-- buttes close it in at about z -140 and 140)
local WAVE_AREAS = {
	{
		name = "Area1",
		minX = 117,
		maxX = 601,
		minZ = -128,
		maxZ = 120,
	},
}
local CAMP_AREAS = {
	{
		name = "Camp",
		minX = -22,
		maxX = 118,
		minZ = -142,
		maxZ = 142,
	},
}
local SPAWNS = {
	Vector3.new(575, 0, -80),
	Vector3.new(575, 0, 0),
	Vector3.new(575, 0, 80),
}

ChangeHistoryService:SetWaypoint("Before monster areas")

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, MAP_NAME .. " is not loaded in Workspace; run map_tools.luau with ACTION = \"load\" first")

local function groundY(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0))
	return if hit then hit.Position.Y else 0
end

local function makeFlatPart(name, minX, maxX, minZ, maxZ, color, parent)
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(maxX - minX, AREA_THICKNESS_STUDS, maxZ - minZ)
	part.CFrame = CFrame.new(centerX, groundY(centerX, centerZ) + LIFT_STUDS - AREA_THICKNESS_STUDS / 2, centerZ)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.9
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function buildFolder(folderName, build)
	if map:FindFirstChild(folderName) then
		print(`build_monster_areas: {map:GetFullName()}.{folderName} already exists; left alone`)
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	build(folder)
	folder.Parent = map
	print(`build_monster_areas: built {folder:GetFullName()} ({#folder:GetChildren()} part(s))`)
end

buildFolder(Constants.CAMP_WAVE_AREAS_FOLDER, function(folder)
	for _, area in WAVE_AREAS do
		makeFlatPart(area.name, area.minX, area.maxX, area.minZ, area.maxZ, WAVE_AREA_COLOR, folder)
	end
end)

buildFolder(Constants.CAMP_CAMP_AREA_FOLDER, function(folder)
	for _, area in CAMP_AREAS do
		makeFlatPart(area.name, area.minX, area.maxX, area.minZ, area.maxZ, CAMP_AREA_COLOR, folder)
	end
end)

buildFolder(Constants.CAMP_MONSTER_SPAWNS_FOLDER, function(folder)
	for number, position in SPAWNS do
		local spawn = Instance.new("Part")
		spawn.Name = tostring(number)
		spawn.Size = SPAWN_SIZE
		spawn.CFrame = CFrame.new(position.X, groundY(position.X, position.Z) + SPAWN_SIZE.Y / 2, position.Z)
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.CanTouch = false
		spawn.CastShadow = false
		spawn.Transparency = 0.5
		spawn.Color = SPAWN_COLOR
		spawn.Material = Enum.Material.Neon
		spawn.Parent = folder
	end
end)

ChangeHistoryService:SetWaypoint("After monster areas")
