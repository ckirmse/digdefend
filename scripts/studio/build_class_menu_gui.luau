-- Rebuilds the lobby "ClassMenu" ScreenGui under StarterGui (GDD
-- "Classes", the Class Equip Menu of 2026-11-04, which replaced the
-- Character Select Menu and the Character Sheet of M37). Run from the
-- Studio command bar (or the MCP execute_luau tool) in the lobby place; it
-- replaces any existing copy. Names must match Constants.CLASS_MENU_* /
-- CLASS_BUTTON_* / CLASS_INFO_* / KIT_SLOT_* / PERK_ROW_* / REROLL_BUTTON_*
-- / INFO_DIALOG_*. Layout follows the GUI standard in CLAUDE.md;
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

-- the designer's slice rectangles on the plate picture, one per button
-- shape (read from the live gui, 2026-11-05)
local WIDE_PLATE_SLICE = Rect.new(136, 207, 292, 291)
local TALL_PLATE_SLICE = Rect.new(136, 105, 356, 400)

-- a button on the designer's slice plate, tinted by ImageColor3 (the
-- Equip, Odds, Reroll, and Back buttons since 2026-11-05)
local function makePlateButton(name, color, slice)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Image = Icons.UI.PANEL_BACKING
	button.ScaleType = Enum.ScaleType.Slice
	button.SliceCenter = slice or WIDE_PLATE_SLICE
	button.ImageColor3 = color
	button.AutoButtonColor = true
	return button
end

-- the word on a plate button: a centred TextLabel child the manager
-- writes (Constants.EQUIP_BUTTON_LABEL names it)
local function addPlateLabel(button, text, color, maxPx)
	local label = makeLabel(Constants.EQUIP_BUTTON_LABEL, text, UiStyle.TITLE_FONT, color, maxPx)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.95, 0.8)
	label.TextTruncate = Enum.TextTruncate.None
	label.Parent = button
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

-- a black box with a rounded corner (the class list column, the EQUIPPED
-- CLASS box's title band, the info panel's header, description, and
-- columns; designer, 2026-11-05)
local function makeBox(name, transparency)
	local box = makeFrame(name, Color3.new(0, 0, 0), transparency or 0)
	return box
end

local function addScaleCorner(parent, scale)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scale, 0)
	corner.Parent = parent
end

-- a title band across the top of a box: TitleFrame holding the Title
local function addTitleBand(parent, text, heightScale, labelPosition, labelAnchor, labelSize)
	local band = makeBox(Constants.CLASS_MENU_TITLE_FRAME)
	band.Size = UDim2.fromScale(1, heightScale)
	band.Parent = parent
	local title = makeLabel(Constants.CLASS_MENU_TITLE_LABEL, UiStyle.formatTitle(text), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 30)
	title.AnchorPoint = labelAnchor
	title.Position = labelPosition
	title.Size = labelSize
	title.TextWrapped = true
	title.TextTruncate = Enum.TextTruncate.None
	title.Parent = band
	return band
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.CLASS_MENU_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.Enabled = false

-- a clear backdrop (designer, 2026-11-05): the HUD's balances stay on
-- screen under the menu, so it carries no wallet of its own
local dialog = makeFrame(Constants.MENU_DIALOG_FRAME, UiStyle.BACKGROUND_COLOR, 1)
dialog.Size = UDim2.fromScale(1, 1)
dialog.Parent = gui

-- header: Back top-right
local backButton = makePlateButton(Constants.CLASS_MENU_BACK_BUTTON, UiStyle.TOGGLE_OFF_COLOR, TALL_PLATE_SLICE)
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.fromScale(0.97, 0.03)
backButton.Size = UDim2.fromScale(0.1, 0.08)
addAspect(backButton, 2.4)
addMaxSize(backButton, Vector2.new(150, 60))
addTextSizeBounds(backButton, 28)
addPlateLabel(backButton, UiStyle.formatTitle("Back"), Color3.new(0, 0, 0), 28)
backButton.Parent = dialog

-- left column: the SELECT A CLASS band over the class list, in one frame
-- (designer, 2026-11-05)
local classListFrame = makeFrame(Constants.CLASS_MENU_CLASS_LIST_FRAME, UiStyle.PANEL_COLOR)
classListFrame.Position = UDim2.fromScale(0.03, 0.14)
classListFrame.Size = UDim2.fromScale(0.15, 0.63)
classListFrame.Parent = dialog
addTitleBand(classListFrame, "Select a class", 0.09, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), UDim2.fromScale(0.9, 0.9))

