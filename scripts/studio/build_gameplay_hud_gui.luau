-- Rebuilds the "GameplayHud" ScreenGui under StarterGui: the backpack button
-- (icon, "taken/total", and the "Backpack full" label) that
-- ClientBackpackManager shows while the pick axe is held (GDD "Mining
-- Rock"); the balance rows top left and the Camp Level bar top centre that
-- ClientRefineryManager keeps current (GDD "Refining Ore"); and the FlyLayer
-- its icons travel across. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.GAMEPLAY_HUD_* / HUD_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before GameplayHud gui")

local existing = StarterGui:FindFirstChild("GameplayHud")
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

local gui = Instance.new("ScreenGui")
gui.Name = "GameplayHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- bottom-right, clear of the tool bar in the centre
local button = Instance.new("TextButton")
button.Name = "BackpackButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.fromScale(0.98, 0.97)
button.Size = UDim2.fromScale(0.11, 0.08)
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 2.2
aspect.Parent = button
local size = Instance.new("UISizeConstraint")
size.MinSize = Vector2.new(110, 50)
size.MaxSize = Vector2.new(260, 118)
size.Parent = button
button.BackgroundColor3 = UiStyle.PANEL_COLOR
button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = true
button.Visible = false
button.Parent = gui
addCorner(button)

-- placeholder icon until art: a bag glyph
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Position = UDim2.fromScale(0.05, 0.12)
icon.Size = UDim2.fromScale(0.28, 0.76)
icon.BackgroundTransparency = 1
icon.Text = "🎒"
icon.TextScaled = true
icon.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(icon, UiStyle.BODY_TEXT_MIN_PX, 40)
icon.Parent = button

local count = Instance.new("TextLabel")
count.Name = "CountLabel"
count.Position = UDim2.fromScale(0.36, 0.12)
count.Size = UDim2.fromScale(0.6, 0.5)
count.BackgroundTransparency = 1
count.Text = "0/50"
count.TextColor3 = UiStyle.TEXT_COLOR
count.TextScaled = true
count.TextXAlignment = Enum.TextXAlignment.Left
count.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(count, UiStyle.BODY_TEXT_MIN_PX, 32)
count.Parent = button

local full = Instance.new("TextLabel")
full.Name = "FullLabel"
full.Position = UDim2.fromScale(0.36, 0.6)
full.Size = UDim2.fromScale(0.6, 0.3)
full.BackgroundTransparency = 1
full.Text = "Backpack full"
full.TextColor3 = UiStyle.NEGATIVE_COLOR
full.TextScaled = true
full.TextXAlignment = Enum.TextXAlignment.Left
full.FontFace = UiStyle.BODY_FONT
full.Visible = false
addTextSizeBounds(full, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
full.Parent = button

-- balances, top left, one row per resource; the icon is a coloured disc
-- until ore art exists
local balances = Instance.new("Frame")
balances.Name = "Balances"
balances.AnchorPoint = Vector2.new(0, 0)
balances.Position = UDim2.fromScale(0.015, 0.03)
balances.Size = UDim2.fromScale(0.13, 0.16)
balances.BackgroundTransparency = 1
local balancesSize = Instance.new("UISizeConstraint")
balancesSize.MinSize = Vector2.new(120, 96)
balancesSize.MaxSize = Vector2.new(300, 240)
balancesSize.Parent = balances
local balancesLayout = Instance.new("UIListLayout")
balancesLayout.FillDirection = Enum.FillDirection.Vertical
balancesLayout.SortOrder = Enum.SortOrder.LayoutOrder
balancesLayout.Padding = UDim.new(0.04, 0)
balancesLayout.Parent = balances
balances.Parent = gui

local ROWS = {
	{ name = "IronRow", color = Color3.fromRGB(160, 165, 175), text = "0" },
	{ name = "GoldRow", color = Color3.fromRGB(240, 200, 60), text = "0" },
	{ name = "UraniumRow", color = Color3.fromRGB(120, 240, 90), text = "0 / 0" },
}
for order, spec in ROWS do
	local row = Instance.new("Frame")
	row.Name = spec.name
	row.LayoutOrder = order
	row.Size = UDim2.fromScale(1, 0.3)
	row.BackgroundColor3 = UiStyle.PANEL_COLOR
	row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	addCorner(row)
	local rowIcon = Instance.new("Frame")
	rowIcon.Name = "Icon"
	rowIcon.AnchorPoint = Vector2.new(0, 0.5)
	rowIcon.Position = UDim2.fromScale(0.05, 0.5)
	rowIcon.Size = UDim2.fromScale(0.7, 0.7)
	rowIcon.BackgroundColor3 = spec.color
	rowIcon.BorderSizePixel = 0
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = rowIcon
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0.5, 0)
	iconCorner.Parent = rowIcon
	rowIcon.Parent = row
	local value = Instance.new("TextLabel")
	value.Name = "ValueLabel"
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.fromScale(0.3, 0.5)
	value.Size = UDim2.fromScale(0.66, 0.8)
	value.BackgroundTransparency = 1
	value.Text = spec.text
	value.TextColor3 = UiStyle.TEXT_COLOR
	value.TextScaled = true
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.FontFace = UiStyle.BODY_BOLD_FONT
	addTextSizeBounds(value, UiStyle.BODY_TEXT_MIN_PX, 30)
	value.Parent = row
	row.Parent = balances
end

-- camp level, top centre: title above an XP-style bar
local campLevel = Instance.new("Frame")
campLevel.Name = "CampLevel"
campLevel.AnchorPoint = Vector2.new(0.5, 0)
campLevel.Position = UDim2.fromScale(0.5, 0.03)
campLevel.Size = UDim2.fromScale(0.26, 0.09)
campLevel.BackgroundTransparency = 1
local campSize = Instance.new("UISizeConstraint")
campSize.MinSize = Vector2.new(200, 54)
campSize.MaxSize = Vector2.new(560, 140)
campSize.Parent = campLevel
campLevel.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "TitleLabel"
title.Position = UDim2.fromScale(0, 0)
title.Size = UDim2.fromScale(1, 0.42)
title.BackgroundTransparency = 1
title.Text = UiStyle.formatTitle("Camp Level 1")
title.TextColor3 = UiStyle.ACCENT_COLOR
title.TextScaled = true
title.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(title, UiStyle.BODY_TEXT_MIN_PX, 34)
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = UiStyle.ACCENT_STROKE_COLOR
titleStroke.Thickness = UiStyle.STROKE_PX
titleStroke.Parent = title
title.Parent = campLevel

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
addTextSizeBounds(progress, UiStyle.LABEL_TEXT_MIN_PX, 24)
local progressStroke = Instance.new("UIStroke")
progressStroke.Color = UiStyle.BACKGROUND_COLOR
progressStroke.Thickness = 1
progressStroke.Parent = progress
progress.Parent = bar
bar.Parent = campLevel

-- the layer flying icons cross; above everything else in this gui
local flyLayer = Instance.new("Frame")
flyLayer.Name = "FlyLayer"
flyLayer.Size = UDim2.fromScale(1, 1)
flyLayer.BackgroundTransparency = 1
flyLayer.ZIndex = 10
flyLayer.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GameplayHud gui")
print("build_gameplay_hud_gui: built StarterGui.GameplayHud")
