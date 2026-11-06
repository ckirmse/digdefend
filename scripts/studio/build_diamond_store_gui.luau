-- Rebuilds the lobby "DiamondStore" ScreenGui under StarterGui (GDD
-- "Monetization", M40, 2026-11-03). Run from the Studio command bar (or the
-- MCP execute_luau tool) in the lobby place; it replaces any existing copy.
-- Names must match Constants.DIAMOND_STORE_*. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
-- ClientDiamondStoreManager clones PackTemplate once per pack and fills
-- the amount, the banner, and the price; the template itself stays hidden.
-- The designer's layout of 2026-11-06 is ported here: a black header band
-- with the title, an X in the top-right corner in place of Back, no wallet
-- of its own (the HUD's Diamonds wallet stays up as the balance), and BUY
-- on the slice plate the Key Store's buttons use.
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
-- the dialog sits a little under centre, leaving the HUD's wallets clear
-- above it, and lets a hint of the world through (designer, 2026-11-06)
local DIALOG_POSITION_Y = 0.55
local DIALOG_TRANSPARENCY = 0.1
-- a card is taller than wide; four sit in a row with gaps, each this share
-- of the row's width (4 x 0.24 + 3 gaps of 0.02 = 1.02 of the row, so the
-- outer cards tuck in by the row's own margin; designer, 2026-11-06)
local CARD_ASPECT = 0.61
local CARD_WIDTH_SHARE = 0.24
local CARD_GAP_SHARE = 0.02
-- the Key Store's slice plate for a wide button
local WIDE_PLATE_SLICE = Rect.new(136, 207, 292, 291)
local HEADER_HEIGHT_SHARE = 0.12
local CLOSE_BUTTON_MAX_PX = 56
local BLACK = Color3.new(0, 0, 0)

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

-- a button on the designer's slice plate, tinted by ImageColor3, its word
-- a TextLabel child (Constants.EQUIP_BUTTON_LABEL names it), as in the
-- Key Store; the manager tints the plate grey for a pack not on sale
local function makePlateButton(name, text, color, slice, maxPx)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Image = Icons.UI.PANEL_BACKING
	button.ScaleType = Enum.ScaleType.Slice
	button.SliceCenter = slice
	button.ImageColor3 = color
	button.AutoButtonColor = true
	local label = makeLabel(Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(text), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, maxPx)
	label.TextTruncate = Enum.TextTruncate.None
	label.Parent = button
	return button, label
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
dialog.Position = UDim2.fromScale(0.5, DIALOG_POSITION_Y)
dialog.Size = UDim2.fromScale(0.84, 0.78)
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = DIALOG_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

-- the header band across the top with the title centred in it
local header = Instance.new("Frame")
header.Name = "Header"
header.Position = UDim2.fromScale(0, 0)
header.Size = UDim2.fromScale(1, HEADER_HEIGHT_SHARE)
header.BackgroundColor3 = BLACK
header.BorderSizePixel = 0
header.Parent = dialog
addCorner(header)

local title = makeLabel("Title", UiStyle.formatTitle("Diamonds"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(0.95, 0.9)
title.Parent = header

-- the X in the top-right corner: a square button on a red plate picture
-- over a dark backing, drawn above the header band
local backButton = Instance.new("TextButton")
backButton.Name = Constants.DIAMOND_STORE_BACK_BUTTON
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.fromScale(0.98, 0.01)
backButton.Size = UDim2.fromScale(0.1, 0.1)
backButton.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
backButton.BorderSizePixel = 0
backButton.ZIndex = 2
backButton.Text = ""
backButton.TextColor3 = UiStyle.TEXT_COLOR
backButton.TextScaled = true
backButton.FontFace = UiStyle.TITLE_FONT
backButton.AutoButtonColor = true
addTextSizeBounds(backButton, 1, 26)
addCorner(backButton)
addAspect(backButton, 1)
addTouchTarget(backButton, Vector2.new(CLOSE_BUTTON_MAX_PX, CLOSE_BUTTON_MAX_PX))
backButton.Parent = dialog

local backBackground = Instance.new("ImageLabel")
backBackground.Name = "Background"
backBackground.Position = UDim2.fromScale(0, 0)
backBackground.Size = UDim2.fromScale(1, 1)
backBackground.BackgroundTransparency = 1
backBackground.Image = Icons.UI.PANEL_BACKING
backBackground.ImageColor3 = UiStyle.TOGGLE_OFF_COLOR
backBackground.Parent = backButton

local backLabel = makeLabel(Constants.EQUIP_BUTTON_LABEL, "X", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
backLabel.AnchorPoint = Vector2.new(0.5, 0.5)
backLabel.Position = UDim2.fromScale(0.5, 0.5)
backLabel.Size = UDim2.fromScale(0.8, 0.8)
backLabel.ZIndex = 2
backLabel.Parent = backButton

-- the packs: one card each in a centred row, smallest to largest
local packs = Instance.new("Frame")
packs.Name = Constants.DIAMOND_STORE_PACKS
packs.AnchorPoint = Vector2.new(0.5, 1)
packs.Position = UDim2.fromScale(0.5, 0.95)
packs.Size = UDim2.fromScale(0.94, 0.8)
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
card.BackgroundColor3 = BLACK
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

-- BUY on the left of the plate and the Robux price (glyph then number) in
-- a dark tab on the right; the manager only changes the number
local buyButton, buyLabel = makePlateButton(Constants.DIAMOND_STORE_PACK_BUY_BUTTON, "Buy", UiStyle.ACCENT_COLOR, WIDE_PLATE_SLICE, 28)
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.fromScale(0.5, 0.95)
buyButton.Size = UDim2.fromScale(0.86, 0.17)
addTouchTarget(buyButton, Vector2.new(260, 72))
buyButton.Parent = card
local buyPadding = Instance.new("UIPadding")
buyPadding.PaddingLeft = UDim.new(0.08, 0)
buyPadding.Parent = buyButton
buyLabel.AnchorPoint = Vector2.new(0, 0.5)
buyLabel.Position = UDim2.fromScale(0, 0.5)
buyLabel.Size = UDim2.fromScale(0.3, 0.8)

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