-- two buttons per row (designer, 2026-11-05 evening; one per row that
-- morning, two the day before) in a narrow column: a horizontal list that
-- wraps, the gap kept small because fitListCanvas turns its scale into
-- pixels of the window height, which is far wider than this column. The
-- canvas is sized by
-- ClientClassMenuManager:fitListCanvas, since AutomaticCanvasSize leaves
-- out children sized by scale (designer, 2026-11-04)
local classList = Instance.new("ScrollingFrame")
classList.Name = Constants.CLASS_MENU_CLASS_LIST
classList.BackgroundColor3 = UiStyle.PANEL_COLOR
classList.BackgroundTransparency = 1
classList.BorderSizePixel = 0
classList.Position = UDim2.fromScale(0, 0.09)
classList.Size = UDim2.fromScale(1, 0.91)
classList.AutomaticCanvasSize = Enum.AutomaticSize.None
classList.CanvasSize = UDim2.fromScale(0, 0)
classList.ScrollBarThickness = 6
classList.ScrollingDirection = Enum.ScrollingDirection.Y
classList.ElasticBehavior = Enum.ElasticBehavior.Never
addCorner(classList)
addPadding(classList, 0.04)
local classListPadding = classList:FindFirstChildOfClass("UIPadding") :: UIPadding
classListPadding.PaddingLeft = UDim.new(0.06, 0)
classListPadding.PaddingRight = UDim.new(0.06, 0)
local classListLayout = addListLayout(classList, Enum.FillDirection.Horizontal, 0.01, Enum.HorizontalAlignment.Center)
classListLayout.Wraps = true
classList.Parent = classListFrame

local classButton = makeButton(Constants.CLASS_MENU_CLASS_BUTTON_TEMPLATE, "", UiStyle.BACKGROUND_COLOR, UiStyle.TEXT_COLOR, 1)
classButton.Size = UDim2.fromScale(0.4, 0)
-- square, the designer's value (2026-11-05); a 0.46 aspect, twice as tall as wide, was tried the same evening
addAspect(classButton, 1, Enum.DominantAxis.Width)
classButton.Visible = false
classButton.Parent = classList

local classIcon = makeImage(Constants.CLASS_BUTTON_ICON, Icons.PLACEHOLDER)
classIcon.AnchorPoint = Vector2.new(0.5, 0)
classIcon.Position = UDim2.fromScale(0.5, 0.14)
classIcon.Size = UDim2.fromScale(0.9, 0.66)
classIcon.Parent = classButton

