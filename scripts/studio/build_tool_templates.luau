-- Rebuilds the placeholder held-tool models under
-- ReplicatedStorage/GameAssets/Tools: a Model per held tool, each with a
-- Handle part the Humanoid grips once ToolManager wraps it in a Tool. The pick
-- axe has one model per level ("PICK_AXE_1" .. "PICK_AXE_6", the level count
-- in GameData/Store/MiningSupplies) so an upgrade shows in the hand and on
-- the store stand; TORCH and DYNAMITE are the consumables, HAMMER is the
-- Repair Mode tool, and every "WEAPON_<KEY>" (M24, the class weapons of
-- 2026-10-16) is made from the designer's art under GameAssets/Weapons,
-- a Model named for the Enums.WeaponKind key, which this script reads and
-- never changes. Run in the gameplay place from the command bar or the MCP
-- execute_luau tool; it replaces any existing copy. Real art replaces the
-- placeholders at M46.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)

local PICK_AXE_LEVEL_COUNT = 6
-- head colour and size grow with the level so the upgrade reads at a glance
local HEAD_COLOR_BY_LEVEL = {
	Color3.fromRGB(150, 150, 155),
	Color3.fromRGB(190, 120, 70),
	Color3.fromRGB(200, 200, 210),
	Color3.fromRGB(240, 200, 60),
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(120, 220, 255),
}
-- the top head glows (2026-10-06)
local NEON_FROM_LEVEL = 6

-- how each weapon's art is read: the part the hand closes on (a named
-- piece of the art, or a spot on the body as shares of its size: right,
-- up, back), how long the held copy is in studs, where the barrel's axis
-- sits above the body's centre as a share of its height, the child part
-- that marks the front when the art's front is not -Z (the Flamethrower
-- lies along X, its Barrel part out front), and whether it is a stream
-- weapon (a flame emitter under the Muzzle instead of smoke)
local WEAPONS = {
	{
		key = "RIFLE",
		gripPartName = "SM_Wep_Rifle_01_Lever",
		lengthStuds = 3.8,
		-- measured by raycasting the built template (2026-09-17)
		muzzleHeightShare = 0.38,
	},
	{
		key = "PISTOL",
		gripShare = Vector3.new(0, -0.2, 0.28),
		lengthStuds = 1.3,
		muzzleHeightShare = 0.3,
	},
	{
		key = "SNIPER",
		gripShare = Vector3.new(0, -0.15, 0.25),
		lengthStuds = 4.4,
		muzzleHeightShare = 0.4,
	},
	{
		key = "FLAMETHROWER",
		gripShare = Vector3.new(0, -0.25, 0.3),
		lengthStuds = 3.6,
		muzzleHeightShare = 0.55,
		frontPartName = "Barrel",
		isStream = true,
	},
	{
		key = "ASSAULT_RIFLE",
		gripShare = Vector3.new(0, -0.2, 0.2),
		lengthStuds = 3.6,
		muzzleHeightShare = 0.45,
	},
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
	local head = makePart("Head", Vector3.new(headWidth, 0.35, 0.35), HEAD_COLOR_BY_LEVEL[level], if level >= NEON_FROM_LEVEL then Enum.Material.Neon else Enum.Material.Metal, CFrame.new(0, 1.2, 0), pickAxe)
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

-- the muzzle flash, as the designer tuned it in the Explorer (2026-09-17);
-- off until ClientWeaponManager pulses it on a shot
local function addMuzzleFlash(muzzle)
	local flash = Instance.new("PointLight")
	flash.Name = Constants.WEAPON_MUZZLE_FLASH_LIGHT
	flash.Enabled = false
	flash.Brightness = 1
	flash.Range = 5
	flash.Color = Color3.fromRGB(255, 165, 38)
	flash.Shadows = false
	flash.Parent = muzzle
end

-- a wisp of smoke out of the barrel (the attachment's front), also
-- pulsed; at this rate a 0.1 s pulse is about six particles
local function addMuzzleSmoke(muzzle)
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
end

-- a stream weapon's flame: a fast cone of fire out of the nozzle, pulsed
-- every tick the trigger is held (the Flamethrower, 2026-10-16)
local function addMuzzleFlame(muzzle)
	local flame = Instance.new("ParticleEmitter")
	flame.Name = Constants.WEAPON_MUZZLE_FLAME_EMITTER
	flame.Enabled = false
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(230, 70, 20))
	flame.LightEmission = 1
	flame.Rate = 120
	flame.Lifetime = NumberRange.new(0.35, 0.5)
	flame.Speed = NumberRange.new(45, 55)
	flame.SpreadAngle = Vector2.new(8, 8)
	flame.Drag = 2
	flame.Acceleration = Vector3.new(0, 4, 0)
	flame.Rotation = NumberRange.new(0, 360)
	flame.RotSpeed = NumberRange.new(-90, 90)
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 2.2),
		NumberSequenceKeypoint.new(1, 3),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.EmissionDirection = Enum.NormalId.Front
	flame.Parent = muzzle
