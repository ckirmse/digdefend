-- Rebuilds the "RescueRadio" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: the radio's sign over
-- Camp.Radio.GuiPart, "RESCUE RADIO" over the uranium count against the
-- target (the uranium icon beside the number, never the word; UI rule,
-- decided 2026-09-24) and a status line (waiting for the target, ready to call,
-- the helicopter's countdown, boarding), that ClientRescueManager clones
-- onto the radio at run start (M31, decided 2026-09-24). Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay place;
-- it replaces any existing copy. Names must match Constants.RESCUE_RADIO_*.
-- Sizes are in studs (BillboardGui scale units), so the sign reads the same
-- on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(ReplicatedStorage.Shared.UiStyle)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Enums = require(ReplicatedStorage.Shared.Enums)

ChangeHistoryService:SetWaypoint("Before RescueRadio billboard")

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = "GameAssets"
	gameAssets.Parent = ReplicatedStorage
end
local guiFolder = gameAssets:FindFirstChild("Gui")
if not guiFolder then
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "Gui"
	guiFolder.Parent = gameAssets
end
local existing = guiFolder:FindFirstChild("RescueRadio")
if existing then
	existing:Destroy()
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

local function addStroke(label, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = label
end

-- 12 studs wide, 3.6 tall: three lines readable from across the pad
local billboard = Instance.new("BillboardGui")
billboard.Name = "RescueRadio"
billboard.Size = UDim2.fromScale(12, 3.6)
billboard.MaxDistance = 120
-- floats this far above GuiPart (decided 2026-09-24)
billboard.StudsOffset = Vector3.new(0, 2, 0)
billboard.AlwaysOnTop = false
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = billboard

local title = Instance.new("TextLabel")
title.Name = "TitleLabel"
title.Position = UDim2.fromScale(0, 0)
title.Size = UDim2.fromScale(1, 0.34)
title.BackgroundTransparency = 1
title.Text = UiStyle.formatTitle("Rescue Radio")
title.TextColor3 = UiStyle.ACCENT_COLOR
title.TextScaled = true
title.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(title, UiStyle.BODY_TEXT_MIN_PX, 56)
addStroke(title, UiStyle.ACCENT_STROKE_COLOR, UiStyle.STROKE_PX)
title.Parent = root

-- the count row: the uranium icon then "0 / 0", centred as a pair
local row = Instance.new("Frame")
row.Name = "UraniumRow"
row.AnchorPoint = Vector2.new(0.5, 0)
row.Position = UDim2.fromScale(0.5, 0.36)
row.Size = UDim2.fromScale(0.6, 0.32)
row.BackgroundTransparency = 1
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0.06, 0)
rowLayout.Parent = row

local uraniumIconId = Icons.REFINED_RESOURCE[Enums.RefinedResource.URANIUM]
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.LayoutOrder = 1
icon.Size = UDim2.fromScale(1, 1)
icon.BackgroundTransparency = 1
icon.Image = if Icons.isPlaceholder(uraniumIconId) then "" else uraniumIconId
icon.ScaleType = Enum.ScaleType.Fit
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
icon.Parent = row

local uranium = Instance.new("TextLabel")
uranium.Name = "UraniumLabel"
uranium.LayoutOrder = 2
-- the label hugs its text so the icon and number centre as one pair
uranium.Size = UDim2.fromScale(0, 1)
uranium.AutomaticSize = Enum.AutomaticSize.X
uranium.BackgroundTransparency = 1
uranium.Text = "0 / 0"
uranium.TextColor3 = UiStyle.TEXT_COLOR
uranium.TextXAlignment = Enum.TextXAlignment.Center
uranium.TextScaled = true
uranium.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(uranium, UiStyle.LABEL_TEXT_MIN_PX, 44)
addStroke(uranium, UiStyle.BACKGROUND_COLOR, 1)
uranium.Parent = row
row.Parent = root

local status = Instance.new("TextLabel")
status.Name = "StatusLabel"
status.Position = UDim2.fromScale(0, 0.7)
status.Size = UDim2.fromScale(1, 0.3)
status.BackgroundTransparency = 1
status.Text = "Complete your Uranium quota to call in a rescue helicopter"
status.TextColor3 = UiStyle.TEXT_MUTED_COLOR
status.TextScaled = true
status.FontFace = UiStyle.BODY_FONT
addTextSizeBounds(status, UiStyle.LABEL_TEXT_MIN_PX, 34)
addStroke(status, UiStyle.BACKGROUND_COLOR, 1)
status.Parent = root

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After RescueRadio billboard")
print("build_rescue_radio_billboard: built " .. billboard:GetFullName())
