-- Builds the placeholder Defense Table in a map's Defense Store (GDD
-- "Defense Table"): a wooden table with a map of the battlefield on it and
-- an invisible Prompt part that carries the Build Mode prompt
-- (DefenseTableManager creates the ProximityPrompt at run start). It takes
-- the place of the six Trap stands, which it removes (decided 2026-09-30:
-- Traps are bought as they are placed). The table stands where the stands
-- were, pulled a little toward the middle of the room; run again, it
-- rebuilds in the spot the table already has, so the designer can move it
-- and keep it. Works on the map in ServerStorage/Maps, or on one loaded
-- into Workspace with map_tools.luau. Names must match
-- Constants.DEFENSE_TABLE_*.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MAP_NAME = "DEADMANS_CANYON"
local TABLE_SIZE = Vector3.new(14, 0.5, 7)
local TABLE_HEIGHT_STUDS = 3
local LEG_SIZE = Vector3.new(0.6, TABLE_HEIGHT_STUDS, 0.6)
local MAP_SIZE = Vector3.new(12.5, 0.12, 5.8)
-- how far the table is pulled from the stands' wall toward the room
local PULL_FROM_WALL_STUDS = 3
local WOOD_COLOR = Color3.fromRGB(105, 70, 45)
local MAP_COLOR = Color3.fromRGB(214, 190, 140)
local ZONE_COLOR = Color3.fromRGB(120, 150, 90)
local CAMP_COLOR = Color3.fromRGB(90, 80, 70)
local TOKEN_COLOR = Color3.fromRGB(200, 60, 50)

ChangeHistoryService:SetWaypoint("Before Defense Table")

local map = workspace:FindFirstChild(MAP_NAME) or ServerStorage:FindFirstChild(Constants.MAPS_FOLDER):FindFirstChild(MAP_NAME)
assert(map, MAP_NAME .. " is neither loaded in Workspace nor under ServerStorage." .. Constants.MAPS_FOLDER)
local store = map:FindFirstChild(Constants.CAMP_DEFENSE_STORE_MODEL)
assert(store, MAP_NAME .. " has no " .. Constants.CAMP_DEFENSE_STORE_MODEL)
local floor = store:FindFirstChild("Floor")

-- where the table goes: where it already is, else the middle of the old
-- stands pulled toward the room
local pose
local existing = store:FindFirstChild(Constants.DEFENSE_TABLE_MODEL)
if existing then
	pose = existing:GetPivot()
	existing:Destroy()
end
local standPositions = {}
for _, child in store:GetChildren() do
	if child:IsA("Model") and string.match(child.Name, "Stand$") then
		table.insert(standPositions, child:GetPivot().Position)
		child:Destroy()
	end
end
if not pose then
	assert(#standPositions > 0 or floor, "the store has neither Trap stands nor a Floor to place the table by")
	local sum = Vector3.zero
	for _, position in standPositions do
		sum += position
	end
	local center = if #standPositions > 0 then sum / #standPositions else floor.Position
	local floorTop = center.Y
	if floor then
		local floorSize = floor.Size
		-- the floor slab may be authored on its side, so its thickness is its smallest dimension
		floorTop = floor.Position.Y + math.min(floorSize.X, floorSize.Y, floorSize.Z) / 2
		local toRoom = Vector3.new(floor.Position.X - center.X, 0, floor.Position.Z - center.Z)
		if toRoom.Magnitude > 0.01 then
			center += toRoom.Unit * PULL_FROM_WALL_STUDS
		end
	end
	pose = CFrame.new(center.X, floorTop, center.Z)
end

local function makePart(name, size, color, material, offset, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = pose * offset
	part.Parent = parent
	return part
end

local model = Instance.new("Model")
model.Name = Constants.DEFENSE_TABLE_MODEL
-- the client reads the table as one thing: every part arrives together
model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

local topY = TABLE_HEIGHT_STUDS + TABLE_SIZE.Y / 2
local top = makePart("Top", TABLE_SIZE, WOOD_COLOR, Enum.Material.WoodPlanks, CFrame.new(0, topY, 0), model)
for index, corner in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
	local x = corner.X * (TABLE_SIZE.X / 2 - LEG_SIZE.X)
	local z = corner.Z * (TABLE_SIZE.Z / 2 - LEG_SIZE.Z)
	makePart("Leg" .. index, LEG_SIZE, WOOD_COLOR, Enum.Material.Wood, CFrame.new(x, TABLE_HEIGHT_STUDS / 2, z), model)
end

-- the map on the table: parchment, the Defensive Zone as a green field,
-- the camp as a dark block at one end, and a few tokens for Towers
local mapY = topY + TABLE_SIZE.Y / 2 + MAP_SIZE.Y / 2
makePart("Map", MAP_SIZE, MAP_COLOR, Enum.Material.Fabric, CFrame.new(0, mapY, 0), model)
makePart("MapZone", Vector3.new(7, 0.05, 4.6), ZONE_COLOR, Enum.Material.Grass, CFrame.new(1.6, mapY + 0.08, 0), model)
makePart("MapCamp", Vector3.new(2.2, 0.5, 3.2), CAMP_COLOR, Enum.Material.Slate, CFrame.new(-4.6, mapY + 0.3, 0), model)
for index, spot in { Vector3.new(-0.6, 0, 1.2), Vector3.new(0.4, 0, -1.4), Vector3.new(2.4, 0, 0.3) } do
	makePart("MapToken" .. index, Vector3.new(0.45, 0.7, 0.45), TOKEN_COLOR, Enum.Material.SmoothPlastic, CFrame.new(spot.X, mapY + 0.4, spot.Z), model)
end

-- the prompt's anchor: invisible, over the middle of the map
local prompt = makePart(Constants.DEFENSE_TABLE_PROMPT_PART, Vector3.new(1, 1, 1), MAP_COLOR, Enum.Material.SmoothPlastic, CFrame.new(0, mapY + 1, 0), model)
prompt.Transparency = 1
prompt.CanCollide = false
prompt.CanQuery = false
prompt.CanTouch = false

model.PrimaryPart = top
model.WorldPivot = pose
model.Parent = store

ChangeHistoryService:SetWaypoint("After Defense Table")
print("build_defense_table: built " .. model:GetFullName() .. " and removed " .. #standPositions .. " Trap stand(s)")
