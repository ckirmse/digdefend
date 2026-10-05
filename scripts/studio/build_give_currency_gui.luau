-- Rebuilds the "GiveCurrency" ScreenGui under StarterGui (M32): the menu
-- a player opens from the "Give Currency" prompt on another player. One
-- dialog, two pages. SendPage: the receiver's thumbnail, "SEND CURRENCY TO
-- [NAME]", a Gold row and an Iron row (the resource icon, a minus button,
-- the amount as a TextBox that can be typed into, a plus button, and what
-- the sender owns), a Send button, and a close button. ConfirmPage: the
-- thumbnail and name again, the amounts being sent beside their icons, a
-- Confirm button, and a Back button. ClientGiveCurrencyManager fills and
-- switches them. Run from the Studio command bar (or the MCP execute_luau
-- tool) in the gameplay place; it replaces any existing copy. Names must
-- match Constants.GIVE_CURRENCY_*. Layout follows the GUI standard in
-- CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before GiveCurrency gui")

local existing = StarterGui:FindFirstChild("GiveCurrency")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addAspect(parent, ratio)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ratio
	aspect.Parent = parent
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

local function makeTextButton(name, text, color, textColor, maxPx)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(text)
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, UiStyle.LABEL_TEXT_MIN_PX, maxPx)
	addCorner(button)
	return button
end

local function makeIcon(name)
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	addAspect(icon, 1)
	return icon
end

