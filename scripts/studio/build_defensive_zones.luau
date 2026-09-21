-- Adds a Defensive Zone to the map that is loaded in Workspace (GDD
-- "Defensive Zones"): a Camp.DefensiveZones folder with one flat anchored
-- part, Zone1, laid on the ground just outside the gate, on the side away
-- from the Refinery. Its size and rotation are the grid
-- (PlacementRules.measureZone cuts it into CELL_SIZE_STUDS cells from the
-- centre out, so keep each side a multiple of the cell size). The designer
-- moves, resizes, and duplicates it in the Explorer afterwards (Area2, …),
-- so an existing folder is left alone: delete it by hand to have it
-- rebuilt. Run in the gameplay place with the map loaded (map_tools.luau
-- "load"), then save the map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlacementData = require(ServerScriptService.GameData.Defenses.Placement)

local MAP_NAME = "DEADMANS_CANYON"
-- cells across (along the wall) and deep (away from it)
local ZONE_COLUMNS = 12
local ZONE_ROWS = 8
local ZONE_THICKNESS_STUDS = 1
-- the near edge sits this far outside the gate's far edge
local GAP_FROM_GATE_STUDS = 6
-- the top face floats a hair above the ground so the grid draws on top of it
local LIFT_STUDS = 0.05
local ZONE_COLOR = Color3.fromRGB(245, 200, 80)

ChangeHistoryService:SetWaypoint("Before defensive zones")

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, MAP_NAME .. " is not loaded in Workspace; run map_tools.luau with ACTION = \"load\" first")
local existing = map:FindFirstChild(Constants.CAMP_DEFENSIVE_ZONES_FOLDER)
if existing then
	print("build_defensive_zones: " .. existing:GetFullName() .. " already exists; left alone")
	return
end
local gate = map:FindFirstChild(Constants.CAMP_GATE_MODEL)
local refinery = map:FindFirstChild(Constants.CAMP_REFINERY_MODEL)
assert(gate and gate:IsA("Model"), MAP_NAME .. " has no Gate model")
assert(refinery and refinery:IsA("Model"), MAP_NAME .. " has no Refinery model")

-- outward is from the Refinery (inside the camp) through the gate, flat
local gateCFrame, gateSize = gate:GetBoundingBox()
local outward = gateCFrame.Position - refinery:GetPivot().Position
outward = Vector3.new(outward.X, 0, outward.Z)
outward = if outward.Magnitude > 0.001 then outward.Unit else Vector3.zAxis
-- the gate's extent along outward, whichever of its axes that is
local gateDepth = math.abs(gateCFrame.LookVector:Dot(outward)) * gateSize.Z + math.abs(gateCFrame.RightVector:Dot(outward)) * gateSize.X

-- the ground under the spot, found from above, ignoring the gate itself
local width = ZONE_COLUMNS * PlacementData.CELL_SIZE_STUDS
local depth = ZONE_ROWS * PlacementData.CELL_SIZE_STUDS
local centre = gateCFrame.Position + outward * (gateDepth / 2 + GAP_FROM_GATE_STUDS + depth / 2)
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { gate }
local hit = workspace:Raycast(centre + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
local groundY = if hit then hit.Position.Y else gateCFrame.Position.Y - gateSize.Y / 2

local folder = Instance.new("Folder")
folder.Name = Constants.CAMP_DEFENSIVE_ZONES_FOLDER
folder.Parent = map

local zone = Instance.new("Part")
zone.Name = "Zone1"
zone.Size = Vector3.new(width, ZONE_THICKNESS_STUDS, depth)
zone.Anchored = true
zone.CanCollide = false
zone.CanQuery = false
zone.CanTouch = false
zone.CastShadow = false
zone.Transparency = 0.85
zone.Color = ZONE_COLOR
zone.Material = Enum.Material.SmoothPlastic
-- +Z of the grid (rows) runs outward, away from the camp
zone.CFrame = CFrame.lookAt(Vector3.new(centre.X, groundY + LIFT_STUDS - ZONE_THICKNESS_STUDS / 2, centre.Z), Vector3.new(centre.X, groundY + LIFT_STUDS - ZONE_THICKNESS_STUDS / 2, centre.Z) - outward)
zone.Parent = folder

ChangeHistoryService:SetWaypoint("After defensive zones")
print("build_defensive_zones: built " .. zone:GetFullName() .. " (" .. ZONE_COLUMNS .. " by " .. ZONE_ROWS .. " cells) outside the gate")
