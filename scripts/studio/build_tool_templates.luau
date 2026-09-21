-- Rebuilds the placeholder held-tool models under
-- ReplicatedStorage/GameAssets/Tools: a Model per held tool, each with a
-- Handle part the Humanoid grips once ToolManager wraps it in a Tool. The pick
-- axe has one model per level ("PICK_AXE_1" .. "PICK_AXE_5", the level count
-- in GameData/Store/MiningSupplies) so an upgrade shows in the hand and on
-- the store stand; TORCH and DYNAMITE are the consumables, HAMMER is the
-- Repair Mode tool, and WEAPON_RIFLE (M24) is made from the designer's art
-- under GameAssets/Weapons, which this script reads and never changes. Run in the
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
-- is Repair Mode
local hammer = Instance.new("Model")
hammer.Name = "HAMMER"
local hammerHaft = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.3, 1.8, 0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, CFrame.new(0, 0, 0), hammer)
local hammerHead = makePart("Head", Vector3.new(1.1, 0.55, 0.55), Color3.fromRGB(150, 150, 155), Enum.Material.Metal, CFrame.new(0, 0.9, 0), hammer)
weldTo(hammerHaft, hammerHead)
hammer.PrimaryPart = hammerHaft
hammer.Parent = tools

-- rifle (M24): the designer's imported model, GameAssets/Weapons/
-- SM_Wep_Rifle_01, is the source art and stays as it is. The held template
-- is a copy scaled to hand size with an invisible Handle at the lever, where
-- the hand closes, and every piece welded to it. The art's front (-Z) is the
-- barrel and the Handle keeps that facing, so the Tool points it forward
local RIFLE_SOURCE_NAME = "SM_Wep_Rifle_01"
local RIFLE_GRIP_PART_NAME = "SM_Wep_Rifle_01_Lever"
local RIFLE_LENGTH_STUDS = 3.8
-- the barrel's axis above the body mesh's centre, as a share of its height
-- (measured by raycasting the built template, 2026-09-17); its tip is the
-- mesh's front face
local RIFLE_MUZZLE_HEIGHT_SHARE = 0.38
local weaponsFolder = gameAssets:FindFirstChild("Weapons")
local rifleSource = if weaponsFolder then weaponsFolder:FindFirstChild(RIFLE_SOURCE_NAME) else nil
if rifleSource and rifleSource:IsA("Model") then
	local rifle = rifleSource:Clone()
	rifle.Name = "WEAPON_RIFLE"
	local extents = rifle:GetExtentsSize()
	rifle:ScaleTo(rifle:GetScale() * RIFLE_LENGTH_STUDS / math.max(extents.X, extents.Y, extents.Z))
	local body = rifle:FindFirstChild(RIFLE_SOURCE_NAME)
	local gripPart = rifle:FindFirstChild(RIFLE_GRIP_PART_NAME, true)
	if body and body:IsA("BasePart") and gripPart and gripPart:IsA("BasePart") then
		-- ToolManager moves a template's children into the Tool, so the
		-- pieces nested under the body come up beside it
		for _, descendant in rifle:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.Parent = rifle
			end
		end
		local handle = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, body.CFrame.Rotation + gripPart.Position, rifle)
		handle.Transparency = 1
		for _, child in rifle:GetChildren() do
			if child:IsA("BasePart") and child ~= handle then
				weldTo(handle, child)
			end
		end
		-- where tracers start (Constants.WEAPON_MUZZLE_ATTACHMENT); every
		-- weapon template carries one
		local muzzle = Instance.new("Attachment")
		muzzle.Name = Constants.WEAPON_MUZZLE_ATTACHMENT
		muzzle.Position = Vector3.new(0, body.Size.Y * RIFLE_MUZZLE_HEIGHT_SHARE, -body.Size.Z / 2)
		muzzle.Parent = body
		-- the muzzle flash, as the designer tuned it in the Explorer
		-- (2026-09-17); off until ClientWeaponManager pulses it on a shot
		local flash = Instance.new("PointLight")
		flash.Name = Constants.WEAPON_MUZZLE_FLASH_LIGHT
		flash.Enabled = false
		flash.Brightness = 1
		flash.Range = 5
		flash.Color = Color3.fromRGB(255, 165, 38)
		flash.Shadows = false
		flash.Parent = muzzle
		-- a wisp of smoke out of the barrel (the attachment's front), also
		-- pulsed; at this rate a 0.1 s pulse is about six particles
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = Constants.WEAPON_MUZZLE_SMOKE_EMITTER
		smoke.Enabled = false
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(215, 210, 200))
		smoke.LightEmission = 0.1
		smoke.Rate = 60
		smoke.Lifetime = NumberRange.new(0.3, 0.6)
		smoke.Speed = NumberRange.new(3, 6)
		smoke.SpreadAngle = Vector2.new(14, 14)
		smoke.Drag = 3
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-40, 40)
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(1, 0.7),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.EmissionDirection = Enum.NormalId.Front
		smoke.Parent = muzzle
		rifle.PrimaryPart = handle
		rifle:PivotTo(CFrame.new(0, 0, 0))
		rifle.Parent = tools
	else
		warn("build_tool_templates: " .. RIFLE_SOURCE_NAME .. " has no body or lever part; WEAPON_RIFLE not built")
	end
else
	warn("build_tool_templates: no GameAssets.Weapons." .. RIFLE_SOURCE_NAME .. "; WEAPON_RIFLE not built")
end

ChangeHistoryService:SetWaypoint("After tool templates")
print("build_tool_templates: built " .. #tools:GetChildren() .. " tool template(s) under " .. tools:GetFullName())
