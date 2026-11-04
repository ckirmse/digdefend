-- Rebuilds the lobby "DiamondStore" ScreenGui under StarterGui (GDD
-- "Monetization", M40, 2026-11-03). Run from the Studio command bar (or the
-- MCP execute_luau tool) in the lobby place; it replaces any existing copy.
-- Names must match Constants.DIAMOND_STORE_*. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
-- ClientDiamondStoreManager clones PackTemplate once per pack and fills
-- the amount, the banner, and the price; the template itself stays hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before DiamondStore gui")

local existing = StarterGui:FindFirstChild(Constants.DIAMOND_STORE_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local DIALOG_ASPECT = 1.9
local DIALOG_MAX_SIZE = Vector2.new(1140, 600)
-- a card is taller than wide; four sit in a row with gaps, each this share
-- of the row's width (4 x 0.22 + 3 gaps of 0.02 = 0.94 of the row)
local CARD_ASPECT = 0.72
local CARD_WIDTH_SHARE = 0.22
local CARD_GAP_SHARE = 0.02

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

-- a wallet: an icon then the amount, the HUD wallet's look
local function makeWallet(name, amountName, icon)
	local wallet = Instance.new("Frame")
	wallet.Name = name
	wallet.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
	wallet.BorderSizePixel = 0
	addCorner(wallet)
	local walletIcon = Instance.new("ImageLabel")
	walletIcon.Name = Constants.HUD_BALANCE_ICON
	walletIcon.AnchorPoint = Vector2.new(0, 0.5)
	walletIcon.Position = UDim2.fromScale(0.05, 0.5)
	walletIcon.Size = UDim2.fromScale(0.22, 0.76)
	addAspect(walletIcon, 1)
	walletIcon.BackgroundTransparency = 1
	walletIcon.Image = icon
	walletIcon.Parent = wallet
	local amount = makeLabel(amountName, "0", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 34)
	amount.AnchorPoint = Vector2.new(0, 0.5)
	amount.Position = UDim2.fromScale(0.32, 0.5)
	amount.Size = UDim2.fromScale(0.64, 0.76)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Parent = wallet
	return wallet
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.DIAMOND_STORE_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.84, 0.78)
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

-- header: Back on the left, the title in the middle, the wallet on the right
local backButton = makeButton(Constants.DIAMOND_STORE_BACK_BUTTON, "Back", UiStyle.NEGATIVE_COLOR, 32)
backButton.AnchorPoint = Vector2.new(0, 0)
backButton.Position = UDim2.fromScale(0.03, 0.05)
backButton.Size = UDim2.fromScale(0.14, 0.11)
addTouchTarget(backButton, Vector2.new(200, 56))
backButton.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Diamonds"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.05)
title.Size = UDim2.fromScale(0.4, 0.11)
title.Parent = dialog

local diamondWallet = makeWallet(Constants.DIAMOND_STORE_WALLET, Constants.HUD_DIAMOND_AMOUNT_LABEL, Icons.UI.DIAMONDS)
diamondWallet.AnchorPoint = Vector2.new(1, 0)
diamondWallet.Position = UDim2.fromScale(0.97, 0.05)
diamondWallet.Size = UDim2.fromScale(0.15, 0.11)
addMaxSize(diamondWallet, Vector2.new(180, 56))
diamondWallet.Parent = dialog

-- the packs: one card each in a centred row, smallest to largest
local packs = Instance.new("Frame")
packs.Name = Constants.DIAMOND_STORE_PACKS
packs.AnchorPoint = Vector2.new(0.5, 1)
packs.Position = UDim2.fromScale(0.5, 0.95)
packs.Size = UDim2.fromScale(0.94, 0.72)
packs.BackgroundTransparency = 1
packs.Parent = dialog

local packsLayout = Instance.new("UIListLayout")
packsLayout.FillDirection = Enum.FillDirection.Horizontal
packsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
packsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
packsLayout.SortOrder = Enum.SortOrder.LayoutOrder
packsLayout.Padding = UDim.new(CARD_GAP_SHARE, 0)
packsLayout.Parent = packs

-- the card: width from the row, height from the aspect (width-dominant,
-- so four always fit across whatever the dialog's shape)
local card = Instance.new("Frame")
card.Name = Constants.DIAMOND_STORE_PACK_TEMPLATE
card.Size = UDim2.fromScale(CARD_WIDTH_SHARE, 0)
card.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
card.BorderSizePixel = 0
card.Visible = false
card.Parent = packs
addCorner(card)
local cardAspect = Instance.new("UIAspectRatioConstraint")
cardAspect.AspectRatio = CARD_ASPECT
cardAspect.AspectType = Enum.AspectType.ScaleWithParentSize
cardAspect.DominantAxis = Enum.DominantAxis.Width
cardAspect.Parent = card

-- the banner across the top: hidden unless the pack carries one
local banner = Instance.new("Frame")
banner.Name = Constants.DIAMOND_STORE_PACK_BANNER
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.fromScale(0.5, 0)
banner.Size = UDim2.fromScale(1, 0.12)
banner.BackgroundColor3 = UiStyle.STORE_BANNER_COLOR
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = card
addCorner(banner)

local bannerText = makeLabel(Constants.DIAMOND_STORE_PACK_BANNER_LABEL, UiStyle.formatTitle("Best value"), UiStyle.TITLE_FONT, UiStyle.STORE_BANNER_TEXT_COLOR, 22)
bannerText.AnchorPoint = Vector2.new(0.5, 0.5)
bannerText.Position = UDim2.fromScale(0.5, 0.5)
bannerText.Size = UDim2.fromScale(0.9, 0.7)
bannerText.Parent = banner

local icon = Instance.new("ImageLabel")
icon.Name = Constants.DIAMOND_STORE_PACK_ICON
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.4)
icon.Size = UDim2.fromScale(0.5, 0.3)
addAspect(icon, 1)
icon.BackgroundTransparency = 1
icon.Image = Icons.UI.DIAMONDS
icon.Parent = card

local amount = makeLabel(Constants.DIAMOND_STORE_PACK_AMOUNT_LABEL, "1,500", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 40)
amount.AnchorPoint = Vector2.new(0.5, 0)
amount.Position = UDim2.fromScale(0.5, 0.59)
amount.Size = UDim2.fromScale(0.86, 0.12)
amount.Parent = card

-- BUY carries the Robux price (glyph then number) in a black tab inside
-- the button; the manager only changes the number
local buyButton = makeButton(Constants.DIAMOND_STORE_PACK_BUY_BUTTON, "Buy", UiStyle.ACCENT_COLOR, 28)
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.fromScale(0.5, 0.95)
buyButton.Size = UDim2.fromScale(0.86, 0.17)
addTouchTarget(buyButton, Vector2.new(260, 72))
buyButton.TextXAlignment = Enum.TextXAlignment.Left
buyButton.Parent = card
local buyPadding = Instance.new("UIPadding")
buyPadding.PaddingLeft = UDim.new(0.08, 0)
buyPadding.Parent = buyButton

local price = makeLabel(Constants.DIAMOND_STORE_PACK_PRICE_LABEL, UiStyle.ROBUX_GLYPH .. "99", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
price.AnchorPoint = Vector2.new(1, 0.5)
price.Position = UDim2.fromScale(0.96, 0.5)
price.Size = UDim2.fromScale(0.6, 0.74)
price.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
price.BackgroundTransparency = 0
price.Parent = buyButton
addCorner(price, UiStyle.CORNER_RADIUS_PX // 2)

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("DiamondStore gui")
return "DiamondStore gui built"
