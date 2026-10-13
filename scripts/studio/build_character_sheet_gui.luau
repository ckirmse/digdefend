-- Rebuilds the lobby "CharacterSheet" ScreenGui under StarterGui (GDD
-- "Character Menu", M37, from docs/mockups/character-sheet-2026-10-12.png).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- lobby place; it replaces any existing copy. Names must match
-- Constants.CHARACTER_SHEET_* / GEAR_CARD_* / SKILL_ROW_* / OFFER_*. Layout
-- follows the GUI standard in CLAUDE.md; fonts and colours come from
-- Shared/UiStyle. ClientCharacterSheetManager clones the gear card, skill
-- row, and offer option templates and fills every label; the templates
-- stay hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
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
local INFO_BUTTON_MIN_PX = UiStyle.TOUCH_TARGET_MIN_PX / 2
local function makeInfoButton(name)
	local button = makeButton(name, "i", UiStyle.TEXT_MUTED_COLOR, UiStyle.BACKGROUND_COLOR, 16)
	addAspectFromHeight(button, 1)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(INFO_BUTTON_MIN_PX, INFO_BUTTON_MIN_PX)
	constraint.MaxSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
	constraint.Parent = button
	addCorner(button, 100)
	return button
end

-- REROLL on the left, the price and the diamond on the right (resources
-- are icons, never words)
local function makeRerollButton(name, isStacked)
	local button = makeButton(name, "", UiStyle.ACCENT_COLOR, UiStyle.TEXT_COLOR, 24)
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
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.Size = UDim2.fromScale(1, 1)
dialog.BackgroundTransparency = 1
dialog.Parent = gui

