-- Builds placeholder Trap models under ReplicatedStorage/GameAssets/Traps,
-- one per Enums.TrapKind key (GDD "Trap Types"): a low slab the size of the
-- Trap's grid footprint with a simple feature on top (teeth, spikes, a
-- puddle, a mine, jaws, a dummy) so they read apart in play. The Model's
-- pivot is the centre of its underside, where PlacementManager stands it
-- on the grid; the Defense Store spins the same model over its stand. The
-- designer reshapes them afterwards, so an existing model is never
-- replaced: delete one by hand to have it rebuilt. Run in the gameplay place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local PlacementData = require(ServerScriptService.GameData.Defenses.Placement)
local TrapsData = require(ServerScriptService.GameData.Defenses.Traps)

local SLAB_HEIGHT_STUDS = 0.3
local SLAB_MARGIN_STUDS = 0.4
local SLAB_COLOR = Color3.fromRGB(95, 85, 75)

ChangeHistoryService:SetWaypoint("Before trap templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local folder = gameAssets:FindFirstChild(Constants.TRAP_TEMPLATES_FOLDER)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = Constants.TRAP_TEMPLATES_FOLDER
	folder.Parent = gameAssets
end

local function addPart(parent, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- each kind's feature on top of its slab, in the slab's footprint
local FEATURE_BY_KIND = {
	-- spikes fill whatever footprint the kind has
	-- a solid wall across the footprint (renamed from Tiger Teeth, M27)
	[Enums.TrapKind.WALL] = function(model, width, depth)
		addPart(model, "WallBlock", Vector3.new(width, 5, depth), CFrame.new(0, SLAB_HEIGHT_STUDS + 2.5, 0), Color3.fromRGB(110, 110, 115), Enum.Material.Concrete)
	end,
	[Enums.TrapKind.SPIKE_TRAP] = function(model, width, depth)
		local columns = math.max(3, math.floor(width / 1.5))
		local rows = math.max(3, math.floor(depth / 1.5))
		for row = 1, rows do
			for column = 1, columns do
				addPart(model, "Spike", Vector3.new(0.3, 1.2, 0.3), CFrame.new((column - (columns + 1) / 2) * width / (columns + 0.5), SLAB_HEIGHT_STUDS + 0.6, (row - (rows + 1) / 2) * depth / (rows + 0.5)), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
			end
		end
	end,
	[Enums.TrapKind.GOO_PIT] = function(model, width, depth)
		addPart(model, "Goo", Vector3.new(width - 0.6, 0.2, depth - 0.6), CFrame.new(0, SLAB_HEIGHT_STUDS + 0.1, 0), Color3.fromRGB(110, 220, 60), Enum.Material.Neon)
	end,
	[Enums.TrapKind.LAND_MINE] = function(model, width, depth)
		addPart(model, "Mine", Vector3.new(0.5, 1.6, 1.6), CFrame.new(0, SLAB_HEIGHT_STUDS + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 80, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
	end,
	[Enums.TrapKind.BEAR_TRAP] = function(model, width, depth)
		addPart(model, "JawLeft", Vector3.new(2, 0.3, 0.4), CFrame.new(0, SLAB_HEIGHT_STUDS + 0.15, -0.8), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
		addPart(model, "JawRight", Vector3.new(2, 0.3, 0.4), CFrame.new(0, SLAB_HEIGHT_STUDS + 0.15, 0.8), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
		addPart(model, "Plate", Vector3.new(0.8, 0.2, 0.8), CFrame.new(0, SLAB_HEIGHT_STUDS + 0.1, 0), Color3.fromRGB(90, 90, 95), Enum.Material.Metal)
	end,
	[Enums.TrapKind.DECOY] = function(model, width, depth)
		addPart(model, "Post", Vector3.new(0.4, 3, 0.4), CFrame.new(0, SLAB_HEIGHT_STUDS + 1.5, 0), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
		addPart(model, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, SLAB_HEIGHT_STUDS + 3.4, 0), Color3.fromRGB(220, 190, 150), Enum.Material.Fabric, Enum.PartType.Ball)
	end,
}

local built = 0
for _, kind in Enums.getAllValues(Enums.TrapKind) do
	local key = Enums.getName(Enums.TrapKind, kind)
	if folder:FindFirstChild(key) then
		continue
	end
	local data = TrapsData.BY_KIND[kind]
	local footprint = data and data.FOOTPRINT_CELLS or { 1, 1 }
	local width = footprint[1] * PlacementData.CELL_SIZE_STUDS - SLAB_MARGIN_STUDS
	local depth = footprint[2] * PlacementData.CELL_SIZE_STUDS - SLAB_MARGIN_STUDS
	local model = Instance.new("Model")
	model.Name = key
	local slab = addPart(model, "Slab", Vector3.new(width, SLAB_HEIGHT_STUDS, depth), CFrame.new(0, SLAB_HEIGHT_STUDS / 2, 0), SLAB_COLOR, Enum.Material.Slate)
	local feature = FEATURE_BY_KIND[kind]
	if feature then
		feature(model, width, depth)
	end
	model.PrimaryPart = slab
	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = folder
	built += 1
end

ChangeHistoryService:SetWaypoint("After trap templates")
print("build_trap_templates: built " .. built .. " new trap model(s) under " .. folder:GetFullName())
