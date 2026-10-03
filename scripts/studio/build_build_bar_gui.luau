-- Rebuilds Build Mode's two ScreenGuis under StarterGui (GDD "Defense
-- Table"), shown by ClientDefenseTableManager while the player is at the
-- Defense Table looking down on the Defensive Zone:
--   "BuildSurface": one invisible full-screen Modal button under every
--     HUD. Modal frees the first-person mouse; the button hears every tap
--     and drag that lands on the world rather than on a HUD element.
--   "BuildBar": the scrolling row of Tower and Trap entries along the
--     bottom (the name above a square slot with the item's picture and a
--     Tower or Trap badge, the Iron price under it), the Exit button, the
--     Tower counter, a hint line, and two panels the client floats beside
--     what they act on: PlacePanel beside the ghost (Place with the price,
--     green while the ghost can stand there and red while it cannot;
--     Rotate, a picture button; Cancel, red) and SellPanel beside one of
--     the player's Traps (Move, Sell with the Iron returned, Close). The
--     client sets each panel's Position and AnchorPoint so it sits to the
--     right of what it acts on, or to the left near the screen's edge
--     (2026-10-02).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copies. Names must match
-- Constants.BUILD_SURFACE_* and Constants.BUILD_BAR_*. Layout follows the
-- GUI standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before BuildBar gui")

for _, name in { "BuildBar", "BuildSurface" } do
	local existing = StarterGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addStroke(parent, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = color
	-- on a button the stroke belongs to the box, not its text
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
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

local function addAspect(frame, ratio, dominantAxis)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	if dominantAxis then
		aspect.DominantAxis = dominantAxis
	end
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

-- an icon and a number side by side, centred: an Iron price. The icon
-- keeps square through the aspect constraint
local function makePriceRow(name)
	local row = Instance.new("Frame")
	row.Name = name
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

-- the surface: under every HUD (theirs are DisplayOrder 0), over the whole
-- screen including the notch and the top bar
local surfaceGui = Instance.new("ScreenGui")
surfaceGui.Name = "BuildSurface"
surfaceGui.ResetOnSpawn = false
surfaceGui.DisplayOrder = -1
surfaceGui.IgnoreGuiInset = true
surfaceGui.ScreenInsets = Enum.ScreenInsets.None
surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
surfaceGui.Enabled = false

local surface = Instance.new("TextButton")
surface.Name = "Surface"
surface.Size = UDim2.fromScale(1, 1)
surface.BackgroundTransparency = 1
surface.BorderSizePixel = 0
surface.Text = ""
surface.AutoButtonColor = false
-- frees the mouse that first person locks to the centre
surface.Modal = true
surface.Parent = surfaceGui
surfaceGui.Parent = StarterGui

local gui = Instance.new("ScreenGui")
gui.Name = "BuildBar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the entries take the tool bar's spot (its row ends at 0.97) and scroll
-- sideways when there are more than fit
local entries = Instance.new("ScrollingFrame")
entries.Name = "Entries"
entries.AnchorPoint = Vector2.new(0.5, 1)
entries.Position = UDim2.fromScale(0.5, 0.97)
entries.Size = UDim2.fromScale(0.62, 0.24)
addMaxSize(entries, Vector2.new(1100, 255))
entries.BackgroundTransparency = 1
entries.BorderSizePixel = 0
entries.ScrollingDirection = Enum.ScrollingDirection.X
entries.AutomaticCanvasSize = Enum.AutomaticSize.X
entries.CanvasSize = UDim2.fromScale(0, 0)
entries.ScrollBarThickness = 4
entries.ScrollBarImageColor3 = UiStyle.ACCENT_COLOR
entries.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
entries.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 14)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = entries

-- room for the names, which are wider than their slots, at both ends
local entriesPadding = Instance.new("UIPadding")
entriesPadding.PaddingLeft = UDim.new(0, 18)
entriesPadding.PaddingRight = UDim.new(0, 18)
entriesPadding.Parent = entries

-- one entry, styled like a tool bar slot: the name above, the square slot
-- in the middle (the item's picture, the kind badge top-left, the number
-- key top-right), and the Iron price under it. Its width follows its
-- height, so the row's height alone sizes every entry
local template = Instance.new("TextButton")
template.Name = "EntryTemplate"
template.Size = UDim2.fromScale(0.62, 0.92)
addAspect(template, 0.62, Enum.DominantAxis.Height)
template.BackgroundTransparency = 1
template.Text = ""
template.AutoButtonColor = false
template.Visible = false
template.Parent = entries

