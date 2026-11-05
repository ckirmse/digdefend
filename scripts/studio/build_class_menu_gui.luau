-- Rebuilds the lobby "ClassMenu" ScreenGui under StarterGui (GDD
-- "Classes", the Class Equip Menu of 2026-11-04, which replaced the
-- Character Select Menu and the Character Sheet of M37). Run from the
-- Studio command bar (or the MCP execute_luau tool) in the lobby place; it
-- replaces any existing copy. Names must match Constants.CLASS_MENU_* /
-- CLASS_BUTTON_* / CLASS_INFO_* / KIT_SLOT_* / PERK_ROW_* / REROLL_BUTTON_*
-- / OFFER_* / INFO_DIALOG_*. Layout follows the GUI standard in CLAUDE.md;
-- fonts and colours come from Shared/UiStyle. ClientClassMenuManager clones
-- the class button, kit slot, perk row, and info row templates and fills
-- every label; the templates stay hidden. The designer tunes appearance in
-- the Explorer and every such change is ported here before any rebuild;
-- never rebuild without diffing the live GUI against this script first.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before ClassMenu gui")

local existing = StarterGui:FindFirstChild(Constants.CLASS_MENU_GUI_NAME)
if existing then
	existing:Destroy()
end

local MENU_DISPLAY_ORDER = 5
local STAR_GLYPH = utf8.char(0x2605)

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

local function addAspect(frame, ratio, dominantAxis)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.DominantAxis = dominantAxis or Enum.DominantAxis.Width
	constraint.AspectType = Enum.AspectType.ScaleWithParentSize
	constraint.Parent = frame
end

-- height-dominant and parent-scaled: a frame whose width is 0 by design
-- takes its width from its height (FitWithinMaxSize would collapse it)
local function addAspectFromHeight(frame, ratio)
	addAspect(frame, ratio, Enum.DominantAxis.Height)
end

local function addPadding(parent, scale)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(scale, 0)
	padding.PaddingBottom = UDim.new(scale, 0)
	padding.PaddingLeft = UDim.new(scale, 0)
	padding.PaddingRight = UDim.new(scale, 0)
	padding.Parent = parent
end

local function addListLayout(parent, direction, paddingScale, horizontalAlignment, verticalAlignment)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(paddingScale, 0)
	layout.HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = verticalAlignment or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

local function makeFrame(name, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color or UiStyle.PANEL_COLOR
	frame.BackgroundTransparency = transparency or 0
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

local function makeImage(name, image)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = image or ""
	label.ScaleType = Enum.ScaleType.Fit
	return label
end

-- a pill with a word in it (ODDS): Roblox's paid random items policy
-- wants the odds behind a descriptive word, never a bare icon
local function makePillButton(name, text, color, ratio, maxHeightPx)
	local button = makeButton(name, UiStyle.formatTitle(text), color, UiStyle.TEXT_COLOR, 20)
	addAspectFromHeight(button, ratio)
	addMaxSize(button, Vector2.new(maxHeightPx * ratio, maxHeightPx))
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 100)
	end
	return button
end

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
gui.Name = Constants.CLASS_MENU_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.Enabled = false

local dialog = makeFrame(Constants.MENU_DIALOG_FRAME, UiStyle.BACKGROUND_COLOR)
dialog.Size = UDim2.fromScale(1, 1)
dialog.Parent = gui

-- header: Back top-right, the wallet beside it
local backButton = makeButton(Constants.CLASS_MENU_BACK_BUTTON, UiStyle.formatTitle("Back"), UiStyle.ACCENT_COLOR, UiStyle.BACKGROUND_COLOR, 28)
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.fromScale(0.97, 0.03)
backButton.Size = UDim2.fromScale(0.1, 0.08)
addAspect(backButton, 2.4)
addMaxSize(backButton, Vector2.new(150, 60))
backButton.Parent = dialog

