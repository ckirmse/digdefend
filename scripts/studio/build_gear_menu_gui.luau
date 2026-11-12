-- Rebuilds the lobby "GearMenu" ScreenGui under StarterGui (the Gear
-- Locker, M61, 2026-11-06). Run from the Studio command bar (or the MCP
-- execute_luau tool) in the lobby place; it replaces any existing copy.
-- Names must match Constants.GEAR_MENU_*. Layout follows the GUI standard
-- in CLAUDE.md and the designer's Diamond Store look of 2026-11-06 (the
-- black header band, the X on its red plate); fonts and colours come from
-- Shared/UiStyle. The designer's layout (2026-11-06): the avatar viewport
-- on the left, and on the right one row per locker slot, each a fixed
-- icon-and-name header beside a sideways-scrolling strip of cards.
-- ClientGearMenuManager clones RowTemplate once per slot and, inside each
-- row's ItemList, ItemTemplate once per card; the templates stay hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before GearMenu gui")

local existing = StarterGui:FindFirstChild(Constants.GEAR_MENU_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local DIALOG_ASPECT = 1.9
local DIALOG_MAX_SIZE = Vector2.new(1140, 600)
local DIALOG_POSITION_Y = 0.55
local DIALOG_TRANSPARENCY = 0.1
local HEADER_HEIGHT_SHARE = 0.12
local CLOSE_BUTTON_MAX_PX = 56
-- two rows share the right side's height with a gap between them
local ROW_GAP_SHARE = 0.04
local ROW_HEIGHT_SHARE = 0.48
-- the row's fixed header takes this share of its width; the strip the rest
local ROW_HEADER_WIDTH_SHARE = 0.2
local ROW_STRIP_LEFT_SHARE = 0.22
-- a card takes the strip's height and is a touch taller than wide
local ITEM_ASPECT = 0.9
local ITEM_GAP_SHARE = 0.02
local BLACK = Color3.new(0, 0, 0)

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

local gui = Instance.new("ScreenGui")
gui.Name = Constants.GEAR_MENU_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = makeFrame(Constants.MENU_DIALOG_FRAME, UiStyle.PANEL_COLOR)
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, DIALOG_POSITION_Y)
dialog.Size = UDim2.fromScale(0.84, 0.78)
dialog.BackgroundTransparency = DIALOG_TRANSPARENCY
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.Parent = gui
addCorner(dialog)

