-- Rebuilds the lobby "Queue" ScreenGui under StarterGui (GDD "Queue Menu").
-- Run from the Studio command bar (or the MCP execute_luau tool) in the lobby
-- place; it replaces any existing copy. Names must match Constants.QUEUE_*.
-- Ported from the designer's live gui on 2026-10-30: the title, one map line
-- ("<MAP> (<DIFFICULTY>)"), the visibility, the CrewMember panel (a heading
-- over a row of seat slots cloned by ClientPartyMenuManager from the hidden
-- FilledTemplate and EmptyTemplate), and the Buttons frame holding the
-- countdown, Launch (host only), and Exit. Fonts and colours come from
-- Shared/UiStyle.
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
-- the designer's sliced plate behind the two buttons
local BUTTON_PLATE_IMAGE = "rbxassetid://99484338119365"
local LAUNCH_PLATE_COLOR = UiStyle.POSITIVE_COLOR
local EXIT_PLATE_COLOR = Color3.fromRGB(68, 68, 68)
local LAUNCH_TEXT_COLOR = Color3.fromRGB(60, 35, 10)
local CREW_PANEL_COLOR = Color3.fromRGB(68, 68, 68)

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

-- a button is a transparent TextButton over the designer's plate picture,
-- its words on a TextLabel so the plate's tint and the text stay separate
local function makeButton(name, text, plateColor, textColor, isPlateOpaque)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = plateColor
	button.BackgroundTransparency = if isPlateOpaque then 0 else 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	button.Size = UDim2.fromScale(0.8, 0.3)
	addTextSizeBounds(button, UiStyle.BODY_TEXT_MIN_PX, 34)
	addTouchTarget(button, Vector2.new(400, 90))
	addCorner(button)
	local plate = Instance.new("ImageLabel")
	plate.Name = "Background"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundTransparency = 1
	plate.Image = BUTTON_PLATE_IMAGE
	plate.ImageColor3 = plateColor
	plate.ScaleType = Enum.ScaleType.Slice
	plate.Parent = button
	local label = makeLabel("TextLabel", UiStyle.formatTitle(text), UiStyle.TITLE_FONT, textColor, UiStyle.BODY_TEXT_MIN_PX, 34)
	label.Size = UDim2.fromScale(1, 1)
	label.TextTruncate = Enum.TextTruncate.None
	label.Parent = button
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
dialog.Size = UDim2.fromScale(0.45, 0.95)
addAspect(dialog, 0.81)
addMaxSize(dialog, Vector2.new(560, 700))
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

local dialogPadding = Instance.new("UIPadding")
dialogPadding.PaddingTop = UDim.new(0.02, 0)
dialogPadding.PaddingBottom = UDim.new(0.02, 0)
dialogPadding.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Your Party"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 48)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0)
title.Size = UDim2.fromScale(0.8, 0.1)
title.LayoutOrder = 1
title.Parent = dialog

local mapLabel = makeLabel(Constants.QUEUE_MAP_LABEL, "", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 36)
mapLabel.AnchorPoint = Vector2.new(0.5, 0)
mapLabel.Position = UDim2.fromScale(0.5, 0.08)
mapLabel.Size = UDim2.fromScale(0.9, 0.1)
mapLabel.LayoutOrder = 2
mapLabel.Parent = dialog

local visibilityLabel = makeLabel(Constants.QUEUE_VISIBILITY_LABEL, "", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 26)
visibilityLabel.AnchorPoint = Vector2.new(0.5, 0)
visibilityLabel.Position = UDim2.fromScale(0.5, 0.16)
visibilityLabel.Size = UDim2.fromScale(0.8, 0.07)
visibilityLabel.LayoutOrder = 5
visibilityLabel.Parent = dialog

-- the crew panel: a heading over the seat row; the two templates stay
-- hidden and are cloned per seat by the client
local crew = Instance.new("Frame")
crew.Name = Constants.QUEUE_CREW_FRAME
crew.Position = UDim2.fromScale(0, 0.26)
crew.Size = UDim2.fromScale(1, 0.43)
crew.BackgroundColor3 = CREW_PANEL_COLOR
crew.BorderSizePixel = 0
crew.Parent = dialog