local wallet = makeWallet(Constants.CLASS_MENU_WALLET, Constants.HUD_DIAMOND_AMOUNT_LABEL, Icons.UI.DIAMONDS)
wallet.AnchorPoint = Vector2.new(1, 0)
wallet.Position = UDim2.fromScale(0.85, 0.03)
wallet.Size = UDim2.fromScale(0.15, 0.08)
addMaxSize(wallet, Vector2.new(180, 56))
wallet.Parent = dialog

-- left column: the title band and the class list under it
local classListTitle = makeLabel(Constants.CLASS_MENU_CLASS_LIST_TITLE, UiStyle.formatTitle("Select a class"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 30)
classListTitle.BackgroundTransparency = 0
classListTitle.BackgroundColor3 = UiStyle.PANEL_COLOR
classListTitle.BorderSizePixel = 0
classListTitle.Position = UDim2.fromScale(0.03, 0.14)
classListTitle.Size = UDim2.fromScale(0.3, 0.06)
addCorner(classListTitle)
classListTitle.Parent = dialog

-- two buttons per row: a horizontal list that wraps. The canvas is sized
-- by ClientClassMenuManager:fitListCanvas, since AutomaticCanvasSize
-- leaves out children sized by scale (designer, 2026-11-04)
local classList = Instance.new("ScrollingFrame")
classList.Name = Constants.CLASS_MENU_CLASS_LIST
classList.BackgroundColor3 = UiStyle.PANEL_COLOR
classList.BorderSizePixel = 0
classList.Position = UDim2.fromScale(0.03, 0.2)
classList.Size = UDim2.fromScale(0.3, 0.76)
classList.AutomaticCanvasSize = Enum.AutomaticSize.None
classList.CanvasSize = UDim2.fromScale(0, 0)
classList.ScrollBarThickness = 6
classList.ScrollingDirection = Enum.ScrollingDirection.Y
classList.ElasticBehavior = Enum.ElasticBehavior.Never
addCorner(classList)
addPadding(classList, 0.04)
local classListPadding = classList:FindFirstChildOfClass("UIPadding") :: UIPadding
classListPadding.PaddingLeft = UDim.new(0.03, 0)
classListPadding.PaddingRight = UDim.new(0.03, 0)
local classListLayout = addListLayout(classList, Enum.FillDirection.Horizontal, 0.02, Enum.HorizontalAlignment.Left)
classListLayout.Wraps = true
classList.Parent = dialog

local classButton = makeButton(Constants.CLASS_MENU_CLASS_BUTTON_TEMPLATE, "", UiStyle.BACKGROUND_COLOR, UiStyle.TEXT_COLOR, 1)
classButton.Size = UDim2.fromScale(0.45, 0)
addAspect(classButton, 1.15, Enum.DominantAxis.Width)
classButton.Visible = false
classButton.Parent = classList

local classIcon = makeImage(Constants.CLASS_BUTTON_ICON, Icons.PLACEHOLDER)
classIcon.AnchorPoint = Vector2.new(0.5, 0)
classIcon.Position = UDim2.fromScale(0.5, 0.05)
classIcon.Size = UDim2.fromScale(0.9, 0.66)
classIcon.Parent = classButton

local className = makeLabel(Constants.CLASS_BUTTON_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
className.AnchorPoint = Vector2.new(0.5, 1)
className.Position = UDim2.fromScale(0.5, 0.95)
className.Size = UDim2.fromScale(0.9, 0.2)
className.Parent = classButton

local classLock = makeImage(Constants.CLASS_BUTTON_LOCK_ICON, Icons.LOCK_MARKER)
classLock.AnchorPoint = Vector2.new(1, 0)
classLock.Position = UDim2.fromScale(0.96, 0.04)
classLock.Size = UDim2.fromScale(0.22, 0.22)
addAspect(classLock, 1)
classLock.Visible = false
classLock.Parent = classButton

local selectedStroke = Instance.new("UIStroke")
selectedStroke.Name = Constants.CLASS_BUTTON_SELECTED_STROKE
selectedStroke.Color = UiStyle.ACCENT_COLOR
selectedStroke.Thickness = 3
selectedStroke.Enabled = false
selectedStroke.Parent = classButton

-- right column: the info panel (the avatar column between the two went
-- with per-class cosmetics, designer 2026-11-04)
local infoPanel = makeFrame(Constants.CLASS_MENU_INFO_PANEL, UiStyle.PANEL_COLOR)
infoPanel.Position = UDim2.fromScale(0.36, 0.14)
infoPanel.Size = UDim2.fromScale(0.61, 0.82)
addCorner(infoPanel)
addPadding(infoPanel, 0.03)
infoPanel.Parent = dialog

-- the header (designer's layout, 2026-11-04): the class icon at the left,
-- its name and stars beside it, the sentence filling the right half
local infoIcon = makeImage(Constants.CLASS_INFO_ICON, Icons.PLACEHOLDER)
infoIcon.Position = UDim2.fromScale(0, 0)
infoIcon.Size = UDim2.fromScale(0, 0.22)
addAspectFromHeight(infoIcon, 1)
infoIcon.Parent = infoPanel

local infoName = makeLabel(Constants.CLASS_INFO_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 40)
infoName.Position = UDim2.fromScale(0.14, 0)
infoName.Size = UDim2.fromScale(0.3, 0.13)
infoName.TextXAlignment = Enum.TextXAlignment.Left
infoName.Parent = infoPanel

local stars = makeFrame(Constants.CLASS_INFO_STARS, UiStyle.PANEL_COLOR, 1)
stars.Position = UDim2.fromScale(0.14, 0.13)
stars.Size = UDim2.fromScale(0.3, 0.09)
addListLayout(stars, Enum.FillDirection.Horizontal, 0.01, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
stars.Parent = infoPanel
for index = 1, Constants.CLASS_INFO_STAR_COUNT do
	local star = makeLabel(string.format(Constants.CLASS_INFO_STAR_NAME_FORMAT, index), STAR_GLYPH, UiStyle.TITLE_FONT, UiStyle.CLASS_CARD_STAR_DARK_COLOR, 36)
	star.Size = UDim2.fromScale(0, 1)
	addAspectFromHeight(star, 1)
	star.LayoutOrder = index
	star.Parent = stars
end

local description = makeLabel(Constants.CLASS_INFO_DESCRIPTION_LABEL, "Steady firepower from a rifle, a minigun post, and an auto turret.", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
description.Position = UDim2.fromScale(0.46, 0)
description.Size = UDim2.fromScale(0.54, 0.22)
description.TextWrapped = true
description.TextTruncate = Enum.TextTruncate.None
description.Parent = infoPanel

local function makeColumnTitle(name, text, alignment)
	local title = makeLabel(name, UiStyle.formatTitle(text), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
	title.TextXAlignment = alignment
	title.Parent = infoPanel
	return title
end

-- the LOADOUT column: four stacked rows, the item's icon in a dark disc,
-- the slot word in the accent over the item's name
local loadoutTitle = makeColumnTitle(Constants.CLASS_INFO_LOADOUT_TITLE, "Loadout", Enum.TextXAlignment.Left)
loadoutTitle.Position = UDim2.fromScale(0, 0.26)
loadoutTitle.Size = UDim2.fromScale(0.42, 0.06)

local kitRow = makeFrame(Constants.CLASS_INFO_KIT_ROW, UiStyle.PANEL_COLOR, 1)
kitRow.Position = UDim2.fromScale(0, 0.33)
kitRow.Size = UDim2.fromScale(0.42, 0.67)
addListLayout(kitRow, Enum.FillDirection.Vertical, 0.02)
kitRow.Parent = infoPanel

local kitSlot = makeButton(Constants.CLASS_INFO_KIT_SLOT_TEMPLATE, "", UiStyle.EMPTY_SLOT_COLOR, UiStyle.TEXT_COLOR, 1)
kitSlot.Size = UDim2.fromScale(1, 0.235)
kitSlot.Visible = false
kitSlot.Parent = kitRow

local kitIcon = makeImage(Constants.KIT_SLOT_ICON, Icons.PLACEHOLDER)
kitIcon.AnchorPoint = Vector2.new(0, 0.5)
kitIcon.Position = UDim2.fromScale(0.03, 0.5)
kitIcon.Size = UDim2.fromScale(0, 0.72)
kitIcon.BackgroundTransparency = 0
kitIcon.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
addAspectFromHeight(kitIcon, 1)
addCorner(kitIcon, 100)
kitIcon.Parent = kitSlot

local kitLabel = makeLabel(Constants.KIT_SLOT_LABEL, UiStyle.formatTitle("Weapon"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 18)
kitLabel.Position = UDim2.fromScale(0.24, 0.1)
kitLabel.Size = UDim2.fromScale(0.72, 0.3)
kitLabel.Parent = kitSlot

local kitItemLabel = makeLabel(Constants.KIT_SLOT_ITEM_LABEL, UiStyle.formatTitle("Sentry Gun"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 16)
kitItemLabel.Position = UDim2.fromScale(0.24, 0.42)
kitItemLabel.Size = UDim2.fromScale(0.72, 0.48)
kitItemLabel.TextWrapped = true
kitItemLabel.Parent = kitSlot

-- the SKILLS column: the three perk rows, ODDS and EQUIP under them
local skillsTitle = makeColumnTitle(Constants.CLASS_INFO_SKILLS_TITLE, "Skills", Enum.TextXAlignment.Center)
skillsTitle.Position = UDim2.fromScale(0.46, 0.26)
skillsTitle.Size = UDim2.fromScale(0.54, 0.06)

local perkRows = makeFrame(Constants.CLASS_INFO_PERK_ROWS, UiStyle.PANEL_COLOR, 1)
perkRows.Position = UDim2.fromScale(0.46, 0.33)
perkRows.Size = UDim2.fromScale(0.54, 0.5)
addListLayout(perkRows, Enum.FillDirection.Vertical, 0.02)
perkRows.Parent = infoPanel

local perkRow = makeFrame(Constants.CLASS_INFO_PERK_ROW_TEMPLATE, UiStyle.EMPTY_SLOT_COLOR)
perkRow.Size = UDim2.fromScale(1, 0.31)
addCorner(perkRow)
perkRow.Visible = false
perkRow.Parent = perkRows

local badge = makeFrame(Constants.PERK_ROW_BADGE, UiStyle.BACKGROUND_COLOR)
badge.AnchorPoint = Vector2.new(0, 0.5)
badge.Position = UDim2.fromScale(0.02, 0.5)
badge.Size = UDim2.fromScale(0, 0.7)
addAspectFromHeight(badge, 1)
addCorner(badge, 100)
badge.Parent = perkRow
local badgeNumber = makeLabel(Constants.PERK_ROW_BADGE_LABEL, "1", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 24)
badgeNumber.Size = UDim2.fromScale(1, 1)
badgeNumber.Parent = badge

local perkName = makeLabel(Constants.PERK_ROW_NAME_LABEL, UiStyle.formatTitle("Gold Digger - Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
perkName.Position = UDim2.fromScale(0.17, 0.08)
perkName.Size = UDim2.fromScale(0.5, 0.4)
perkName.TextXAlignment = Enum.TextXAlignment.Left
perkName.Parent = perkRow

local perkDescription = makeLabel(Constants.PERK_ROW_DESCRIPTION_LABEL, "Start a run with 20 Gold Bars", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
perkDescription.Position = UDim2.fromScale(0.17, 0.52)
perkDescription.Size = UDim2.fromScale(0.5, 0.4)
perkDescription.TextXAlignment = Enum.TextXAlignment.Left
perkDescription.Parent = perkRow

local rerollButton = makeButton(Constants.PERK_ROW_REROLL_BUTTON, "", UiStyle.ACCENT_COLOR, UiStyle.BACKGROUND_COLOR, 1)
rerollButton.AnchorPoint = Vector2.new(1, 0.5)
rerollButton.Position = UDim2.fromScale(0.98, 0.5)
rerollButton.Size = UDim2.fromScale(0.28, 0.72)
addMaxSize(rerollButton, Vector2.new(140, 48))
rerollButton.Parent = perkRow
local rerollLabel = makeLabel(Constants.REROLL_BUTTON_LABEL, UiStyle.formatTitle("Reroll"), UiStyle.TITLE_FONT, UiStyle.BACKGROUND_COLOR, 18)
rerollLabel.Position = UDim2.fromScale(0.04, 0.05)
rerollLabel.Size = UDim2.fromScale(0.92, 0.46)
rerollLabel.Parent = rerollButton
local rerollPrice = makeLabel(Constants.REROLL_BUTTON_PRICE_LABEL, "10", UiStyle.BODY_BOLD_FONT, UiStyle.BACKGROUND_COLOR, 16)
rerollPrice.Position = UDim2.fromScale(0.04, 0.52)
rerollPrice.Size = UDim2.fromScale(0.56, 0.4)
rerollPrice.TextXAlignment = Enum.TextXAlignment.Right
rerollPrice.Parent = rerollButton
local rerollIcon = makeImage(Constants.REROLL_BUTTON_PRICE_ICON, Icons.UI.DIAMONDS)
rerollIcon.AnchorPoint = Vector2.new(0, 0.5)
rerollIcon.Position = UDim2.fromScale(0.64, 0.72)
rerollIcon.Size = UDim2.fromScale(0, 0.36)
addAspectFromHeight(rerollIcon, 1)
rerollIcon.Parent = rerollButton

local perkLock = makeImage(Constants.PERK_ROW_LOCK_ICON, Icons.LOCK_MARKER)
perkLock.AnchorPoint = Vector2.new(1, 0.5)
perkLock.Position = UDim2.fromScale(0.98, 0.5)
perkLock.Size = UDim2.fromScale(0, 0.6)
addAspectFromHeight(perkLock, 1)
perkLock.Visible = false
perkLock.Parent = perkRow

local requirementLabel = makeLabel(Constants.PERK_ROW_REQUIREMENT_LABEL, "2", UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
requirementLabel.AnchorPoint = Vector2.new(0, 0.5)
requirementLabel.Position = UDim2.fromScale(0.17, 0.5)
requirementLabel.Size = UDim2.fromScale(0.08, 0.5)
requirementLabel.TextXAlignment = Enum.TextXAlignment.Right
requirementLabel.Visible = false
requirementLabel.Parent = perkRow

local requirementStar = makeLabel(Constants.PERK_ROW_REQUIREMENT_STAR, STAR_GLYPH .. "  " .. UiStyle.formatTitle("Required"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
requirementStar.AnchorPoint = Vector2.new(0, 0.5)
requirementStar.Position = UDim2.fromScale(0.26, 0.5)
requirementStar.Size = UDim2.fromScale(0.44, 0.5)
requirementStar.TextXAlignment = Enum.TextXAlignment.Left
requirementStar.Visible = false
requirementStar.Parent = perkRow

local oddsButton = makePillButton(Constants.CLASS_INFO_ODDS_BUTTON, "Odds", UiStyle.ODDS_BUTTON_COLOR, 2.6, 40)
oddsButton.AnchorPoint = Vector2.new(0, 1)
oddsButton.Position = UDim2.fromScale(0.46, 1)
oddsButton.Size = UDim2.fromScale(0, 0.1)
oddsButton.Parent = infoPanel

local equipButton = makeButton(Constants.CLASS_INFO_EQUIP_BUTTON, UiStyle.formatTitle("Equip"), UiStyle.POSITIVE_COLOR, UiStyle.TEXT_COLOR, 30)
equipButton.AnchorPoint = Vector2.new(1, 1)
equipButton.Position = UDim2.fromScale(1, 1)
equipButton.Size = UDim2.fromScale(0.32, 0.1)
addAspect(equipButton, 4.5)
addMaxSize(equipButton, Vector2.new(260, 56))
equipButton.Parent = infoPanel

-- the roll screen over everything: CURRENT and NEW boxes, Keep and Undo
local offerDialog = makeFrame(Constants.CLASS_MENU_OFFER_DIALOG, UiStyle.BACKGROUND_COLOR)
offerDialog.Size = UDim2.fromScale(1, 1)
offerDialog.Visible = false
offerDialog.ZIndex = 5
offerDialog.Parent = dialog

local offerTitle = makeLabel(Constants.OFFER_DIALOG_TITLE, UiStyle.formatTitle("New roll"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 40)
offerTitle.AnchorPoint = Vector2.new(0.5, 0)
offerTitle.Position = UDim2.fromScale(0.5, 0.08)
offerTitle.Size = UDim2.fromScale(0.6, 0.08)
offerTitle.Parent = offerDialog

local function makeOfferBox(name, headerText, x)
	local box = makeFrame(name, UiStyle.PANEL_COLOR)
	box.Position = UDim2.fromScale(x, 0.22)
	box.Size = UDim2.fromScale(0.33, 0.52)
	addCorner(box)
	box.Parent = offerDialog
	local header = makeLabel(Constants.OFFER_BOX_HEADER, UiStyle.formatTitle(headerText), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 30)
	header.Position = UDim2.fromScale(0.05, 0.03)
	header.Size = UDim2.fromScale(0.9, 0.1)
	header.Parent = box
	local icon = makeImage(Constants.OFFER_BOX_ICON, "")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.16)
	icon.Size = UDim2.fromScale(0, 0.4)
	addAspectFromHeight(icon, 1)
	icon.Parent = box
	local spin = makeLabel(Constants.OFFER_BOX_SPIN_LABEL, "", UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 72)
	spin.Position = UDim2.fromScale(0.05, 0.16)
	spin.Size = UDim2.fromScale(0.9, 0.4)
	spin.TextWrapped = true
	spin.Parent = box
	local nameLabel = makeLabel(Constants.OFFER_BOX_NAME_LABEL, UiStyle.formatTitle("Gold Digger - Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 32)
	nameLabel.Position = UDim2.fromScale(0.05, 0.6)
	nameLabel.Size = UDim2.fromScale(0.9, 0.12)
	nameLabel.Parent = box
	local detail = makeLabel(Constants.OFFER_BOX_DETAIL_LABEL, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
	detail.Position = UDim2.fromScale(0.05, 0.74)
	detail.Size = UDim2.fromScale(0.9, 0.22)
	detail.TextWrapped = true
	detail.TextTruncate = Enum.TextTruncate.None
	detail.Parent = box
	return box
end

makeOfferBox(Constants.OFFER_CURRENT_BOX, "Current", 0.15)
makeOfferBox(Constants.OFFER_NEW_BOX, "New", 0.52)

local undoButton = makeButton(Constants.OFFER_UNDO_BUTTON, UiStyle.formatTitle("Undo"), UiStyle.NEGATIVE_COLOR, UiStyle.TEXT_COLOR, 32)
undoButton.AnchorPoint = Vector2.new(1, 0)
undoButton.Position = UDim2.fromScale(0.48, 0.8)
undoButton.Size = UDim2.fromScale(0.2, 0.09)
addAspect(undoButton, 3.6)
addMaxSize(undoButton, Vector2.new(240, 66))
undoButton.Parent = offerDialog

local keepButton = makeButton(Constants.OFFER_KEEP_BUTTON, UiStyle.formatTitle("Accept"), UiStyle.POSITIVE_COLOR, UiStyle.TEXT_COLOR, 32)
keepButton.AnchorPoint = Vector2.new(0, 0)
keepButton.Position = UDim2.fromScale(0.52, 0.8)
keepButton.Size = UDim2.fromScale(0.2, 0.09)
addAspect(keepButton, 3.6)
addMaxSize(keepButton, Vector2.new(240, 66))
keepButton.Parent = offerDialog

-- the info dialog: a kit item's tooltip or the roll odds
local infoDialog = makeFrame(Constants.CLASS_MENU_INFO_DIALOG, UiStyle.PANEL_COLOR)
infoDialog.AnchorPoint = Vector2.new(0.5, 0.5)
infoDialog.Position = UDim2.fromScale(0.5, 0.5)
infoDialog.Size = UDim2.fromScale(0.5, 0.6)
addAspect(infoDialog, 1.3)
addCorner(infoDialog)
addPadding(infoDialog, 0.03)
infoDialog.Visible = false
infoDialog.ZIndex = 10
infoDialog.Parent = dialog
local infoStroke = Instance.new("UIStroke")
infoStroke.Color = UiStyle.ACCENT_COLOR
infoStroke.Thickness = UiStyle.STROKE_PX
infoStroke.Parent = infoDialog

local infoTitle = makeLabel(Constants.INFO_DIALOG_TITLE, UiStyle.formatTitle("Reroll odds"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 36)
infoTitle.Position = UDim2.fromScale(0, 0)
infoTitle.Size = UDim2.fromScale(1, 0.12)
infoTitle.Parent = infoDialog

local infoPicture = makeImage(Constants.INFO_DIALOG_PICTURE, "")
infoPicture.AnchorPoint = Vector2.new(0.5, 0)
infoPicture.Position = UDim2.fromScale(0.5, 0.15)
infoPicture.Size = UDim2.fromScale(0, 0.3)
addAspectFromHeight(infoPicture, 1)
infoPicture.Visible = false
infoPicture.Parent = infoDialog

local infoRows = Instance.new("ScrollingFrame")
infoRows.Name = Constants.INFO_DIALOG_ROWS
infoRows.BackgroundTransparency = 1
infoRows.BorderSizePixel = 0
infoRows.Position = UDim2.fromScale(0, 0.15)
infoRows.Size = UDim2.fromScale(1, 0.5)
infoRows.AutomaticCanvasSize = Enum.AutomaticSize.Y
infoRows.CanvasSize = UDim2.fromScale(0, 0)
infoRows.ScrollBarThickness = 6
infoRows.ScrollingDirection = Enum.ScrollingDirection.Y
addListLayout(infoRows, Enum.FillDirection.Vertical, 0.02)
infoRows.Parent = infoDialog

local infoRow = makeFrame(Constants.INFO_DIALOG_ROW_TEMPLATE, UiStyle.EMPTY_SLOT_COLOR)
infoRow.Size = UDim2.fromScale(1, 0.16)
addCorner(infoRow)
infoRow.Visible = false
infoRow.Parent = infoRows
local infoRowLabel = makeLabel(Constants.INFO_ROW_LABEL, UiStyle.formatTitle("Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
infoRowLabel.Position = UDim2.fromScale(0.03, 0.1)
infoRowLabel.Size = UDim2.fromScale(0.6, 0.8)
infoRowLabel.TextXAlignment = Enum.TextXAlignment.Left
infoRowLabel.Parent = infoRow
local infoRowValue = makeLabel(Constants.INFO_ROW_VALUE, "50%", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, 22)
infoRowValue.Position = UDim2.fromScale(0.65, 0.1)
infoRowValue.Size = UDim2.fromScale(0.32, 0.8)
infoRowValue.TextXAlignment = Enum.TextXAlignment.Right
infoRowValue.Parent = infoRow

local infoNote = makeLabel(Constants.INFO_DIALOG_NOTE, "", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
infoNote.Position = UDim2.fromScale(0, 0.67)
infoNote.Size = UDim2.fromScale(1, 0.18)
infoNote.TextWrapped = true
infoNote.TextTruncate = Enum.TextTruncate.None
infoNote.Parent = infoDialog

local infoClose = makeButton(Constants.INFO_DIALOG_CLOSE_BUTTON, UiStyle.formatTitle("Close"), UiStyle.ACCENT_COLOR, UiStyle.BACKGROUND_COLOR, 28)
infoClose.AnchorPoint = Vector2.new(0.5, 1)
infoClose.Position = UDim2.fromScale(0.5, 1)
infoClose.Size = UDim2.fromScale(0.4, 0.11)
addAspect(infoClose, 4)
addMaxSize(infoClose, Vector2.new(220, 56))
infoClose.Parent = infoDialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("After ClassMenu gui")
print("build_class_menu_gui: built StarterGui." .. Constants.CLASS_MENU_GUI_NAME)
