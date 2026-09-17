-- Adds a placeholder Workbench to the map loaded in Workspace: the bench the
-- crew donates Iron at to upgrade the fortifications (GDD "Wall Repair"). A
-- Model named by Constants.CAMP_WORKBENCH_MODEL with an invisible anchored
-- Prompt part on top, which StructureManager gives its ProximityPrompt and
-- ClientWorkbenchManager floats the Fortifications sign above. Placed just
-- inside the gate on the camp side.
--
-- The designer moves and reshapes the bench in the Explorer afterwards, so
-- this script NEVER replaces an existing Workbench: delete it by hand to
-- have it rebuilt. Run in the gameplay place with the map loaded for editing
-- (scripts/studio/map_tools.luau "load"), then save the map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MAP_NAME = "DEADMANS_CANYON"
-- floor level, camp side of the gate, clear of the post stairs
local BENCH_CFRAME = CFrame.new(100, 0, 14) * CFrame.Angles(0, math.rad(90), 0)
local TOP_SIZE = Vector3.new(7, 0.5, 3.5)
local TOP_HEIGHT_STUDS = 3
local LEG_SIZE = Vector3.new(0.5, TOP_HEIGHT_STUDS, 0.5)
local WOOD_COLOR = Color3.fromRGB(120, 85, 50)

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, `load {MAP_NAME} into Workspace first (map_tools.luau, ACTION = "load")`)
if map:FindFirstChild(Constants.CAMP_WORKBENCH_MODEL) then
	return `{MAP_NAME} already has a {Constants.CAMP_WORKBENCH_MODEL}; left alone`
end

ChangeHistoryService:SetWaypoint("Before workbench")

local workbench = Instance.new("Model")
workbench.Name = Constants.CAMP_WORKBENCH_MODEL

local function addPart(name, size, offset, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = BENCH_CFRAME * offset
	part.Parent = workbench
	return part
end

local top = addPart("Top", TOP_SIZE, CFrame.new(0, TOP_HEIGHT_STUDS + TOP_SIZE.Y / 2, 0), WOOD_COLOR, Enum.Material.WoodPlanks)
for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
	local x = corner.X * (TOP_SIZE.X / 2 - LEG_SIZE.X)
	local z = corner.Y * (TOP_SIZE.Z / 2 - LEG_SIZE.Z)
	addPart("Leg", LEG_SIZE, CFrame.new(x, TOP_HEIGHT_STUDS / 2, z), WOOD_COLOR, Enum.Material.Wood)
end
-- a blueprint and an anvil block so it reads as a place to build
local surfaceY = TOP_HEIGHT_STUDS + TOP_SIZE.Y
addPart("Blueprint", Vector3.new(3, 0.1, 2.2), CFrame.new(-1.4, surfaceY + 0.05, 0), Color3.fromRGB(60, 110, 200), Enum.Material.SmoothPlastic)
addPart("Anvil", Vector3.new(1.6, 0.9, 1), CFrame.new(2.2, surfaceY + 0.45, 0), Color3.fromRGB(80, 82, 88), Enum.Material.Metal)

local prompt = addPart(Constants.WORKBENCH_PROMPT_PART, Vector3.new(1, 1, 1), CFrame.new(0, surfaceY + 0.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
prompt.Transparency = 1
prompt.CanCollide = false
prompt.CanQuery = false
prompt.CanTouch = false

workbench.PrimaryPart = top
-- the sign hangs on the Prompt part the moment the Model appears on a client
workbench.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
workbench.Parent = map

ChangeHistoryService:SetWaypoint("After workbench")
return `built {workbench:GetFullName()}`
