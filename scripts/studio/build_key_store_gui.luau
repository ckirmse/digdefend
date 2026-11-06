-- Rebuilds the lobby "KeyStore" ScreenGui under StarterGui (GDD "Class
-- Unlock System", Keys; M61, 2026-11-05). Run from the Studio command bar
-- (or the MCP execute_luau tool) in the lobby place; it replaces any
-- existing copy. Names must match Constants.KEY_STORE_*. Layout follows
-- the GUI standard in CLAUDE.md; fonts and colours come from
-- Shared/UiStyle. ClientKeyStoreManager clones ItemTemplate once per
-- cosmetic into the grid on the left and fills the info panel on the
-- right for the picked one; the template itself stays hidden. BUY carries
-- the Keys price (icon then number); EQUIP stands in its place once the
-- item is owned.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before KeyStore gui")

local existing = StarterGui:FindFirstChild(Constants.KEY_STORE_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local DIALOG_ASPECT = 1.9
local DIALOG_MAX_SIZE = Vector2.new(1140, 600)
-- the designer's slice rectangles on the plate picture (the Class Menu's)
local WIDE_PLATE_SLICE = Rect.new(136, 207, 292, 291)
local TALL_PLATE_SLICE = Rect.new(136, 105, 356, 400)
-- three cards per grid row, each a touch taller than wide for the name
local ITEM_COLUMNS = 3
local ITEM_GAP_SHARE = 0.03
local ITEM_ASPECT = 0.9

local function addCorner(parent, radiusPx)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radiusPx or UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 1
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

-- max only: menus carry no pixel floor (designer, 2026-11-03)
local function addMaxSize(frame, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addAspect(frame, ratio, dominantAxis)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	if dominantAxis then
		constraint.AspectType = Enum.AspectType.ScaleWithParentSize
		constraint.DominantAxis = dominantAxis
	end
	constraint.Parent = frame
end

local function makeFrame(name, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	return frame
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
	addTextSizeBounds(label, maxPx)
	return label
end

local function makeImage(name, image)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = image or ""
	label.ScaleType = Enum.ScaleType.Fit
	return label
end

-- a button on the designer's slice plate, tinted by ImageColor3, its word
-- a centred TextLabel child (Constants.EQUIP_BUTTON_LABEL names it)
local function makePlateButton(name, text, color, slice, maxPx)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Image = Icons.UI.PANEL_BACKING
	button.ScaleType = Enum.ScaleType.Slice
	button.SliceCenter = slice
	button.ImageColor3 = color
	button.AutoButtonColor = true
	local label = makeLabel(Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(text), UiStyle.TITLE_FONT, Color3.new(0, 0, 0), maxPx)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.7)
	label.TextTruncate = Enum.TextTruncate.None
	label.Parent = button
	return button
end

-- a wallet: an icon then the amount, the HUD wallet's look
local function makeWallet(name, amountName, icon)
	local wallet = makeFrame(name, UiStyle.BACKGROUND_COLOR)
	addCorner(wallet)
	local walletIcon = makeImage(Constants.HUD_BALANCE_ICON, icon)
	walletIcon.AnchorPoint = Vector2.new(0, 0.5)
	walletIcon.Position = UDim2.fromScale(0.05, 0.5)
	walletIcon.Size = UDim2.fromScale(0.22, 0.76)
	addAspect(walletIcon, 1)
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
gui.Name = Constants.KEY_STORE_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = makeFrame(Constants.MENU_DIALOG_FRAME, UiStyle.PANEL_COLOR)
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.84, 0.78)
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.Parent = gui
addCorner(dialog)

-- header: Back on the left, the title in the middle, the Keys wallet on the right
local backButton = makePlateButton(Constants.KEY_STORE_BACK_BUTTON, "Back", UiStyle.TOGGLE_OFF_COLOR, TALL_PLATE_SLICE, 32)
backButton.AnchorPoint = Vector2.new(0, 0)
backButton.Position = UDim2.fromScale(0.03, 0.05)
backButton.Size = UDim2.fromScale(0.14, 0.11)
backButton.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Key Store"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.05)
title.Size = UDim2.fromScale(0.4, 0.11)
title.Parent = dialog

local keysWallet = makeWallet(Constants.KEY_STORE_WALLET, Constants.HUD_KEYS_AMOUNT_LABEL, Icons.UI.KEYS)
keysWallet.AnchorPoint = Vector2.new(1, 0)
keysWallet.Position = UDim2.fromScale(0.97, 0.05)
keysWallet.Size = UDim2.fromScale(0.15, 0.11)
addMaxSize(keysWallet, Vector2.new(180, 56))
keysWallet.Parent = dialog

-- the item grid on the left: a scrolling frame of cards, three to a row,
-- each card the item's picture over its name
local itemList = Instance.new("ScrollingFrame")
itemList.Name = Constants.KEY_STORE_ITEM_LIST
itemList.AnchorPoint = Vector2.new(0, 1)
itemList.Position = UDim2.fromScale(0.03, 0.95)
itemList.Size = UDim2.fromScale(0.6, 0.74)
itemList.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
itemList.BorderSizePixel = 0
itemList.ScrollBarThickness = 6
itemList.ScrollBarImageColor3 = UiStyle.TEXT_MUTED_COLOR
itemList.ScrollingDirection = Enum.ScrollingDirection.Y
itemList.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemList.CanvasSize = UDim2.fromScale(0, 0)
itemList.Parent = dialog
addCorner(itemList)
local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(ITEM_GAP_SHARE, 0)
listPadding.PaddingBottom = UDim.new(ITEM_GAP_SHARE, 0)
listPadding.PaddingLeft = UDim.new(ITEM_GAP_SHARE, 0)
listPadding.PaddingRight = UDim.new(ITEM_GAP_SHARE, 0)
listPadding.Parent = itemList

-- a wrapping list rather than a grid, so the cards take a scale width and
-- their height from an aspect (a grid's cell size would be fixed pixels)
local itemLayout = Instance.new("UIListLayout")
itemLayout.FillDirection = Enum.FillDirection.Horizontal
itemLayout.Wraps = true
itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
itemLayout.VerticalAlignment = Enum.VerticalAlignment.Top
itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
itemLayout.Padding = UDim.new(ITEM_GAP_SHARE, 0)
itemLayout.Parent = itemList

local itemWidthShare = (1 - ITEM_GAP_SHARE * (ITEM_COLUMNS + 1)) / ITEM_COLUMNS
local item = Instance.new("ImageButton")
item.Name = Constants.KEY_STORE_ITEM_TEMPLATE
item.Size = UDim2.fromScale(itemWidthShare, 0)
addAspect(item, ITEM_ASPECT, Enum.DominantAxis.Width)
item.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
item.BorderSizePixel = 0
item.AutoButtonColor = true
item.Image = ""
item.Visible = false
item.Parent = itemList
addCorner(item)

local itemIcon = makeImage(Constants.KEY_STORE_ITEM_ICON, Icons.PLACEHOLDER)
itemIcon.AnchorPoint = Vector2.new(0.5, 0)
itemIcon.Position = UDim2.fromScale(0.5, 0.06)
itemIcon.Size = UDim2.fromScale(0.7, 0.6)
addAspect(itemIcon, 1)
itemIcon.Parent = item

local itemName = makeLabel(Constants.KEY_STORE_ITEM_NAME_LABEL, "Hard Hat", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, 22)
itemName.AnchorPoint = Vector2.new(0.5, 1)
itemName.Position = UDim2.fromScale(0.5, 0.94)
itemName.Size = UDim2.fromScale(0.9, 0.22)
itemName.Parent = item

-- a small OWNED tag across the card's top corner, shown by the manager
local ownedTag = makeLabel(Constants.KEY_STORE_ITEM_OWNED_LABEL, UiStyle.formatTitle("Owned"), UiStyle.TITLE_FONT, UiStyle.STORE_BANNER_TEXT_COLOR, 16)
ownedTag.AnchorPoint = Vector2.new(1, 0)
ownedTag.Position = UDim2.fromScale(0.97, 0.04)
ownedTag.Size = UDim2.fromScale(0.42, 0.14)
ownedTag.BackgroundTransparency = 0
ownedTag.BackgroundColor3 = UiStyle.POSITIVE_COLOR
ownedTag.Visible = false
ownedTag.Parent = item
addCorner(ownedTag, UiStyle.CORNER_RADIUS_PX // 2)

-- the info panel on the right: the picked item's picture, name, and slot,
-- then BUY with the Keys price or EQUIP, with a hint before a pick
local infoPanel = makeFrame(Constants.KEY_STORE_INFO_PANEL, UiStyle.BACKGROUND_COLOR)
infoPanel.AnchorPoint = Vector2.new(1, 1)
infoPanel.Position = UDim2.fromScale(0.97, 0.95)
infoPanel.Size = UDim2.fromScale(0.32, 0.74)
infoPanel.Parent = dialog
addCorner(infoPanel)

local infoIcon = makeImage(Constants.KEY_STORE_INFO_ICON, Icons.PLACEHOLDER)
infoIcon.AnchorPoint = Vector2.new(0.5, 0)
infoIcon.Position = UDim2.fromScale(0.5, 0.05)
infoIcon.Size = UDim2.fromScale(0.6, 0.38)
addAspect(infoIcon, 1)
infoIcon.Parent = infoPanel

local infoName = makeLabel(Constants.KEY_STORE_INFO_NAME_LABEL, UiStyle.formatTitle("Hard Hat"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 32)
infoName.AnchorPoint = Vector2.new(0.5, 0)
infoName.Position = UDim2.fromScale(0.5, 0.46)
infoName.Size = UDim2.fromScale(0.9, 0.1)
infoName.Parent = infoPanel

local infoSlot = makeLabel(Constants.KEY_STORE_INFO_SLOT_LABEL, "Helmet", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
infoSlot.AnchorPoint = Vector2.new(0.5, 0)
infoSlot.Position = UDim2.fromScale(0.5, 0.57)
infoSlot.Size = UDim2.fromScale(0.9, 0.07)
infoSlot.Parent = infoPanel

local infoHint = makeLabel(Constants.KEY_STORE_INFO_HINT_LABEL, "Pick an item to see it here", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, 24)
infoHint.AnchorPoint = Vector2.new(0.5, 0.5)
infoHint.Position = UDim2.fromScale(0.5, 0.5)
infoHint.Size = UDim2.fromScale(0.8, 0.3)
infoHint.TextWrapped = true
infoHint.Parent = infoPanel

-- BUY: the word on the left, the Keys price (icon then number) in a black
-- tab on the right; the manager changes the number only
local buyButton = makePlateButton(Constants.KEY_STORE_BUY_BUTTON, "Buy", UiStyle.ACCENT_COLOR, WIDE_PLATE_SLICE, 28)
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.fromScale(0.5, 0.94)
buyButton.Size = UDim2.fromScale(0.86, 0.15)
buyButton.Parent = infoPanel
local buyWord = buyButton:FindFirstChild(Constants.EQUIP_BUTTON_LABEL)
buyWord.AnchorPoint = Vector2.new(0, 0.5)
buyWord.Position = UDim2.fromScale(0.08, 0.5)
buyWord.Size = UDim2.fromScale(0.36, 0.7)
buyWord.TextXAlignment = Enum.TextXAlignment.Left

local priceTab = makeFrame(Constants.KEY_STORE_BUY_PRICE_LABEL .. "Tab", UiStyle.BACKGROUND_COLOR)
priceTab.AnchorPoint = Vector2.new(1, 0.5)
priceTab.Position = UDim2.fromScale(0.94, 0.5)
priceTab.Size = UDim2.fromScale(0.46, 0.7)
priceTab.Parent = buyButton
addCorner(priceTab, UiStyle.CORNER_RADIUS_PX // 2)
local priceIcon = makeImage(Constants.HUD_BALANCE_ICON, Icons.UI.KEYS)
priceIcon.AnchorPoint = Vector2.new(0, 0.5)
priceIcon.Position = UDim2.fromScale(0.06, 0.5)
priceIcon.Size = UDim2.fromScale(0.3, 0.8)
addAspect(priceIcon, 1)
priceIcon.Parent = priceTab
local price = makeLabel(Constants.KEY_STORE_BUY_PRICE_LABEL, "10", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
price.AnchorPoint = Vector2.new(1, 0.5)
price.Position = UDim2.fromScale(0.92, 0.5)
price.Size = UDim2.fromScale(0.5, 0.8)
price.TextXAlignment = Enum.TextXAlignment.Right
price.Parent = priceTab

-- EQUIP stands where BUY stood once the item is owned; the manager shows
-- one or the other (EQUIPPED, clear plate, on the one worn)
local equipButton = makePlateButton(Constants.KEY_STORE_EQUIP_BUTTON, "Equip", UiStyle.POSITIVE_COLOR, WIDE_PLATE_SLICE, 28)
equipButton.AnchorPoint = Vector2.new(0.5, 1)
equipButton.Position = UDim2.fromScale(0.5, 0.94)
equipButton.Size = UDim2.fromScale(0.86, 0.15)
equipButton.Visible = false
equipButton.Parent = infoPanel

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("KeyStore gui")
return "KeyStore gui built"
