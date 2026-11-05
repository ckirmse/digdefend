-- Builds the cosmetic skin templates under ReplicatedStorage/GameAssets/
-- Cosmetics/<SLOT>/<TEMPLATE> (GDD "Characters" cosmetics, M61 first pass,
-- 2026-11-04), one folder per Enums.CosmeticSlot name, each template a
-- Model the crate reveal flies out of the Supply Crate (fitted to the
-- PrizeEnd pose by its bounding box) and the character later wears.
-- The two placeholders are the stock art: TEST_PICK_AXE is the level 1
-- pick axe's parts (build_tool_templates' haft and head, which the lobby
-- place does not carry), TEST_JET_PACK a copy of Wearables/JET_PACK; the
-- DEFAULT template of each slot is the same stock art, the one the Class
-- Menu avatar wears for a class with no skin picked (2026-11-04)
-- Run in the lobby place from the command bar or the MCP execute_luau
-- tool; it replaces any existing copy of each template it builds and
-- leaves the designer's others alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)

ChangeHistoryService:SetWaypoint("Before cosmetic templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	error(`no ReplicatedStorage.{Constants.GAME_ASSETS_FOLDER} folder`)
end
local cosmetics = gameAssets:FindFirstChild(Constants.COSMETIC_TEMPLATES_FOLDER)
if not cosmetics then
	cosmetics = Instance.new("Folder")
	cosmetics.Name = Constants.COSMETIC_TEMPLATES_FOLDER
	cosmetics.Parent = gameAssets
end

local function slotFolder(slot)
	local name = Enums.getName(Enums.CosmeticSlot, slot)
	local folder = cosmetics:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = cosmetics
	end
	return folder
end

local function replace(folder, model)
	local existing = folder:FindFirstChild(model.Name)
	if existing then
		existing:Destroy()
	end
	model.Parent = folder
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

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
end

-- the level 1 pick axe as build_tool_templates makes it
local pickAxe = Instance.new("Model")
pickAxe.Name = "TEST_PICK_AXE"
local haft = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.3, 2.4, 0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), pickAxe)
local head = makePart("Head", Vector3.new(1.8, 0.35, 0.35), Color3.fromRGB(150, 150, 155), Enum.Material.Metal, CFrame.new(0, 1.2, 0), pickAxe)
weldTo(haft, head)
pickAxe.PrimaryPart = haft
local defaultPickAxe = pickAxe:Clone()
defaultPickAxe.Name = Constants.DEFAULT_SKIN_TEMPLATE
replace(slotFolder(Enums.CosmeticSlot.PICK_AXE), defaultPickAxe)
replace(slotFolder(Enums.CosmeticSlot.PICK_AXE), pickAxe)

-- the stock jet pack, copied so a skin edit never touches the worn one
local wearables = gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER)
local jetPackSource = wearables and wearables:FindFirstChild(Constants.JET_PACK_TEMPLATE)
if not jetPackSource then
	error(`no {Constants.GAME_ASSETS_FOLDER}.{Constants.WEARABLE_TEMPLATES_FOLDER}.{Constants.JET_PACK_TEMPLATE} to copy`)
end
local defaultJetPack = jetPackSource:Clone()
defaultJetPack.Name = Constants.DEFAULT_SKIN_TEMPLATE
replace(slotFolder(Enums.CosmeticSlot.JET_PACK), defaultJetPack)
local jetPack = jetPackSource:Clone()
jetPack.Name = "TEST_JET_PACK"
replace(slotFolder(Enums.CosmeticSlot.JET_PACK), jetPack)

ChangeHistoryService:SetWaypoint("After cosmetic templates")
print("build_cosmetic_templates: built TEST_PICK_AXE and TEST_JET_PACK under " .. cosmetics:GetFullName())
