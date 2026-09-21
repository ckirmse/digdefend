-- Rebuilds the "TowerMenu" ScreenGui under StarterGui: the Upgrade/Sell
-- menu a Tower's owner opens at it (GDD "Upgrading and Selling Towers"),
-- in the tower defense layout. Left column: the Tower's picture with its
-- name and level, the Target Priority toggle (header, value, arrows), the
-- Stats panel (one row per stat cloned from RowTemplate by
-- ClientTowerMenuManager), and a red Sell button. Right column: the
-- Upgrade button naming the next level with its Iron price, four pips
-- under it, and the Upgrade Stats panel (rows of current, arrow, next).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy. Names must match
-- Constants.TOWER_MENU_*. Layout follows the GUI standard in CLAUDE.md;
-- fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before TowerMenu gui")

local existing = StarterGui:FindFirstChild("TowerMenu")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local PIP_COUNT = 4

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
	return label
end

local function makePanel(name, position, size)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Position = position
	panel.Size = size
	panel.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	panel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	addCorner(panel)
	return panel
end

local function makeTextButton(name, text, backgroundColor, textColor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = backgroundColor
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
	addCorner(button)
	return button
end

-- a stat row: the name on the left, the value on the right; the Upgrade
-- Stats panel also shows an arrow and the next value
local function makeStatRow(parent, hasNext)
	local row = Instance.new("Frame")
	row.Name = "RowTemplate"
	row.Size = UDim2.fromScale(1, 0.22)
	row.BackgroundTransparency = 1
	row.Visible = false
	local nameLabel = makeLabel("NameLabel", "Damage", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	nameLabel.Position = UDim2.fromScale(0.04, 0)
	nameLabel.Size = UDim2.fromScale(if hasNext then 0.34 else 0.5, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row
	local valueLabel = makeLabel("ValueLabel", "6", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	if hasNext then
		valueLabel.Position = UDim2.fromScale(0.4, 0)
		valueLabel.Size = UDim2.fromScale(0.22, 1)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		local arrow = makeLabel("ArrowLabel", ">", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
		arrow.Position = UDim2.fromScale(0.64, 0)
		arrow.Size = UDim2.fromScale(0.08, 1)
		arrow.Parent = row
		local nextLabel = makeLabel("NextLabel", "8", UiStyle.BODY_BOLD_FONT, UiStyle.POSITIVE_COLOR, UiStyle.BODY_TEXT_MAX_PX)
		nextLabel.Position = UDim2.fromScale(0.74, 0)
		nextLabel.Size = UDim2.fromScale(0.22, 1)
		nextLabel.TextXAlignment = Enum.TextXAlignment.Left
		nextLabel.Parent = row
	else
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.Position = UDim2.fromScale(0.96, 0)
		valueLabel.Size = UDim2.fromScale(0.4, 1)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	end
	valueLabel.Parent = row
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.04, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.Parent = parent
end

local gui = Instance.new("ScreenGui")
gui.Name = "TowerMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.7, 0.72)
addAspect(dialog, 1.6)
addMaxSize(dialog, Vector2.new(960, 600))
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)
local dialogStroke = Instance.new("UIStroke")
dialogStroke.Thickness = UiStyle.STROKE_PX
dialogStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dialogStroke.Parent = dialog

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.035, 0)
padding.PaddingRight = UDim.new(0.035, 0)
padding.PaddingTop = UDim.new(0.05, 0)
padding.PaddingBottom = UDim.new(0.05, 0)
padding.Parent = dialog

local closeButton = makeTextButton("CloseButton", "X", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1.02, -0.04)
closeButton.Size = UDim2.fromScale(0.07, 0.11)
addAspect(closeButton, 1)
addTouchTarget(closeButton, Vector2.new(56, 56))
closeButton.Parent = dialog

-- left column: 46% wide
local portrait = Instance.new("ImageLabel")
portrait.Name = "Portrait"
portrait.Position = UDim2.fromScale(0, 0)
portrait.Size = UDim2.fromScale(0.2, 0.3)
addAspect(portrait, 1)
portrait.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
portrait.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
portrait.BorderSizePixel = 0
portrait.ScaleType = Enum.ScaleType.Fit
addCorner(portrait)
portrait.Parent = dialog

local nameLabel = makeLabel("NameLabel", UiStyle.formatTitle("Sentry Gun"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 36)
nameLabel.Position = UDim2.fromScale(0.22, 0.02)
nameLabel.Size = UDim2.fromScale(0.24, 0.14)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = dialog

local levelLabel = makeLabel("LevelLabel", "Level 1", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
levelLabel.Position = UDim2.fromScale(0.22, 0.17)
levelLabel.Size = UDim2.fromScale(0.24, 0.1)
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.Parent = dialog

local priority = makePanel("Priority", UDim2.fromScale(0, 0.34), UDim2.fromScale(0.46, 0.17))
priority.Parent = dialog
local priorityHeader = makeLabel("Header", UiStyle.formatTitle("Target Priority"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MAX_PX)
priorityHeader.Position = UDim2.fromScale(0, 0.06)
priorityHeader.Size = UDim2.fromScale(1, 0.34)
priorityHeader.Parent = priority
local priorityValue = makeLabel("ValueLabel", "Closest", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
priorityValue.AnchorPoint = Vector2.new(0.5, 0)
priorityValue.Position = UDim2.fromScale(0.5, 0.45)
priorityValue.Size = UDim2.fromScale(0.5, 0.45)
priorityValue.Parent = priority
for _, entry in { { name = "PreviousButton", text = "<", anchorX = 0, x = 0.04 }, { name = "NextButton", text = ">", anchorX = 1, x = 0.96 } } do
	local arrow = makeTextButton(entry.name, entry.text, UiStyle.PANEL_COLOR, UiStyle.ACCENT_COLOR)
	arrow.AnchorPoint = Vector2.new(entry.anchorX, 0.5)
	arrow.Position = UDim2.fromScale(entry.x, 0.68)
	arrow.Size = UDim2.fromScale(0.16, 0.5)
	addAspect(arrow, 1)
	addTouchTarget(arrow, Vector2.new(56, 56))
	arrow.Parent = priority
end

local stats = makePanel("Stats", UDim2.fromScale(0, 0.54), UDim2.fromScale(0.46, 0.3))
stats.Parent = dialog
makeStatRow(stats, false)

local sellButton = makeTextButton("SellButton", UiStyle.formatTitle("Sell 10"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR)
sellButton.Position = UDim2.fromScale(0, 0.88)
sellButton.Size = UDim2.fromScale(0.46, 0.12)
addTouchTarget(sellButton, Vector2.new(440, 64))
sellButton.Parent = dialog

-- right column: from 52% across
local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "UpgradeButton"
upgradeButton.Position = UDim2.fromScale(0.52, 0)
upgradeButton.Size = UDim2.fromScale(0.48, 0.24)
addTouchTarget(upgradeButton, Vector2.new(460, 140))
upgradeButton.BackgroundColor3 = UiStyle.ACCENT_COLOR
upgradeButton.BorderSizePixel = 0
upgradeButton.Text = ""
upgradeButton.AutoButtonColor = true
addCorner(upgradeButton)
upgradeButton.Parent = dialog

local upgradeName = makeLabel("NameLabel", UiStyle.formatTitle("Level 2"), UiStyle.TITLE_FONT, UiStyle.ACCENT_STROKE_COLOR, 34)
upgradeName.Position = UDim2.fromScale(0, 0.08)
upgradeName.Size = UDim2.fromScale(1, 0.46)
upgradeName.Parent = upgradeButton

local upgradePrice = Instance.new("Frame")
upgradePrice.Name = "PriceRow"
upgradePrice.AnchorPoint = Vector2.new(0.5, 1)
upgradePrice.Position = UDim2.fromScale(0.5, 0.92)
upgradePrice.Size = UDim2.fromScale(0.6, 0.36)
upgradePrice.BackgroundTransparency = 1
local upgradePriceLayout = Instance.new("UIListLayout")
upgradePriceLayout.FillDirection = Enum.FillDirection.Horizontal
upgradePriceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
upgradePriceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
upgradePriceLayout.Padding = UDim.new(0.04, 0)
upgradePriceLayout.SortOrder = Enum.SortOrder.LayoutOrder
upgradePriceLayout.Parent = upgradePrice
local upgradeIcon = Instance.new("ImageLabel")
upgradeIcon.Name = "ResourceIcon"
upgradeIcon.LayoutOrder = 1
upgradeIcon.Size = UDim2.fromScale(0.3, 0.9)
addAspect(upgradeIcon, 1)
upgradeIcon.BackgroundTransparency = 1
upgradeIcon.ScaleType = Enum.ScaleType.Fit
upgradeIcon.Parent = upgradePrice
local upgradePriceLabel = makeLabel("Price", "15", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.BODY_TEXT_MAX_PX)
upgradePriceLabel.LayoutOrder = 2
upgradePriceLabel.Size = UDim2.fromScale(0.4, 1)
upgradePriceLabel.TextXAlignment = Enum.TextXAlignment.Left
upgradePriceLabel.Parent = upgradePrice
upgradePrice.Parent = upgradeButton

local pips = Instance.new("Frame")
pips.Name = "Pips"
pips.Position = UDim2.fromScale(0.52, 0.27)
pips.Size = UDim2.fromScale(0.48, 0.09)
pips.BackgroundTransparency = 1
pips.Parent = dialog
local pipLayout = Instance.new("UIListLayout")
pipLayout.FillDirection = Enum.FillDirection.Horizontal
pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pipLayout.Padding = UDim.new(0.05, 0)
pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
pipLayout.Parent = pips
for index = 1, PIP_COUNT do
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. index
	pip.LayoutOrder = index
	pip.Size = UDim2.fromScale(0.16, 1)
	addAspect(pip, 1)
	pip.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	pip.BorderSizePixel = 0
	addCorner(pip, UDim.new(1, 0))
	local pipStroke = Instance.new("UIStroke")
	pipStroke.Thickness = UiStyle.STROKE_PX
	pipStroke.Color = UiStyle.ACCENT_STROKE_COLOR
	pipStroke.Parent = pip
	pip.Parent = pips
end

local upgradeStats = makePanel("UpgradeStats", UDim2.fromScale(0.52, 0.4), UDim2.fromScale(0.48, 0.6))
upgradeStats.Parent = dialog
makeStatRow(upgradeStats, true)

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After TowerMenu gui")
print("build_tower_menu_gui: built StarterGui.TowerMenu")
