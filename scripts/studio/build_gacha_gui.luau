-- Rebuilds the lobby "Gacha" ScreenGui under StarterGui (GDD "Class
-- Unlock System", M70; the 3D crate opening since 2026-11-03). Run from
-- the Studio command bar (or the MCP execute_luau tool) in the lobby
-- place; it replaces any existing copy. Names must match Constants.GACHA_*.
-- Layout follows the GUI standard in CLAUDE.md; fonts and colours come
-- from Shared/UiStyle.
--
-- The panel sits on the right third of the screen while the camera holds
-- the crate on the left two thirds (CameraMenuOpen): an X close button
-- in the corner as the gameplay upgrade menus have, the title, the odds
-- list over the top two thirds of the panel (the
-- classes to buy outright for a player restricted from paid random
-- items, from ClassRowTemplate), and the green OPEN CRATE button with
-- its Diamonds price. Outside the panel: the TAP CRATE TO OPEN line
-- along the bottom and the prize card that flies out of the crate, with
-- CLAIM. ClientGachaMenuManager clones the row templates and fills every
-- label; the templates themselves stay hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before Gacha gui")

local existing = StarterGui:FindFirstChild(Constants.GACHA_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local PANEL_MAX_SIZE = Vector2.new(520, 900)
-- the prize card is taller than wide
local CARD_ASPECT = 0.72

local function addCorner(parent, radiusPx)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radiusPx or UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

-- max only: a pixel minimum would override scale on small screens (GUI
-- standard, 2026-09-16); menus carry no floor at all (designer, 2026-11-03):
-- a minimum breaks the menu on a small screen, so addTouchTarget caps only
local function addMaxSize(frame, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addTouchTarget(button, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = maxSize
	constraint.Parent = button
end

local function addAspect(frame, ratio)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = frame
end

local function addPadding(frame, scale)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(scale, 0)
	padding.PaddingBottom = UDim.new(scale, 0)
	padding.PaddingLeft = UDim.new(scale, 0)
	padding.PaddingRight = UDim.new(scale, 0)
	padding.Parent = frame
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
	addTextSizeBounds(label, 1, maxPx)
	return label
end

local function makeButton(name, text, color, maxPx)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(text)
	button.TextColor3 = UiStyle.TEXT_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, 1, maxPx)
	addCorner(button)
	return button
end

-- the X in the panel's top-right corner, the gameplay upgrade menus' close
-- button: a square on the designer's panel backing tinted red
local function makeCloseButton(name)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.fromScale(1, 0)
	button.Size = UDim2.fromScale(0.1, 0.1)
	button.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	button.BorderSizePixel = 0
	button.Text = "X"
	button.TextColor3 = UiStyle.TEXT_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, 1, 26)
	addCorner(button)
	addAspect(button, 1)
	addTouchTarget(button, Vector2.new(56, 56))
	local backing = Instance.new("ImageLabel")
	backing.Name = "Background"
	backing.Size = UDim2.fromScale(1, 1)
	backing.BackgroundTransparency = 1
	backing.Image = Icons.UI.PANEL_BACKING
	backing.ImageColor3 = UiStyle.TOGGLE_OFF_COLOR
	backing.ZIndex = 1
	backing.Parent = button
	local x = makeLabel("TextLabel", "X", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
	x.Size = UDim2.fromScale(0.8, 0.8)
	x.ZIndex = 2
	x.Parent = button
	-- the label draws the X; the button's own text would double it
	button.Text = ""
	return button
end

-- a price tab inside a button: the number then the Diamonds icon
local function addPriceTab(button, labelName, widthShare)
	local tab = Instance.new("Frame")
	tab.Name = "PriceFrame"
	tab.AnchorPoint = Vector2.new(1, 0.5)
	tab.Position = UDim2.fromScale(0.96, 0.5)
	tab.Size = UDim2.fromScale(widthShare, 0.7)
	tab.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
	tab.BorderSizePixel = 0
	tab.Parent = button
	addCorner(tab, UiStyle.CORNER_RADIUS_PX // 2)
	local priceLabel = makeLabel(labelName, "100", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
	priceLabel.AnchorPoint = Vector2.new(0, 0.5)
	priceLabel.Position = UDim2.fromScale(0.08, 0.5)
	priceLabel.Size = UDim2.fromScale(0.54, 0.8)
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Parent = tab
	local priceIcon = Instance.new("ImageLabel")
	priceIcon.Name = "PriceIcon"
	priceIcon.AnchorPoint = Vector2.new(1, 0.5)
	priceIcon.Position = UDim2.fromScale(0.94, 0.5)
	priceIcon.Size = UDim2.fromScale(0.3, 0.8)
	addAspect(priceIcon, 1)
	priceIcon.BackgroundTransparency = 1
	priceIcon.Image = Icons.UI.DIAMONDS
	priceIcon.Parent = tab
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.GACHA_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the panel: the right third, a little in from the edge
local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(1, 0.5)
dialog.Position = UDim2.fromScale(0.985, 0.5)
dialog.Size = UDim2.fromScale(0.3, 0.86)
addMaxSize(dialog, PANEL_MAX_SIZE)
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

local closeButton = makeCloseButton(Constants.GACHA_CLOSE_BUTTON)
closeButton.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Supply Crate"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 40)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.04)
title.Size = UDim2.fromScale(0.76, 0.065)
title.Parent = dialog

local oddsTitle = makeLabel("OddsTitle", UiStyle.formatTitle("Odds"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 24)
oddsTitle.AnchorPoint = Vector2.new(0, 0)
oddsTitle.Position = UDim2.fromScale(0.04, 0.13)
oddsTitle.Size = UDim2.fromScale(0.92, 0.04)
oddsTitle.TextXAlignment = Enum.TextXAlignment.Left
oddsTitle.Parent = dialog

-- one row per prize the pool can land on (the reference game shows each
-- prize's own chance), scrolling, a colour bar on the left for its kind;
-- a restricted player sees class rows with BUY here instead
local odds = Instance.new("ScrollingFrame")
odds.Name = Constants.GACHA_ODDS_PANEL
odds.AnchorPoint = Vector2.new(0, 0)
odds.Position = UDim2.fromScale(0.04, 0.175)
odds.Size = UDim2.fromScale(0.92, 0.6)
odds.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
odds.BorderSizePixel = 0
odds.ScrollBarThickness = 6
odds.ScrollBarImageColor3 = UiStyle.TEXT_MUTED_COLOR
odds.AutomaticCanvasSize = Enum.AutomaticSize.Y
odds.CanvasSize = UDim2.fromScale(0, 0)
odds.Parent = dialog
addCorner(odds)
addPadding(odds, 0.03)

local oddsLayout = Instance.new("UIListLayout")
oddsLayout.FillDirection = Enum.FillDirection.Vertical
oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
oddsLayout.Padding = UDim.new(0.02, 0)
oddsLayout.Parent = odds

local oddsRow = Instance.new("Frame")
oddsRow.Name = Constants.GACHA_ODDS_ROW_TEMPLATE
oddsRow.Size = UDim2.fromScale(1, 0.1)
oddsRow.BackgroundColor3 = UiStyle.PANEL_COLOR
oddsRow.BorderSizePixel = 0
oddsRow.Visible = false
oddsRow.Parent = odds
addCorner(oddsRow, UiStyle.CORNER_RADIUS_PX // 2)

local oddsBar = Instance.new("Frame")
oddsBar.Name = "KindBar"
oddsBar.AnchorPoint = Vector2.new(0, 0.5)
oddsBar.Position = UDim2.fromScale(0.02, 0.5)
oddsBar.Size = UDim2.fromScale(0.02, 0.7)
oddsBar.BackgroundColor3 = UiStyle.ACCENT_COLOR
oddsBar.BorderSizePixel = 0
oddsBar.Parent = oddsRow

local oddsName = makeLabel(Constants.GACHA_ODDS_ROW_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
oddsName.AnchorPoint = Vector2.new(0, 0.5)
oddsName.Position = UDim2.fromScale(0.07, 0.5)
oddsName.Size = UDim2.fromScale(0.6, 0.8)
oddsName.TextXAlignment = Enum.TextXAlignment.Left
oddsName.Parent = oddsRow

local oddsShare = makeLabel(Constants.GACHA_ODDS_ROW_SHARE_LABEL, "8.6%", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 24)
oddsShare.AnchorPoint = Vector2.new(1, 0.5)
oddsShare.Position = UDim2.fromScale(0.97, 0.5)
oddsShare.Size = UDim2.fromScale(0.28, 0.8)
oddsShare.TextXAlignment = Enum.TextXAlignment.Right
oddsShare.Parent = oddsRow

-- the restricted player's class row: name, progress, BUY with the price
local classRow = Instance.new("Frame")
classRow.Name = Constants.GACHA_CLASS_ROW_TEMPLATE
classRow.Size = UDim2.fromScale(1, 0.13)
classRow.BackgroundColor3 = UiStyle.PANEL_COLOR
classRow.BorderSizePixel = 0
classRow.Visible = false
classRow.Parent = odds
addCorner(classRow, UiStyle.CORNER_RADIUS_PX // 2)

local className = makeLabel(Constants.GACHA_CLASS_ROW_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 24)
className.AnchorPoint = Vector2.new(0, 0.5)
className.Position = UDim2.fromScale(0.03, 0.5)
className.Size = UDim2.fromScale(0.36, 0.7)
className.TextXAlignment = Enum.TextXAlignment.Left
className.Parent = classRow

local classProgress = makeLabel(Constants.GACHA_CLASS_ROW_PROGRESS_LABEL, "Locked", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
classProgress.AnchorPoint = Vector2.new(0, 0.5)
classProgress.Position = UDim2.fromScale(0.4, 0.5)
classProgress.Size = UDim2.fromScale(0.26, 0.7)
classProgress.TextXAlignment = Enum.TextXAlignment.Left
classProgress.Parent = classRow

local buyButton = makeButton(Constants.GACHA_CLASS_ROW_BUY_BUTTON, "Buy", UiStyle.ACCENT_COLOR, 22)
buyButton.AnchorPoint = Vector2.new(1, 0.5)
buyButton.Position = UDim2.fromScale(0.97, 0.5)
buyButton.Size = UDim2.fromScale(0.3, 0.76)
addTouchTarget(buyButton, Vector2.new(200, 56))
buyButton.TextXAlignment = Enum.TextXAlignment.Left
buyButton.Visible = false
buyButton.Parent = classRow
local buyPadding = Instance.new("UIPadding")
buyPadding.PaddingLeft = UDim.new(0.08, 0)
buyPadding.Parent = buyButton
addPriceTab(buyButton, Constants.GACHA_ROLL_PRICE_LABEL, 0.56)

-- OPEN CRATE in green with the price on a black tab inside the button;
-- the manager only changes the number and the word
local rollButton = makeButton(Constants.GACHA_ROLL_BUTTON, "Open Crate", UiStyle.POSITIVE_COLOR, 32)
rollButton.AnchorPoint = Vector2.new(0.5, 1)
rollButton.Position = UDim2.fromScale(0.5, 0.97)
rollButton.Size = UDim2.fromScale(0.92, 0.16)
addTouchTarget(rollButton, Vector2.new(480, 112))
rollButton.TextXAlignment = Enum.TextXAlignment.Left
rollButton.Parent = dialog
local rollPadding = Instance.new("UIPadding")
rollPadding.PaddingLeft = UDim.new(0.06, 0)
rollPadding.Parent = rollButton
addPriceTab(rollButton, Constants.GACHA_ROLL_PRICE_LABEL, 0.4)

-- KEY STORE above OPEN CRATE (designer, 2026-11-06): a clear button over
-- a grey slice plate with the Keys icon on the left and the word in black;
-- the manager closes this menu and opens the Key Store on a tap
local keyStoreButton = makeButton(Constants.GACHA_KEY_STORE_BUTTON, "Open Crate", UiStyle.POSITIVE_COLOR, 32)
keyStoreButton.BackgroundTransparency = 1
keyStoreButton.AnchorPoint = Vector2.new(0.5, 1)
keyStoreButton.Position = UDim2.fromScale(0.5, 0.82)
keyStoreButton.Size = UDim2.fromScale(0.92, 0.1)
addTouchTarget(keyStoreButton, Vector2.new(480, 112))
keyStoreButton.Parent = dialog
local keyStorePlate = Instance.new("ImageLabel")
keyStorePlate.Name = "Background"
keyStorePlate.Size = UDim2.fromScale(1, 1)
keyStorePlate.BackgroundTransparency = 1
keyStorePlate.Image = Icons.UI.PANEL_BACKING
keyStorePlate.ImageColor3 = Color3.fromRGB(124, 124, 124)
keyStorePlate.ScaleType = Enum.ScaleType.Slice
keyStorePlate.SliceCenter = Rect.new(238, 207, 284, 278)
keyStorePlate.Parent = keyStoreButton
local keyStoreWord = Instance.new("TextLabel")
keyStoreWord.Name = "TextLabel"
keyStoreWord.AnchorPoint = Vector2.new(0.5, 0.5)
keyStoreWord.Position = UDim2.fromScale(0.5, 0.5)
keyStoreWord.Size = UDim2.fromScale(0.7, 0.8)
keyStoreWord.BackgroundTransparency = 1
keyStoreWord.Text = UiStyle.formatTitle("Key Store")
keyStoreWord.TextColor3 = Color3.new(0, 0, 0)
keyStoreWord.TextScaled = true
keyStoreWord.FontFace = UiStyle.TITLE_FONT
keyStoreWord.Parent = keyStoreButton
local keyStoreIcon = Instance.new("ImageLabel")
keyStoreIcon.Name = "Icon"
keyStoreIcon.Position = UDim2.fromScale(0.04, 0.1)
keyStoreIcon.Size = UDim2.fromScale(0.2, 0.8)
keyStoreIcon.BackgroundTransparency = 1
keyStoreIcon.Image = Icons.UI.KEYS
keyStoreIcon.ScaleType = Enum.ScaleType.Fit
keyStoreIcon.ZIndex = 2
addAspect(keyStoreIcon, 1)
keyStoreIcon.Parent = keyStoreButton

-- outside the panel: the tap line along the bottom while the camera
-- holds the crate, hidden until then
local tapHint = makeLabel(Constants.GACHA_TAP_HINT, UiStyle.formatTitle("Tap crate to open"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
tapHint.AnchorPoint = Vector2.new(0.5, 1)
tapHint.Position = UDim2.fromScale(0.5, 0.92)
tapHint.Size = UDim2.fromScale(0.7, 0.08)
tapHint.TextStrokeColor3 = UiStyle.ACCENT_STROKE_COLOR
tapHint.TextStrokeTransparency = 0.2
tapHint.Visible = false
tapHint.Parent = gui

-- the headline along the top once a class card has landed: NEW CLASS
-- UNLOCKED! or CLASS TIER INCREASED! (designer, 2026-11-03), hidden until then
-- the designer's picture backing with the words inside it (ported from
-- the live gui, 2026-11-03)
local revealTitle = Instance.new("ImageLabel")
revealTitle.Name = Constants.GACHA_REVEAL_TITLE
revealTitle.BackgroundTransparency = 1
revealTitle.Image = "rbxassetid://129096785125881"
revealTitle.ImageColor3 = Color3.new(0, 0, 0)
revealTitle.ImageTransparency = 0.45
revealTitle.AnchorPoint = Vector2.new(0.5, 0)
-- high enough to clear the landed card's top edge under CameraOpen
revealTitle.Position = UDim2.fromScale(0.5, 0.015)
revealTitle.Size = UDim2.fromScale(0.5, 0.075)
revealTitle.Visible = false
revealTitle.Parent = gui
local revealText = makeLabel(Constants.GACHA_REVEAL_TEXT, UiStyle.formatTitle("New class unlocked!"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 56)
revealText.AnchorPoint = Vector2.new(0.5, 0)
revealText.Position = UDim2.fromScale(0.5, 0.015)
revealText.Size = UDim2.fromScale(0.95, 0.95)
revealText.TextStrokeTransparency = 1
revealText.Parent = revealTitle

-- the 2D prize card (Keys and cosmetics): flies out of the crate to the
-- screen's centre, the kind over the name over a line of detail
local card = Instance.new("Frame")
card.Name = Constants.GACHA_CARD
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromScale(0, 0.56)
card.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
card.BorderSizePixel = 0
card.Visible = false
card.Parent = gui
addCorner(card)
local cardAspect = Instance.new("UIAspectRatioConstraint")
cardAspect.AspectRatio = CARD_ASPECT
cardAspect.AspectType = Enum.AspectType.ScaleWithParentSize
cardAspect.DominantAxis = Enum.DominantAxis.Height
cardAspect.Parent = card
addMaxSize(card, Vector2.new(420, 584))
local cardScale = Instance.new("UIScale")
cardScale.Name = "Scale"
cardScale.Scale = 1
cardScale.Parent = card
local cardStroke = Instance.new("UIStroke")
cardStroke.Name = "KindStroke"
cardStroke.Thickness = UiStyle.STROKE_PX * 2
cardStroke.Color = UiStyle.ACCENT_COLOR
cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
cardStroke.Parent = card

local cardKind = makeLabel(Constants.GACHA_CARD_KIND_LABEL, UiStyle.formatTitle("Class"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
cardKind.AnchorPoint = Vector2.new(0.5, 0)
cardKind.Position = UDim2.fromScale(0.5, 0.08)
cardKind.Size = UDim2.fromScale(0.86, 0.08)
cardKind.Parent = card

local cardName = makeLabel(Constants.GACHA_CARD_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 56)
cardName.AnchorPoint = Vector2.new(0.5, 0)
cardName.Position = UDim2.fromScale(0.5, 0.3)
cardName.Size = UDim2.fromScale(0.86, 0.2)
cardName.TextWrapped = true
cardName.Parent = card

local cardDetail = makeLabel(Constants.GACHA_CARD_DETAIL_LABEL, "Equip it from the Classes menu", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
cardDetail.AnchorPoint = Vector2.new(0.5, 0)
cardDetail.Position = UDim2.fromScale(0.5, 0.54)
cardDetail.Size = UDim2.fromScale(0.86, 0.16)
cardDetail.TextWrapped = true
cardDetail.Parent = card

-- CLAIM under whichever card is up: the 2D card for Keys and cosmetics,
-- the designer's 3D class card rising out of the crate for a class
local claimButton = makeButton(Constants.GACHA_CARD_CLAIM_BUTTON, "Claim", UiStyle.ACCENT_COLOR, 30)
claimButton.AnchorPoint = Vector2.new(0.5, 0.5)
claimButton.Position = UDim2.fromScale(0.5, 0.88)
claimButton.Size = UDim2.fromScale(0.22, 0.09)
addTouchTarget(claimButton, Vector2.new(300, 72))
claimButton.Visible = false
claimButton.Parent = gui

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("Gacha gui")
return "Gacha gui built"
