-- Rebuilds the lobby "CreateParty" ScreenGui under StarterGui (GDD "Create
-- Party Menu"). Run from the Studio command bar (or the MCP execute_luau tool)
-- in the lobby place; it replaces any existing copy. Names must match
-- Constants.CREATE_PARTY_* / CAROUSEL_* / STEPPER_* / TOGGLE_*. Layout follows
-- the GUI standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
-- ClientPartyMenuManager fills every label and wires every button.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before CreateParty gui")

local existing = StarterGui:FindFirstChild(Constants.CREATE_PARTY_GUI_NAME)
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

local function makeButton(name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = UiStyle.ACCENT_COLOR
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(text)
	button.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, UiStyle.BODY_TEXT_MIN_PX, 34)
	addCorner(button)
	return button
end

-- a square arrow button; the 44px minimum is the touch target rule
local function makeArrowButton(name, text)
	local button = makeButton(name, text)
	button.BackgroundColor3 = UiStyle.PANEL_COLOR
	button.TextColor3 = UiStyle.ACCENT_COLOR
	addAspect(button, 1)
	addSizeBounds(button, Vector2.new(44, 44), Vector2.new(90, 90))
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.CREATE_PARTY_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the dialog hugs the left so the host still sees their helicopter on the right
local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(0, 0.5)
dialog.Position = UDim2.fromScale(0.04, 0.5)
dialog.Size = UDim2.fromScale(0.36, 0.9)
addAspect(dialog, 0.68)
addSizeBounds(dialog, Vector2.new(250, 360), Vector2.new(620, 900))
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
rows.Padding = UDim.new(0.01, 0)
rows.SortOrder = Enum.SortOrder.LayoutOrder
rows.Parent = dialog

-- row heights plus the seven gaps sum to 0.94 inside the dialog padding
local title = makeLabel("Title", UiStyle.formatTitle("Create Party"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 48)
title.LayoutOrder = 1
title.Size = UDim2.fromScale(1, 0.07)
title.Parent = dialog

-- a carousel row: arrows either side of a picture (or name) with the lock
-- state and requirement text under it
local function makeCarousel(name, order, heightScale, hasThumbnail)
	local carousel = Instance.new("Frame")
	carousel.Name = name
	carousel.LayoutOrder = order
	carousel.Size = UDim2.fromScale(1, heightScale)
	carousel.BackgroundTransparency = 1
	carousel.Parent = dialog

	local previous = makeArrowButton(Constants.CAROUSEL_PREVIOUS_BUTTON, "<")
	previous.AnchorPoint = Vector2.new(0, 0.5)
	previous.Position = UDim2.fromScale(0, 0.4)
	previous.Size = UDim2.fromScale(0.14, 0.3)
	previous.Parent = carousel

	local nextButton = makeArrowButton(Constants.CAROUSEL_NEXT_BUTTON, ">")
	nextButton.AnchorPoint = Vector2.new(1, 0.5)
	nextButton.Position = UDim2.fromScale(1, 0.4)
	nextButton.Size = UDim2.fromScale(0.14, 0.3)
	nextButton.Parent = carousel

	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Name = Constants.CAROUSEL_THUMBNAIL
	thumbnail.AnchorPoint = Vector2.new(0.5, 0)
	thumbnail.Position = UDim2.fromScale(0.5, 0)
	thumbnail.Size = UDim2.fromScale(0.68, 0.78)
	thumbnail.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	thumbnail.BorderSizePixel = 0
	thumbnail.Image = ""
	thumbnail.ScaleType = Enum.ScaleType.Crop
	thumbnail.Parent = carousel
	addCorner(thumbnail)
	if hasThumbnail then
		addAspect(thumbnail, 1.6)
	end

	local nameLabel = makeLabel(Constants.CAROUSEL_NAME_LABEL, "", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 36)
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.fromScale(0.5, 0.96)
	nameLabel.Size = UDim2.fromScale(0.9, if hasThumbnail then 0.3 else 0.8)
	nameLabel.Parent = thumbnail
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = UiStyle.STROKE_PX
	nameStroke.Color = UiStyle.BACKGROUND_COLOR
	nameStroke.Parent = nameLabel

	local lockIcon = makeLabel(Constants.CAROUSEL_LOCK_ICON, "🔒", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 48)
	lockIcon.AnchorPoint = Vector2.new(0.5, 0)
	lockIcon.Position = UDim2.fromScale(0.5, 0.06)
	lockIcon.Size = UDim2.fromScale(0.3, 0.4)
	lockIcon.Visible = false
	lockIcon.Parent = thumbnail

	local requirement = makeLabel(Constants.CAROUSEL_REQUIREMENT_LABEL, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
	requirement.AnchorPoint = Vector2.new(0.5, 1)
	requirement.Position = UDim2.fromScale(0.5, 1)
	requirement.Size = UDim2.fromScale(1, 0.18)
	requirement.Parent = carousel
	return carousel
end

makeCarousel(Constants.CREATE_PARTY_MAP_CAROUSEL, 2, 0.27, true)
makeCarousel(Constants.CREATE_PARTY_DIFFICULTY_CAROUSEL, 3, 0.15, false)

-- players stepper: label, minus, value, plus
local stepper = Instance.new("Frame")
stepper.Name = Constants.CREATE_PARTY_PLAYERS_STEPPER
stepper.LayoutOrder = 4
stepper.Size = UDim2.fromScale(1, 0.09)
stepper.BackgroundTransparency = 1
stepper.Parent = dialog

local stepperLabel = makeLabel("Label", "Players", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
stepperLabel.AnchorPoint = Vector2.new(0, 0.5)
stepperLabel.Position = UDim2.fromScale(0, 0.5)
stepperLabel.Size = UDim2.fromScale(0.4, 0.8)
stepperLabel.TextXAlignment = Enum.TextXAlignment.Left
stepperLabel.Parent = stepper

local minus = makeArrowButton(Constants.STEPPER_MINUS_BUTTON, "-")
minus.AnchorPoint = Vector2.new(1, 0.5)
minus.Position = UDim2.fromScale(0.62, 0.5)
minus.Size = UDim2.fromScale(0.14, 1)
minus.Parent = stepper

local value = makeLabel(Constants.STEPPER_VALUE_LABEL, "4", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 36)
value.AnchorPoint = Vector2.new(0.5, 0.5)
value.Position = UDim2.fromScale(0.74, 0.5)
value.Size = UDim2.fromScale(0.2, 1)
value.Parent = stepper

local plus = makeArrowButton(Constants.STEPPER_PLUS_BUTTON, "+")
plus.AnchorPoint = Vector2.new(0, 0.5)
plus.Position = UDim2.fromScale(0.86, 0.5)
plus.Size = UDim2.fromScale(0.14, 1)
plus.Parent = stepper

-- visibility toggle: one button whose state label reads Off / On
local toggle = Instance.new("TextButton")
toggle.Name = Constants.CREATE_PARTY_FRIENDS_ONLY_TOGGLE
toggle.LayoutOrder = 5
toggle.Size = UDim2.fromScale(1, 0.08)
toggle.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
toggle.BorderSizePixel = 0
toggle.Text = ""
toggle.AutoButtonColor = true
toggle.Parent = dialog
addCorner(toggle)

local toggleLabel = makeLabel("Label", "Friends Only", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
toggleLabel.AnchorPoint = Vector2.new(0, 0.5)
toggleLabel.Position = UDim2.fromScale(0.04, 0.5)
toggleLabel.Size = UDim2.fromScale(0.6, 0.7)
toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
toggleLabel.Parent = toggle

local toggleState = makeLabel(Constants.TOGGLE_STATE_LABEL, UiStyle.formatTitle("Off"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
toggleState.AnchorPoint = Vector2.new(1, 0.5)
toggleState.Position = UDim2.fromScale(0.96, 0.5)
toggleState.Size = UDim2.fromScale(0.3, 0.7)
toggleState.TextXAlignment = Enum.TextXAlignment.Right
toggleState.Parent = toggle

local countdown = makeLabel(Constants.CREATE_PARTY_COUNTDOWN_LABEL, "Cancelling in 30 seconds", UiStyle.BODY_FONT, UiStyle.NEGATIVE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
countdown.LayoutOrder = 6
countdown.Size = UDim2.fromScale(1, 0.05)
countdown.Parent = dialog

local create = makeButton(Constants.CREATE_PARTY_CREATE_BUTTON, "Create")
create.LayoutOrder = 7
create.Size = UDim2.fromScale(0.7, 0.09)
addSizeBounds(create, Vector2.new(140, 44), Vector2.new(400, 90))
create.Parent = dialog

-- GDD: Cancel behaves exactly like the creation timeout
local cancel = makeButton(Constants.CREATE_PARTY_CANCEL_BUTTON, "Cancel")
cancel.LayoutOrder = 8
cancel.Size = UDim2.fromScale(0.7, 0.07)
addSizeBounds(cancel, Vector2.new(140, 44), Vector2.new(400, 80))
cancel.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
cancel.TextColor3 = UiStyle.TEXT_COLOR
cancel.Parent = dialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("CreateParty gui")
return "CreateParty gui built"