local function makeThumbnail()
	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Name = "Thumbnail"
	thumbnail.AnchorPoint = Vector2.new(0.5, 0)
	thumbnail.Position = UDim2.fromScale(0.5, 0)
	thumbnail.Size = UDim2.fromScale(0.24, 0.24)
	addAspect(thumbnail, 1)
	addMaxSize(thumbnail, Vector2.new(140, 140))
	thumbnail.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	thumbnail.BorderSizePixel = 0
	thumbnail.ScaleType = Enum.ScaleType.Fit
	addCorner(thumbnail, UDim.new(1, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = UiStyle.ACCENT_COLOR
	stroke.Parent = thumbnail
	return thumbnail
end

local function makePage(name, parent)
	local page = Instance.new("Frame")
	page.Name = name
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.Parent = parent
	return page
end

local gui = Instance.new("ScreenGui")
gui.Name = "GiveCurrency"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.5, 0.8)
addAspect(dialog, 0.95)
addMaxSize(dialog, Vector2.new(600, 632))
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
padding.PaddingLeft = UDim.new(0.06, 0)
padding.PaddingRight = UDim.new(0.06, 0)
padding.PaddingTop = UDim.new(0.04, 0)
padding.PaddingBottom = UDim.new(0.04, 0)
padding.Parent = dialog

-- the send page
local sendPage = makePage("SendPage", dialog)
makeThumbnail().Parent = sendPage

local sendTitle = makeLabel("Title", UiStyle.formatTitle("Send currency to Player"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 34)
sendTitle.AnchorPoint = Vector2.new(0.5, 0)
sendTitle.Position = UDim2.fromScale(0.5, 0.26)
sendTitle.Size = UDim2.fromScale(1, 0.1)
sendTitle.Parent = sendPage

local closeButton = makeTextButton("CloseButton", "X", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)
closeButton.Size = UDim2.fromScale(0.1, 0.1)
addAspect(closeButton, 1)
addTouchTarget(closeButton, Vector2.new(56, 56))
closeButton.Parent = sendPage

local function makeAmountRow(name, positionY)
	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, positionY)
	row.Size = UDim2.fromScale(1, 0.18)
	row.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	row.Parent = sendPage
	addCorner(row)
	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0.03, 0)
	rowPadding.PaddingRight = UDim.new(0.03, 0)
	rowPadding.Parent = row

	local icon = makeIcon("Icon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = UDim2.fromScale(0.14, 0.7)
	icon.Parent = row

	local minus = makeTextButton("MinusButton", "-", UiStyle.ACCENT_COLOR, UiStyle.ACCENT_STROKE_COLOR, 40)
	minus.AnchorPoint = Vector2.new(0, 0.5)
	minus.Position = UDim2.fromScale(0.18, 0.5)
	minus.Size = UDim2.fromScale(0.16, 0.7)
	addAspect(minus, 1)
	addTouchTarget(minus, Vector2.new(72, 72))
	minus.Parent = row

	-- a TextBox, so a tap on the number opens the keyboard
	local amount = Instance.new("TextBox")
	amount.Name = "Amount"
	amount.AnchorPoint = Vector2.new(0.5, 0)
	amount.Position = UDim2.fromScale(0.56, 0.08)
	amount.Size = UDim2.fromScale(0.36, 0.56)
	amount.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
	amount.BorderSizePixel = 0
	amount.Text = "0"
	amount.PlaceholderText = "0"
	amount.TextColor3 = UiStyle.TEXT_COLOR
	amount.TextScaled = true
	amount.FontFace = UiStyle.BODY_BOLD_FONT
	amount.ClearTextOnFocus = true
	addTextSizeBounds(amount, UiStyle.BODY_TEXT_MIN_PX, 34)
	addCorner(amount)
	amount.Parent = row

	local owned = makeLabel("Owned", "of 0", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
	owned.AnchorPoint = Vector2.new(0.5, 1)
	owned.Position = UDim2.fromScale(0.56, 0.96)
	owned.Size = UDim2.fromScale(0.36, 0.26)
	owned.Parent = row

	local plus = makeTextButton("PlusButton", "+", UiStyle.ACCENT_COLOR, UiStyle.ACCENT_STROKE_COLOR, 40)
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.fromScale(1, 0.5)
	plus.Size = UDim2.fromScale(0.16, 0.7)
	addAspect(plus, 1)
	addTouchTarget(plus, Vector2.new(72, 72))
	plus.Parent = row
end

makeAmountRow("GoldRow", 0.39)
makeAmountRow("IronRow", 0.6)

local sendButton = makeTextButton("SendButton", "Send", UiStyle.POSITIVE_COLOR, UiStyle.ACCENT_STROKE_COLOR, 30)
sendButton.AnchorPoint = Vector2.new(0.5, 1)
sendButton.Position = UDim2.fromScale(0.5, 1)
sendButton.Size = UDim2.fromScale(0.7, 0.14)
addTouchTarget(sendButton, Vector2.new(400, 80))
sendButton.Parent = sendPage

-- the confirmation page
local confirmPage = makePage("ConfirmPage", dialog)
confirmPage.Visible = false
makeThumbnail().Parent = confirmPage

local confirmTitle = makeLabel("Title", UiStyle.formatTitle("Send this to"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 30)
confirmTitle.AnchorPoint = Vector2.new(0.5, 0)
confirmTitle.Position = UDim2.fromScale(0.5, 0.26)
confirmTitle.Size = UDim2.fromScale(1, 0.08)
confirmTitle.Parent = confirmPage

local confirmName = makeLabel("Name", "Player", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 34)
confirmName.AnchorPoint = Vector2.new(0.5, 0)
confirmName.Position = UDim2.fromScale(0.5, 0.35)
confirmName.Size = UDim2.fromScale(1, 0.09)
confirmName.Parent = confirmPage

local function makeConfirmAmount(name, positionY)
	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, positionY)
	row.Size = UDim2.fromScale(0.6, 0.13)
	row.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	row.Parent = confirmPage
	addCorner(row)

	local icon = makeIcon("Icon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.08, 0.5)
	icon.Size = UDim2.fromScale(0.24, 0.76)
	icon.Parent = row

	local value = makeLabel("Value", "0", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, 34)
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Position = UDim2.fromScale(0.92, 0.5)
	value.Size = UDim2.fromScale(0.56, 0.7)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row
end

makeConfirmAmount("GoldAmount", 0.48)
makeConfirmAmount("IronAmount", 0.63)

local backButton = makeTextButton("BackButton", "Back", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, 28)
backButton.AnchorPoint = Vector2.new(0, 1)
backButton.Position = UDim2.fromScale(0, 1)
backButton.Size = UDim2.fromScale(0.34, 0.14)
addTouchTarget(backButton, Vector2.new(200, 80))
backButton.Parent = confirmPage

local confirmButton = makeTextButton("ConfirmButton", "Confirm", UiStyle.POSITIVE_COLOR, UiStyle.ACCENT_STROKE_COLOR, 30)
confirmButton.AnchorPoint = Vector2.new(1, 1)
confirmButton.Position = UDim2.fromScale(1, 1)
confirmButton.Size = UDim2.fromScale(0.62, 0.14)
addTouchTarget(confirmButton, Vector2.new(360, 80))
confirmButton.Parent = confirmPage

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GiveCurrency gui")
print("build_give_currency_gui: built StarterGui.GiveCurrency")
