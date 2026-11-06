-- Rebuilds the lobby "SupplyCrateChoice" ScreenGui under StarterGui
-- (designer, 2026-11-05): the Supply Crate stall's first screen, a small
-- dialog with Back and two plates, OPEN SUPPLY CRATES (into the crate
-- menu) and KEY STORE (into the Key Store). Run from the Studio command
-- bar (or the MCP execute_luau tool) in the lobby place; it replaces any
-- existing copy. Names must match Constants.SUPPLY_CRATE_CHOICE_*. Layout
-- follows the GUI standard in CLAUDE.md; fonts and colours come from
-- Shared/UiStyle. ClientSupplyCrateChoiceManager only enables it and wires
-- the three buttons.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before SupplyCrateChoice gui")

local existing = StarterGui:FindFirstChild(Constants.SUPPLY_CRATE_CHOICE_GUI_NAME)
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5
local DIALOG_ASPECT = 1.6
local DIALOG_MAX_SIZE = Vector2.new(720, 450)
-- the designer's slice rectangles on the plate picture (the Class Menu's)
local WIDE_PLATE_SLICE = Rect.new(136, 207, 292, 291)
local TALL_PLATE_SLICE = Rect.new(136, 105, 356, 400)

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
	addTextSizeBounds(label, maxPx)
	return label
end

-- a button on the designer's slice plate, tinted by ImageColor3, its word
-- a centred TextLabel child the manager never touches
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
	label.Parent = button
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = Constants.SUPPLY_CRATE_CHOICE_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = Constants.MENU_DIALOG_FRAME
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.6, 0.55)
addAspect(dialog, DIALOG_ASPECT)
addMaxSize(dialog, DIALOG_MAX_SIZE)
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)

local backButton = makePlateButton(Constants.SUPPLY_CRATE_CHOICE_BACK_BUTTON, "Back", UiStyle.TOGGLE_OFF_COLOR, TALL_PLATE_SLICE, 28)
backButton.AnchorPoint = Vector2.new(0, 0)
backButton.Position = UDim2.fromScale(0.04, 0.06)
backButton.Size = UDim2.fromScale(0.2, 0.14)
backButton.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Supply Crate Store"), UiStyle.TITLE_FONT, UiStyle.TEXT_COLOR, 44)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0.06)
title.Size = UDim2.fromScale(0.5, 0.14)
title.Parent = dialog

-- the two roads, side by side: the crate in the accent, the Key Store in
-- the Keys' own colour
local cratesButton = makePlateButton(Constants.SUPPLY_CRATE_CHOICE_CRATES_BUTTON, "Open Supply Crates", UiStyle.ACCENT_COLOR, WIDE_PLATE_SLICE, 34)
cratesButton.AnchorPoint = Vector2.new(0, 0.5)
cratesButton.Position = UDim2.fromScale(0.06, 0.6)
cratesButton.Size = UDim2.fromScale(0.42, 0.5)
cratesButton.Parent = dialog

local keyStoreButton = makePlateButton(Constants.SUPPLY_CRATE_CHOICE_KEY_STORE_BUTTON, "Key Store", UiStyle.SUPPLY_CRATE_BUTTON_COLOR, WIDE_PLATE_SLICE, 34)
keyStoreButton.AnchorPoint = Vector2.new(1, 0.5)
keyStoreButton.Position = UDim2.fromScale(0.94, 0.6)
keyStoreButton.Size = UDim2.fromScale(0.42, 0.5)
keyStoreButton.Parent = dialog

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("SupplyCrateChoice gui")
return "SupplyCrateChoice gui built"
