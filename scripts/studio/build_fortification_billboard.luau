-- Rebuilds the "Fortification" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: the shared fortification tier,
-- "FORTIFICATIONS LEVEL n" over a bar of the crew's donated Iron reading
-- "pool / required" with the Iron Bar icon, and a red "Camp Level N required"
-- line under it while the next tier is locked. ClientWorkbenchManager clones
-- it above the camp's Workbench (GDD "Wall Repair"), the way the Camp Level
-- sign hangs over the Refinery. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.FORTIFICATION_*. Sizes are in studs
-- (BillboardGui scale units), so the sign reads the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Icons = require(ReplicatedStorage.Shared.Icons)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before Fortification billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
if not guiFolder then
	guiFolder = Instance.new("Folder")
	guiFolder.Name = Constants.GUI_TEMPLATES_FOLDER
	guiFolder.Parent = gameAssets
end
local existing = guiFolder:FindFirstChild(Constants.FORTIFICATION_BILLBOARD)
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

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

-- 10 studs wide, 3.4 tall: title, bar, lock line; readable from the gate and
-- gone at distance
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.FORTIFICATION_BILLBOARD
billboard.Size = UDim2.fromScale(10, 3.4)
billboard.MaxDistance = 100
billboard.AlwaysOnTop = false
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local root = Instance.new("Frame")
root.Name = Constants.FORTIFICATION_ROOT_FRAME
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = billboard

local title = Instance.new("TextLabel")
title.Name = Constants.FORTIFICATION_TITLE_LABEL
title.Position = UDim2.fromScale(0, 0)
title.Size = UDim2.fromScale(1, 0.32)
title.BackgroundTransparency = 1
title.Text = UiStyle.formatTitle("Fortifications Level 1")
title.TextColor3 = UiStyle.ACCENT_COLOR
title.TextScaled = true
title.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(title, UiStyle.BODY_TEXT_MIN_PX, 60)
addStroke(title, UiStyle.ACCENT_STROKE_COLOR, UiStyle.STROKE_PX)
title.Parent = root

local bar = Instance.new("Frame")
bar.Name = Constants.FORTIFICATION_BAR
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.fromScale(0.5, 0.35)
bar.Size = UDim2.fromScale(1, 0.38)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
bar.ClipsDescendants = true
addCorner(bar)
addStroke(bar, UiStyle.ACCENT_STROKE_COLOR, UiStyle.STROKE_PX)
local fill = Instance.new("Frame")
fill.Name = Constants.FORTIFICATION_FILL
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(170, 175, 185)
fill.BorderSizePixel = 0
addCorner(fill)
fill.Parent = bar
local progress = Instance.new("TextLabel")
progress.Name = Constants.FORTIFICATION_PROGRESS_LABEL
progress.Size = UDim2.fromScale(1, 1)
progress.BackgroundTransparency = 1
progress.Text = "0 / 150"
progress.TextColor3 = UiStyle.TEXT_COLOR
progress.TextScaled = true
progress.FontFace = UiStyle.BODY_BOLD_FONT
progress.ZIndex = 2
addTextSizeBounds(progress, UiStyle.LABEL_TEXT_MIN_PX, 40)
addStroke(progress, UiStyle.BACKGROUND_COLOR, 1)
progress.Parent = bar
bar.Parent = root

-- the Iron Bar over the bar's left end says what fills it; on the root
-- frame (the bar clips its children)
local ironIconId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
local icon = Instance.new("ImageLabel")
icon.Name = Constants.FORTIFICATION_ICON
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0, 0.54)
icon.Size = UDim2.fromScale(0.6, 0.6)
icon.BackgroundTransparency = 1
icon.Image = if Icons.isPlaceholder(ironIconId) then "" else ironIconId
icon.ScaleType = Enum.ScaleType.Fit
icon.ZIndex = 3
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
icon.Parent = root

local lock = Instance.new("TextLabel")
lock.Name = Constants.FORTIFICATION_LOCK_LABEL
lock.AnchorPoint = Vector2.new(0.5, 1)
lock.Position = UDim2.fromScale(0.5, 1)
lock.Size = UDim2.fromScale(1, 0.24)
lock.BackgroundTransparency = 1
lock.Text = "Camp Level 2 required"
lock.TextColor3 = UiStyle.NEGATIVE_COLOR
lock.TextScaled = true
lock.FontFace = UiStyle.BODY_BOLD_FONT
lock.Visible = false
addTextSizeBounds(lock, UiStyle.LABEL_TEXT_MIN_PX, 36)
addStroke(lock, UiStyle.BACKGROUND_COLOR, UiStyle.STROKE_PX)
lock.Parent = root

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After Fortification billboard")
print("build_fortification_billboard: built " .. billboard:GetFullName())
