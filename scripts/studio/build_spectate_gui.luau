-- Rebuilds the "Spectate" ScreenGui under StarterGui (GDD "Spectate
-- Mode", M32): a bar at the bottom centre of the screen, clear of the
-- touch thumbstick and jump button, with a left arrow, a box naming the
-- player being watched under a small "Spectating" caption, and a right
-- arrow; above them, centred, Results (reopens the Results Menu) and
-- Return to Lobby. To the right of the bar, while a revive is on offer,
-- a Revive button with the seconds left counting down above it. It
-- is a HUD element, not a menu, so the camera stays free while it shows.
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy. Names must match
-- Constants.SPECTATE_*. Layout follows the GUI standard in CLAUDE.md;
-- fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before Spectate gui")

local existing = StarterGui:FindFirstChild("Spectate")
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

local function makeArrow(name, text, anchorX)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(anchorX, 1)
	button.Position = UDim2.fromScale(anchorX, 1)
	button.Size = UDim2.fromScale(0.11, 0.56)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = button
	addTouchTarget(button, Vector2.new(64, 64))
	button.BackgroundColor3 = UiStyle.ACCENT_COLOR
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(button, UiStyle.LABEL_TEXT_MIN_PX, 36)
	addCorner(button)
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = "Spectate"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.fromScale(0.5, 0.97)
bar.Size = UDim2.fromScale(0.52, 0.2)
local barAspect = Instance.new("UIAspectRatioConstraint")
barAspect.AspectRatio = 4.9
barAspect.Parent = bar
addMaxSize(bar, Vector2.new(700, 142))
bar.BackgroundTransparency = 1
bar.Parent = gui

local previousButton = makeArrow("PreviousButton", "<", 0)
previousButton.Parent = bar
local nextButton = makeArrow("NextButton", ">", 1)
nextButton.Parent = bar

local nameBox = Instance.new("Frame")
nameBox.Name = "NameBox"
nameBox.AnchorPoint = Vector2.new(0.5, 1)
nameBox.Position = UDim2.fromScale(0.5, 1)
nameBox.Size = UDim2.fromScale(0.74, 0.56)
nameBox.BackgroundColor3 = UiStyle.PANEL_COLOR
nameBox.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
nameBox.BorderSizePixel = 0
nameBox.Parent = bar
addCorner(nameBox)
local nameStroke = Instance.new("UIStroke")
nameStroke.Thickness = UiStyle.STROKE_PX
nameStroke.Color = UiStyle.ACCENT_STROKE_COLOR
nameStroke.Parent = nameBox

local caption = makeLabel("Caption", "Spectating", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
caption.AnchorPoint = Vector2.new(0.5, 0)
caption.Position = UDim2.fromScale(0.5, 0.08)
caption.Size = UDim2.fromScale(0.9, 0.3)
caption.Parent = nameBox

-- found by name anywhere under the bar (Constants.SPECTATE_NAME_LABEL)
local nameLabel = makeLabel("NameLabel", "Player", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
nameLabel.AnchorPoint = Vector2.new(0.5, 1)
nameLabel.Position = UDim2.fromScale(0.5, 0.92)
nameLabel.Size = UDim2.fromScale(0.9, 0.5)
nameLabel.Parent = nameBox

-- the top row: Results and Return to Lobby
local function makeTopButton(name, text, color, textColor, positionX, anchorX)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(anchorX, 0)
	button.Position = UDim2.fromScale(positionX, 0)
	button.Size = UDim2.fromScale(0.32, 0.36)
	addTouchTarget(button, Vector2.new(240, 52))
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(text)
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(button, UiStyle.LABEL_TEXT_MIN_PX, 22)
	addCorner(button)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = button
	button.Parent = bar
	return button
end

-- Results and Return to Lobby, side by side over the middle of the bar
makeTopButton("ResultsButton", "Results", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, 0.49, 1)
makeTopButton("LobbyButton", "Return to Lobby", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, 0.51, 0)

-- the Revive on offer, in a box of its own to the right of the bar:
-- ClientSpectateManager centres it between the bar's right edge and the
-- right edge of the screen, writes its words and price, and counts the
-- seconds left on the timer above it; the whole box is hidden once the
-- revive's time is up
local reviveBox = Instance.new("Frame")
reviveBox.Name = "ReviveBox"
reviveBox.AnchorPoint = Vector2.new(0.5, 1)
reviveBox.Position = UDim2.fromScale(0.88, 0.97)
reviveBox.Size = UDim2.fromScale(0.18, 0.2)
local reviveAspect = Instance.new("UIAspectRatioConstraint")
reviveAspect.AspectRatio = 1.7
reviveAspect.Parent = reviveBox
addMaxSize(reviveBox, Vector2.new(242, 142))
reviveBox.BackgroundTransparency = 1
reviveBox.Visible = false
reviveBox.Parent = gui

local timer = makeLabel("Timer", "60 s", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
timer.AnchorPoint = Vector2.new(0.5, 0)
timer.Position = UDim2.fromScale(0.5, 0.04)
timer.Size = UDim2.fromScale(1, 0.32)
timer.Parent = reviveBox

local reviveButton = Instance.new("TextButton")
reviveButton.Name = "ReviveButton"
reviveButton.AnchorPoint = Vector2.new(0.5, 1)
reviveButton.Position = UDim2.fromScale(0.5, 1)
reviveButton.Size = UDim2.fromScale(1, 0.56)
addTouchTarget(reviveButton, Vector2.new(242, 80))
reviveButton.BackgroundColor3 = UiStyle.POSITIVE_COLOR
reviveButton.BorderSizePixel = 0
reviveButton.Text = UiStyle.formatTitle("Revive")
reviveButton.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
reviveButton.TextScaled = true
reviveButton.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(reviveButton, UiStyle.LABEL_TEXT_MIN_PX, 28)
addCorner(reviveButton)
local revivePadding = Instance.new("UIPadding")
revivePadding.PaddingLeft = UDim.new(0.06, 0)
revivePadding.PaddingRight = UDim.new(0.06, 0)
revivePadding.Parent = reviveButton
reviveButton.Parent = reviveBox

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After Spectate gui")
print("build_spectate_gui: built StarterGui.Spectate")