local nameLabel = makeLabel("NameLabel", UiStyle.formatTitle("Sentry Gun"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, UiStyle.LABEL_TEXT_MAX_PX)
nameLabel.AnchorPoint = Vector2.new(0.5, 0)
nameLabel.Position = UDim2.fromScale(0.5, 0)
nameLabel.Size = UDim2.fromScale(1.25, 0.16)
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

local priceRow = makePriceRow("PriceRow")
priceRow.AnchorPoint = Vector2.new(0.5, 1)
priceRow.Position = UDim2.fromScale(0.5, 1)
priceRow.Size = UDim2.fromScale(1.25, 0.18)
priceRow.Parent = template

-- always up in Build Mode, bottom right
local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.AnchorPoint = Vector2.new(1, 1)
exitButton.Position = UDim2.fromScale(0.98, 0.97)
exitButton.Size = UDim2.fromScale(0.12, 0.08)
addTouchTarget(exitButton, Vector2.new(180, 72))
exitButton.BackgroundColor3 = UiStyle.NEGATIVE_COLOR
exitButton.BorderSizePixel = 0
exitButton.Text = UiStyle.formatTitle("Exit")
exitButton.TextColor3 = UiStyle.TEXT_COLOR
exitButton.TextScaled = true
exitButton.FontFace = UiStyle.TITLE_FONT
exitButton.AutoButtonColor = true
addTextSizeBounds(exitButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
addCorner(exitButton)
addStroke(exitButton, UiStyle.ACCENT_STROKE_COLOR)
local exitPadding = Instance.new("UIPadding")
exitPadding.PaddingTop = UDim.new(0.18, 0)
exitPadding.PaddingBottom = UDim.new(0.18, 0)
exitPadding.Parent = exitButton
exitButton.Parent = gui

-- the Tower counter, bottom left (the thumbstick is hidden in Build
-- Mode): a Tower icon and "2 / 5"
local towerCount = Instance.new("Frame")
towerCount.Name = "TowerCount"
towerCount.AnchorPoint = Vector2.new(0, 1)
towerCount.Position = UDim2.fromScale(0.02, 0.97)
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

-- a square button in a panel's row: the dismiss X, or a picture
local function makeSquareButton(name, layoutOrder, widthShare, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.fromScale(widthShare, 1)
	addAspect(button, 1, Enum.DominantAxis.Height)
	addTouchTarget(button, Vector2.new(72, 72))
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	addCorner(button)
	addStroke(button, UiStyle.ACCENT_STROKE_COLOR)
	return button
end

-- a panel the client floats beside what it acts on: a wide action button
-- (a word, then the Iron icon and a number) and a square dismiss button,
-- red like Exit. The client sets its Position and AnchorPoint
local function makeActionPanel(panelName, actionName, actionText, actionColor, textColor, dismissName)
	local panel = Instance.new("Frame")
	panel.Name = panelName
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.22, 0.075)
	addMaxSize(panel, Vector2.new(330, 72))
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.ZIndex = 3

	local panelLayout = Instance.new("UIListLayout")
	panelLayout.FillDirection = Enum.FillDirection.Horizontal
	panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	panelLayout.Padding = UDim.new(0.03, 0)
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Parent = panel

	local action = Instance.new("TextButton")
	action.Name = actionName
	action.LayoutOrder = 1
	action.Size = UDim2.fromScale(0.72, 1)
	addTouchTarget(action, Vector2.new(240, 72))
	action.BackgroundColor3 = actionColor
	action.BorderSizePixel = 0
	action.Text = ""
	action.AutoButtonColor = true
	addCorner(action)
	addStroke(action, UiStyle.ACCENT_STROKE_COLOR)
	action.Parent = panel

	local text = makeLabel("Text", UiStyle.formatTitle(actionText), UiStyle.TITLE_FONT, textColor, UiStyle.BODY_TEXT_MAX_PX)
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.fromScale(0.08, 0.5)
	text.Size = UDim2.fromScale(0.44, 0.62)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text:FindFirstChildOfClass("UIStroke"):Destroy()
	text.Parent = action

	local price = makePriceRow("PriceRow")
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.fromScale(0.95, 0.5)
	price.Size = UDim2.fromScale(0.42, 0.62)
	local priceLabel = price:FindFirstChild("Price")
	priceLabel.TextColor3 = textColor
	priceLabel:FindFirstChildOfClass("UIStroke"):Destroy()
	price.Parent = action

	local dismiss = makeSquareButton(dismissName, 3, 0.2, UiStyle.NEGATIVE_COLOR)
	dismiss.Text = "X"
	dismiss.TextColor3 = UiStyle.TEXT_COLOR
	dismiss.TextScaled = true
	dismiss.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(dismiss, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
	local dismissPadding = Instance.new("UIPadding")
	dismissPadding.PaddingTop = UDim.new(0.2, 0)
	dismissPadding.PaddingBottom = UDim.new(0.2, 0)
	dismissPadding.Parent = dismiss
	dismiss.Parent = panel

	panel.Parent = gui
	return panel
end

-- the Place panel: Place (the client colours it green or red by whether
-- the ghost can stand), Rotate (a picture button between Place and
-- Cancel), Cancel. The panel is wider for the third button
local placePanel = makeActionPanel("PlacePanel", "PlaceButton", "Place", UiStyle.POSITIVE_COLOR, UiStyle.TEXT_COLOR, "CancelButton")
placePanel.Size = UDim2.fromScale(0.28, 0.075)
placePanel:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(420, 72)
placePanel.PlaceButton.Size = UDim2.fromScale(0.58, 1)
placePanel.CancelButton.Size = UDim2.fromScale(0.16, 1)
local rotateButton = makeSquareButton("RotateButton", 2, 0.16, UiStyle.PANEL_COLOR)
local rotateIcon = Instance.new("ImageLabel")
rotateIcon.Name = "Icon"
rotateIcon.AnchorPoint = Vector2.new(0.5, 0.5)
rotateIcon.Position = UDim2.fromScale(0.5, 0.5)
rotateIcon.Size = UDim2.fromScale(0.7, 0.7)
rotateIcon.BackgroundTransparency = 1
rotateIcon.Image = Icons.UI.ROTATE
rotateIcon.ImageColor3 = UiStyle.TEXT_COLOR
rotateIcon.ScaleType = Enum.ScaleType.Fit
rotateIcon.Parent = rotateButton
rotateButton.Parent = placePanel

local sellPanel = makeActionPanel("SellPanel", "SellButton", "Sell", UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, "CloseButton")

-- the Sell panel also offers Move, first in the row: the panel is wider
-- and the three buttons share it
sellPanel.Size = UDim2.fromScale(0.32, 0.075)
sellPanel:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(480, 72)
sellPanel.SellButton.Size = UDim2.fromScale(0.48, 1)
sellPanel.CloseButton.Size = UDim2.fromScale(0.14, 1)
local moveButton = Instance.new("TextButton")
moveButton.Name = "MoveButton"
moveButton.LayoutOrder = 0
moveButton.Size = UDim2.fromScale(0.3, 1)
addTouchTarget(moveButton, Vector2.new(150, 72))
moveButton.BackgroundColor3 = UiStyle.ACCENT_COLOR
moveButton.BorderSizePixel = 0
moveButton.Text = UiStyle.formatTitle("Move")
moveButton.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
moveButton.TextScaled = true
moveButton.FontFace = UiStyle.TITLE_FONT
moveButton.AutoButtonColor = true
addTextSizeBounds(moveButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
addCorner(moveButton)
addStroke(moveButton, UiStyle.ACCENT_STROKE_COLOR)
local movePadding = Instance.new("UIPadding")
movePadding.PaddingTop = UDim.new(0.2, 0)
movePadding.PaddingBottom = UDim.new(0.2, 0)
movePadding.Parent = moveButton
moveButton.Parent = sellPanel

-- the hint, under the day clock and the compass
local hint = makeLabel("Hint", UiStyle.formatTitle("Select a defense to place"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 32)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.fromScale(0.5, 0.14)
hint.Size = UDim2.fromScale(0.6, 0.045)
local hintStroke = hint:FindFirstChildOfClass("UIStroke")
hintStroke.Thickness = UiStyle.STROKE_PX
hint.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After BuildBar gui")
print("build_build_bar_gui: built StarterGui.BuildBar and StarterGui.BuildSurface")
