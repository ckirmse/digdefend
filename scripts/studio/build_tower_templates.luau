-- Builds placeholder Tower models under ReplicatedStorage/GameAssets/Towers,
-- one per Enums.TowerKind key (GDD "Tower Types"): a base slab the size of
-- the Tower's grid footprint, a body, and a barrel, each kind in its own
-- colour so they read apart in play. The Model's pivot is the centre of its
-- base's underside, which is where PlacementManager stands it on the grid.
-- The designer reshapes them in the Explorer afterwards, so this script
-- never replaces an existing model: delete one by hand to have it rebuilt.
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local PlacementData = require(ServerScriptService.GameData.Defenses.Placement)
local TowersData = require(ServerScriptService.GameData.Defenses.Towers)

local BASE_HEIGHT_STUDS = 0.6
-- the base stops short of the cell edges so neighbours never touch
local BASE_MARGIN_STUDS = 0.4
local BODY_SIZE = Vector3.new(1.8, 2.4, 1.8)
local BARREL_SIZE = Vector3.new(0.5, 0.5, 2.2)
local COLOR_BY_KIND = {
	[Enums.TowerKind.SENTRY_GUN] = Color3.fromRGB(120, 130, 150),
	[Enums.TowerKind.FLAMETHROWER] = Color3.fromRGB(200, 90, 40),
	[Enums.TowerKind.AA_TURRET] = Color3.fromRGB(90, 140, 210),
	[Enums.TowerKind.FROST_TOWER] = Color3.fromRGB(150, 220, 240),
	[Enums.TowerKind.TESLA_COIL] = Color3.fromRGB(190, 120, 230),
	[Enums.TowerKind.SNIPER_TOWER] = Color3.fromRGB(70, 110, 70),
}

ChangeHistoryService:SetWaypoint("Before tower templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local folder = gameAssets:FindFirstChild(Constants.TOWER_TEMPLATES_FOLDER)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = Constants.TOWER_TEMPLATES_FOLDER
	folder.Parent = gameAssets
end

local function addPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local built = 0
for _, kind in Enums.getAllValues(Enums.TowerKind) do
	local key = Enums.getName(Enums.TowerKind, kind)
	if folder:FindFirstChild(key) then
		continue
	end
	local data = TowersData.BY_KIND[kind]
	local footprint = data and data.FOOTPRINT_CELLS or { 1, 1 }
	local color = COLOR_BY_KIND[kind] or Color3.fromRGB(150, 150, 150)
	local model = Instance.new("Model")
	model.Name = key
	local baseSize = Vector3.new(footprint[1] * PlacementData.CELL_SIZE_STUDS - BASE_MARGIN_STUDS, BASE_HEIGHT_STUDS, footprint[2] * PlacementData.CELL_SIZE_STUDS - BASE_MARGIN_STUDS)
	local base = addPart(model, "Base", baseSize, CFrame.new(0, BASE_HEIGHT_STUDS / 2, 0), Color3.fromRGB(80, 80, 85), Enum.Material.Metal)
	-- the body and barrel grow with the footprint so a big Tower reads big
	local scale = math.min(baseSize.X, baseSize.Z) / (PlacementData.CELL_SIZE_STUDS - BASE_MARGIN_STUDS)
	local bodySize = BODY_SIZE * scale
	local barrelSize = BARREL_SIZE * scale
	local bodyY = BASE_HEIGHT_STUDS + bodySize.Y / 2
	addPart(model, "Body", bodySize, CFrame.new(0, bodyY, 0), color, Enum.Material.SmoothPlastic)
	-- the barrel points along the model's -Z, the direction the grid's rows run away from the camp
	addPart(model, "Barrel", barrelSize, CFrame.new(0, bodyY + bodySize.Y * 0.2, -(bodySize.Z / 2 + barrelSize.Z / 2 - 0.3 * scale)), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
	model.PrimaryPart = base
	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = folder
	built += 1
end

ChangeHistoryService:SetWaypoint("After tower templates")
print("build_tower_templates: built " .. built .. " new tower model(s) under " .. folder:GetFullName())