local crewLabel = makeLabel("TextLabel", UiStyle.formatTitle("Crew (1/5)"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 34)
crewLabel.Position = UDim2.fromScale(0, 0.03)
crewLabel.Size = UDim2.fromScale(1, 0.15)
crewLabel.TextTruncate = Enum.TextTruncate.None
crewLabel.Parent = crew

local crewSlots = Instance.new("Frame")
crewSlots.Name = Constants.QUEUE_CREW_SLOTS
crewSlots.AnchorPoint = Vector2.new(0.5, 1)
crewSlots.Position = UDim2.fromScale(0.5, 0.95)
crewSlots.Size = UDim2.fromScale(0.9, 0.7)
crewSlots.BackgroundTransparency = 1
crewSlots.Parent = crew
addAspect(crewSlots, 2.41)
local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
slotLayout.Padding = UDim.new(0.03, 0)
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.Parent = crewSlots

-- a seat: a round head shot (black for an empty seat) with, for a member,
-- the display name under it; the client sets the width by the party's size
local function makeSlotTemplate(name, thumbnailColor, hasName)
	local slot = Instance.new("Frame")
	slot.Name = name
	slot.Size = UDim2.fromScale(0.48, 1)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.Visible = false
	addAspect(slot, 0.67)
	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Name = Constants.QUEUE_CREW_THUMBNAIL
	thumbnail.Size = UDim2.fromScale(1, 1)
	thumbnail.BackgroundColor3 = thumbnailColor
	thumbnail.Image = ""
	thumbnail.Parent = slot
	addCorner(thumbnail, UDim.new(1, 0))
	addAspect(thumbnail, 1)
	if hasName then
		local shadow = Instance.new("UIShadow")
		shadow.Color = Color3.new(0, 0, 0)
		shadow.Transparency = 0.5
		shadow.Parent = thumbnail
		local displayName = makeLabel(Constants.QUEUE_CREW_DISPLAY_NAME, "", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
		displayName.AnchorPoint = Vector2.new(0.5, 0)
		displayName.Position = UDim2.fromScale(0.5, 0.7)
		displayName.Size = UDim2.fromScale(1, 0.2)
		displayName.TextTruncate = Enum.TextTruncate.None
		displayName.Parent = slot
	end
	slot.Parent = crewSlots
end
makeSlotTemplate(Constants.QUEUE_CREW_FILLED_TEMPLATE, Color3.new(1, 1, 1), true)
makeSlotTemplate(Constants.QUEUE_CREW_EMPTY_TEMPLATE, Color3.new(0, 0, 0), false)

-- the countdown and the two buttons, stacked from the dialog's foot
local buttons = Instance.new("Frame")
buttons.Name = Constants.QUEUE_BUTTONS_FRAME
buttons.Position = UDim2.fromScale(0, 0.7)
buttons.Size = UDim2.fromScale(1, 0.3)
buttons.BackgroundTransparency = 1
buttons.Parent = dialog
local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Vertical
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
buttonLayout.Padding = UDim.new(0.05, 0)
buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
buttonLayout.Parent = buttons

local countdown = makeLabel(Constants.QUEUE_COUNTDOWN_LABEL, "Departing in 20 seconds", UiStyle.BODY_BOLD_FONT, UiStyle.POSITIVE_COLOR, UiStyle.BODY_TEXT_MIN_PX, 26)
countdown.LayoutOrder = 1
countdown.Size = UDim2.fromScale(1, 0.2)
countdown.Parent = buttons

local launch = makeButton(Constants.QUEUE_LAUNCH_BUTTON, "Launch", LAUNCH_PLATE_COLOR, LAUNCH_TEXT_COLOR, false)
launch.LayoutOrder = 2
launch.Visible = false
launch.Parent = buttons

local exit = makeButton(Constants.QUEUE_EXIT_BUTTON, "Exit", EXIT_PLATE_COLOR, UiStyle.TEXT_COLOR, true)
exit.LayoutOrder = 3
exit.Parent = buttons

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("Queue gui")
return "Queue gui built"
