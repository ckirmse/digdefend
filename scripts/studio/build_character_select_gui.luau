-- Rebuilds the lobby "CharacterSelect" ScreenGui under StarterGui (GDD
-- "Character Menu", M37, from docs/mockups/character-select-2026-10-12.png).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- lobby place; it replaces any existing copy. Names must match
-- Constants.CHARACTER_SELECT_* / CHARACTER_CARD_*. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
-- ClientCharacterMenuManager clones CardTemplate per character and fills
-- every label; the template itself stays hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before CharacterSelect gui")

local existing = StarterGui:FindFirstChild(Constants.CHARACTER_SELECT_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
-- the mock-up's card: a tall rectangle, about 0.74 wide for its height
local CARD_ASPECT = 0.74
local CARD_MAX_SIZE = Vector2.new(440, 600)

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

local function addAspect(frame, ratio, dominantAxis)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	if dominantAxis then
		-- a frame whose width is 0 by design (the list row sets its height)
		-- needs the parent-scaled aspect: FitWithinMaxSize reads the zero
		-- width and collapses the frame
		constraint.DominantAxis = dominantAxis
		constraint.AspectType = Enum.AspectType.ScaleWithParentSize
	end
	constraint.Parent = frame
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

local gui = Instance.new("ScreenGui")
gui.Name = Constants.CHARACTER_SELECT_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the whole screen is the menu (the mock-up has no dialog box), so the
-- root is a full-screen frame the overlay manager treats as the dialog
local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.Size = UDim2.fromScale(1, 1)
dialog.BackgroundTransparency = 1
dialog.Parent = gui

-- header: Back top left, the Diamonds wallet top centre (the HUD wallet's
-- look, so the balance reads the same in and out of the menu)
local backButton = Instance.new("TextButton")
backButton.Name = Constants.CHARACTER_SELECT_BACK_BUTTON
backButton.AnchorPoint = Vector2.new(0, 0)
backButton.Position = UDim2.fromScale(0.055, 0.045)
backButton.Size = UDim2.fromScale(0.2, 0.07)
addAspect(backButton, 5)
addTouchTarget(backButton, Vector2.new(280, 56))
backButton.BackgroundColor3 = UiStyle.NEGATIVE_COLOR
backButton.BorderSizePixel = 0
backButton.Text = UiStyle.formatTitle("Back")
backButton.TextColor3 = UiStyle.TEXT_COLOR
backButton.TextScaled = true
backButton.FontFace = UiStyle.TITLE_FONT
backButton.AutoButtonColor = true
addTextSizeBounds(backButton, 1, 40)
addCorner(backButton)
backButton.Parent = dialog

local wallet = Instance.new("Frame")
wallet.Name = Constants.CHARACTER_SELECT_WALLET
wallet.AnchorPoint = Vector2.new(0.5, 0)
wallet.Position = UDim2.fromScale(0.5, 0.03)
wallet.Size = UDim2.fromScale(0.16, 0.07)
addMaxSize(wallet, Vector2.new(260, 64))
wallet.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
wallet.BorderSizePixel = 0
wallet.Parent = dialog
addCorner(wallet)

local walletIcon = Instance.new("ImageLabel")
walletIcon.Name = Constants.HUD_BALANCE_ICON
walletIcon.AnchorPoint = Vector2.new(0, 0.5)
walletIcon.Position = UDim2.fromScale(0.04, 0.5)
walletIcon.Size = UDim2.fromScale(0.2, 0.8)
addAspect(walletIcon, 1)
walletIcon.BackgroundTransparency = 1
walletIcon.Image = Icons.UI.DIAMONDS
walletIcon.Parent = wallet

local walletAmount = makeLabel(Constants.HUD_DIAMOND_AMOUNT_LABEL, "0", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 40)
walletAmount.AnchorPoint = Vector2.new(0, 0.5)
walletAmount.Position = UDim2.fromScale(0.26, 0.5)
walletAmount.Size = UDim2.fromScale(0.7, 0.8)
walletAmount.Parent = wallet

-- the cards: a centred row sized by the screen's height so a card keeps
-- its shape from phone to ultrawide
local cards = Instance.new("Frame")
cards.Name = Constants.CHARACTER_SELECT_CARDS
cards.AnchorPoint = Vector2.new(0.5, 0.5)
cards.Position = UDim2.fromScale(0.5, 0.53)
cards.Size = UDim2.fromScale(0.9, 0.74)
cards.BackgroundTransparency = 1
cards.Parent = dialog

local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardLayout.Padding = UDim.new(0.03, 0)
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Parent = cards

-- the card template, hidden; the manager clones it per character
local card = Instance.new("TextButton")
card.Name = Constants.CHARACTER_SELECT_CARD_TEMPLATE
-- the card takes its height from the row and its width from the aspect,
-- so the dominant axis must be the height (a width of 0 is the point)
card.Size = UDim2.fromScale(0, 1)
addAspect(card, CARD_ASPECT, Enum.DominantAxis.Height)
addMaxSize(card, CARD_MAX_SIZE)
card.BackgroundColor3 = UiStyle.PANEL_COLOR
card.BorderSizePixel = 0
card.Text = ""
card.AutoButtonColor = true
card.Visible = false
card.Parent = cards
addCorner(card)

local selectedStroke = Instance.new("UIStroke")
selectedStroke.Name = Constants.CHARACTER_CARD_SELECTED_STROKE
selectedStroke.Thickness = UiStyle.STROKE_PX * 2
selectedStroke.Color = UiStyle.ACCENT_COLOR
selectedStroke.Enabled = false
selectedStroke.Parent = card

local title = makeLabel(Constants.CHARACTER_CARD_TITLE, UiStyle.formatTitle("Character 1"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 44)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.05)
title.Size = UDim2.fromScale(0.9, 0.09)
title.Parent = card

local avatar = Instance.new("ViewportFrame")
avatar.Name = Constants.CHARACTER_CARD_AVATAR
avatar.AnchorPoint = Vector2.new(0.5, 0)
avatar.Position = UDim2.fromScale(0.5, 0.16)
avatar.Size = UDim2.fromScale(0.9, 0.58)
avatar.BackgroundTransparency = 1
avatar.Ambient = Color3.new(1, 1, 1)
avatar.LightColor = Color3.new(1, 1, 1)
avatar.Parent = card

local rankLabel = makeLabel(Constants.CHARACTER_CARD_RANK_LABEL, UiStyle.formatTitle("Rank 1"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 36)
rankLabel.AnchorPoint = Vector2.new(0.5, 0)
rankLabel.Position = UDim2.fromScale(0.5, 0.78)
rankLabel.Size = UDim2.fromScale(0.9, 0.08)
rankLabel.Parent = card

local nightsLabel = makeLabel(Constants.CHARACTER_CARD_NIGHTS_LABEL, UiStyle.formatTitle("Nights survived: 0"), UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
nightsLabel.AnchorPoint = Vector2.new(0.5, 0)
nightsLabel.Position = UDim2.fromScale(0.5, 0.87)
nightsLabel.Size = UDim2.fromScale(0.9, 0.06)
nightsLabel.Parent = card

-- the next slot's buy button: UNLOCK SLOT on the left, the price (number
-- then icon, the resource rule) on a black tab on the right
local unlockButton = Instance.new("TextButton")
unlockButton.Name = Constants.CHARACTER_CARD_UNLOCK_BUTTON
unlockButton.AnchorPoint = Vector2.new(0.5, 1)
unlockButton.Position = UDim2.fromScale(0.5, 0.95)
unlockButton.Size = UDim2.fromScale(0.86, 0.14)
addTouchTarget(unlockButton, Vector2.new(380, 84))
unlockButton.BackgroundColor3 = UiStyle.ACCENT_COLOR
unlockButton.BorderSizePixel = 0
unlockButton.Text = ""
unlockButton.AutoButtonColor = true
unlockButton.Visible = false
unlockButton.Parent = card
addCorner(unlockButton, UiStyle.CORNER_RADIUS_PX // 2)

local unlockLabel = makeLabel(Constants.CHARACTER_CARD_UNLOCK_LABEL, UiStyle.formatTitle("Unlock Slot"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
unlockLabel.AnchorPoint = Vector2.new(0, 0.5)
unlockLabel.Position = UDim2.fromScale(0.04, 0.5)
unlockLabel.Size = UDim2.fromScale(0.46, 0.8)
unlockLabel.Parent = unlockButton

local price = Instance.new("Frame")
price.Name = Constants.CHARACTER_CARD_PRICE_FRAME
price.AnchorPoint = Vector2.new(1, 0.5)
price.Position = UDim2.fromScale(0.96, 0.5)
price.Size = UDim2.fromScale(0.44, 0.8)
price.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
price.BorderSizePixel = 0
price.Parent = unlockButton
addCorner(price, UiStyle.CORNER_RADIUS_PX // 2)

local priceLabel = makeLabel(Constants.CHARACTER_CARD_PRICE_LABEL, "300", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 34)
priceLabel.AnchorPoint = Vector2.new(0, 0.5)
priceLabel.Position = UDim2.fromScale(0.06, 0.5)
priceLabel.Size = UDim2.fromScale(0.56, 0.8)
priceLabel.Parent = price

local priceIcon = Instance.new("ImageLabel")
priceIcon.Name = Constants.CHARACTER_CARD_PRICE_ICON
priceIcon.AnchorPoint = Vector2.new(1, 0.5)
priceIcon.Position = UDim2.fromScale(0.94, 0.5)
priceIcon.Size = UDim2.fromScale(0.3, 0.8)
addAspect(priceIcon, 1)
priceIcon.BackgroundTransparency = 1
priceIcon.Image = Icons.UI.DIAMONDS
priceIcon.Parent = price

local hint = makeLabel(Constants.CHARACTER_SELECT_HINT, UiStyle.formatTitle("Select a character to edit its loadout and skills"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.fromScale(0.5, 0.97)
hint.Size = UDim2.fromScale(0.8, 0.05)
hint.Parent = dialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("CharacterSelect gui")
return "CharacterSelect gui built"