end

-- a weapon: the designer's imported model is the source art and stays as
-- it is. The held template is a copy turned so its front is -Z (the way a
-- Tool points forward), scaled to hand size, with an invisible Handle at
-- the grip, where the hand closes, every piece welded to it, and the
-- Muzzle attachment (Constants.WEAPON_MUZZLE_ATTACHMENT) at the barrel's
-- tip, where tracers start
local weaponsFolder = gameAssets:FindFirstChild("Weapons")
local function buildWeapon(spec)
	local source = if weaponsFolder then weaponsFolder:FindFirstChild(spec.key) else nil
	if not source or not source:IsA("Model") then
		warn("build_tool_templates: no GameAssets.Weapons." .. spec.key .. "; WEAPON_" .. spec.key .. " not built")
		return
	end
	local weapon = source:Clone()
	weapon.Name = "WEAPON_" .. spec.key
	local body = weapon:FindFirstChildWhichIsA("MeshPart")
	if not body then
		warn("build_tool_templates: " .. spec.key .. " has no MeshPart body; not built")
		weapon:Destroy()
		return
	end
	-- ToolManager moves a template's children into the Tool, so the
	-- pieces nested under the body come up beside it
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.Parent = weapon
		end
	end
	-- the front: the body's -Z unless a named child marks it (the
	-- Flamethrower's Barrel sits along its X); the Handle faces the front
	-- so the Tool points the barrel forward whichever axis the art uses
	local frontLocal = -Vector3.zAxis
	if spec.frontPartName then
		local frontPart = weapon:FindFirstChild(spec.frontPartName)
		if frontPart and frontPart:IsA("BasePart") then
			local offset = body.CFrame:VectorToObjectSpace(frontPart.Position - body.Position)
			offset = Vector3.new(offset.X, 0, offset.Z)
			if offset.Magnitude > 0.01 then
				frontLocal = offset.Unit
			end
		else
			warn("build_tool_templates: " .. spec.key .. " has no " .. spec.frontPartName .. " part; its front is taken as -Z")
		end
	end
	local extents = weapon:GetExtentsSize()
	weapon:ScaleTo(weapon:GetScale() * spec.lengthStuds / math.max(extents.X, extents.Y, extents.Z))
	local bodySize = body.Size
	-- the barrel's length is the body's size along the front axis
	local lengthStuds = math.abs(frontLocal.X) * bodySize.X + math.abs(frontLocal.Z) * bodySize.Z
	local backWorld = body.CFrame:VectorToWorldSpace(-frontLocal)
	local rightWorld = body.CFrame:VectorToWorldSpace(frontLocal:Cross(Vector3.yAxis))
	-- the grip: a named piece of the art, or a spot on the body as shares
	-- of its size (right, up, back)
	local gripPosition
	local gripPart = if spec.gripPartName then weapon:FindFirstChild(spec.gripPartName, true) else nil
	if gripPart and gripPart:IsA("BasePart") then
		gripPosition = gripPart.Position
	else
		local share = spec.gripShare or Vector3.new(0, -0.2, 0.25)
		gripPosition = body.Position + body.CFrame.UpVector * (share.Y * bodySize.Y) + backWorld * (share.Z * lengthStuds) + rightWorld * (share.X * lengthStuds)
	end
	local frontWorld = body.CFrame:VectorToWorldSpace(frontLocal)
	local handle = makePart(Constants.TOOL_HANDLE_PART, Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, CFrame.lookAt(gripPosition, gripPosition + frontWorld, body.CFrame.UpVector), weapon)
	handle.Transparency = 1
	for _, child in weapon:GetChildren() do
		if child:IsA("BasePart") and child ~= handle then
			weldTo(handle, child)
		end
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = Constants.WEAPON_MUZZLE_ATTACHMENT
	muzzle.Position = frontLocal * (lengthStuds / 2) + Vector3.new(0, bodySize.Y * spec.muzzleHeightShare, 0)
	-- the attachment's own front is where the smoke and flame leave
	muzzle.CFrame = CFrame.lookAt(muzzle.Position, muzzle.Position + frontLocal)
	muzzle.Parent = body
	addMuzzleFlash(muzzle)
	if spec.isStream then
		addMuzzleFlame(muzzle)
	else
		addMuzzleSmoke(muzzle)
	end
	weapon.PrimaryPart = handle
	weapon:PivotTo(CFrame.new(0, 0, 0))
	weapon.Parent = tools
end

for _, spec in WEAPONS do
	if Enums.WeaponKind[spec.key] == nil then
		warn("build_tool_templates: " .. spec.key .. " is not an Enums.WeaponKind; skipped")
		continue
	end
	buildWeapon(spec)
end

ChangeHistoryService:SetWaypoint("After tool templates")
print("build_tool_templates: built " .. #tools:GetChildren() .. " tool template(s) under " .. tools:GetFullName())
