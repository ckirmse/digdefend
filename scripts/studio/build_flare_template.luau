-- Builds the Flare's models from the designer's art (2026-10-21, the
-- flare gun; a thrown placeholder tube before):
--   GameAssets/Gadgets/FlareGun: the designer's FLAREGUN model, moved
--     out of the Workspace and kept as the source art, which
--     build_tool_templates.luau turns into the held GADGET_FLARE the way
--     it builds a weapon (its MuzzleAttachment places the Muzzle).
--   GameAssets/Gadgets/Flare: the designer's Flare part, the source art.
--   GameAssets/Gadgets/FLARE: the lit flare every client stands on the
--     ground (the part in a Model; ClientFlareManager adds fire and light).
--   GameAssets/Projectiles/Flare: the fired flare ClientProjectileManager
--     flies, nose -X like the Rocket, a TailAttachment at +X carrying the
--     red smoke trail and a red PointLight so it lights what it passes.
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy of each built model. The
-- projectile's name must match GameData/Gadgets/Flare's FIRE.TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local GUN_WORKSPACE_NAME = "FLAREGUN"
local GUN_SOURCE_NAME = "FlareGun"
local FLARE_SOURCE_NAME = "Flare"
local PROJECTILE_NAME = "Flare"
-- the fired flare's length in studs
local PROJECTILE_LENGTH_STUDS = 0.9
local TRAIL_COLOR = ColorSequence.new(Color3.fromRGB(255, 70, 60), Color3.fromRGB(120, 30, 30))
local LIGHT_COLOR = Color3.fromRGB(255, 60, 50)
local LIGHT_RANGE = 24
local LIGHT_BRIGHTNESS = 4

ChangeHistoryService:SetWaypoint("Before Flare templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local gadgets = gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER)
local projectiles = gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER)

-- the gun: the designer's model comes in from the Workspace once
local gun = gadgets:FindFirstChild(GUN_SOURCE_NAME) or workspace:FindFirstChild(GUN_WORKSPACE_NAME) or workspace:FindFirstChild(GUN_SOURCE_NAME)
if not gun or not gun:IsA("Model") then
	error("build_flare_template: no " .. GUN_WORKSPACE_NAME .. " model under GameAssets.Gadgets or Workspace")
end
gun.Name = GUN_SOURCE_NAME
gun.Parent = gadgets

-- the flare: the designer's part; the placeholder model of the same name goes
local flare = workspace:FindFirstChild(FLARE_SOURCE_NAME)
local kept = gadgets:FindFirstChild(FLARE_SOURCE_NAME)
if flare and flare:IsA("BasePart") then
	if kept then
		kept:Destroy()
	end
	flare.Parent = gadgets
elseif kept and kept:IsA("BasePart") then
	flare = kept
else
	error("build_flare_template: no " .. FLARE_SOURCE_NAME .. " part under GameAssets.Gadgets or Workspace")
end
flare.Anchored = true
flare.CanCollide = false
flare.CanQuery = false
flare.CanTouch = false
flare.Massless = true

local function prepareCopy(copy: BasePart)
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	for _, child in copy:GetChildren() do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Attachment") then
			child:Destroy()
		end
	end
end

-- the lit flare on the ground: the part standing on its end
local existingLit = gadgets:FindFirstChild(Constants.FLARE_TEMPLATE)
if existingLit then
	existingLit:Destroy()
end
local lit = Instance.new("Model")
lit.Name = Constants.FLARE_TEMPLATE
local litPart = flare:Clone()
prepareCopy(litPart)
litPart.Name = "Flare"
litPart.CFrame = CFrame.new(0, litPart.Size.X / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
litPart.Parent = lit
lit.PrimaryPart = litPart
lit.Parent = gadgets

-- the fired flare: nose -X, tail +X, scaled to the flight's length
local existingProjectile = projectiles:FindFirstChild(PROJECTILE_NAME)
if existingProjectile then
	existingProjectile:Destroy()
end
local projectile = flare:Clone()
prepareCopy(projectile)
projectile.Name = PROJECTILE_NAME
projectile.Size = projectile.Size * (PROJECTILE_LENGTH_STUDS / math.max(projectile.Size.X, projectile.Size.Y, projectile.Size.Z))
projectile.CFrame = CFrame.new(0, 0, 0)
local tail = Instance.new("Attachment")
tail.Name = Constants.PROJECTILE_TAIL_ATTACHMENT
tail.Position = Vector3.new(projectile.Size.X / 2, 0, 0)
tail.Parent = projectile

-- the red smoke: the rocket's trail in the flare's colours, off until
-- ClientProjectileManager enables it for the flight
local smoke = Instance.new("ParticleEmitter")
smoke.Name = "Trail"
smoke.Enabled = false
smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
smoke.Color = TRAIL_COLOR
smoke.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 2.2),
})
smoke.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
smoke.Lifetime = NumberRange.new(0.9, 1.5)
smoke.Speed = NumberRange.new(1, 3)
smoke.SpreadAngle = Vector2.new(15, 15)
smoke.Rate = 70
smoke.LightEmission = 0.4
smoke.Rotation = NumberRange.new(0, 360)
smoke.RotSpeed = NumberRange.new(-30, 30)
smoke.Parent = tail

local light = Instance.new("PointLight")
light.Name = "Glow"
light.Color = LIGHT_COLOR
light.Range = LIGHT_RANGE
light.Brightness = LIGHT_BRIGHTNESS
light.Shadows = true
light.Parent = tail

projectile.Parent = projectiles

ChangeHistoryService:SetWaypoint("After Flare templates")
print("build_flare_template: built GameAssets." .. Constants.GADGET_TEMPLATES_FOLDER .. "." .. Constants.FLARE_TEMPLATE .. " and GameAssets." .. Constants.PROJECTILE_TEMPLATES_FOLDER .. "." .. PROJECTILE_NAME .. " from " .. GUN_SOURCE_NAME .. " and " .. FLARE_SOURCE_NAME)
