-- Rebuilds the "SpiderSpawn" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui (M62, dev tool, 2026-10-08): the label
-- LurkerManager hangs over every sleeping lurker pocket's resting cell
-- when the Monsters dev panel's "Show Cave Spider spawns" is on, drawn on
-- top of everything and from far off so a tester can see it through the
-- rock and walk straight to it. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. The name must match Constants.SPIDER_SPAWN_BILLBOARD.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before SpiderSpawn billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
local existing = guiFolder:FindFirstChild(Constants.SPIDER_SPAWN_BILLBOARD)
if existing then
	existing:Destroy()
end

-- 8 studs wide, 2 tall, on top of the world, seen from 400 studs
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.SPIDER_SPAWN_BILLBOARD
billboard.Size = UDim2.fromScale(8, 2)
billboard.MaxDistance = 400
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = UiStyle.formatTitle("Spider Spawn")
label.TextColor3 = Color3.fromRGB(255, 80, 80)
label.TextScaled = true
label.FontFace = UiStyle.TITLE_FONT
local constraint = Instance.new("UITextSizeConstraint")
constraint.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
constraint.MaxTextSize = UiStyle.TITLE_TEXT_MAX_PX
constraint.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(0, 0, 0)
stroke.Thickness = UiStyle.STROKE_PX
stroke.Parent = label
label.Parent = billboard

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After SpiderSpawn billboard")
print("build_spider_spawn_billboard: rebuilt " .. billboard:GetFullName())
