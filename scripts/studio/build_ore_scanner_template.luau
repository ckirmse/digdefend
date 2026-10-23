-- Builds the Ore Scanner's placeholder model under
-- ReplicatedStorage/GameAssets/Gadgets (2026-10-22) until the designer's
-- art lands, when it is replaced by a model of the same name:
--   OreScanner: the source art build_tool_templates.luau turns into the
--     held GADGET_ORE_SCANNER, a handheld box with a dish on top and a
--     red lamp, standing upright.
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SOURCE_NAME = "OreScanner"
local BODY_COLOR = Color3.fromRGB(70, 75, 80)
local DISH_COLOR = Color3.fromRGB(190, 195, 200)
local LAMP_COLOR = Color3.fromRGB(255, 50, 50)

ChangeHistoryService:SetWaypoint("Before OreScanner template")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local gadgets = gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER)
local existing = gadgets:FindFirstChild(SOURCE_NAME)
if existing then
	existing:Destroy()
end

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

local scanner = Instance.new("Model")
scanner.Name = SOURCE_NAME
local body = makePart("Body", Vector3.new(0.5, 0.9, 0.3), BODY_COLOR, Enum.Material.SmoothPlastic, CFrame.new(0, 0.45, 0), scanner)
local dish = makePart("Dish", Vector3.new(0.7, 0.12, 0.7), DISH_COLOR, Enum.Material.Metal, CFrame.new(0, 1.0, 0), scanner)
dish.Shape = Enum.PartType.Cylinder
dish.CFrame = CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.pi / 2)
makePart("Lamp", Vector3.new(0.14, 0.14, 0.14), LAMP_COLOR, Enum.Material.Neon, CFrame.new(0, 0.7, -0.18), scanner)
scanner.PrimaryPart = body
scanner.Parent = gadgets

ChangeHistoryService:SetWaypoint("After OreScanner template")
print("build_ore_scanner_template: built GameAssets." .. Constants.GADGET_TEMPLATES_FOLDER .. "." .. SOURCE_NAME)
