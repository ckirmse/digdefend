-- Builds the "DrillImpact" burst under ReplicatedStorage/GameAssets/
-- Effects (2026-10-22): the sand thrown up where the Fault Line Drill's
-- bit hits the ground, played by ClientProjectileManager:playAuthoredBlast
-- (every emitter fired once for its BurstCount attribute). One invisible
-- anchored part with a single emitter on the designer's sand texture,
-- its values ported from the designer's tuning in the Explorer the same
-- day (a second, faster grit emitter was dropped then). Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy. The name must match
-- GameData/Posts/PostWeapons' DRILL_GUN PROJECTILE.BLAST_TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local Constants = require(ReplicatedStorage.Shared.Constants)

local TEMPLATE_NAME = "DrillImpact"
local SAND_TEXTURE = "rbxassetid://528256032"
local SAND_LIGHT = Color3.fromRGB(214, 190, 140)
local SAND_DARK = Color3.fromRGB(150, 125, 85)

ChangeHistoryService:SetWaypoint("Before DrillImpact")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local effects = gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER)
local existing = effects:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local anchor = Instance.new("Part")
anchor.Name = TEMPLATE_NAME
anchor.Size = Vector3.one
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.CastShadow = false
anchor.Parent = effects

local grit = Instance.new("ParticleEmitter")
grit.Name = "Grit"
grit.Texture = SAND_TEXTURE
grit.Color = ColorSequence.new(SAND_LIGHT, SAND_DARK)
grit.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 4),
	NumberSequenceKeypoint.new(0.3, 10),
	NumberSequenceKeypoint.new(1, 16),
})
grit.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.887),
	NumberSequenceKeypoint.new(1, 1),
})
grit.Lifetime = NumberRange.new(1, 1)
grit.Speed = NumberRange.new(14, 26)
grit.SpreadAngle = Vector2.new(55, 55)
grit.Rotation = NumberRange.new(-180, 180)
grit.RotSpeed = NumberRange.new(-40, 40)
grit.Acceleration = Vector3.new(0, -6, 0)
grit.Drag = 2
grit.EmissionDirection = Enum.NormalId.Top
grit.Rate = 0
grit.Enabled = false
grit:SetAttribute(Attributes.BURST_COUNT, 40)
grit.Parent = anchor

ChangeHistoryService:SetWaypoint("After DrillImpact")
print("build_drill_impact: built GameAssets." .. Constants.EFFECT_TEMPLATES_FOLDER .. "." .. TEMPLATE_NAME)
