-- Rebuilds the lobby "CharacterSheet" ScreenGui under StarterGui (GDD
-- "Character Menu", M37, from docs/mockups/character-sheet-2026-10-12.png).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- lobby place; it replaces any existing copy. Names must match
-- Constants.CHARACTER_SHEET_* / GEAR_CARD_* / SKILL_ROW_* / OFFER_*. Layout
-- follows the GUI standard in CLAUDE.md; fonts and colours come from
-- Shared/UiStyle. ClientCharacterSheetManager clones the gear card, skill
-- row, and offer option templates and fills every label; the templates
-- stay hidden. The designer tunes the live instance in the Explorer and
-- every such change is ported here before any rebuild (the 2026-10-13
-- pass: full-screen insets, Back top-right, taller panels, the card's
-- left slot word over a centred name, square tabs); never rebuild
-- without diffing the live GUI against this script first.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Attributes = require(game.ReplicatedStorage.Shared.Attributes)
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local SoundNames = require(game.ReplicatedStorage.Shared.SoundNames)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before CharacterSheet gui")

local existing = StarterGui:FindFirstChild(Constants.CHARACTER_SHEET_GUI_NAME)
if existing then
	existing:Destroy()
end

local MENU_DISPLAY_ORDER = 5

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

-- height-dominant and parent-scaled: a frame whose width is 0 by design
-- takes its width from its height (FitWithinMaxSize would collapse it)
local function addAspectFromHeight(frame, ratio)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.DominantAxis = Enum.DominantAxis.Height
	constraint.AspectType = Enum.AspectType.ScaleWithParentSize
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
	addTextSizeBounds(label, maxPx)
	return label
end

local function makeButton(name, text, backgroundColor, textColor, maxPx)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = backgroundColor
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = textColor
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	button.AutoButtonColor = true
	addTextSizeBounds(button, maxPx)
	addCorner(button)
	return button
end

-- a square "i" button in a card's corner. Half the touch-target floor
-- (designer, 2026-10-12): it is a help button, not a play action, and at
-- 44 px it crowded the card titles; the one standing exception to the rule
-- `text` is nil for a help note's "i"; a button that opens a reroll's
-- odds says ODDS, because Roblox's paid random items policy wants the odds
-- behind a descriptive word, never a bare (i) icon (2026-10-13), so it is
-- a wider pill
local INFO_BUTTON_MIN_PX = UiStyle.TOUCH_TARGET_MIN_PX / 2
local function makeInfoButton(name, text)
	local isWord = text ~= nil
	local ratio = if isWord then 2.6 else 1
	local button = makeButton(name, if isWord then UiStyle.formatTitle(text) else "i", UiStyle.TEXT_MUTED_COLOR, UiStyle.BACKGROUND_COLOR, 16)
	addAspectFromHeight(button, ratio)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(INFO_BUTTON_MIN_PX * ratio, INFO_BUTTON_MIN_PX)
	constraint.MaxSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX * ratio, UiStyle.TOUCH_TARGET_MIN_PX)
	constraint.Parent = button
	-- a pill: the button helper's own corner, widened, never a second one
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 100)
	end
	return button
end

