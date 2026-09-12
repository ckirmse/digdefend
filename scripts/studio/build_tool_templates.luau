-- Rebuilds the placeholder held-tool models under
-- ReplicatedStorage/GameAssets/Tools: one Model per Enums.ToolKind key with
-- a Handle part that ClientToolModelManager welds to the right hand. Run in
-- the gameplay place from the command bar or the MCP execute_luau tool; it
-- replaces any existing copy. Real art replaces these at M46.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

ChangeHistoryService:SetWaypoint("Before tool templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local existing = gameAssets:FindFirstChild(Constants.TOOL_TEMPLATES_FOLDER)
if existing then
	existing:Destroy()
end
local tools = Instance.new("Folder")
tools.Name = Constants.TOOL_TEMPLATES_FOLDER
tools.Parent = gameAssets

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

-- pick axe: a wooden haft (the Handle, gripped near its lower end) with a
-- steel head across the top
local pickAxe = Instance.new("Model")
pickAxe.Name = "PICK_AXE"
local haft = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.3, 2.4, 0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), pickAxe)
local head = makePart("Head", Vector3.new(1.8, 0.35, 0.35), Color3.fromRGB(150, 150, 155), Enum.Material.Metal, CFrame.new(0, 1.2, 0), pickAxe)
local weld = Instance.new("WeldConstraint")
weld.Part0 = haft
weld.Part1 = head
weld.Parent = haft
pickAxe.PrimaryPart = haft
pickAxe.Parent = tools

ChangeHistoryService:SetWaypoint("After tool templates")
print("build_tool_templates: built " .. #tools:GetChildren() .. " tool template(s) under " .. tools:GetFullName())
