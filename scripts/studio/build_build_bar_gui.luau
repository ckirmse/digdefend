-- Rebuilds the "BuildBar" ScreenGui under StarterGui: the row of Tower and
-- Trap entries ClientPlacementToolManager shows in the tool bar's place
-- in Build Mode (GDD "Building Towers": a circle with the item's
-- picture, its price above it, its number key in the corner, greyed while
-- unaffordable), the touch-only Exit button beside it, and the Placement
-- panel above, with a Cancel button and a Build button carrying the price,
-- shown while a preview is out. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.BUILD_BAR_*. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before BuildBar gui")

local existing = StarterGui:FindFirstChild("BuildBar")
if existing then
	existing:Destroy()
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

local function addMaxSize(frame, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addTouchTarget(button, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
	constraint.MaxSize = maxSize
	constraint.Parent = button
end

local function addAspect(frame, ratio)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	aspect.Parent = frame
end

local function makeLabel(name, text, font, color, maxPx)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = font
	label.TextTruncate = Enum.TextTruncate.AtEnd
	addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, maxPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiStyle.BACKGROUND_COLOR
	stroke.Thickness = 1
	stroke.Parent = label
	return label
end

-- an icon and a number side by side, centred: the price of a Tower or a
-- Trap count. The icon keeps square through the aspect constraint
local function makePriceRow(name, height)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.fromScale(1, height)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.04, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local icon = Instance.new("ImageLabel")
	icon.Name = "ResourceIcon"
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromScale(0.35, 0.9)
	addAspect(icon, 1)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row
	local price = makeLabel("Price", "20", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	price.LayoutOrder = 2
	price.Size = UDim2.fromScale(0.5, 1)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.Parent = row
	return row
end

local gui = Instance.new("ScreenGui")
gui.Name = "BuildBar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the entries take the tool bar's spot (its row ends at 0.97)
local entries = Instance.new("Frame")
entries.Name = "Entries"
entries.AnchorPoint = Vector2.new(0.5, 1)
entries.Position = UDim2.fromScale(0.5, 0.97)
entries.Size = UDim2.fromScale(0.85, 0.24)
addMaxSize(entries, Vector2.new(1500, 255))
entries.BackgroundTransparency = 1
entries.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0.015, 0)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = entries

-- one entry, styled like a tool bar slot: the name above, the square slot
-- in the middle (the item's picture, the kind badge top-left, the number
-- key top-right), and the price (or the Trap count) under it
local template = Instance.new("TextButton")
template.Name = "EntryTemplate"
template.Size = UDim2.fromScale(0.1, 1)
addAspect(template, 0.62)
addMaxSize(template, Vector2.new(150, 240))
template.BackgroundTransparency = 1
template.Text = ""
template.AutoButtonColor = false
template.Visible = false
template.Parent = entries

local nameLabel = makeLabel("NameLabel", UiStyle.formatTitle("Sentry Gun"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.LABEL_TEXT_MAX_PX)
nameLabel.AnchorPoint = Vector2.new(0.5, 0)
nameLabel.Position = UDim2.fromScale(0.5, 0)
nameLabel.Size = UDim2.fromScale(1.3, 0.16)
nameLabel.Parent = template

local slot = Instance.new("Frame")
slot.Name = "Slot"
slot.AnchorPoint = Vector2.new(0.5, 0)
slot.Position = UDim2.fromScale(0.5, 0.19)
slot.Size = UDim2.fromScale(1, 0.6)
addAspect(slot, 1)
addTouchTarget(slot, Vector2.new(144, 144))
slot.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
slot.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
slot.BorderSizePixel = 0
addCorner(slot)
local slotStroke = Instance.new("UIStroke")
slotStroke.Thickness = UiStyle.STROKE_PX
slotStroke.Color = UiStyle.PANEL_COLOR
slotStroke.Parent = slot
slot.Parent = template

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.Position = UDim2.fromScale(0.1, 0.1)
icon.Size = UDim2.fromScale(0.8, 0.8)
icon.BackgroundTransparency = 1
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = slot

-- the kind badge, top-left: Icons.UI.TOWER or Icons.UI.TRAP
local typeIcon = Instance.new("ImageLabel")
typeIcon.Name = "TypeIcon"
typeIcon.Position = UDim2.fromScale(0.05, 0.05)
typeIcon.Size = UDim2.fromScale(0.28, 0.28)
addAspect(typeIcon, 1)
typeIcon.BackgroundTransparency = 1
typeIcon.ScaleType = Enum.ScaleType.Fit
typeIcon.ZIndex = 2
typeIcon.Parent = slot

-- the number key, top-right; hidden without a keyboard
local keyLabel = makeLabel("KeyLabel", "1", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MAX_PX)
keyLabel.AnchorPoint = Vector2.new(1, 0)
keyLabel.Position = UDim2.fromScale(0.94, 0.04)
keyLabel.Size = UDim2.fromScale(0.3, 0.26)
keyLabel.TextXAlignment = Enum.TextXAlignment.Right
keyLabel.ZIndex = 2
keyLabel.Parent = slot

local priceRow = makePriceRow("PriceRow", 0.18)
priceRow.AnchorPoint = Vector2.new(0.5, 1)
priceRow.Position = UDim2.fromScale(0.5, 1)
priceRow.Size = UDim2.fromScale(1.3, 0.18)
priceRow.Parent = template

-- always up in Build Mode: "EXIT BUILD MODE", tapped on touch, with the
-- shortcut ([RMB] or [B]) in its corner for keyboard and gamepad
local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.AnchorPoint = Vector2.new(0, 1)
exitButton.Position = UDim2.fromScale(0.86, 0.97)
exitButton.Size = UDim2.fromScale(0.12, 0.08)
addTouchTarget(exitButton, Vector2.new(180, 72))
exitButton.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
exitButton.BorderSizePixel = 0
exitButton.Text = ""
exitButton.AutoButtonColor = true
exitButton.Visible = true
addCorner(exitButton)
local exitStroke = Instance.new("UIStroke")
exitStroke.Thickness = UiStyle.STROKE_PX
exitStroke.Color = UiStyle.ACCENT_STROKE_COLOR
exitStroke.Parent = exitButton
local exitText = makeLabel("Text", UiStyle.formatTitle("Exit Build Mode"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
exitText.Position = UDim2.fromScale(0.05, 0.08)
exitText.Size = UDim2.fromScale(0.9, 0.5)
exitText.Parent = exitButton
local exitKey = makeLabel("KeyLabel", UiStyle.formatTitle("[RMB]"), UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_COLOR, UiStyle.LABEL_TEXT_MAX_PX)
exitKey.Position = UDim2.fromScale(0.05, 0.6)
exitKey.Size = UDim2.fromScale(0.9, 0.32)
exitKey.Parent = exitButton
exitButton.Parent = gui

-- the Placement panel above the entries, touch only: a Build button with
-- the price while the preview is green. The Cancel button is kept for a
-- later design that wants it; an entry is always selected now, so it is hidden
local panel = Instance.new("Frame")
panel.Name = "Placement"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.fromScale(0.5, 0.71)
panel.Size = UDim2.fromScale(0.36, 0.08)
addMaxSize(panel, Vector2.new(480, 80))
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui

local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Horizontal
panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
panelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
panelLayout.Padding = UDim.new(0.04, 0)
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.LayoutOrder = 1
cancelButton.Size = UDim2.fromScale(0.36, 1)
addTouchTarget(cancelButton, Vector2.new(180, 72))
cancelButton.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
cancelButton.BorderSizePixel = 0
cancelButton.Text = UiStyle.formatTitle("Cancel")
cancelButton.TextColor3 = UiStyle.TEXT_COLOR
cancelButton.TextScaled = true
cancelButton.FontFace = UiStyle.TITLE_FONT
cancelButton.AutoButtonColor = true
cancelButton.Visible = false
addTextSizeBounds(cancelButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
addCorner(cancelButton)
local cancelStroke = Instance.new("UIStroke")
cancelStroke.Thickness = UiStyle.STROKE_PX
cancelStroke.Color = UiStyle.ACCENT_STROKE_COLOR
cancelStroke.Parent = cancelButton
cancelButton.Parent = panel

local buildButton = Instance.new("TextButton")
buildButton.Name = "BuildButton"
buildButton.LayoutOrder = 2
buildButton.Size = UDim2.fromScale(0.6, 1)
addTouchTarget(buildButton, Vector2.new(300, 72))
buildButton.BackgroundColor3 = UiStyle.ACCENT_COLOR
buildButton.BorderSizePixel = 0
buildButton.Text = ""
buildButton.AutoButtonColor = true
addCorner(buildButton)
buildButton.Parent = panel

local buildText = makeLabel("Text", UiStyle.formatTitle("Build"), UiStyle.TITLE_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.BODY_TEXT_MAX_PX)
buildText.AnchorPoint = Vector2.new(0, 0.5)
buildText.Position = UDim2.fromScale(0.08, 0.5)
buildText.Size = UDim2.fromScale(0.42, 0.7)
buildText.TextXAlignment = Enum.TextXAlignment.Left
buildText:FindFirstChildOfClass("UIStroke"):Destroy()
buildText.Parent = buildButton

local buildPrice = makePriceRow("PriceRow", 0.7)
buildPrice.AnchorPoint = Vector2.new(1, 0.5)
buildPrice.Position = UDim2.fromScale(0.95, 0.5)
buildPrice.Size = UDim2.fromScale(0.45, 0.7)
local buildPriceLabel = buildPrice:FindFirstChild("Price")
buildPriceLabel.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
buildPriceLabel:FindFirstChildOfClass("UIStroke"):Destroy()
buildPrice.Parent = buildButton

-- the Tower counter, centred above the bar: a Tower icon (a disc until
-- Icons.UI.TOWER has an image) and "2 / 5"
local towerCount = Instance.new("Frame")
towerCount.Name = "TowerCount"
towerCount.AnchorPoint = Vector2.new(0.5, 1)
towerCount.Position = UDim2.fromScale(0.5, 0.62)
towerCount.Size = UDim2.fromScale(0.12, 0.08)
addMaxSize(towerCount, Vector2.new(180, 72))
towerCount.BackgroundColor3 = UiStyle.PANEL_COLOR
towerCount.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
towerCount.BorderSizePixel = 0
addCorner(towerCount)
local towerCountStroke = Instance.new("UIStroke")
towerCountStroke.Thickness = UiStyle.STROKE_PX
towerCountStroke.Color = UiStyle.ACCENT_STROKE_COLOR
towerCountStroke.Parent = towerCount
local towerIcon = Instance.new("ImageLabel")
towerIcon.Name = "Icon"
towerIcon.AnchorPoint = Vector2.new(0, 0.5)
towerIcon.Position = UDim2.fromScale(0.06, 0.5)
towerIcon.Size = UDim2.fromScale(0.3, 0.7)
addAspect(towerIcon, 1)
towerIcon.BackgroundColor3 = UiStyle.ACCENT_COLOR
-- the disc only shows while Icons.UI.TOWER is the placeholder
towerIcon.BackgroundTransparency = 1
towerIcon.BorderSizePixel = 0
towerIcon.ScaleType = Enum.ScaleType.Fit
addCorner(towerIcon, UDim.new(1, 0))
towerIcon.Parent = towerCount
local towerCountLabel = makeLabel("Label", "0 / 5", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
towerCountLabel.AnchorPoint = Vector2.new(1, 0.5)
towerCountLabel.Position = UDim2.fromScale(0.94, 0.5)
towerCountLabel.Size = UDim2.fromScale(0.55, 0.7)
towerCountLabel.TextXAlignment = Enum.TextXAlignment.Right
towerCountLabel.Parent = towerCount
towerCount.Parent = gui

-- the hint, top centre of the screen (under the top bar inset), clear of the bar
local hint = makeLabel("Hint", UiStyle.formatTitle("LMB to place, RMB to exit"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 32)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.fromScale(0.5, 0.12)
hint.Size = UDim2.fromScale(0.5, 0.05)
hint.Visible = false
local hintStroke = hint:FindFirstChildOfClass("UIStroke")
hintStroke.Thickness = UiStyle.STROKE_PX
hint.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After BuildBar gui")
print("build_build_bar_gui: built StarterGui.BuildBar")
