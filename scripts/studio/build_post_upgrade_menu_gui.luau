-- Rebuilds the "PostUpgrade" ScreenGui under StarterGui: the menu the
-- owner of a post opens at their bench (GDD "Upgrading a Post Weapon"). A
-- dialog with a title ("UPGRADE MACHINE GUN"), one row per attribute cloned
-- from RowTemplate by ClientPostUpgradeManager (the name, four pips filled
-- one per upgrade bought, an Upgrade button with the Gold Bar icon and the
-- price, and a red "Camp Level N required" line while locked), and a close
-- button. Run from the Studio command bar (or the MCP execute_luau tool) in
-- the gameplay place; it replaces any existing copy. Names must match
-- Constants.POST_UPGRADE_*. Layout follows the GUI standard in CLAUDE.md;
-- fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before PostUpgrade gui")

local existing = StarterGui:FindFirstChild("PostUpgrade")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local PIP_COUNT = 4

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

-- max only: a pixel minimum would override scale on small screens (GUI
-- standard, 2026-09-16); touch targets alone keep a floor, via addTouchTarget
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

local function makeLabel(name, text, font, color, minPx, maxPx)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = font
	label.TextTruncate = Enum.TextTruncate.AtEnd
	addTextSizeBounds(label, minPx, maxPx)
	return label
end

local gui = Instance.new("ScreenGui")
gui.Name = "PostUpgrade"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.6, 0.66)
local dialogAspect = Instance.new("UIAspectRatioConstraint")
dialogAspect.AspectRatio = 1.5
dialogAspect.Parent = dialog
addMaxSize(dialog, Vector2.new(864, 576))
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
padding.PaddingLeft = UDim.new(0.04, 0)
padding.PaddingRight = UDim.new(0.04, 0)
padding.PaddingTop = UDim.new(0.03, 0)
padding.PaddingBottom = UDim.new(0.04, 0)
padding.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Upgrade Machine Gun"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 44)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0)
title.Size = UDim2.fromScale(0.8, 0.14)
title.Parent = dialog

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)
closeButton.Size = UDim2.fromScale(0.08, 0.12)
local closeAspect = Instance.new("UIAspectRatioConstraint")
closeAspect.AspectRatio = 1
closeAspect.Parent = closeButton
addTouchTarget(closeButton, Vector2.new(56, 56))
closeButton.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = UiStyle.TEXT_COLOR
closeButton.TextScaled = true
closeButton.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(closeButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
addCorner(closeButton)
closeButton.Parent = dialog

local list = Instance.new("Frame")
list.Name = "List"
list.AnchorPoint = Vector2.new(0.5, 1)
list.Position = UDim2.fromScale(0.5, 1)
list.Size = UDim2.fromScale(1, 0.8)
list.BackgroundTransparency = 1
list.Parent = dialog

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Padding = UDim.new(0.03, 0)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local row = Instance.new("Frame")
row.Name = "RowTemplate"
row.Size = UDim2.fromScale(1, 0.22)
addMaxSize(row, Vector2.new(816, 100))
row.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
row.BorderSizePixel = 0
row.Visible = false
row.Parent = list
addCorner(row)
local rowPadding = Instance.new("UIPadding")
rowPadding.PaddingLeft = UDim.new(0.02, 0)
rowPadding.PaddingRight = UDim.new(0.02, 0)
rowPadding.Parent = row

local name = makeLabel("Name", UiStyle.formatTitle("Damage"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 26)
name.AnchorPoint = Vector2.new(0, 0.5)
name.Position = UDim2.fromScale(0, 0.5)
name.Size = UDim2.fromScale(0.3, 0.5)
name.TextXAlignment = Enum.TextXAlignment.Left
name.Parent = row

local pips = Instance.new("Frame")
pips.Name = "Pips"
-- the pips sit in the upper half of the row's middle, leaving the lower
-- half for the Camp Level line under them
pips.AnchorPoint = Vector2.new(0, 0.5)
pips.Position = UDim2.fromScale(0.32, 0.32)
pips.Size = UDim2.fromScale(0.36, 0.42)
pips.BackgroundTransparency = 1
pips.Parent = row
local pipLayout = Instance.new("UIListLayout")
pipLayout.FillDirection = Enum.FillDirection.Horizontal
pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pipLayout.Padding = UDim.new(0.04, 0)
pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
pipLayout.Parent = pips
for index = 1, PIP_COUNT do
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. index
	pip.LayoutOrder = index
	pip.Size = UDim2.fromScale(0.2, 1)
	local pipAspect = Instance.new("UIAspectRatioConstraint")
	pipAspect.AspectRatio = 1
	pipAspect.Parent = pip
	pip.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	pip.BorderSizePixel = 0
	addCorner(pip)
	local pipStroke = Instance.new("UIStroke")
	pipStroke.Thickness = UiStyle.STROKE_PX
	pipStroke.Color = UiStyle.ACCENT_STROKE_COLOR
	pipStroke.Parent = pip
	pip.Parent = pips
end

local button = Instance.new("TextButton")
button.Name = "UpgradeButton"
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.fromScale(1, 0.5)
button.Size = UDim2.fromScale(0.28, 0.7)
addTouchTarget(button, Vector2.new(200, 56))
button.BackgroundColor3 = UiStyle.ACCENT_COLOR
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = true
addCorner(button)
button.Parent = row

local resourceIcon = Instance.new("ImageLabel")
resourceIcon.Name = "ResourceIcon"
resourceIcon.AnchorPoint = Vector2.new(0, 0.5)
resourceIcon.Position = UDim2.fromScale(0.08, 0.5)
resourceIcon.Size = UDim2.fromScale(0.2, 0.7)
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.Parent = resourceIcon
resourceIcon.BackgroundTransparency = 1
resourceIcon.ScaleType = Enum.ScaleType.Fit
resourceIcon.Parent = button

local price = makeLabel("Price", "15", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
price.AnchorPoint = Vector2.new(1, 0.5)
price.Position = UDim2.fromScale(0.92, 0.5)
price.Size = UDim2.fromScale(0.6, 0.6)
price.TextXAlignment = Enum.TextXAlignment.Right
price.Parent = button

-- under the pips, red, only while the Camp Level is short
local lock = makeLabel("Lock", UiStyle.formatTitle("Camp Level 2 required"), UiStyle.BODY_BOLD_FONT, UiStyle.NEGATIVE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 22)
lock.AnchorPoint = Vector2.new(0, 0.5)
lock.Position = UDim2.fromScale(0.32, 0.75)
lock.Size = UDim2.fromScale(0.36, 0.3)
lock.TextXAlignment = Enum.TextXAlignment.Left
lock.Visible = false
lock.Parent = row

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After PostUpgrade gui")
print("build_post_upgrade_menu_gui: built StarterGui.PostUpgrade")
