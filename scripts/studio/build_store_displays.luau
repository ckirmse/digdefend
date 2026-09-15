-- Rebuilds the placeholder display models the Mining Supplies Store stands
-- spin over their ItemSpawn parts, under ReplicatedStorage/GameAssets/
-- StoreDisplays: "BOOTS_<level>", "BACKPACK_<level>", "JET_PACK_<level>"
-- for the upgrade tracks (the level count in GameData/Store/MiningSupplies).
-- Pick axes, torches, and dynamite are shown from the held-tool templates,
-- so they are not here. Run in the gameplay place from the command bar or
-- the MCP execute_luau tool; it replaces any existing copy. Real art
-- replaces these at M46.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local LEVEL_COUNT = 5
local TRIM_COLOR_BY_LEVEL = {
	Color3.fromRGB(150, 150, 155),
	Color3.fromRGB(190, 120, 70),
	Color3.fromRGB(200, 200, 210),
	Color3.fromRGB(240, 200, 60),
	Color3.fromRGB(120, 220, 255),
}

ChangeHistoryService:SetWaypoint("Before store displays")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local existing = gameAssets:FindFirstChild(Constants.STORE_DISPLAY_TEMPLATES_FOLDER)
if existing then
	existing:Destroy()
end
local displays = Instance.new("Folder")
displays.Name = Constants.STORE_DISPLAY_TEMPLATES_FOLDER
displays.Parent = gameAssets

local function makePart(name, size, color, material, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = cframe
	part.Parent = parent
	return part
end

for level = 1, LEVEL_COUNT do
	local trim = TRIM_COLOR_BY_LEVEL[level]

	-- boots: two blocks side by side with a coloured sole
	local boots = Instance.new("Model")
	boots.Name = "BOOTS_" .. level
	local left = makePart("Left", Vector3.new(0.5, 0.6, 1), Color3.fromRGB(90, 60, 35), Enum.Material.Fabric, CFrame.new(-0.35, 0.3, 0), boots)
	makePart("Right", Vector3.new(0.5, 0.6, 1), Color3.fromRGB(90, 60, 35), Enum.Material.Fabric, CFrame.new(0.35, 0.3, 0), boots)
	makePart("LeftSole", Vector3.new(0.5, 0.12, 1), trim, Enum.Material.SmoothPlastic, CFrame.new(-0.35, 0.06, 0), boots)
	makePart("RightSole", Vector3.new(0.5, 0.12, 1), trim, Enum.Material.SmoothPlastic, CFrame.new(0.35, 0.06, 0), boots)
	boots.PrimaryPart = left
	boots.Parent = displays

	-- backpack: a bag that grows with the level, with a coloured flap
	local backpack = Instance.new("Model")
	backpack.Name = "BACKPACK_" .. level
	local bagSize = 0.9 + 0.15 * level
	local bag = makePart("Bag", Vector3.new(bagSize, bagSize * 1.2, bagSize * 0.6), Color3.fromRGB(110, 90, 60), Enum.Material.Fabric, CFrame.new(0, bagSize * 0.6, 0), backpack)
	makePart("Flap", Vector3.new(bagSize, bagSize * 0.35, bagSize * 0.65), trim, Enum.Material.Fabric, CFrame.new(0, bagSize * 1.05, 0), backpack)
	backpack.PrimaryPart = bag
	backpack.Parent = displays

	-- jet pack: two tanks and a coloured nozzle; the same shape is worn
	local jetPack = Instance.new("Model")
	jetPack.Name = "JET_PACK_" .. level
	local tankHeight = 1.2 + 0.1 * level
	local leftTank = makePart("LeftTank", Vector3.new(0.45, tankHeight, 0.45), Color3.fromRGB(130, 130, 140), Enum.Material.Metal, CFrame.new(-0.3, tankHeight / 2, 0), jetPack)
	makePart("RightTank", Vector3.new(0.45, tankHeight, 0.45), Color3.fromRGB(130, 130, 140), Enum.Material.Metal, CFrame.new(0.3, tankHeight / 2, 0), jetPack)
	makePart("LeftNozzle", Vector3.new(0.3, 0.2, 0.3), trim, Enum.Material.Metal, CFrame.new(-0.3, -0.1, 0), jetPack)
	makePart("RightNozzle", Vector3.new(0.3, 0.2, 0.3), trim, Enum.Material.Metal, CFrame.new(0.3, -0.1, 0), jetPack)
	jetPack.PrimaryPart = leftTank
	jetPack.Parent = displays
end

ChangeHistoryService:SetWaypoint("After store displays")
print("build_store_displays: built " .. #displays:GetChildren() .. " display model(s) under " .. displays:GetFullName())
