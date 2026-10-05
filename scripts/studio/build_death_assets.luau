-- Builds the placeholder DeathRoom for death and revives (GDD "Health and
-- Revives", M32): Workspace.DeathRoom, one closed, lit room far above
-- every camp, a Model streamed to every client always (Persistent), whose
-- Spawn part a dead character is moved onto. It exists once in the
-- gameplay place, not per map. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.DEATH_ROOM_*. The grave itself
-- (GameAssets.Grave) and each map's Cemetery are the designer's own.
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ROOM_COLOR = Color3.fromRGB(30, 30, 34)
local ROOM_CENTER = Vector3.new(0, 4000, 0)
local ROOM_SIZE = Vector3.new(40, 16, 40)
local WALL_THICKNESS = 2

ChangeHistoryService:SetWaypoint("Before death assets")

local function makePart(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Slate
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- the DeathRoom
local oldRoom = workspace:FindFirstChild("DeathRoom")
if oldRoom then
	oldRoom:Destroy()
end

local room = Instance.new("Model")
room.Name = "DeathRoom"
room.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

local half = ROOM_SIZE / 2
local floor = makePart("Floor", Vector3.new(ROOM_SIZE.X, WALL_THICKNESS, ROOM_SIZE.Z), CFrame.new(ROOM_CENTER - Vector3.new(0, half.Y, 0)), ROOM_COLOR, room)
makePart("Ceiling", Vector3.new(ROOM_SIZE.X, WALL_THICKNESS, ROOM_SIZE.Z), CFrame.new(ROOM_CENTER + Vector3.new(0, half.Y, 0)), ROOM_COLOR, room)
makePart("WallNorth", Vector3.new(ROOM_SIZE.X, ROOM_SIZE.Y, WALL_THICKNESS), CFrame.new(ROOM_CENTER + Vector3.new(0, 0, half.Z)), ROOM_COLOR, room)
makePart("WallSouth", Vector3.new(ROOM_SIZE.X, ROOM_SIZE.Y, WALL_THICKNESS), CFrame.new(ROOM_CENTER - Vector3.new(0, 0, half.Z)), ROOM_COLOR, room)
makePart("WallEast", Vector3.new(WALL_THICKNESS, ROOM_SIZE.Y, ROOM_SIZE.Z), CFrame.new(ROOM_CENTER + Vector3.new(half.X, 0, 0)), ROOM_COLOR, room)
makePart("WallWest", Vector3.new(WALL_THICKNESS, ROOM_SIZE.Y, ROOM_SIZE.Z), CFrame.new(ROOM_CENTER - Vector3.new(half.X, 0, 0)), ROOM_COLOR, room)

local spawnPart = makePart("Spawn", Vector3.new(6, 1, 6), CFrame.new(floor.Position + Vector3.new(0, WALL_THICKNESS / 2 + 0.5, 0)), ROOM_COLOR, room)
spawnPart.CanCollide = false
spawnPart.Transparency = 1
local light = Instance.new("PointLight")
light.Range = 40
light.Brightness = 1
light.Parent = spawnPart
room.PrimaryPart = floor
room.Parent = workspace

ChangeHistoryService:SetWaypoint("After death assets")
print("build_death_assets: built Workspace.DeathRoom")
