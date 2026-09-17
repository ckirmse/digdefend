-- Rebuilds the placeholder held-tool models under
-- ReplicatedStorage/GameAssets/Tools: a Model per held tool, each with a
-- Handle part the Humanoid grips once ToolManager wraps it in a Tool. The pick
-- axe has one model per level ("PICK_AXE_1" .. "PICK_AXE_5", the level count
-- in GameData/Store/MiningSupplies) so an upgrade shows in the hand and on
-- the store stand; TORCH and DYNAMITE are the consumables and HAMMER is the
-- Build Mode tool. Run in the
-- gameplay place from the command bar or the MCP execute_luau tool; it
-- replaces any existing copy. Real art replaces these at M46.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local PICK_AXE_LEVEL_COUNT = 5
-- head colour and size grow with the level so the upgrade reads at a glance
local HEAD_COLOR_BY_LEVEL = {
	Color3.fromRGB(150, 150, 155),
	Color3.fromRGB(190, 120, 70),
	Color3.fromRGB(200, 200, 210),
	Color3.fromRGB(240, 200, 60),
	Color3.fromRGB(120, 220, 255),
}

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

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
end

-- pick axe: a wooden haft (the Handle, gripped near its lower end) with a
-- steel head across the top
for level = 1, PICK_AXE_LEVEL_COUNT do
	local pickAxe = Instance.new("Model")
	pickAxe.Name = "PICK_AXE_" .. level
	local haft = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.3, 2.4, 0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), pickAxe)
	local headWidth = 1.6 + 0.2 * level
	local head = makePart("Head", Vector3.new(headWidth, 0.35, 0.35), HEAD_COLOR_BY_LEVEL[level], Enum.Material.Metal, CFrame.new(0, 1.2, 0), pickAxe)
	weldTo(haft, head)
	pickAxe.PrimaryPart = haft
	pickAxe.Parent = tools
end

-- torch: a short stick with an unlit head (the flame is drawn when placed)
local torch = Instance.new("Model")
torch.Name = "TORCH"
local torchStick = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.25, 1.1, 0.25), Color3.fromRGB(110, 75, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), torch)
local torchHead = makePart("Head", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 150, 40), Enum.Material.Neon, CFrame.new(0, 0.7, 0), torch)
weldTo(torchStick, torchHead)
torch.PrimaryPart = torchStick
torch.Parent = tools

-- dynamite: a red stick with a short fuse
local dynamite = Instance.new("Model")
dynamite.Name = "DYNAMITE"
local stick = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.5, 1.2, 0.5), Color3.fromRGB(190, 40, 40), Enum.Material.SmoothPlastic, CFrame.new(0, 0, 0), dynamite)
local fuse = makePart("Fuse", Vector3.new(0.08, 0.4, 0.08), Color3.fromRGB(230, 230, 200), Enum.Material.Fabric, CFrame.new(0, 0.75, 0), dynamite)
weldTo(stick, fuse)
dynamite.PrimaryPart = stick
dynamite.Parent = tools

-- hammer (M23): a short wooden haft with a blocky steel head; equipping it
-- is Build Mode
local hammer = Instance.new("Model")
hammer.Name = "HAMMER"
local hammerHaft = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.3, 1.8, 0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), hammer)
local hammerHead = makePart("Head", Vector3.new(1.1, 0.55, 0.55), Color3.fromRGB(150, 150, 155), Enum.Material.Metal, CFrame.new(0, 0.9, 0), hammer)
weldTo(hammerHaft, hammerHead)
hammer.PrimaryPart = hammerHaft
hammer.Parent = tools

ChangeHistoryService:SetWaypoint("After tool templates")
print("build_tool_templates: built " .. #tools:GetChildren() .. " tool template(s) under " .. tools:GetFullName())