local className = makeLabel(Constants.CLASS_BUTTON_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
className.AnchorPoint = Vector2.new(0.5, 1)
className.Position = UDim2.fromScale(0.5, 0.98)
className.Size = UDim2.fromScale(0.9, 0.15)
className.Parent = classButton

local classLock = makeImage(Constants.CLASS_BUTTON_LOCK_ICON, Icons.UI.LOCK)
classLock.AnchorPoint = Vector2.new(1, 0)
classLock.Position = UDim2.fromScale(0.96, 0.04)
classLock.Size = UDim2.fromScale(0.22, 0.22)
addAspect(classLock, 1)
classLock.Visible = false
classLock.Parent = classButton

-- the EQUIPPED CLASS box under the list (designer, 2026-11-05): the icon
-- and name of the class in play, written by the manager
local equippedClass = makeFrame(Constants.CLASS_MENU_EQUIPPED_CLASS, UiStyle.PANEL_COLOR, 0.1)
equippedClass.Position = UDim2.fromScale(0.03, 0.78)
equippedClass.Size = UDim2.fromScale(0.15, 0.18)
equippedClass.Parent = dialog
addTitleBand(equippedClass, "Equipped class", 0.2, UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), UDim2.fromScale(1, 1))
local equippedIcon = makeImage(Constants.EQUIPPED_CLASS_ICON, Icons.PLACEHOLDER)
equippedIcon.Position = UDim2.fromScale(0.05, 0.25)
equippedIcon.Size = UDim2.fromScale(0.4, 0.66)
equippedIcon.Parent = equippedClass
-- white at rest; the manager flashes it green when the class in play changes
local equippedTitle = makeLabel(Constants.EQUIPPED_CLASS_TITLE, UiStyle.formatTitle("Ranger"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
equippedTitle.Position = UDim2.fromScale(0.45, 0.33)
equippedTitle.Size = UDim2.fromScale(0.5, 0.5)
equippedTitle.TextWrapped = true
equippedTitle.TextTruncate = Enum.TextTruncate.None
equippedTitle.Parent = equippedClass

-- right column: the info panel (the avatar column between the two went
-- with per-class cosmetics, designer 2026-11-04)
local infoPanel = makeFrame(Constants.CLASS_MENU_INFO_PANEL, UiStyle.PANEL_COLOR, 0.1)
infoPanel.Position = UDim2.fromScale(0.19, 0.14)
infoPanel.Size = UDim2.fromScale(0.78, 0.82)
addPadding(infoPanel, 0.02)
infoPanel.Parent = dialog

-- the header box (designer's layout, 2026-11-05): the class icon at the
-- left, its name over its stars beside it
local header = makeBox(Constants.CLASS_INFO_HEADER)
header.Size = UDim2.fromScale(0.3, 0.23)
addScaleCorner(header, 0.1)
addPadding(header, 0.04)
header.Parent = infoPanel

local infoIcon = makeImage(Constants.CLASS_INFO_ICON, Icons.PLACEHOLDER)
infoIcon.AnchorPoint = Vector2.new(0, 0.5)
infoIcon.Position = UDim2.fromScale(0, 0.5)
infoIcon.Size = UDim2.fromScale(0, 0.9)
addAspectFromHeight(infoIcon, 1)
infoIcon.Parent = header

local infoName = makeLabel(Constants.CLASS_INFO_NAME_LABEL, UiStyle.formatTitle("Gunner"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 40)
infoName.Position = UDim2.fromScale(0.3, 0.1)
infoName.Size = UDim2.fromScale(0.7, 0.4)
infoName.Parent = header

local stars = makeFrame(Constants.CLASS_INFO_STARS, UiStyle.PANEL_COLOR, 1)
stars.Position = UDim2.fromScale(0.3, 0.55)
stars.Size = UDim2.fromScale(0.7, 0.3)
addListLayout(stars, Enum.FillDirection.Horizontal, 0.01, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
stars.Parent = header
for index = 1, Constants.CLASS_INFO_STAR_COUNT do
	local star = makeLabel(string.format(Constants.CLASS_INFO_STAR_NAME_FORMAT, index), STAR_GLYPH, UiStyle.TITLE_FONT, UiStyle.CLASS_MENU_STAR_DARK_COLOR, 36)
	star.Size = UDim2.fromScale(0, 1)
	addAspectFromHeight(star, 1)
	star.LayoutOrder = index
	star.Parent = stars
end

-- the sentence in its own box beside the header (designer, 2026-11-05)
local descriptionFrame = makeBox(Constants.CLASS_INFO_DESCRIPTION_FRAME)
descriptionFrame.Position = UDim2.fromScale(0.31, 0)
descriptionFrame.Size = UDim2.fromScale(0.69, 0.23)
addScaleCorner(descriptionFrame, 0.1)
local descriptionPadding = Instance.new("UIPadding")
descriptionPadding.PaddingTop = UDim.new(0.1, 0)
descriptionPadding.PaddingBottom = UDim.new(0.1, 0)
descriptionPadding.PaddingLeft = UDim.new(0.02, 0)
descriptionPadding.PaddingRight = UDim.new(0.02, 0)
descriptionPadding.Parent = descriptionFrame
descriptionFrame.Parent = infoPanel
local description = makeLabel(Constants.CLASS_INFO_DESCRIPTION_LABEL, "Steady firepower from a rifle, a minigun post, and an auto turret.", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MAX_PX)
description.AnchorPoint = Vector2.new(0.5, 0.5)
description.Position = UDim2.fromScale(0.5, 0.5)
description.Size = UDim2.fromScale(1, 1)
description.TextWrapped = true
description.TextTruncate = Enum.TextTruncate.None
description.Parent = descriptionFrame

local function makeColumnTitle(name, text, alignment)
	local title = makeLabel(name, UiStyle.formatTitle(text), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 26)
	title.TextXAlignment = alignment
	title.Parent = infoPanel
	return title
end

-- the LOADOUT column: four stacked rows, the item's icon in a dark disc,
-- the slot word in the accent over the item's name
local loadoutTitle = makeColumnTitle(Constants.CLASS_INFO_LOADOUT_TITLE, "Loadout", Enum.TextXAlignment.Center)
loadoutTitle.Position = UDim2.fromScale(0, 0.26)
loadoutTitle.Size = UDim2.fromScale(0.3, 0.06)

-- the two columns are black boxes since 2026-11-05
local kitRow = makeBox(Constants.CLASS_INFO_KIT_ROW)
kitRow.Position = UDim2.fromScale(0, 0.33)
kitRow.Size = UDim2.fromScale(0.3, 0.67)
addScaleCorner(kitRow, 0.05)
addPadding(kitRow, 0.04)
addListLayout(kitRow, Enum.FillDirection.Vertical, 0.02)
kitRow.Parent = infoPanel

-- a plain coloured slot (the designer cleared its plate picture, 2026-11-05)
local kitSlot = makePlateButton(Constants.CLASS_INFO_KIT_SLOT_TEMPLATE, UiStyle.EMPTY_SLOT_COLOR, Rect.new(190, 214, 356, 281))
kitSlot.Image = ""
kitSlot.BackgroundTransparency = 0
kitSlot.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
addCorner(kitSlot)
kitSlot.Size = UDim2.fromScale(1, 0.22)
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
local kitIconStroke = Instance.new("UIStroke")
kitIconStroke.Color = UiStyle.ACCENT_COLOR
kitIconStroke.Thickness = 2
kitIconStroke.Parent = kitIcon
kitIcon.Parent = kitSlot

local kitLabel = makeLabel(Constants.KIT_SLOT_LABEL, UiStyle.formatTitle("Weapon"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, 25)
kitLabel.Position = UDim2.fromScale(0.24, 0.05)
kitLabel.Size = UDim2.fromScale(0.72, 0.3)
kitLabel.Parent = kitSlot

local kitItemLabel = makeLabel(Constants.KIT_SLOT_ITEM_LABEL, UiStyle.formatTitle("Sentry Gun"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 30)
kitItemLabel.Position = UDim2.fromScale(0.24, 0.35)
kitItemLabel.Size = UDim2.fromScale(0.72, 0.6)
kitItemLabel.TextWrapped = true
kitItemLabel.Parent = kitSlot

-- the SKILLS column: the three perk rows, ODDS and EQUIP under them
local skillsTitle = makeColumnTitle(Constants.CLASS_INFO_SKILLS_TITLE, "Skills", Enum.TextXAlignment.Center)
skillsTitle.Position = UDim2.fromScale(0.32, 0.26)
skillsTitle.Size = UDim2.fromScale(0.68, 0.06)

local perkRows = makeBox(Constants.CLASS_INFO_PERK_ROWS)
perkRows.Position = UDim2.fromScale(0.31, 0.33)
perkRows.Size = UDim2.fromScale(0.69, 0.51)
addScaleCorner(perkRows, 0.05)
addPadding(perkRows, 0.04)
local perkRowsPadding = perkRows:FindFirstChildOfClass("UIPadding") :: UIPadding
perkRowsPadding.PaddingLeft = UDim.new(0.015, 0)
perkRowsPadding.PaddingRight = UDim.new(0.015, 0)
addListLayout(perkRows, Enum.FillDirection.Vertical, 0.02)
perkRows.Parent = infoPanel

-- the row (designer, 2026-11-05: a filled plate with a rounded corner,
-- no slot-number badge, the words in the SkillText frame from the left
-- edge). SkillText clips its children: a reroll scrolls a reel of entries
-- through it like a slot machine (ClientClassMenuManager:spinReel)
local perkRow = makeFrame(Constants.CLASS_INFO_PERK_ROW_TEMPLATE, UiStyle.EMPTY_SLOT_COLOR)
perkRow.Size = UDim2.fromScale(1, 0.31)
addScaleCorner(perkRow, 0.1)
perkRow.Visible = false
perkRow.Parent = perkRows

local skillText = makeFrame(Constants.PERK_ROW_SKILL_TEXT, UiStyle.TEXT_COLOR, 1)
skillText.Position = UDim2.fromScale(0.01, 0.08)
skillText.Size = UDim2.fromScale(0.66, 0.84)
skillText.ClipsDescendants = true
skillText.Parent = perkRow

local perkName = makeLabel(Constants.PERK_ROW_NAME_LABEL, UiStyle.formatTitle("Gold Digger - Common"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 22)
perkName.Position = UDim2.fromScale(0, 0)
perkName.Size = UDim2.fromScale(1, 0.4)
perkName.TextXAlignment = Enum.TextXAlignment.Left
perkName.Parent = skillText

local perkDescription = makeLabel(Constants.PERK_ROW_DESCRIPTION_LABEL, "Start a run with 20 Gold Bars", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, 26)
perkDescription.Position = UDim2.fromScale(0, 0.4)
perkDescription.Size = UDim2.fromScale(1, 0.6)
perkDescription.TextXAlignment = Enum.TextXAlignment.Left
perkDescription.Parent = skillText

-- KEEP and X beside the words once a reel lands; hidden until then
local function makeRowPlateButton(name, color, x, width, word)
	local button = makePlateButton(name, color, TALL_PLATE_SLICE)
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.fromScale(x, 0.5)
	button.Size = UDim2.fromScale(width, 0.72)
	addMaxSize(button, Vector2.new(140, 48))
	addTextSizeBounds(button, 1)
	button.Visible = false
	local label = makeLabel(Constants.REROLL_BUTTON_LABEL, UiStyle.formatTitle(word), UiStyle.TITLE_FONT, UiStyle.BACKGROUND_COLOR, 18)
	label.Position = UDim2.fromScale(0.04, 0.05)
	label.Size = UDim2.fromScale(0.92, 0.9)
	label.Parent = button
	button.Parent = perkRow
	return button
end
makeRowPlateButton(Constants.PERK_ROW_KEEP_BUTTON, UiStyle.POSITIVE_COLOR, 0.68, 0.2, "Keep")
makeRowPlateButton(Constants.PERK_ROW_CANCEL_BUTTON, UiStyle.TOGGLE_OFF_COLOR, 0.89, 0.1, "X")

local rerollButton = makePlateButton(Constants.PERK_ROW_REROLL_BUTTON, UiStyle.ACCENT_COLOR, TALL_PLATE_SLICE)
rerollButton.AnchorPoint = Vector2.new(1, 0.5)
rerollButton.Position = UDim2.fromScale(0.98, 0.5)
rerollButton.Size = UDim2.fromScale(0.28, 0.72)
addMaxSize(rerollButton, Vector2.new(140, 48))
addTextSizeBounds(rerollButton, 1)
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

local perkLock = makeImage(Constants.PERK_ROW_LOCK_ICON, Icons.UI.LOCK)
perkLock.AnchorPoint = Vector2.new(1, 0.5)
perkLock.Position = UDim2.fromScale(0.98, 0.5)
perkLock.Size = UDim2.fromScale(0, 0.6)
addAspectFromHeight(perkLock, 1)
perkLock.Visible = false
perkLock.Parent = perkRow

-- a locked row's one line; the manager writes the whole of it
local requirementLabel = makeLabel(Constants.PERK_ROW_REQUIREMENT_LABEL, UiStyle.formatTitle("Unlocked at 2 " .. STAR_GLYPH), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, 22)
requirementLabel.AnchorPoint = Vector2.new(0, 0.5)
requirementLabel.Position = UDim2.fromScale(0.02, 0.5)
requirementLabel.Size = UDim2.fromScale(0.65, 0.5)
requirementLabel.TextXAlignment = Enum.TextXAlignment.Left
requirementLabel.Visible = false
requirementLabel.Parent = perkRow

-- REROLL ODDS and EQUIP on plates along the panel's bottom edge (designer,
-- 2026-11-05): Roblox's paid random items policy wants the odds behind a
-- descriptive word, never a bare icon
local oddsButton = makePlateButton(Constants.CLASS_INFO_ODDS_BUTTON, UiStyle.ODDS_BUTTON_COLOR)
oddsButton.AnchorPoint = Vector2.new(0, 1)
oddsButton.Position = UDim2.fromScale(0.31, 1)
oddsButton.Size = UDim2.fromScale(0.3, 0.14)
addTextSizeBounds(oddsButton, 30)
addPlateLabel(oddsButton, UiStyle.formatTitle("Reroll odds"), Color3.new(0, 0, 0), 30)
oddsButton.Parent = infoPanel

local equipButton = makePlateButton(Constants.CLASS_INFO_EQUIP_BUTTON, UiStyle.POSITIVE_COLOR)
equipButton.AnchorPoint = Vector2.new(0, 1)
equipButton.Position = UDim2.fromScale(0.62, 1)
equipButton.Size = UDim2.fromScale(0.38, 0.14)
addTextSizeBounds(equipButton, 30)
addPlateLabel(equipButton, UiStyle.formatTitle("Equip"), Color3.new(0, 0, 0), 30)
equipButton.Parent = infoPanel

-- on a locked class one yellow plate spans the Odds and Equip spots and
-- opens the Supply Crate menu (designer, 2026-11-05); the manager shows
-- one or the other
local supplyCrateButton = makePlateButton(Constants.CLASS_INFO_SUPPLY_CRATE_BUTTON, UiStyle.SUPPLY_CRATE_BUTTON_COLOR)
supplyCrateButton.AnchorPoint = Vector2.new(0, 1)
supplyCrateButton.Position = UDim2.fromScale(0.31, 1)
supplyCrateButton.Size = UDim2.fromScale(0.69, 0.14)
addTextSizeBounds(supplyCrateButton, 30)
addPlateLabel(supplyCrateButton, UiStyle.formatTitle("Draw from Supply Crates to unlock"), Color3.new(0, 0, 0), 30)
supplyCrateButton.Visible = false
supplyCrateButton.Parent = infoPanel

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
