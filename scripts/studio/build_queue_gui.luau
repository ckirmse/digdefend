-- Rebuilds the lobby "Queue" ScreenGui under StarterGui (GDD "Queue Menu").
-- Run from the Studio command bar (or the MCP execute_luau tool) in the lobby
-- place; it replaces any existing copy. Names must match Constants.QUEUE_*.
-- Layout follows the GUI standard in CLAUDE.md; fonts and colours come from
-- Shared/UiStyle. ClientPartyMenuManager fills the labels and wires buttons;
-- the Launch button is shown only to the host.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before Queue gui")

local existing = StarterGui:FindFirstChild(Constants.QUEUE_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5

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

local function addSizeBounds(frame, minSize, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = minSize
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addAspect(frame, ratio)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = frame
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

local function makeButton(name, text, backgroundColor, textColor)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = backgroundColor
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(text)
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, UiStyle.BODY_TEXT_MIN_PX, 34)
	addSizeBounds(button, Vector2.new(140, 44), Vector2.new(400, 90))
	addCorner(button)
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.QUEUE_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the dialog hugs the left so members still see the helicopter on the right
local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(0, 0.5)
dialog.Position = UDim2.fromScale(0.04, 0.5)
dialog.Size = UDim2.fromScale(0.32, 0.7)
addAspect(dialog, 0.8)
addSizeBounds(dialog, Vector2.new(240, 300), Vector2.new(560, 700))
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)
local dialogStroke = Instance.new("UIStroke")
dialogStroke.Thickness = UiStyle.STROKE_PX
dialogStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dialogStroke.Parent = dialog

local dialogPadding = Instance.new("UIPadding")
dialogPadding.PaddingLeft = UDim.new(0.06, 0)
dialogPadding.PaddingRight = UDim.new(0.06, 0)
dialogPadding.PaddingTop = UDim.new(0.03, 0)
dialogPadding.PaddingBottom = UDim.new(0.03, 0)
dialogPadding.Parent = dialog

local rows = Instance.new("UIListLayout")
rows.FillDirection = Enum.FillDirection.Vertical
rows.HorizontalAlignment = Enum.HorizontalAlignment.Center
rows.VerticalAlignment = Enum.VerticalAlignment.Top
rows.Padding = UDim.new(0.015, 0)
rows.SortOrder = Enum.SortOrder.LayoutOrder
rows.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Party"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 48)
title.LayoutOrder = 1
title.Size = UDim2.fromScale(1, 0.12)
title.Parent = dialog

local mapLabel = makeLabel(Constants.QUEUE_MAP_LABEL, "", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 36)
mapLabel.LayoutOrder = 2
mapLabel.Size = UDim2.fromScale(1, 0.1)
mapLabel.Parent = dialog

local infoRows = {
	{ name = Constants.QUEUE_DIFFICULTY_LABEL, order = 3 },
	{ name = Constants.QUEUE_PLAYERS_LABEL, order = 4 },
	{ name = Constants.QUEUE_VISIBILITY_LABEL, order = 5 },
	{ name = Constants.QUEUE_HOST_LABEL, order = 6 },
}
for _, entry in infoRows do
	local label = makeLabel(entry.name, "", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
	label.LayoutOrder = entry.order
	label.Size = UDim2.fromScale(1, 0.07)
	label.Parent = dialog
end

local countdown = makeLabel(Constants.QUEUE_COUNTDOWN_LABEL, "Departing in 20 seconds", UiStyle.BODY_BOLD_FONT, UiStyle.POSITIVE_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
countdown.LayoutOrder = 7
countdown.Size = UDim2.fromScale(1, 0.08)
countdown.Parent = dialog

local launch = makeButton(Constants.QUEUE_LAUNCH_BUTTON, "Launch", UiStyle.ACCENT_COLOR, UiStyle.ACCENT_STROKE_COLOR)
launch.LayoutOrder = 8
launch.Size = UDim2.fromScale(0.7, 0.12)
launch.Visible = false
launch.Parent = dialog

local exit = makeButton(Constants.QUEUE_EXIT_BUTTON, "Exit", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR)
exit.LayoutOrder = 9
exit.Size = UDim2.fromScale(0.7, 0.12)
exit.Parent = dialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("Queue gui")
return "Queue gui built"
