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
local InsertService = game:GetService("InsertService")

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

-- the level 1 pick axe: the artist's three meshes, made from their asset
-- ids because the lobby has no GameAssets/Tools to copy from (ported from
-- the gameplay place's Tools/PICK_AXE_1 on 2026-11-13; wooden blocks before)
local PICK_AXE_PARTS = {
	{
		name = Constants.TOOL_HANDLE_PART,
		meshId = "rbxassetid://77614497494559",
		size = Vector3.new(0.36750, 2.73763, 0.38210),
		offset = CFrame.new(0, 0, 0),
		color = Color3.new(0.639216, 0.635294, 0.647059),
		material = Enum.Material.Plastic,
		colorMap = "rbxassetid://82273385408445",
	},
	{
		name = "Pickaxe_Head",
		meshId = "rbxassetid://76697011800846",
		size = Vector3.new(2.02714, 0.76866, 0.44675),
		offset = CFrame.new(-0.0400009155, 0.909999847, 0.0399999991),
		color = Color3.new(0.627451, 0.372549, 0.207843),
		material = Enum.Material.Wood,
	},
	{
		name = "Pickaxe_Wrap",
		meshId = "rbxassetid://132662423823887",
		size = Vector3.new(0.31219, 1.00970, 0.36927),
		offset = CFrame.new(0, -0.115251541, 0.0399999991),
		color = Color3.new(0.827451, 0.745098, 0.588235),
		material = Enum.Material.Plastic,
	},
}
local pickAxe = Instance.new("Model")
pickAxe.Name = "TEST_PICK_AXE"
local haft
for _, spec in PICK_AXE_PARTS do
	local part = InsertService:CreateMeshPartAsync(spec.meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	part.Name = spec.name
	part.Size = spec.size
	part.Color = spec.color
	part.Material = spec.material
	part.CFrame = spec.offset
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	if spec.colorMap then
		local surface = Instance.new("SurfaceAppearance")
		surface.ColorMap = spec.colorMap
		surface.Parent = part
	end
	part.Parent = pickAxe
	if spec.name == Constants.TOOL_HANDLE_PART then
		haft = part
	else
		weldTo(haft, part)
	end
end
pickAxe.PrimaryPart = haft
local defaultPickAxe = pickAxe:Clone()
defaultPickAxe.Name = Constants.DEFAULT_SKIN_TEMPLATE
replace(slotFolder(Enums.CosmeticSlot.PICK_AXE), defaultPickAxe)
replace(slotFolder(Enums.CosmeticSlot.PICK_AXE), pickAxe)

-- the stock jet pack, copied so a skin edit never touches the worn one
local wearables = gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER)
-- the base pack (level 1; Wearables.jetPackTemplateName)
local baseJetPackName = Constants.JET_PACK_TEMPLATE .. "_1"
local jetPackSource = wearables and wearables:FindFirstChild(baseJetPackName)
if not jetPackSource then
	error(`no {Constants.GAME_ASSETS_FOLDER}.{Constants.WEARABLE_TEMPLATES_FOLDER}.{baseJetPackName} to copy; run build_wearable_templates.luau first`)
end
local defaultJetPack = jetPackSource:Clone()
defaultJetPack.Name = Constants.DEFAULT_SKIN_TEMPLATE
-- the worn template stands wherever the designer left it; a skin sits at the origin
defaultJetPack:PivotTo(CFrame.new(0, 0, 0))
replace(slotFolder(Enums.CosmeticSlot.JET_PACK), defaultJetPack)
local jetPack = jetPackSource:Clone()
jetPack.Name = "TEST_JET_PACK"
jetPack:PivotTo(CFrame.new(0, 0, 0))
replace(slotFolder(Enums.CosmeticSlot.JET_PACK), jetPack)

ChangeHistoryService:SetWaypoint("After cosmetic templates")
print("build_cosmetic_templates: built TEST_PICK_AXE and TEST_JET_PACK under " .. cosmetics:GetFullName())
