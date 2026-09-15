-- Rebuilds the placeholder worn models under ReplicatedStorage/GameAssets/
-- Wearables: JET_PACK, a Model whose Handle ClientJetPackManager welds to
-- every character's back and whose Flame part it shows while the pack
-- burns. Run in the gameplay place from the command bar or the MCP
-- execute_luau tool; it replaces any existing copy. Real art replaces this
-- at M46.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

ChangeHistoryService:SetWaypoint("Before wearable templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local existing = gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER)
if existing then
	existing:Destroy()
end
local wearables = Instance.new("Folder")
wearables.Name = Constants.WEARABLE_TEMPLATES_FOLDER
wearables.Parent = gameAssets

local function makePart(name, size, color, material, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
end

-- the Handle is a thin back plate; its front (-Z) sits against the torso
local jetPack = Instance.new("Model")
jetPack.Name = Constants.JET_PACK_TEMPLATE
local plate = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(1.3, 1.4, 0.2), Color3.fromRGB(80, 80, 90), Enum.Material.Metal, CFrame.new(0, 0, 0), jetPack)
local leftTank = makePart("LeftTank", Vector3.new(0.45, 1.3, 0.45), Color3.fromRGB(130, 130, 140), Enum.Material.Metal, CFrame.new(-0.3, 0, 0.3), jetPack)
local rightTank = makePart("RightTank", Vector3.new(0.45, 1.3, 0.45), Color3.fromRGB(130, 130, 140), Enum.Material.Metal, CFrame.new(0.3, 0, 0.3), jetPack)
local flame = makePart(Constants.JET_PACK_FLAME_PART, Vector3.new(1, 1.2, 0.5), Color3.fromRGB(255, 150, 40), Enum.Material.Neon, CFrame.new(0, -1.2, 0.3), jetPack)
flame.Transparency = 1
flame.Shape = Enum.PartType.Ball
local flameLight = Instance.new("PointLight")
flameLight.Color = Color3.fromRGB(255, 150, 40)
flameLight.Range = 12
flameLight.Brightness = 2
-- lit only while burning (ClientJetPackManager)
flameLight.Enabled = false
flameLight.Parent = flame
for _, part in { leftTank, rightTank, flame } do
	weldTo(plate, part)
end
jetPack.PrimaryPart = plate
jetPack.Parent = wearables

ChangeHistoryService:SetWaypoint("After wearable templates")
print("build_wearable_templates: built " .. #wearables:GetChildren() .. " wearable template(s) under " .. wearables:GetFullName())