-- the header band with the title, and the X in the corner (the Diamond
-- Store's, designer 2026-11-06)
local header = makeFrame("Header", BLACK)
header.Size = UDim2.fromScale(1, HEADER_HEIGHT_SHARE)
header.Parent = dialog
addCorner(header)

local title = makeLabel("Title", UiStyle.formatTitle("Gear Locker"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 48)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(0.95, 0.9)
title.Parent = header

local backButton = Instance.new("TextButton")
backButton.Name = Constants.GEAR_MENU_BACK_BUTTON
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
addTextSizeBounds(backButton, 26)
addCorner(backButton)
addAspect(backButton, 1)
addMaxSize(backButton, Vector2.new(CLOSE_BUTTON_MAX_PX, CLOSE_BUTTON_MAX_PX))
backButton.Parent = dialog

local backBackground = makeImage("Background", Icons.UI.PANEL_BACKING)
backBackground.Size = UDim2.fromScale(1, 1)
backBackground.ScaleType = Enum.ScaleType.Stretch
backBackground.ImageColor3 = UiStyle.TOGGLE_OFF_COLOR
backBackground.Parent = backButton

local backLabel = makeLabel(Constants.EQUIP_BUTTON_LABEL, "X", UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 26)
backLabel.AnchorPoint = Vector2.new(0.5, 0.5)
backLabel.Position = UDim2.fromScale(0.5, 0.5)
backLabel.Size = UDim2.fromScale(0.8, 0.8)
backLabel.ZIndex = 2
backLabel.Parent = backButton

-- the avatar on the left, the player's copy dressed in the loadout
local avatar = Instance.new("ViewportFrame")
avatar.Name = Constants.GEAR_MENU_AVATAR
avatar.AnchorPoint = Vector2.new(0, 1)
avatar.Position = UDim2.fromScale(0.03, 0.95)
avatar.Size = UDim2.fromScale(0.3, 0.78)
avatar.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
avatar.BackgroundTransparency = 0
avatar.BorderSizePixel = 0
avatar.Ambient = Color3.fromRGB(200, 200, 200)
avatar.LightColor = Color3.fromRGB(255, 255, 255)
avatar.Parent = dialog
addCorner(avatar)

-- the rows on the right, one per locker slot, stacked top to bottom
local rows = makeFrame(Constants.GEAR_MENU_ROWS, UiStyle.PANEL_COLOR)
rows.BackgroundTransparency = 1
rows.AnchorPoint = Vector2.new(1, 1)
rows.Position = UDim2.fromScale(0.97, 0.95)
rows.Size = UDim2.fromScale(0.61, 0.78)
rows.Parent = dialog

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
rowsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Padding = UDim.new(ROW_GAP_SHARE, 0)
rowsLayout.Parent = rows

-- a row: the fixed header (the slot's stock art over its name) on the
-- left, the strip of cards scrolling sideways beside it
local row = makeFrame(Constants.GEAR_MENU_ROW_TEMPLATE, UiStyle.BACKGROUND_COLOR)
row.Size = UDim2.fromScale(1, ROW_HEIGHT_SHARE)
row.Visible = false
row.Parent = rows
addCorner(row)

local rowIcon = makeImage(Constants.GEAR_MENU_ROW_ICON, Icons.PLACEHOLDER)
rowIcon.AnchorPoint = Vector2.new(0.5, 0)
rowIcon.Position = UDim2.fromScale(ROW_HEADER_WIDTH_SHARE / 2, 0.1)
rowIcon.Size = UDim2.fromScale(ROW_HEADER_WIDTH_SHARE * 0.7, 0.5)
addAspect(rowIcon, 1)
rowIcon.Parent = row

local rowName = makeLabel(Constants.GEAR_MENU_ROW_NAME_LABEL, UiStyle.formatTitle("Pick Axes"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 24)
rowName.AnchorPoint = Vector2.new(0.5, 1)
rowName.Position = UDim2.fromScale(ROW_HEADER_WIDTH_SHARE / 2, 0.9)
rowName.Size = UDim2.fromScale(ROW_HEADER_WIDTH_SHARE * 0.9, 0.22)
rowName.Parent = row

local itemList = Instance.new("ScrollingFrame")
itemList.Name = Constants.GEAR_MENU_ROW_ITEM_LIST
itemList.AnchorPoint = Vector2.new(0, 0.5)
itemList.Position = UDim2.fromScale(ROW_STRIP_LEFT_SHARE, 0.5)
itemList.Size = UDim2.fromScale(1 - ROW_STRIP_LEFT_SHARE - 0.02, 0.9)
itemList.BackgroundTransparency = 1
itemList.BorderSizePixel = 0
itemList.ScrollBarThickness = 6
itemList.ScrollBarImageColor3 = UiStyle.TEXT_MUTED_COLOR
itemList.ScrollingDirection = Enum.ScrollingDirection.X
itemList.AutomaticCanvasSize = Enum.AutomaticSize.X
itemList.CanvasSize = UDim2.fromScale(0, 0)
itemList.Parent = row

local itemLayout = Instance.new("UIListLayout")
itemLayout.FillDirection = Enum.FillDirection.Horizontal
itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
itemLayout.VerticalAlignment = Enum.VerticalAlignment.Center
itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
itemLayout.Padding = UDim.new(ITEM_GAP_SHARE, 0)
itemLayout.Parent = itemList

-- a card takes the strip's height; its width follows from the aspect
local item = Instance.new("ImageButton")
item.Name = Constants.GEAR_MENU_ITEM_TEMPLATE
item.Size = UDim2.fromScale(0, 0.9)
addAspect(item, ITEM_ASPECT, Enum.DominantAxis.Height)
item.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
item.BorderSizePixel = 0
item.AutoButtonColor = true
item.Image = ""
item.Visible = false
item.Parent = itemList
addCorner(item)

local itemIcon = makeImage(Constants.GEAR_MENU_ITEM_ICON, Icons.PLACEHOLDER)
itemIcon.AnchorPoint = Vector2.new(0.5, 0)
itemIcon.Position = UDim2.fromScale(0.5, 0.06)
itemIcon.Size = UDim2.fromScale(0.7, 0.6)
addAspect(itemIcon, 1)
itemIcon.Parent = item

local itemName = makeLabel(Constants.GEAR_MENU_ITEM_NAME_LABEL, "Standard issue", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, 22)
itemName.AnchorPoint = Vector2.new(0.5, 1)
itemName.Position = UDim2.fromScale(0.5, 0.94)
itemName.Size = UDim2.fromScale(0.9, 0.22)
itemName.Parent = item

-- an EQUIPPED tag across the card's top corner on the one worn
local equippedTag = makeLabel(Constants.GEAR_MENU_ITEM_EQUIPPED_LABEL, UiStyle.formatTitle("Equipped"), UiStyle.TITLE_FONT, BLACK, 16)
equippedTag.AnchorPoint = Vector2.new(1, 0)
equippedTag.Position = UDim2.fromScale(0.97, 0.04)
equippedTag.Size = UDim2.fromScale(0.55, 0.14)
equippedTag.BackgroundTransparency = 0
equippedTag.BackgroundColor3 = UiStyle.POSITIVE_COLOR
equippedTag.Visible = false
equippedTag.Parent = item
addCorner(equippedTag, UiStyle.CORNER_RADIUS_PX // 2)

-- a lock over the picture of a card not owned
local lockIcon = makeImage(Constants.GEAR_MENU_ITEM_LOCK_ICON, Icons.UI.LOCK)
lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
lockIcon.Position = UDim2.fromScale(0.5, 0.36)
lockIcon.Size = UDim2.fromScale(0.3, 0.3)
addAspect(lockIcon, 1)
lockIcon.ZIndex = 2
lockIcon.Visible = false
lockIcon.Parent = item

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("GearMenu gui")
return "GearMenu gui built"
