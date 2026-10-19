-- Rebuilds the "HeadshotBonus" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui (2026-10-19): the "HEADSHOT BONUS"
-- callout ClientHeadshotManager clones over a monster the local player
-- just headshot, rising and fading for a second, seen by that player
-- alone. Run from the Studio command bar (or the MCP execute_luau tool)
-- in the gameplay place; it replaces any existing copy. Names must match
-- Constants.HEADSHOT_*. Sizes are in studs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before HeadshotBonus billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
local existing = guiFolder:FindFirstChild(Constants.HEADSHOT_BILLBOARD)
if existing then
	existing:Destroy()
end

local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.HEADSHOT_BILLBOARD
billboard.Size = UDim2.fromScale(8, 1.6)
billboard.MaxDistance = 400
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local label = Instance.new("TextLabel")
label.Name = Constants.HEADSHOT_LABEL
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = UiStyle.formatTitle("Headshot Bonus")
label.TextColor3 = UiStyle.ACCENT_COLOR
label.TextScaled = true
label.FontFace = UiStyle.TITLE_FONT
label.Parent = billboard
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
textSize.MaxTextSize = 40
textSize.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX
stroke.Color = UiStyle.ACCENT_STROKE_COLOR
stroke.Parent = label

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After HeadshotBonus billboard")
print("Built GameAssets.Gui." .. Constants.HEADSHOT_BILLBOARD)
