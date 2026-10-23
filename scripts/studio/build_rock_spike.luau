-- Builds the "RockSpike" under ReplicatedStorage/GameAssets/Effects
-- (2026-10-22): one spike of rock the Fault Line Drill's crack raises
-- along the ground, cloned, scaled, and leaned by ClientFaultLineManager.
-- A placeholder until the designer's art lands: a tall slate block,
-- never collides; the designer tunes its look in the Explorer. Run from
-- the Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local TEMPLATE_NAME = "RockSpike"
local SIZE = Vector3.new(1.4, 5, 1.4)
local COLOR = Color3.fromRGB(120, 108, 96)

ChangeHistoryService:SetWaypoint("Before RockSpike")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local effects = gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER)
local existing = effects:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local spike = Instance.new("Part")
spike.Name = TEMPLATE_NAME
spike.Size = SIZE
spike.Color = COLOR
spike.Material = Enum.Material.Slate
spike.Anchored = true
spike.CanCollide = false
spike.CanQuery = false
spike.CanTouch = false
spike.CastShadow = true
spike.Parent = effects

ChangeHistoryService:SetWaypoint("After RockSpike")
print("build_rock_spike: built GameAssets." .. Constants.EFFECT_TEMPLATES_FOLDER .. "." .. TEMPLATE_NAME)
