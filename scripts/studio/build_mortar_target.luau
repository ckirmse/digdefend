-- Builds the "MortarTarget" landing marker under
-- ReplicatedStorage/GameAssets/Effects (2026-10-20): the flat ring a
-- gunner on a lob post (the Napalm Mortar) sees where the shell will
-- fall, cloned and sized by ClientPostManager to the pool it leaves. A
-- cylinder on end, Neon, never collides; the designer tunes its look in
-- the Explorer. Run from the Studio command bar (or the MCP execute_luau
-- tool) in the gameplay place; it replaces any existing copy. The name
-- must match GameData/Posts/PostWeapons' PROJECTILE.TARGET_TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local TEMPLATE_NAME = "MortarTarget"
local THICKNESS_STUDS = 0.2
local COLOR = Color3.fromRGB(255, 120, 40)

ChangeHistoryService:SetWaypoint("Before MortarTarget")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local effects = gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER)
local existing = effects:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local marker = Instance.new("Part")
marker.Name = TEMPLATE_NAME
marker.Shape = Enum.PartType.Cylinder
marker.Size = Vector3.new(THICKNESS_STUDS, 16, 16)
marker.Color = COLOR
marker.Material = Enum.Material.Neon
marker.Transparency = 0.45
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.CastShadow = false
marker.Parent = effects

ChangeHistoryService:SetWaypoint("After MortarTarget")
print("build_mortar_target: built GameAssets." .. Constants.EFFECT_TEMPLATES_FOLDER .. "." .. TEMPLATE_NAME)
