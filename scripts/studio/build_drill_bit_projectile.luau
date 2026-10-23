-- Builds the "DrillBit" projectile under ReplicatedStorage/GameAssets/
-- Projectiles (2026-10-22) from the designer's DrillBit model (the Base
-- seat, the Union collar with its Fire, and the Drill union), kept beside
-- it as "DrillBitSource" so this can be run again after the art changes.
-- ClientProjectileManager flies one root part, so the Base becomes the
-- root, named DrillBit, with the other pieces anchored under it (the
-- clients place every part by hand from its pose against the root; a
-- weld would not follow a client-made part moved by its CFrame), and a
-- TailAttachment on its back face (the bit points along the Base's +X)
-- carrying an emitter that emits nothing, so no smoke trail is drawn.
-- The same part is what ClientPostManager seats in the Fault Line
-- Drill's DrillSpawn between shots (the Base matches that seat's size,
-- so the two frames coincide). Run from the Studio command bar (or
-- the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing DrillBit part. The name must match GameData/Posts/PostWeapons'
-- DRILL_GUN PROJECTILE.TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local TEMPLATE_NAME = "DrillBit"
local SOURCE_NAME = "DrillBitSource"
local ROOT_PART_NAME = "Base"

ChangeHistoryService:SetWaypoint("Before DrillBit projectile")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local projectiles = gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER)
local source = projectiles:FindFirstChild(SOURCE_NAME)
if not source then
	-- the first run: the designer's model carries the template's name
	local model = projectiles:FindFirstChild(TEMPLATE_NAME)
	if model and model:IsA("Model") then
		model.Name = SOURCE_NAME
		source = model
	end
end
if not source or not source:IsA("Model") then
	error("build_drill_bit_projectile: no " .. SOURCE_NAME .. " model under GameAssets.Projectiles")
end

local old = projectiles:FindFirstChild(TEMPLATE_NAME)
if old then
	old:Destroy()
end

local copy = source:Clone()
local root = copy:FindFirstChild(ROOT_PART_NAME)
if not root or not root:IsA("BasePart") then
	error("build_drill_bit_projectile: the source has no " .. ROOT_PART_NAME .. " part")
end
root.Name = TEMPLATE_NAME
root.Anchored = true
for _, part in copy:GetDescendants() do
	if part:IsA("BasePart") then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
	end
end
for _, part in copy:GetChildren() do
	if part:IsA("BasePart") and part ~= root then
		part.Anchored = true
		part.Parent = root
	end
end
-- the source's welds do nothing for anchored parts placed by hand
for _, child in root:GetDescendants() do
	if child:IsA("WeldConstraint") then
		child:Destroy()
	end
end

local tail = Instance.new("Attachment")
tail.Name = Constants.PROJECTILE_TAIL_ATTACHMENT
tail.Position = Vector3.new(-root.Size.X / 2, 0, 0)
tail.Parent = root
local trail = Instance.new("ParticleEmitter")
trail.Name = "Trail"
trail.Rate = 0
trail.Enabled = false
trail.Parent = tail

root.Parent = projectiles
copy:Destroy()

ChangeHistoryService:SetWaypoint("After DrillBit projectile")
print("build_drill_bit_projectile: built GameAssets." .. Constants.PROJECTILE_TEMPLATES_FOLDER .. "." .. TEMPLATE_NAME .. " from " .. SOURCE_NAME)