-- header, as on the select menu
local backButton = makeButton(Constants.CHARACTER_SELECT_BACK_BUTTON, UiStyle.formatTitle("Back"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, 40)
backButton.Position = UDim2.fromScale(0.055, 0.045)
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
leftPanel.Position = UDim2.fromScale(0.055, 0.145)
leftPanel.Size = UDim2.fromScale(0.31, 0.78)
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
rightPanel.Position = UDim2.fromScale(0.38, 0.145)
rightPanel.Size = UDim2.fromScale(0.565, 0.78)
rightPanel.BackgroundColor3 = UiStyle.PANEL_COLOR
rightPanel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
rightPanel.BorderSizePixel = 0
rightPanel.Parent = dialog
addCorner(rightPanel)

local loadoutTab = makeButton(Constants.CHARACTER_SHEET_LOADOUT_TAB, UiStyle.formatTitle("Loadout"), UiStyle.PANEL_COLOR, UiStyle.TEXT_COLOR, 36)
loadoutTab.Position = UDim2.fromScale(0, 0)
loadoutTab.Size = UDim2.fromScale(0.5, 0.085)
loadoutTab.Parent = rightPanel

local cosmeticsTab = makeButton(Constants.CHARACTER_SHEET_COSMETICS_TAB, UiStyle.formatTitle("Cosmetics"), UiStyle.BACKGROUND_COLOR, UiStyle.TEXT_COLOR, 36)
cosmeticsTab.Position = UDim2.fromScale(0.5, 0)
cosmeticsTab.Size = UDim2.fromScale(0.5, 0.085)
cosmeticsTab.Parent = rightPanel

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

-- the hat picker (cosmetics first pass, 2026-10-12): a heading and a grid
-- of hat buttons cloned from one template; the gear skins join with M61
local hatsHeading = makeLabel("HatsHeading", UiStyle.formatTitle("Hat"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
hatsHeading.Position = UDim2.fromScale(0.01, 0)
hatsHeading.Size = UDim2.fromScale(0.5, 0.06)
hatsHeading.TextXAlignment = Enum.TextXAlignment.Left
hatsHeading.Parent = cosmeticsPage

local hatGrid = Instance.new("ScrollingFrame")
hatGrid.Name = Constants.CHARACTER_SHEET_HAT_GRID
hatGrid.Position = UDim2.fromScale(0, 0.08)
hatGrid.Size = UDim2.fromScale(1, 0.92)
hatGrid.BackgroundTransparency = 1
hatGrid.BorderSizePixel = 0
hatGrid.ScrollBarThickness = 6
-- the canvas is the frame itself: a scale cell height needs a sized
-- canvas, and eight hats fit without scrolling
hatGrid.CanvasSize = UDim2.fromScale(0, 0)
hatGrid.ScrollingDirection = Enum.ScrollingDirection.Y
hatGrid.Parent = cosmeticsPage

local hatLayout = Instance.new("UIGridLayout")
hatLayout.CellSize = UDim2.fromScale(0.23, 0.3)
hatLayout.CellPadding = UDim2.fromScale(0.02, 0.03)
hatLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
hatLayout.SortOrder = Enum.SortOrder.LayoutOrder
hatLayout.Parent = hatGrid
-- a cell's height follows its width
local hatCellAspect = Instance.new("UIAspectRatioConstraint")
hatCellAspect.AspectRatio = 0.85
hatCellAspect.DominantAxis = Enum.DominantAxis.Width
hatCellAspect.Parent = hatLayout

local hatButton = makeButton(Constants.CHARACTER_SHEET_HAT_BUTTON_TEMPLATE, "", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, 20)
hatButton.Visible = false
hatButton.Parent = hatGrid

local hatPicture = Instance.new("ImageLabel")
hatPicture.Name = Constants.HAT_BUTTON_PICTURE
hatPicture.BackgroundTransparency = 1
hatPicture.AnchorPoint = Vector2.new(0.5, 0)
hatPicture.Position = UDim2.fromScale(0.5, 0.05)
hatPicture.Size = UDim2.fromScale(0.8, 0.65)
hatPicture.ScaleType = Enum.ScaleType.Fit
hatPicture.Parent = hatButton

local hatName = makeLabel(Constants.HAT_BUTTON_NAME_LABEL, UiStyle.formatTitle("Own hat"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 20)
hatName.AnchorPoint = Vector2.new(0.5, 1)
hatName.Position = UDim2.fromScale(0.5, 0.96)
hatName.Size = UDim2.fromScale(0.9, 0.22)
hatName.Parent = hatButton

local hatStroke = Instance.new("UIStroke")
hatStroke.Name = Constants.HAT_BUTTON_SELECTED_STROKE
hatStroke.Color = UiStyle.ACCENT_COLOR
hatStroke.Thickness = UiStyle.STROKE_PX * 2
hatStroke.Enabled = false
hatStroke.Parent = hatButton

-- gear row: four cards side by side
local gearRow = Instance.new("Frame")
gearRow.Name = Constants.CHARACTER_SHEET_GEAR_ROW
gearRow.Size = UDim2.fromScale(1, 0.47)
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
slotLabel.Position = UDim2.fromScale(0.05, 0.03)
slotLabel.Size = UDim2.fromScale(0.7, 0.1)
slotLabel.Parent = gearCard

local kindLabel = makeLabel(Constants.GEAR_CARD_KIND_LABEL, UiStyle.formatTitle("Machine Gun"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
kindLabel.AnchorPoint = Vector2.new(0, 0)
kindLabel.Position = UDim2.fromScale(0.05, 0.14)
kindLabel.Size = UDim2.fromScale(0.7, 0.1)
kindLabel.Parent = gearCard

local gearInfo = makeInfoButton(Constants.GEAR_CARD_INFO_BUTTON)
gearInfo.AnchorPoint = Vector2.new(1, 0)
gearInfo.Position = UDim2.fromScale(0.96, 0.05)
gearInfo.Size = UDim2.fromScale(0, 0.07)
gearInfo.Parent = gearCard

local picture = Instance.new("ImageLabel")
picture.Name = Constants.GEAR_CARD_PICTURE
picture.AnchorPoint = Vector2.new(0.5, 0)
picture.Position = UDim2.fromScale(0.5, 0.25)
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
skillsHeading.Position = UDim2.fromScale(0.01, 0.49)
skillsHeading.Size = UDim2.fromScale(0.5, 0.06)
skillsHeading.TextXAlignment = Enum.TextXAlignment.Left
skillsHeading.Parent = loadoutPage

local skillRows = Instance.new("Frame")
skillRows.Name = Constants.CHARACTER_SHEET_SKILL_ROWS
skillRows.Position = UDim2.fromScale(0, 0.56)
skillRows.Size = UDim2.fromScale(1, 0.44)
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
skillName.Size = UDim2.fromScale(0.58, 0.36)
skillName.TextXAlignment = Enum.TextXAlignment.Left
skillName.Parent = skillRow

local skillDescription = makeLabel(Constants.SKILL_ROW_DESCRIPTION_LABEL, "Start a run with 20 Gold Bars", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MAX_PX)
skillDescription.Position = UDim2.fromScale(0.14, 0.52)
skillDescription.Size = UDim2.fromScale(0.58, 0.32)
skillDescription.TextXAlignment = Enum.TextXAlignment.Left
skillDescription.Parent = skillRow

local skillInfo = makeInfoButton(Constants.SKILL_ROW_INFO_BUTTON)
skillInfo.AnchorPoint = Vector2.new(1, 0.5)
skillInfo.Position = UDim2.fromScale(0.8, 0.5)
skillInfo.Size = UDim2.fromScale(0, 0.28)
skillInfo.Parent = skillRow

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

-- the roll screen over everything: CURRENT and NEW boxes, Keep and Undo
local offerDialog = Instance.new("Frame")
offerDialog.Name = Constants.CHARACTER_SHEET_OFFER_DIALOG
offerDialog.AnchorPoint = Vector2.new(0.5, 0.5)
offerDialog.Position = UDim2.fromScale(0.5, 0.5)
offerDialog.Size = UDim2.fromScale(0.6, 0.7)
addMaxSize(offerDialog, Vector2.new(900, 700))
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
offerTitle.Size = UDim2.fromScale(0.9, 0.1)
offerTitle.ZIndex = 11
offerTitle.Parent = offerDialog

-- one box: a header word, the icon (with a large label over it for the
-- flipping numeral or name), then the name and a detail line
local function makeOfferBox(name, headerText, positionX)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(positionX, 0.16)
	box.Size = UDim2.fromScale(0.42, 0.55)
	box.BackgroundColor3 = UiStyle.PANEL_COLOR
	box.BorderSizePixel = 0
	box.ZIndex = 11
	box.Parent = offerDialog
	addCorner(box)

	local header = makeLabel(Constants.OFFER_BOX_HEADER, UiStyle.formatTitle(headerText), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 30)
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.fromScale(0.5, 0.04)
	header.Size = UDim2.fromScale(0.9, 0.1)
	header.ZIndex = 12
	header.Parent = box

	local icon = Instance.new("ImageLabel")
	icon.Name = Constants.OFFER_BOX_ICON
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.17)
	icon.Size = UDim2.fromScale(0.8, 0.44)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 12
	icon.Parent = box

	local spin = makeLabel(Constants.OFFER_BOX_SPIN_LABEL, "", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 72)
	spin.AnchorPoint = Vector2.new(0.5, 0)
	spin.Position = UDim2.fromScale(0.5, 0.17)
	spin.Size = UDim2.fromScale(0.9, 0.44)
	spin.ZIndex = 13
	spin.Parent = box
	local spinStroke = Instance.new("UIStroke")
	spinStroke.Thickness = UiStyle.STROKE_PX
	spinStroke.Color = UiStyle.BACKGROUND_COLOR
	spinStroke.Parent = spin

	local nameLabel = makeLabel(Constants.OFFER_BOX_NAME_LABEL, UiStyle.formatTitle("Rifle I"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 32)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.fromScale(0.5, 0.66)
	nameLabel.Size = UDim2.fromScale(0.9, 0.12)
	nameLabel.ZIndex = 12
	nameLabel.Parent = box

	local detail = makeLabel(Constants.OFFER_BOX_DETAIL_LABEL, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	detail.AnchorPoint = Vector2.new(0.5, 0)
	detail.Position = UDim2.fromScale(0.5, 0.8)
	detail.Size = UDim2.fromScale(0.9, 0.15)
	detail.TextWrapped = true
	detail.ZIndex = 12
	detail.Parent = box
	return box
end

makeOfferBox(Constants.OFFER_CURRENT_BOX, "Current", 0.27)
makeOfferBox(Constants.OFFER_NEW_BOX, "New", 0.73)

-- the Rank the character has now and would have with the roll (designer,
-- 2026-10-12); it follows the flip
local offerRank = makeLabel(Constants.OFFER_RANK_LABEL, UiStyle.formatTitle("Character rank:  1  >>  2"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
offerRank.AnchorPoint = Vector2.new(0.5, 0)
offerRank.Position = UDim2.fromScale(0.5, 0.73)
offerRank.Size = UDim2.fromScale(0.9, 0.07)
offerRank.ZIndex = 11
offerRank.Parent = offerDialog

-- Undo on the left in red, Accept on the right in green (designer, 2026-10-12)
local undoButton = makeButton(Constants.OFFER_UNDO_BUTTON, UiStyle.formatTitle("Undo"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, 32)
undoButton.AnchorPoint = Vector2.new(1, 1)
undoButton.Position = UDim2.fromScale(0.48, 0.95)
undoButton.Size = UDim2.fromScale(0.3, 0.12)
addTouchTarget(undoButton, Vector2.new(300, 72))
undoButton.ZIndex = 11
undoButton.Parent = offerDialog

local keepButton = makeButton(Constants.OFFER_KEEP_BUTTON, UiStyle.formatTitle("Accept"), UiStyle.POSITIVE_COLOR, UiStyle.TEXT_COLOR, 32)
keepButton.AnchorPoint = Vector2.new(0, 1)
keepButton.Position = UDim2.fromScale(0.52, 0.95)
keepButton.Size = UDim2.fromScale(0.3, 0.12)
addTouchTarget(keepButton, Vector2.new(300, 72))
keepButton.ZIndex = 11
keepButton.Parent = offerDialog
gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("CharacterSheet gui")
return "CharacterSheet gui built"