-- REROLL on the left, the price and the diamond on the right (resources
-- are icons, never words)
local function makeRerollButton(name, isStacked)
	local button = makeButton(name, "", UiStyle.ACCENT_COLOR, UiStyle.TEXT_COLOR, 24)
	-- its own sound in place of the menu click (ClientButtonSoundManager)
	button:SetAttribute(Attributes.BUTTON_SOUND, SoundNames.Sfx.REROLL)
	addTouchTarget(button, Vector2.new(260, 64))
	local label = makeLabel(Constants.REROLL_BUTTON_LABEL, UiStyle.formatTitle("Reroll"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
	local priceLabel = makeLabel(Constants.REROLL_BUTTON_PRICE_LABEL, "10", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
	local priceIcon = Instance.new("ImageLabel")
	priceIcon.Name = Constants.REROLL_BUTTON_PRICE_ICON
	priceIcon.BackgroundTransparency = 1
	priceIcon.Image = Icons.UI.DIAMONDS
	addAspectFromHeight(priceIcon, 1)
	if isStacked then
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, 0.08)
		label.Size = UDim2.fromScale(0.9, 0.4)
		priceLabel.AnchorPoint = Vector2.new(1, 1)
		priceLabel.Position = UDim2.fromScale(0.52, 0.92)
		priceLabel.Size = UDim2.fromScale(0.4, 0.4)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceIcon.AnchorPoint = Vector2.new(0, 1)
		priceIcon.Position = UDim2.fromScale(0.56, 0.92)
		priceIcon.Size = UDim2.fromScale(0, 0.4)
	else
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.fromScale(0.05, 0.5)
		label.Size = UDim2.fromScale(0.5, 0.7)
		label.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.AnchorPoint = Vector2.new(1, 0.5)
		priceLabel.Position = UDim2.fromScale(0.78, 0.5)
		priceLabel.Size = UDim2.fromScale(0.25, 0.7)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceIcon.AnchorPoint = Vector2.new(1, 0.5)
		priceIcon.Position = UDim2.fromScale(0.96, 0.5)
		priceIcon.Size = UDim2.fromScale(0, 0.7)
	end
	label.Parent = button
	priceLabel.Parent = button
	priceIcon.Parent = button
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.CHARACTER_SHEET_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- the sheet covers the whole screen, notch and home bar included (designer, 2026-10-13)
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.Size = UDim2.fromScale(1, 1)
dialog.BackgroundTransparency = 1
dialog.Parent = gui

-- header, as on the select menu
local backButton = makeButton(Constants.CHARACTER_SELECT_BACK_BUTTON, UiStyle.formatTitle("Back"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, 40)
-- top-right (designer, 2026-10-13)
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.fromScale(0.945, 0.03)
backButton.Size = UDim2.fromScale(0.2, 0.07)
addAspectFromHeight(backButton, 5)
addTouchTarget(backButton, Vector2.new(280, 56))
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
walletIcon.Size = UDim2.fromScale(0, 0.8)
addAspectFromHeight(walletIcon, 1)
walletIcon.BackgroundTransparency = 1
walletIcon.Image = Icons.UI.DIAMONDS
walletIcon.Parent = wallet

local walletAmount = makeLabel(Constants.HUD_DIAMOND_AMOUNT_LABEL, "0", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 40)
walletAmount.AnchorPoint = Vector2.new(0, 0.5)
walletAmount.Position = UDim2.fromScale(0.26, 0.5)
walletAmount.Size = UDim2.fromScale(0.7, 0.8)
walletAmount.Parent = wallet

-- left panel: the character
local leftPanel = Instance.new("Frame")
leftPanel.Name = Constants.CHARACTER_SHEET_LEFT_PANEL
leftPanel.Position = UDim2.fromScale(0.055, 0.12)
-- shorter than the right panel: the REROLL ODDS button sits under it (designer, 2026-10-13)
leftPanel.Size = UDim2.fromScale(0.31, 0.77)
leftPanel.BackgroundColor3 = UiStyle.PANEL_COLOR
leftPanel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
leftPanel.BorderSizePixel = 0
leftPanel.Parent = dialog
addCorner(leftPanel)

local nameLabel = makeLabel(Constants.CHARACTER_SHEET_NAME_LABEL, UiStyle.formatTitle("Character 1"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 44)
nameLabel.Position = UDim2.fromScale(0.05, 0.03)
nameLabel.Size = UDim2.fromScale(0.62, 0.1)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = leftPanel

-- the rename box sits where the name is and shows only while renaming
local nameBox = Instance.new("TextBox")
nameBox.Name = Constants.CHARACTER_SHEET_NAME_BOX
nameBox.Position = UDim2.fromScale(0.05, 0.03)
nameBox.Size = UDim2.fromScale(0.62, 0.1)
nameBox.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
nameBox.BorderSizePixel = 0
nameBox.Text = ""
nameBox.PlaceholderText = "Name"
nameBox.TextColor3 = UiStyle.TEXT_COLOR
nameBox.TextScaled = true
nameBox.FontFace = UiStyle.TITLE_FONT
nameBox.ClearTextOnFocus = false
nameBox.Visible = false
addTextSizeBounds(nameBox, 40)
addCorner(nameBox)
nameBox.Parent = leftPanel

-- the mock-up's pencil; the title font has no pencil glyph, so the
-- button reads EDIT until the icon art lands
local renameButton = makeButton(Constants.CHARACTER_SHEET_RENAME_BUTTON, UiStyle.formatTitle("Rename"), UiStyle.BACKGROUND_COLOR, UiStyle.TEXT_COLOR, 24)
renameButton.AnchorPoint = Vector2.new(1, 0)
renameButton.Position = UDim2.fromScale(0.95, 0.03)
renameButton.Size = UDim2.fromScale(0.26, 0.1)
addTouchTarget(renameButton, Vector2.new(160, 56))
renameButton.Parent = leftPanel

local avatar = Instance.new("ViewportFrame")
avatar.Name = Constants.CHARACTER_CARD_AVATAR
avatar.AnchorPoint = Vector2.new(0.5, 0)
avatar.Position = UDim2.fromScale(0.5, 0.16)
avatar.Size = UDim2.fromScale(0.8, 0.54)
avatar.BackgroundTransparency = 1
avatar.Ambient = Color3.new(1, 1, 1)
avatar.LightColor = Color3.new(1, 1, 1)
avatar.Parent = leftPanel

local rankLabel = makeLabel(Constants.CHARACTER_CARD_RANK_LABEL, UiStyle.formatTitle("Rank 1 - Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 36)
rankLabel.AnchorPoint = Vector2.new(0.5, 0)
rankLabel.Position = UDim2.fromScale(0.5, 0.78)
rankLabel.Size = UDim2.fromScale(0.8, 0.08)
rankLabel.Parent = leftPanel

-- what Rank is, once (designer, 2026-10-12): a toast off this button
local rankInfo = makeInfoButton(Constants.CHARACTER_SHEET_RANK_INFO_BUTTON)
rankInfo.AnchorPoint = Vector2.new(0, 0.5)
rankInfo.Position = UDim2.fromScale(0.91, 0.82)
rankInfo.Size = UDim2.fromScale(0, 0.05)
rankInfo.Parent = leftPanel

local nightsLabel = makeLabel(Constants.CHARACTER_CARD_NIGHTS_LABEL, UiStyle.formatTitle("Nights survived: 0"), UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
nightsLabel.AnchorPoint = Vector2.new(0.5, 0)
nightsLabel.Position = UDim2.fromScale(0.5, 0.87)
nightsLabel.Size = UDim2.fromScale(0.9, 0.06)
nightsLabel.Parent = leftPanel

-- right panel: the tabs and their pages
local rightPanel = Instance.new("Frame")
rightPanel.Name = Constants.CHARACTER_SHEET_RIGHT_PANEL
rightPanel.Position = UDim2.fromScale(0.38, 0.12)
rightPanel.Size = UDim2.fromScale(0.565, 0.85)
rightPanel.BackgroundColor3 = UiStyle.PANEL_COLOR
rightPanel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
rightPanel.BorderSizePixel = 0
rightPanel.Parent = dialog
addCorner(rightPanel)

-- the selected tab is the accent yellow of every other button, the other
-- the panel colour (designer, 2026-10-13); the manager swaps them
local loadoutTab = makeButton(Constants.CHARACTER_SHEET_LOADOUT_TAB, UiStyle.formatTitle("Loadout"), UiStyle.ACCENT_COLOR, UiStyle.TEXT_COLOR, 36)
loadoutTab.Position = UDim2.fromScale(0, 0)
loadoutTab.Size = UDim2.fromScale(0.5, 0.085)
-- square tabs (designer, 2026-10-13)
loadoutTab:FindFirstChildOfClass("UICorner"):Destroy()
loadoutTab.Parent = rightPanel

local cosmeticsTab = makeButton(Constants.CHARACTER_SHEET_COSMETICS_TAB, UiStyle.formatTitle("Cosmetics"), UiStyle.PANEL_COLOR, UiStyle.TEXT_COLOR, 36)
cosmeticsTab.Position = UDim2.fromScale(0.5, 0)
cosmeticsTab.Size = UDim2.fromScale(0.5, 0.085)
cosmeticsTab:FindFirstChildOfClass("UICorner"):Destroy()
cosmeticsTab.Parent = rightPanel

-- the one REROLL ODDS button, under the left panel (designer, 2026-10-13,
-- replacing an ODDS pill on every card and row): every roll's odds in one
-- dialog, on the same screen as every REROLL
local oddsButton = makeButton(Constants.CHARACTER_SHEET_ODDS_BUTTON, UiStyle.formatTitle("Reroll odds"), UiStyle.ODDS_BUTTON_COLOR, UiStyle.TEXT_COLOR, 40)
oddsButton.Position = UDim2.fromScale(0.055, 0.9)
oddsButton.Size = UDim2.fromScale(0.31, 0.07)
oddsButton.Parent = dialog

local loadoutPage = Instance.new("Frame")
loadoutPage.Name = Constants.CHARACTER_SHEET_LOADOUT_PAGE
loadoutPage.Position = UDim2.fromScale(0.02, 0.105)
loadoutPage.Size = UDim2.fromScale(0.96, 0.875)
loadoutPage.BackgroundTransparency = 1
loadoutPage.Parent = rightPanel

local cosmeticsPage = Instance.new("Frame")
cosmeticsPage.Name = Constants.CHARACTER_SHEET_COSMETICS_PAGE
cosmeticsPage.Position = UDim2.fromScale(0.02, 0.105)
cosmeticsPage.Size = UDim2.fromScale(0.96, 0.875)
cosmeticsPage.BackgroundTransparency = 1
cosmeticsPage.Visible = false
cosmeticsPage.Parent = rightPanel

-- the COSMETICS tab (designer's mock-up, 2026-10-13, replacing the hat
-- grid of 2026-10-12): a vertical scrolling list with one row per
-- cosmetic slot, cloned from a hidden template. A row is a square type
-- box (the slot's picture and name) beside a horizontal scrolling strip
-- of picture-only item buttons; the equipped item wears the accent stroke
local cosmeticRows = Instance.new("ScrollingFrame")
cosmeticRows.Name = Constants.CHARACTER_SHEET_COSMETIC_ROWS
cosmeticRows.Size = UDim2.fromScale(1, 1)
cosmeticRows.BackgroundTransparency = 1
cosmeticRows.BorderSizePixel = 0
cosmeticRows.ScrollBarThickness = 6
cosmeticRows.ScrollingDirection = Enum.ScrollingDirection.Y
cosmeticRows.CanvasSize = UDim2.fromScale(0, 0)
cosmeticRows.AutomaticCanvasSize = Enum.AutomaticSize.Y
cosmeticRows.Parent = cosmeticsPage

local cosmeticRowLayout = Instance.new("UIListLayout")
cosmeticRowLayout.FillDirection = Enum.FillDirection.Vertical
cosmeticRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
cosmeticRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
cosmeticRowLayout.Padding = UDim.new(0.03, 0)
cosmeticRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
cosmeticRowLayout.Parent = cosmeticRows

local cosmeticRow = Instance.new("Frame")
cosmeticRow.Name = Constants.CHARACTER_SHEET_COSMETIC_ROW_TEMPLATE
-- a little under a third of the page, so three rows show before scrolling
cosmeticRow.Size = UDim2.fromScale(0.98, 0.31)
cosmeticRow.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
cosmeticRow.BorderSizePixel = 0
cosmeticRow.Visible = false
cosmeticRow.Parent = cosmeticRows
addCorner(cosmeticRow)

local typeBox = Instance.new("Frame")
typeBox.Name = Constants.COSMETIC_ROW_TYPE_BOX
typeBox.AnchorPoint = Vector2.new(0, 0.5)
typeBox.Position = UDim2.fromScale(0.01, 0.5)
typeBox.Size = UDim2.fromScale(0, 0.92)
addAspectFromHeight(typeBox, 1)
typeBox.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
typeBox.BorderSizePixel = 0
typeBox.Parent = cosmeticRow
addCorner(typeBox)

local typeIcon = Instance.new("ImageLabel")
typeIcon.Name = Constants.COSMETIC_ROW_TYPE_ICON
typeIcon.AnchorPoint = Vector2.new(0.5, 0)
typeIcon.Position = UDim2.fromScale(0.5, 0.06)
typeIcon.Size = UDim2.fromScale(0.7, 0.6)
typeIcon.BackgroundTransparency = 1
typeIcon.ScaleType = Enum.ScaleType.Fit
typeIcon.Parent = typeBox

local typeName = makeLabel(Constants.COSMETIC_ROW_TYPE_LABEL, UiStyle.formatTitle("Pick Axe"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 24)
typeName.AnchorPoint = Vector2.new(0.5, 1)
typeName.Position = UDim2.fromScale(0.5, 0.95)
typeName.Size = UDim2.fromScale(0.92, 0.2)
typeName.Parent = typeBox

-- the strip: it starts after the square type box, which is as wide as
-- the row is tall, so its left edge is set by the manager from the box's
-- measured width (the one place a layout number is computed, because a
-- scale cannot say "the height, in width")
local items = Instance.new("ScrollingFrame")
items.Name = Constants.COSMETIC_ROW_ITEMS
items.AnchorPoint = Vector2.new(1, 0.5)
items.Position = UDim2.fromScale(0.99, 0.5)
items.Size = UDim2.fromScale(0.72, 0.92)
items.BackgroundTransparency = 1
items.BorderSizePixel = 0
items.ScrollBarThickness = 6
items.ScrollingDirection = Enum.ScrollingDirection.X
items.CanvasSize = UDim2.fromScale(0, 0)
items.AutomaticCanvasSize = Enum.AutomaticSize.X
items.Parent = cosmeticRow

-- the strip clips at its edge, so the selected stroke needs this much
-- room on every side (designer, 2026-10-13: the first square was cut off)
local itemPadding = Instance.new("UIPadding")
itemPadding.PaddingLeft = UDim.new(0, UiStyle.STROKE_PX * 3)
itemPadding.PaddingRight = UDim.new(0, UiStyle.STROKE_PX * 3)
itemPadding.PaddingTop = UDim.new(0, UiStyle.STROKE_PX * 3)
itemPadding.PaddingBottom = UDim.new(0, UiStyle.STROKE_PX * 3)
itemPadding.Parent = items

local itemLayout = Instance.new("UIListLayout")
itemLayout.FillDirection = Enum.FillDirection.Horizontal
itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
itemLayout.VerticalAlignment = Enum.VerticalAlignment.Center
itemLayout.Padding = UDim.new(0.03, 0)
itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
itemLayout.Parent = items

local itemButton = Instance.new("ImageButton")
itemButton.Name = Constants.COSMETIC_ROW_ITEM_TEMPLATE
itemButton.Size = UDim2.fromScale(0, 0.84)
addAspectFromHeight(itemButton, 1)
-- the odds button's grey (designer, 2026-10-13; white before)
itemButton.BackgroundColor3 = UiStyle.ODDS_BUTTON_COLOR
itemButton.BorderSizePixel = 0
itemButton.ScaleType = Enum.ScaleType.Fit
itemButton.AutoButtonColor = true
itemButton.Visible = false
addTouchTarget(itemButton, Vector2.new(160, 160))
itemButton.Parent = items
addCorner(itemButton)

local itemStroke = Instance.new("UIStroke")
itemStroke.Name = Constants.COSMETIC_ITEM_SELECTED_STROKE
itemStroke.Color = UiStyle.ACCENT_COLOR
itemStroke.Thickness = UiStyle.STROKE_PX * 2
itemStroke.Enabled = false
itemStroke.Parent = itemButton

-- gear row: four cards side by side
local gearRow = Instance.new("Frame")
gearRow.Name = Constants.CHARACTER_SHEET_GEAR_ROW
gearRow.Size = UDim2.fromScale(1, 0.55)
gearRow.BackgroundTransparency = 1
gearRow.Parent = loadoutPage

local gearLayout = Instance.new("UIListLayout")
gearLayout.FillDirection = Enum.FillDirection.Horizontal
gearLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gearLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gearLayout.Padding = UDim.new(0.02, 0)
gearLayout.SortOrder = Enum.SortOrder.LayoutOrder
gearLayout.Parent = gearRow

local gearCard = Instance.new("Frame")
gearCard.Name = Constants.CHARACTER_SHEET_GEAR_CARD_TEMPLATE
gearCard.Size = UDim2.fromScale(0.235, 1)
gearCard.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
gearCard.BorderSizePixel = 0
gearCard.Visible = false
gearCard.Parent = gearRow
addCorner(gearCard)

local slotLabel = makeLabel(Constants.GEAR_CARD_SLOT_LABEL, UiStyle.formatTitle("Post"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
-- the two title lines leave the right edge to the info button, which sits
-- in line with them (designer, 2026-10-12)
slotLabel.AnchorPoint = Vector2.new(0, 0)
slotLabel.Position = UDim2.fromScale(0.15, 0.03)
slotLabel.Size = UDim2.fromScale(0.7, 0.12)
slotLabel.TextXAlignment = Enum.TextXAlignment.Left
slotLabel.Parent = gearCard

-- the kind's name and its picture are buttons: tapping either opens the
-- stats page (designer, 2026-10-13); they look like the label and image
-- they replaced
local kindLabel = makeButton(Constants.GEAR_CARD_KIND_LABEL, UiStyle.formatTitle("Machine Gun I"), UiStyle.TEXT_COLOR, UiStyle.TEXT_COLOR, 22)
kindLabel.BackgroundTransparency = 1
kindLabel.AutoButtonColor = false
kindLabel.TextTruncate = Enum.TextTruncate.AtEnd
-- the slot word sits left, the name centred under it (designer, 2026-10-13)
kindLabel.AnchorPoint = Vector2.new(0.5, 0)
kindLabel.Position = UDim2.fromScale(0.5, 0.17)
kindLabel.Size = UDim2.fromScale(0.7, 0.1)
kindLabel.Parent = gearCard

local picture = Instance.new("ImageButton")
picture.Name = Constants.GEAR_CARD_PICTURE
picture.AutoButtonColor = false
picture.AnchorPoint = Vector2.new(0.5, 0)
picture.Position = UDim2.fromScale(0.5, 0.27)
picture.Size = UDim2.fromScale(0.8, 0.36)
picture.BackgroundTransparency = 1
picture.ScaleType = Enum.ScaleType.Fit
picture.Parent = gearCard

-- the rarity word under the picture (Common to Legendary, never a star
-- rating; designer, 2026-10-12)
local rarityLabel = makeLabel(Constants.GEAR_CARD_RARITY_LABEL, UiStyle.formatTitle("Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
rarityLabel.Position = UDim2.fromScale(0.5, 0.63)
rarityLabel.Size = UDim2.fromScale(0.9, 0.1)
rarityLabel.Parent = gearCard

local gearReroll = makeRerollButton(Constants.GEAR_CARD_REROLL_BUTTON, false)
gearReroll.AnchorPoint = Vector2.new(0.5, 1)
gearReroll.Position = UDim2.fromScale(0.5, 0.96)
gearReroll.Size = UDim2.fromScale(0.9, 0.15)
gearReroll.Parent = gearCard

-- a heading so the rows read as skills (designer, 2026-10-12), then
-- three stacked rows
local skillsHeading = makeLabel(Constants.CHARACTER_SHEET_SKILLS_HEADING, UiStyle.formatTitle("Skills"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
skillsHeading.Position = UDim2.fromScale(0.01, 0.61)
skillsHeading.Size = UDim2.fromScale(0.5, 0.06)
skillsHeading.TextXAlignment = Enum.TextXAlignment.Left
skillsHeading.Parent = loadoutPage

local skillRows = Instance.new("Frame")
skillRows.Name = Constants.CHARACTER_SHEET_SKILL_ROWS
skillRows.Position = UDim2.fromScale(0, 0.66)
skillRows.Size = UDim2.fromScale(1, 0.35)
skillRows.BackgroundTransparency = 1
skillRows.Parent = loadoutPage

local skillLayout = Instance.new("UIListLayout")
skillLayout.FillDirection = Enum.FillDirection.Vertical
skillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
skillLayout.VerticalAlignment = Enum.VerticalAlignment.Top
skillLayout.Padding = UDim.new(0.03, 0)
skillLayout.SortOrder = Enum.SortOrder.LayoutOrder
skillLayout.Parent = skillRows

local skillRow = Instance.new("Frame")
skillRow.Name = Constants.CHARACTER_SHEET_SKILL_ROW_TEMPLATE
skillRow.Size = UDim2.fromScale(1, 0.31)
skillRow.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
skillRow.BorderSizePixel = 0
skillRow.Visible = false
skillRow.Parent = skillRows
addCorner(skillRow)

local badge = Instance.new("Frame")
badge.Name = Constants.SKILL_ROW_BADGE
badge.AnchorPoint = Vector2.new(0, 0.5)
badge.Position = UDim2.fromScale(0.015, 0.5)
badge.Size = UDim2.fromScale(0, 0.76)
addAspectFromHeight(badge, 1)
badge.BackgroundColor3 = UiStyle.PANEL_COLOR
badge.BorderSizePixel = 0
badge.Parent = skillRow
addCorner(badge, 100)

local badgeNumber = makeLabel(Constants.SKILL_ROW_BADGE_LABEL, "1", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 36)
badgeNumber.AnchorPoint = Vector2.new(0.5, 0.5)
badgeNumber.Position = UDim2.fromScale(0.5, 0.5)
badgeNumber.Size = UDim2.fromScale(0.7, 0.7)
badgeNumber.Parent = badge

local skillName = makeLabel(Constants.SKILL_ROW_NAME_LABEL, UiStyle.formatTitle("Gold Digger - Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
skillName.Position = UDim2.fromScale(0.14, 0.12)
skillName.Size = UDim2.fromScale(0.52, 0.36)
skillName.TextXAlignment = Enum.TextXAlignment.Left
skillName.Parent = skillRow

local skillDescription = makeLabel(Constants.SKILL_ROW_DESCRIPTION_LABEL, "Start a run with 20 Gold Bars", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
skillDescription.Position = UDim2.fromScale(0.14, 0.52)
skillDescription.Size = UDim2.fromScale(0.52, 0.32)
skillDescription.TextXAlignment = Enum.TextXAlignment.Left
skillDescription.Parent = skillRow

local skillReroll = makeRerollButton(Constants.SKILL_ROW_REROLL_BUTTON, true)
skillReroll.AnchorPoint = Vector2.new(1, 0.5)
skillReroll.Position = UDim2.fromScale(0.985, 0.5)
skillReroll.Size = UDim2.fromScale(0.17, 0.8)
skillReroll.Parent = skillRow

local lockIcon = makeLabel(Constants.SKILL_ROW_LOCK_ICON, utf8.char(0x1F512), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
lockIcon.AnchorPoint = Vector2.new(1, 0.5)
lockIcon.Position = UDim2.fromScale(0.97, 0.5)
lockIcon.Size = UDim2.fromScale(0, 0.7)
addAspectFromHeight(lockIcon, 1)
lockIcon.Visible = false
lockIcon.Parent = skillRow

-- the roll screen over everything (designer's layout of 2026-10-13):
-- CURRENT and NEW boxes on the left with Undo and Accept right under
-- them, and a stats panel on the right that lists every stat as the
-- current value then the candidate's, with the Rank line at its foot
local offerDialog = Instance.new("Frame")
offerDialog.Name = Constants.CHARACTER_SHEET_OFFER_DIALOG
offerDialog.AnchorPoint = Vector2.new(0.5, 0.5)
offerDialog.Position = UDim2.fromScale(0.5, 0.5)
offerDialog.Size = UDim2.fromScale(0.78, 0.72)
addMaxSize(offerDialog, Vector2.new(1100, 720))
offerDialog.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
offerDialog.BorderSizePixel = 0
offerDialog.Visible = false
offerDialog.ZIndex = 10
offerDialog.Parent = dialog
addCorner(offerDialog)
local offerStroke = Instance.new("UIStroke")
offerStroke.Thickness = UiStyle.STROKE_PX
offerStroke.Color = UiStyle.ACCENT_COLOR
offerStroke.Parent = offerDialog

local offerTitle = makeLabel(Constants.OFFER_DIALOG_TITLE, UiStyle.formatTitle("New roll"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 40)
offerTitle.AnchorPoint = Vector2.new(0.5, 0)
offerTitle.Position = UDim2.fromScale(0.5, 0.03)
offerTitle.Size = UDim2.fromScale(0.9, 0.09)
offerTitle.ZIndex = 11
offerTitle.Parent = offerDialog

-- one box: a header word, the icon (with a large label over it for the
-- flipping numeral or name), then the name and a detail line
local function makeOfferBox(name, headerText, positionX)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0.5, 0)
	-- down to the buttons, which sit level with the stats panel's foot
	-- (designer, 2026-10-13)
	box.Position = UDim2.fromScale(positionX, 0.15)
	box.Size = UDim2.fromScale(0.27, 0.65)
	box.BackgroundColor3 = UiStyle.PANEL_COLOR
	box.BorderSizePixel = 0
	box.ZIndex = 11
	box.Parent = offerDialog
	addCorner(box)

	local header = makeLabel(Constants.OFFER_BOX_HEADER, UiStyle.formatTitle(headerText), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 30)
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.fromScale(0.5, 0.03)
	header.Size = UDim2.fromScale(0.9, 0.09)
	header.ZIndex = 12
	header.Parent = box

	-- the icon takes most of the box (designer, 2026-10-13: it read too small)
	local icon = Instance.new("ImageLabel")
	icon.Name = Constants.OFFER_BOX_ICON
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.13)
	icon.Size = UDim2.fromScale(0.92, 0.56)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 12
	icon.Parent = box

	local spin = makeLabel(Constants.OFFER_BOX_SPIN_LABEL, "", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 72)
	spin.AnchorPoint = Vector2.new(0.5, 0)
	spin.Position = UDim2.fromScale(0.5, 0.13)
	spin.Size = UDim2.fromScale(0.9, 0.56)
	spin.ZIndex = 13
	spin.Parent = box
	local spinStroke = Instance.new("UIStroke")
	spinStroke.Thickness = UiStyle.STROKE_PX
	spinStroke.Color = UiStyle.BACKGROUND_COLOR
	spinStroke.Parent = spin

	local nameLabel = makeLabel(Constants.OFFER_BOX_NAME_LABEL, UiStyle.formatTitle("Rifle I"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 32)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	-- the name and the rarity line sit together under the icon
	nameLabel.Position = UDim2.fromScale(0.5, 0.72)
	nameLabel.Size = UDim2.fromScale(0.9, 0.11)
	nameLabel.ZIndex = 12
	nameLabel.Parent = box

	local detail = makeLabel(Constants.OFFER_BOX_DETAIL_LABEL, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	detail.AnchorPoint = Vector2.new(0.5, 0)
	detail.Position = UDim2.fromScale(0.5, 0.83)
	detail.Size = UDim2.fromScale(0.9, 0.12)
	detail.TextWrapped = true
	detail.ZIndex = 12
	detail.Parent = box
	return box
end

makeOfferBox(Constants.OFFER_CURRENT_BOX, "Current", 0.175)
makeOfferBox(Constants.OFFER_NEW_BOX, "New", 0.465)

-- Undo on the left in red, Accept on the right in green (designer,
-- 2026-10-12), right under the boxes (2026-10-13)
local undoButton = makeButton(Constants.OFFER_UNDO_BUTTON, UiStyle.formatTitle("Undo"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, 32)
undoButton.AnchorPoint = Vector2.new(0.5, 1)
undoButton.Position = UDim2.fromScale(0.175, 0.95)
undoButton.Size = UDim2.fromScale(0.27, 0.12)
addTouchTarget(undoButton, Vector2.new(300, 72))
undoButton.ZIndex = 11
undoButton.Parent = offerDialog

local keepButton = makeButton(Constants.OFFER_KEEP_BUTTON, UiStyle.formatTitle("Accept"), UiStyle.POSITIVE_COLOR, UiStyle.TEXT_COLOR, 32)
keepButton.AnchorPoint = Vector2.new(0.5, 1)
keepButton.Position = UDim2.fromScale(0.465, 0.95)
keepButton.Size = UDim2.fromScale(0.27, 0.12)
addTouchTarget(keepButton, Vector2.new(300, 72))
keepButton.ZIndex = 11
keepButton.Parent = offerDialog

-- the stats panel: the item's numbers as they are and as the candidate
-- would make them, one row each, green or red by direction; the Rank
-- line (designer, 2026-10-12) moved to its foot
local statsPanel = Instance.new("Frame")
statsPanel.Name = Constants.OFFER_STATS_PANEL
statsPanel.AnchorPoint = Vector2.new(0, 0)
statsPanel.Position = UDim2.fromScale(0.63, 0.15)
statsPanel.Size = UDim2.fromScale(0.34, 0.8)
statsPanel.BackgroundColor3 = UiStyle.PANEL_COLOR
statsPanel.BorderSizePixel = 0
statsPanel.ZIndex = 11
statsPanel.Parent = offerDialog
addCorner(statsPanel)

local statsHeader = makeLabel("Header", UiStyle.formatTitle("Stats"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 30)
statsHeader.AnchorPoint = Vector2.new(0.5, 0)
statsHeader.Position = UDim2.fromScale(0.5, 0.03)
statsHeader.Size = UDim2.fromScale(0.9, 0.08)
statsHeader.ZIndex = 12
statsHeader.Parent = statsPanel

local statRows = Instance.new("Frame")
statRows.Name = Constants.OFFER_STAT_ROWS
statRows.AnchorPoint = Vector2.new(0.5, 0)
statRows.Position = UDim2.fromScale(0.5, 0.13)
statRows.Size = UDim2.fromScale(0.92, 0.7)
statRows.BackgroundTransparency = 1
statRows.ZIndex = 12
statRows.Parent = statsPanel

local statRowLayout = Instance.new("UIListLayout")
statRowLayout.FillDirection = Enum.FillDirection.Vertical
statRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
statRowLayout.Padding = UDim.new(0.015, 0)
statRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
statRowLayout.Parent = statRows

local statRow = Instance.new("Frame")
statRow.Name = Constants.OFFER_STAT_ROW_TEMPLATE
statRow.Size = UDim2.fromScale(1, 0.11)
statRow.BackgroundTransparency = 1
statRow.Visible = false
statRow.ZIndex = 12
statRow.Parent = statRows

local statLabel = makeLabel(Constants.OFFER_STAT_ROW_LABEL, UiStyle.formatTitle("Damage"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
statLabel.AnchorPoint = Vector2.new(0, 0.5)
statLabel.Position = UDim2.fromScale(0, 0.5)
statLabel.Size = UDim2.fromScale(0.44, 0.9)
statLabel.TextXAlignment = Enum.TextXAlignment.Left
statLabel.ZIndex = 13
statLabel.Parent = statRow

local statCurrent = makeLabel(Constants.OFFER_STAT_ROW_CURRENT, "60", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
statCurrent.AnchorPoint = Vector2.new(1, 0.5)
statCurrent.Position = UDim2.fromScale(0.68, 0.5)
statCurrent.Size = UDim2.fromScale(0.22, 0.9)
statCurrent.TextXAlignment = Enum.TextXAlignment.Right
statCurrent.ZIndex = 13
statCurrent.Parent = statRow

local statArrow = makeLabel("Arrow", ">>", UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 20)
statArrow.AnchorPoint = Vector2.new(0.5, 0.5)
statArrow.Position = UDim2.fromScale(0.73, 0.5)
statArrow.Size = UDim2.fromScale(0.08, 0.7)
statArrow.ZIndex = 13
statArrow.Parent = statRow

local statNew = makeLabel(Constants.OFFER_STAT_ROW_NEW, "72", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, 22)
statNew.AnchorPoint = Vector2.new(1, 0.5)
statNew.Position = UDim2.fromScale(1, 0.5)
statNew.Size = UDim2.fromScale(0.22, 0.9)
statNew.TextXAlignment = Enum.TextXAlignment.Right
statNew.ZIndex = 13
statNew.Parent = statRow

local offerRank = makeLabel(Constants.OFFER_RANK_LABEL, UiStyle.formatTitle("Character rank:  1  >>  2"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
offerRank.AnchorPoint = Vector2.new(0.5, 1)
offerRank.Position = UDim2.fromScale(0.5, 0.96)
offerRank.Size = UDim2.fromScale(0.92, 0.09)
offerRank.ZIndex = 12
offerRank.Parent = statsPanel
-- the info dialog over everything (2026-10-13): a title, an optional
-- picture, rows of label and value cloned from one template (a reroll's
-- odds by rarity, or a gear kind's stats), a note line, and Close
local infoDialog = Instance.new("Frame")
infoDialog.Name = Constants.CHARACTER_SHEET_INFO_DIALOG
infoDialog.AnchorPoint = Vector2.new(0.5, 0.5)
infoDialog.Position = UDim2.fromScale(0.5, 0.5)
infoDialog.Size = UDim2.fromScale(0.42, 0.7)
addMaxSize(infoDialog, Vector2.new(560, 640))
infoDialog.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
infoDialog.BorderSizePixel = 0
infoDialog.Visible = false
infoDialog.ZIndex = 20
infoDialog.Parent = dialog
addCorner(infoDialog)
local infoStroke = Instance.new("UIStroke")
infoStroke.Thickness = UiStyle.STROKE_PX
infoStroke.Color = UiStyle.ACCENT_COLOR
infoStroke.Parent = infoDialog

local infoTitle = makeLabel(Constants.INFO_DIALOG_TITLE, UiStyle.formatTitle("Reroll odds"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 36)
infoTitle.AnchorPoint = Vector2.new(0.5, 0)
infoTitle.Position = UDim2.fromScale(0.5, 0.03)
infoTitle.Size = UDim2.fromScale(0.9, 0.1)
infoTitle.ZIndex = 21
infoTitle.Parent = infoDialog

local infoPicture = Instance.new("ImageLabel")
infoPicture.Name = Constants.INFO_DIALOG_PICTURE
infoPicture.AnchorPoint = Vector2.new(0.5, 0)
infoPicture.Position = UDim2.fromScale(0.5, 0.14)
infoPicture.Size = UDim2.fromScale(0.5, 0.22)
infoPicture.BackgroundTransparency = 1
infoPicture.ScaleType = Enum.ScaleType.Fit
infoPicture.ZIndex = 21
infoPicture.Parent = infoDialog

-- the rows start under the picture; with no picture the manager moves
-- them up into its place
-- a scrolling list (designer, 2026-10-13) so a longer table (the two odds
-- tables, more rarities one day) scrolls instead of shrinking its rows
local infoRows = Instance.new("ScrollingFrame")
infoRows.Name = Constants.INFO_DIALOG_ROWS
infoRows.AnchorPoint = Vector2.new(0.5, 0)
infoRows.Position = UDim2.fromScale(0.5, 0.38)
infoRows.Size = UDim2.fromScale(0.9, 0.4)
infoRows.BackgroundTransparency = 1
infoRows.BorderSizePixel = 0
infoRows.ScrollBarThickness = 6
infoRows.ScrollingDirection = Enum.ScrollingDirection.Y
infoRows.CanvasSize = UDim2.fromScale(0, 0)
infoRows.AutomaticCanvasSize = Enum.AutomaticSize.Y
infoRows.ZIndex = 21
infoRows.Parent = infoDialog

local infoRowLayout = Instance.new("UIListLayout")
infoRowLayout.FillDirection = Enum.FillDirection.Vertical
infoRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
infoRowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
infoRowLayout.Padding = UDim.new(0.02, 0)
infoRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
infoRowLayout.Parent = infoRows

local infoRow = Instance.new("Frame")
infoRow.Name = Constants.INFO_DIALOG_ROW_TEMPLATE
infoRow.Size = UDim2.fromScale(1, 0.14)
infoRow.BackgroundColor3 = UiStyle.PANEL_COLOR
infoRow.BorderSizePixel = 0
infoRow.Visible = false
infoRow.ZIndex = 21
infoRow.Parent = infoRows
addCorner(infoRow)

local infoRowLabel = makeLabel(Constants.INFO_ROW_LABEL, UiStyle.formatTitle("Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 24)
infoRowLabel.AnchorPoint = Vector2.new(0, 0.5)
infoRowLabel.Position = UDim2.fromScale(0.04, 0.5)
infoRowLabel.Size = UDim2.fromScale(0.6, 0.7)
infoRowLabel.TextXAlignment = Enum.TextXAlignment.Left
infoRowLabel.ZIndex = 22
infoRowLabel.Parent = infoRow

local infoRowValue = makeLabel(Constants.INFO_ROW_VALUE, "20%", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, 24)
infoRowValue.AnchorPoint = Vector2.new(1, 0.5)
infoRowValue.Position = UDim2.fromScale(0.96, 0.5)
infoRowValue.Size = UDim2.fromScale(0.32, 0.7)
infoRowValue.TextXAlignment = Enum.TextXAlignment.Right
infoRowValue.ZIndex = 22
infoRowValue.Parent = infoRow

local infoNote = makeLabel(Constants.INFO_DIALOG_NOTE, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
infoNote.AnchorPoint = Vector2.new(0.5, 1)
infoNote.Position = UDim2.fromScale(0.5, 0.84)
infoNote.Size = UDim2.fromScale(0.9, 0.08)
infoNote.TextWrapped = true
infoNote.ZIndex = 21
infoNote.Parent = infoDialog

local infoClose = makeButton(Constants.INFO_DIALOG_CLOSE_BUTTON, UiStyle.formatTitle("Close"), UiStyle.ACCENT_COLOR, UiStyle.TEXT_COLOR, 28)
infoClose.AnchorPoint = Vector2.new(0.5, 1)
infoClose.Position = UDim2.fromScale(0.5, 0.96)
infoClose.Size = UDim2.fromScale(0.4, 0.1)
addTouchTarget(infoClose, Vector2.new(260, 64))
infoClose.ZIndex = 21
infoClose.Parent = infoDialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("CharacterSheet gui")
return "CharacterSheet gui built"
