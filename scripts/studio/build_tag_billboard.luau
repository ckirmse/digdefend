-- Rebuilds the "TagCallout" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui (2026-10-19): the callout every player
-- sees over a monster a Sniper has tagged with the Binoculars, a reticle
-- icon beside "TAGGED BY <name>". ClientBinocularsManager clones it onto
-- an anchor that follows the body and fills the label and icon. Run from
-- the Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy. Names must match Constants.TAG_*.
-- Sizes are in studs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Icons = require(ReplicatedStorage.Shared.Icons)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before TagCallout billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
local existing = guiFolder:FindFirstChild(Constants.TAG_BILLBOARD)
if existing then
	existing:Destroy()
end

local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.TAG_BILLBOARD
billboard.Size = UDim2.fromScale(12, 1.4)
billboard.MaxDistance = 600
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local row = Instance.new("Frame")
row.Name = "Row"
row.AnchorPoint = Vector2.new(0.5, 0.5)
row.Position = UDim2.fromScale(0.5, 0.5)
row.Size = UDim2.fromScale(1, 1)
row.BackgroundTransparency = 1
row.Parent = billboard
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0.02, 0)
layout.Parent = row

local icon = Instance.new("ImageLabel")
icon.Name = Constants.TAG_ICON
icon.LayoutOrder = 1
icon.Size = UDim2.fromScale(1, 1)
icon.BackgroundTransparency = 1
icon.Image = Icons.TAG_RETICLE
icon.ImageColor3 = UiStyle.ACCENT_COLOR
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = row
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = icon

local label = Instance.new("TextLabel")
label.Name = Constants.TAG_LABEL
label.LayoutOrder = 2
label.AutomaticSize = Enum.AutomaticSize.X
label.Size = UDim2.fromScale(0, 1)
label.BackgroundTransparency = 1
label.Text = UiStyle.formatTitle("Tagged by Sniper")
label.TextColor3 = UiStyle.ACCENT_COLOR
label.TextScaled = true
label.FontFace = UiStyle.TITLE_FONT
label.Parent = row
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
textSize.MaxTextSize = 32
textSize.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX
stroke.Color = UiStyle.ACCENT_STROKE_COLOR
stroke.Parent = label

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After TagCallout billboard")
print("Built GameAssets.Gui." .. Constants.TAG_BILLBOARD)
