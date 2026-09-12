-- Rebuilds the placeholder rock templates under
-- ReplicatedStorage/GameAssets/Rocks: one anchored 4x4x4 Part per
-- Enums.RockName key (Constants.MINE_BLOCK_SIZE_STUDS), coloured by kind and
-- tier so a mine reads at a glance until real meshes exist. Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay place;
-- it replaces any existing copy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)

ChangeHistoryService:SetWaypoint("Before rock templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end

local existing = gameAssets:FindFirstChild(Constants.ROCK_TEMPLATES_FOLDER)
if existing then
	existing:Destroy()
end

local rocks = Instance.new("Folder")
rocks.Name = Constants.ROCK_TEMPLATES_FOLDER
rocks.Parent = gameAssets

-- placeholder looks; tiers of one resource darken and saturate as they rise
local LOOKS = {
	SHALE = { color = Color3.fromRGB(150, 140, 120), material = Enum.Material.Slate },
	SANDSTONE = { color = Color3.fromRGB(196, 168, 110), material = Enum.Material.Sandstone },
	GRANITE = { color = Color3.fromRGB(128, 128, 132), material = Enum.Material.Granite },
	BASALT = { color = Color3.fromRGB(62, 60, 64), material = Enum.Material.Basalt },
	IRON_1 = { color = Color3.fromRGB(190, 140, 110), material = Enum.Material.Rock },
	IRON_2 = { color = Color3.fromRGB(170, 110, 80), material = Enum.Material.Rock },
	IRON_3 = { color = Color3.fromRGB(150, 85, 55), material = Enum.Material.Rock },
	IRON_4 = { color = Color3.fromRGB(120, 60, 35), material = Enum.Material.Rock },
	GOLD_1 = { color = Color3.fromRGB(235, 215, 120), material = Enum.Material.Rock },
	GOLD_2 = { color = Color3.fromRGB(230, 195, 70), material = Enum.Material.Rock },
	GOLD_3 = { color = Color3.fromRGB(220, 170, 30), material = Enum.Material.Metal },
	GOLD_4 = { color = Color3.fromRGB(200, 140, 0), material = Enum.Material.Metal },
	CRYSTAL_1 = { color = Color3.fromRGB(170, 230, 240), material = Enum.Material.Glass },
	CRYSTAL_2 = { color = Color3.fromRGB(120, 210, 235), material = Enum.Material.Glass },
	CRYSTAL_3 = { color = Color3.fromRGB(70, 180, 230), material = Enum.Material.Glass },
	CRYSTAL_4 = { color = Color3.fromRGB(30, 140, 220), material = Enum.Material.Glass },
	URANIUM = { color = Color3.fromRGB(110, 255, 90), material = Enum.Material.Neon },
	BEDROCK = { color = Color3.fromRGB(28, 28, 32), material = Enum.Material.Basalt },
	GATE = { color = Color3.fromRGB(150, 90, 200), material = Enum.Material.Metal, transparency = 0.25 },
}

local size = Constants.MINE_BLOCK_SIZE_STUDS
local count = 0
for _, rockName in Enums.getAllValues(Enums.RockName) do
	local key = Enums.getName(Enums.RockName, rockName)
	local look = LOOKS[key]
	if not look then
		warn("build_rock_templates: no look defined for " .. key .. "; using grey")
		look = { color = Color3.fromRGB(120, 120, 120), material = Enum.Material.Rock }
	end
	local part = Instance.new("Part")
	part.Name = key
	part.Size = Vector3.new(size, size, size)
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = true
	part.Color = look.color
	part.Material = look.material
	part.Transparency = look.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = rocks
	count += 1
end

ChangeHistoryService:SetWaypoint("After rock templates")
print("build_rock_templates: built " .. count .. " templates under " .. rocks:GetFullName())
