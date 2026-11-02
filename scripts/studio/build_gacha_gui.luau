-- Rebuilds the lobby "Gacha" ScreenGui under StarterGui (GDD "Class
-- Unlock System", M70). Run from the Studio command bar (or the MCP
-- execute_luau tool) in the lobby place; it replaces any existing copy.
-- Names must match Constants.GACHA_*. Layout follows the GUI standard in
-- CLAUDE.md; fonts and colours come from Shared/UiStyle.
-- ClientGachaMenuManager clones OddsRowTemplate and ClassRowTemplate and
-- fills every label; the templates themselves stay hidden. The title is
-- a placeholder until the designer names the crate.
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
local DIALOG_ASPECT = 1.6
local DIALOG_MAX_SIZE = Vector2.new(1120, 700)

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
gui.Name = Constants.GACHA_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.8, 0.82)
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

-- header: Back on the left, the title in the middle, the two wallets on
-- the right
local backButton = makeButton(Constants.GACHA_BACK_BUTTON, "Back", UiStyle.NEGATIVE_COLOR, 32)
backButton.AnchorPoint = Vector2.new(0, 0)
backButton.Position = UDim2.fromScale(0.03, 0.04)
backButton.Size = UDim2.fromScale(0.14, 0.09)
addTouchTarget(backButton, Vector2.new(200, 56))
backButton.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Loot Crate"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.04)
title.Size = UDim2.fromScale(0.36, 0.09)
title.Parent = dialog

local keysWallet = makeWallet(Constants.GACHA_KEYS_WALLET, Constants.GACHA_KEYS_AMOUNT_LABEL, Icons.UI.KEYS)
keysWallet.AnchorPoint = Vector2.new(1, 0)
keysWallet.Position = UDim2.fromScale(0.97, 0.04)
keysWallet.Size = UDim2.fromScale(0.13, 0.09)
addMaxSize(keysWallet, Vector2.new(180, 56))
keysWallet.Parent = dialog

local diamondWallet = makeWallet(Constants.GACHA_WALLET, Constants.HUD_DIAMOND_AMOUNT_LABEL, Icons.UI.DIAMONDS)
diamondWallet.AnchorPoint = Vector2.new(1, 0)
diamondWallet.Position = UDim2.fromScale(0.83, 0.04)
diamondWallet.Size = UDim2.fromScale(0.13, 0.09)
addMaxSize(diamondWallet, Vector2.new(180, 56))
diamondWallet.Parent = dialog

