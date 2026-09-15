-- Rebuilds the "CampLevel" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: the crew's Camp Level, "CAMP LEVEL n"
-- over an XP-style bar with the diamond icon, that ClientRefineryManager
-- clones onto the Refinery at run start (GDD "Camp Level": the permanent
-- display lives on the Refinery, not in the HUD; decided 2026-09-15). Run
-- from the Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy. Names must match
-- Constants.CAMP_LEVEL_*. Sizes are in studs (BillboardGui scale units), so
-- the sign reads the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(ReplicatedStorage.Shared.UiStyle)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Enums = require(ReplicatedStorage.Shared.Enums)

ChangeHistoryService:SetWaypoint("Before CampLevel billboard")

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
local existing = guiFolder:FindFirstChild("CampLevel")
if existing then
	existing:Destroy()
end

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

-- 12 studs wide, 3 tall, readable from across the camp and gone at distance
local billboard = Instance.new("BillboardGui")
billboard.Name = "CampLevel"
billboard.Size = UDim2.fromScale(12, 3)
billboard.MaxDistance = 140
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
title.Size = UDim2.fromScale(1, 0.42)
title.BackgroundTransparency = 1
title.Text = UiStyle.formatTitle("Camp Level 1")
title.TextColor3 = UiStyle.ACCENT_COLOR
title.TextScaled = true
title.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(title, UiStyle.BODY_TEXT_MIN_PX, 60)
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = UiStyle.ACCENT_STROKE_COLOR
titleStroke.Thickness = UiStyle.STROKE_PX
titleStroke.Parent = title
title.Parent = root

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.fromScale(0.5, 1)
bar.Size = UDim2.fromScale(1, 0.5)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
bar.ClipsDescendants = true
addCorner(bar)
local barStroke = Instance.new("UIStroke")
barStroke.Color = UiStyle.ACCENT_STROKE_COLOR
barStroke.Thickness = UiStyle.STROKE_PX
barStroke.Parent = bar
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
fill.BorderSizePixel = 0
addCorner(fill)
fill.Parent = bar
local progress = Instance.new("TextLabel")
progress.Name = "ProgressLabel"
progress.Size = UDim2.fromScale(1, 1)
progress.BackgroundTransparency = 1
progress.Text = "0 / 0"
progress.TextColor3 = UiStyle.TEXT_COLOR
progress.TextScaled = true
progress.FontFace = UiStyle.BODY_BOLD_FONT
progress.ZIndex = 2
addTextSizeBounds(progress, UiStyle.LABEL_TEXT_MIN_PX, 40)
local progressStroke = Instance.new("UIStroke")
progressStroke.Color = UiStyle.BACKGROUND_COLOR
progressStroke.Thickness = 1
progressStroke.Parent = progress
progress.Parent = bar
bar.Parent = root

-- the diamond over the bar's left end says what fills it; on the root
-- frame (the bar clips its children) at twice the bar's height
local campIconId = Icons.REFINED_RESOURCE[Enums.RefinedResource.DIAMOND]
local campIcon = Instance.new("ImageLabel")
campIcon.Name = "Icon"
campIcon.AnchorPoint = Vector2.new(0.5, 0.5)
campIcon.Position = UDim2.fromScale(0, 0.75)
campIcon.Size = UDim2.fromScale(0.9, 0.9)
campIcon.BackgroundTransparency = 1
campIcon.Image = if Icons.isPlaceholder(campIconId) then "" else campIconId
campIcon.ScaleType = Enum.ScaleType.Fit
campIcon.ZIndex = 3
local campIconAspect = Instance.new("UIAspectRatioConstraint")
campIconAspect.AspectRatio = 1
campIconAspect.DominantAxis = Enum.DominantAxis.Height
campIconAspect.Parent = campIcon
campIcon.Parent = root

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After CampLevel billboard")
print("build_camp_level_billboard: built " .. billboard:GetFullName())