-- left column: the odds, then the ROLL button under them
local oddsTitle = makeLabel("OddsTitle", UiStyle.formatTitle("Odds"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 28)
oddsTitle.AnchorPoint = Vector2.new(0, 0)
oddsTitle.Position = UDim2.fromScale(0.03, 0.17)
oddsTitle.Size = UDim2.fromScale(0.4, 0.06)
oddsTitle.TextXAlignment = Enum.TextXAlignment.Left
oddsTitle.Parent = dialog

-- one row per prize the pool can land on (the reference game shows each
-- prize's own chance), scrolling, a colour bar on the left for its kind
local odds = Instance.new("ScrollingFrame")
odds.Name = Constants.GACHA_ODDS_PANEL
odds.AnchorPoint = Vector2.new(0, 0)
odds.Position = UDim2.fromScale(0.03, 0.24)
odds.Size = UDim2.fromScale(0.4, 0.46)
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
oddsRow.Size = UDim2.fromScale(1, 0.11)
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

local oddsShare = makeLabel(Constants.GACHA_ODDS_ROW_SHARE_LABEL, "8.6%", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 26)
oddsShare.AnchorPoint = Vector2.new(1, 0.5)
oddsShare.Position = UDim2.fromScale(0.97, 0.5)
oddsShare.Size = UDim2.fromScale(0.28, 0.8)
oddsShare.TextXAlignment = Enum.TextXAlignment.Right
oddsShare.Parent = oddsRow

-- ROLL with the price (number then icon, the resource rule) on a black
-- tab inside the button
local rollButton = makeButton(Constants.GACHA_ROLL_BUTTON, "Roll", UiStyle.ACCENT_COLOR, 40)
rollButton.AnchorPoint = Vector2.new(0, 1)
rollButton.Position = UDim2.fromScale(0.03, 0.94)
rollButton.Size = UDim2.fromScale(0.4, 0.16)
addTouchTarget(rollButton, Vector2.new(460, 112))
rollButton.TextXAlignment = Enum.TextXAlignment.Left
rollButton.Parent = dialog
local rollPadding = Instance.new("UIPadding")
rollPadding.PaddingLeft = UDim.new(0.06, 0)
rollPadding.Parent = rollButton

local rollPrice = Instance.new("Frame")
rollPrice.Name = "PriceFrame"
rollPrice.AnchorPoint = Vector2.new(1, 0.5)
rollPrice.Position = UDim2.fromScale(0.96, 0.5)
rollPrice.Size = UDim2.fromScale(0.42, 0.7)
rollPrice.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
rollPrice.BorderSizePixel = 0
rollPrice.Parent = rollButton
addCorner(rollPrice, UiStyle.CORNER_RADIUS_PX // 2)

local rollPriceLabel = makeLabel(Constants.GACHA_ROLL_PRICE_LABEL, "100", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 34)
rollPriceLabel.AnchorPoint = Vector2.new(0, 0.5)
rollPriceLabel.Position = UDim2.fromScale(0.08, 0.5)
rollPriceLabel.Size = UDim2.fromScale(0.54, 0.8)
rollPriceLabel.TextXAlignment = Enum.TextXAlignment.Right
rollPriceLabel.Parent = rollPrice

local rollPriceIcon = Instance.new("ImageLabel")
rollPriceIcon.Name = "PriceIcon"
rollPriceIcon.AnchorPoint = Vector2.new(1, 0.5)
rollPriceIcon.Position = UDim2.fromScale(0.94, 0.5)
rollPriceIcon.Size = UDim2.fromScale(0.3, 0.8)
addAspect(rollPriceIcon, 1)
rollPriceIcon.BackgroundTransparency = 1
rollPriceIcon.Image = Icons.UI.DIAMONDS
rollPriceIcon.Parent = rollPrice

-- the price label sits on the right of the ROLL word; the manager only
-- changes the number
rollButton.Text = UiStyle.formatTitle("Roll")

-- right column: every class in the pool with the player's progress
local classesTitle = makeLabel("ClassesTitle", UiStyle.formatTitle("Classes"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 28)
classesTitle.AnchorPoint = Vector2.new(0, 0)
classesTitle.Position = UDim2.fromScale(0.47, 0.17)
classesTitle.Size = UDim2.fromScale(0.5, 0.06)
classesTitle.TextXAlignment = Enum.TextXAlignment.Left
classesTitle.Parent = dialog

local classes = Instance.new("ScrollingFrame")
classes.Name = Constants.GACHA_CLASSES_PANEL
classes.AnchorPoint = Vector2.new(0, 0)
classes.Position = UDim2.fromScale(0.47, 0.24)
classes.Size = UDim2.fromScale(0.5, 0.7)
classes.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
classes.BorderSizePixel = 0
classes.ScrollBarThickness = 6
classes.ScrollBarImageColor3 = UiStyle.TEXT_MUTED_COLOR
classes.AutomaticCanvasSize = Enum.AutomaticSize.Y
classes.CanvasSize = UDim2.fromScale(0, 0)
classes.Parent = dialog
addCorner(classes)
addPadding(classes, 0.03)

local classesLayout = Instance.new("UIListLayout")
classesLayout.FillDirection = Enum.FillDirection.Vertical
classesLayout.SortOrder = Enum.SortOrder.LayoutOrder
classesLayout.Padding = UDim.new(0.02, 0)
classesLayout.Parent = classes

local classRow = Instance.new("Frame")
classRow.Name = Constants.GACHA_CLASS_ROW_TEMPLATE
classRow.Size = UDim2.fromScale(1, 0.13)
classRow.BackgroundColor3 = UiStyle.PANEL_COLOR
classRow.BorderSizePixel = 0
classRow.Visible = false
classRow.Parent = classes
addCorner(classRow, UiStyle.CORNER_RADIUS_PX // 2)

local className = makeLabel(Constants.GACHA_CLASS_ROW_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 28)
className.AnchorPoint = Vector2.new(0, 0.5)
className.Position = UDim2.fromScale(0.03, 0.5)
className.Size = UDim2.fromScale(0.36, 0.7)
className.TextXAlignment = Enum.TextXAlignment.Left
className.Parent = classRow

local classProgress = makeLabel(Constants.GACHA_CLASS_ROW_PROGRESS_LABEL, "Locked", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
classProgress.AnchorPoint = Vector2.new(0, 0.5)
classProgress.Position = UDim2.fromScale(0.4, 0.5)
classProgress.Size = UDim2.fromScale(0.3, 0.7)
classProgress.TextXAlignment = Enum.TextXAlignment.Left
classProgress.Parent = classRow

-- the restricted player's BUY: hidden for everyone else
local buyButton = makeButton(Constants.GACHA_CLASS_ROW_BUY_BUTTON, "Buy", UiStyle.ACCENT_COLOR, 24)
buyButton.AnchorPoint = Vector2.new(1, 0.5)
buyButton.Position = UDim2.fromScale(0.97, 0.5)
buyButton.Size = UDim2.fromScale(0.26, 0.76)
addTouchTarget(buyButton, Vector2.new(200, 56))
buyButton.TextXAlignment = Enum.TextXAlignment.Left
buyButton.Visible = false
buyButton.Parent = classRow
local buyPadding = Instance.new("UIPadding")
buyPadding.PaddingLeft = UDim.new(0.08, 0)
buyPadding.Parent = buyButton

local buyPriceLabel = makeLabel(Constants.GACHA_ROLL_PRICE_LABEL, "400", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
buyPriceLabel.AnchorPoint = Vector2.new(1, 0.5)
buyPriceLabel.Position = UDim2.fromScale(0.78, 0.5)
buyPriceLabel.Size = UDim2.fromScale(0.36, 0.8)
buyPriceLabel.TextXAlignment = Enum.TextXAlignment.Right
buyPriceLabel.Parent = buyButton

local buyPriceIcon = Instance.new("ImageLabel")
buyPriceIcon.Name = "PriceIcon"
buyPriceIcon.AnchorPoint = Vector2.new(1, 0.5)
buyPriceIcon.Position = UDim2.fromScale(0.98, 0.5)
buyPriceIcon.Size = UDim2.fromScale(0.18, 0.7)
addAspect(buyPriceIcon, 1)
buyPriceIcon.BackgroundTransparency = 1
buyPriceIcon.Image = Icons.UI.DIAMONDS
buyPriceIcon.Parent = buyButton

-- the reveal: a panel over the whole dialog. A roulette strip of prize
-- tiles slides under a centre pointer and eases onto the winner (the
-- reference game's Lucky Box reveal), then the result reads below and
-- DONE puts the dialog back. The strip cannot be skipped
local reveal = Instance.new("Frame")
reveal.Name = Constants.GACHA_REVEAL_PANEL
reveal.Size = UDim2.fromScale(1, 1)
reveal.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
reveal.BackgroundTransparency = 0.05
reveal.BorderSizePixel = 0
reveal.ZIndex = 10
reveal.Visible = false
reveal.Parent = dialog
addCorner(reveal)

local revealKind = makeLabel(Constants.GACHA_REVEAL_KIND_LABEL, UiStyle.formatTitle("Rolling"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 32)
revealKind.AnchorPoint = Vector2.new(0.5, 0)
revealKind.Position = UDim2.fromScale(0.5, 0.05)
revealKind.Size = UDim2.fromScale(0.8, 0.08)
revealKind.ZIndex = 11
revealKind.Parent = reveal

-- the window clips the strip; the strip is wider than the window by far
-- and is moved by its X offset
local stripWindow = Instance.new("Frame")
stripWindow.Name = Constants.GACHA_REVEAL_STRIP_WINDOW
stripWindow.AnchorPoint = Vector2.new(0.5, 0)
stripWindow.Position = UDim2.fromScale(0.5, 0.16)
stripWindow.Size = UDim2.fromScale(0.92, 0.42)
stripWindow.BackgroundColor3 = UiStyle.PANEL_COLOR
stripWindow.BorderSizePixel = 0
stripWindow.ClipsDescendants = true
stripWindow.ZIndex = 11
stripWindow.Parent = reveal
addCorner(stripWindow)

local strip = Instance.new("Frame")
strip.Name = Constants.GACHA_REVEAL_STRIP
strip.Position = UDim2.fromOffset(0, 0)
strip.Size = UDim2.fromScale(0, 1)
strip.AutomaticSize = Enum.AutomaticSize.X
strip.BackgroundTransparency = 1
strip.ZIndex = 11
strip.Parent = stripWindow

local stripLayout = Instance.new("UIListLayout")
stripLayout.FillDirection = Enum.FillDirection.Horizontal
stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
stripLayout.Padding = UDim.new(0, 8)
stripLayout.Parent = strip

-- a tile is a fifth of the window wide, so about five show at once; the
-- strip is as wide as its tiles, so the manager sets each clone's width
-- in pixels from the window when it builds the strip (the offset here is
-- only what the Explorer shows)
local tile = Instance.new("Frame")
tile.Name = Constants.GACHA_REVEAL_TILE_TEMPLATE
tile.Size = UDim2.new(0, 160, 0.84, 0)
tile.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
tile.BorderSizePixel = 0
tile.ZIndex = 12
tile.Visible = false
tile.Parent = strip
addCorner(tile)

local tileStroke = Instance.new("UIStroke")
tileStroke.Name = "KindStroke"
tileStroke.Thickness = UiStyle.STROKE_PX
tileStroke.Color = UiStyle.ACCENT_COLOR
tileStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
tileStroke.Parent = tile

local tileKind = makeLabel(Constants.GACHA_REVEAL_TILE_KIND_LABEL, UiStyle.formatTitle("Class"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 18)
tileKind.AnchorPoint = Vector2.new(0.5, 0)
tileKind.Position = UDim2.fromScale(0.5, 0.08)
tileKind.Size = UDim2.fromScale(0.9, 0.12)
tileKind.ZIndex = 13
tileKind.Parent = tile

local tileName = makeLabel(Constants.GACHA_REVEAL_TILE_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
tileName.AnchorPoint = Vector2.new(0.5, 0.5)
tileName.Position = UDim2.fromScale(0.5, 0.5)
tileName.Size = UDim2.fromScale(0.9, 0.34)
tileName.TextWrapped = true
tileName.ZIndex = 13
tileName.Parent = tile

local tileOdds = makeLabel(Constants.GACHA_REVEAL_TILE_ODDS_LABEL, "8.6%", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_MUTED_COLOR, 18)
tileOdds.AnchorPoint = Vector2.new(0.5, 1)
tileOdds.Position = UDim2.fromScale(0.5, 0.92)
tileOdds.Size = UDim2.fromScale(0.9, 0.12)
tileOdds.ZIndex = 13
tileOdds.Parent = tile

-- the pointer: a thin accent line down the window's centre, over the strip
local pointer = Instance.new("Frame")
pointer.Name = Constants.GACHA_REVEAL_POINTER
pointer.AnchorPoint = Vector2.new(0.5, 0.5)
pointer.Position = UDim2.fromScale(0.5, 0.5)
pointer.Size = UDim2.new(0, 4, 1, 0)
pointer.BackgroundColor3 = UiStyle.ACCENT_COLOR
pointer.BorderSizePixel = 0
pointer.ZIndex = 14
pointer.Parent = stripWindow

local revealName = makeLabel(Constants.GACHA_REVEAL_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 60)
revealName.AnchorPoint = Vector2.new(0.5, 0)
revealName.Position = UDim2.fromScale(0.5, 0.61)
revealName.Size = UDim2.fromScale(0.8, 0.13)
revealName.ZIndex = 11
revealName.Parent = reveal

local revealDetail = makeLabel(Constants.GACHA_REVEAL_DETAIL_LABEL, "Equip it from the Classes menu", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
revealDetail.AnchorPoint = Vector2.new(0.5, 0)
revealDetail.Position = UDim2.fromScale(0.5, 0.75)
revealDetail.Size = UDim2.fromScale(0.8, 0.07)
revealDetail.TextWrapped = true
revealDetail.ZIndex = 11
revealDetail.Parent = reveal

local doneButton = makeButton(Constants.GACHA_REVEAL_DONE_BUTTON, "Done", UiStyle.ACCENT_COLOR, 28)
doneButton.AnchorPoint = Vector2.new(0.5, 1)
doneButton.Position = UDim2.fromScale(0.5, 0.96)
doneButton.Size = UDim2.fromScale(0.24, 0.1)
addTouchTarget(doneButton, Vector2.new(300, 72))
doneButton.ZIndex = 11
doneButton.Parent = reveal

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("Gacha gui")
return "Gacha gui built"
