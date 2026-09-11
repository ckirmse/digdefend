-- Rebuilds the lobby "HUD" ScreenGui under StarterGui. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the lobby place; it replaces
-- any existing copy. Names must match Constants.HUD_*; each loadout slot
-- carries the Attributes.LOADOUT_SLOT attribute. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Enums = require(game.ReplicatedStorage.Shared.Enums)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before HUD gui")

local existing = StarterGui:FindFirstChild("HUD")
if existing then
	existing:Destroy()
end

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

local function addSizeBounds(frame, minSize, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = minSize
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addAspect(frame, ratio)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = frame
end

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- Cash wallet, top center (designer decision 2026-09-11); a button because
-- tapping it opens the store later
local cashWallet = Instance.new("TextButton")
cashWallet.Name = "CashWallet"
cashWallet.AnchorPoint = Vector2.new(0.5, 0)
cashWallet.Position = UDim2.fromScale(0.5, 0.03)
cashWallet.Size = UDim2.fromScale(0.16, 0.07)
addSizeBounds(cashWallet, Vector2.new(140, 40), Vector2.new(320, 72))
cashWallet.BackgroundColor3 = UiStyle.PANEL_COLOR
cashWallet.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
cashWallet.BorderSizePixel = 0
cashWallet.Text = ""
cashWallet.AutoButtonColor = true
cashWallet.Parent = gui
addCorner(cashWallet)

local cashIcon = Instance.new("TextLabel")
cashIcon.Name = "Icon"
cashIcon.Position = UDim2.fromScale(0.04, 0.1)
cashIcon.Size = UDim2.fromScale(0.2, 0.8)
cashIcon.BackgroundTransparency = 1
cashIcon.Text = "$"
cashIcon.TextColor3 = UiStyle.ACCENT_COLOR
cashIcon.TextScaled = true
cashIcon.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(cashIcon, UiStyle.BODY_TEXT_MIN_PX, UiStyle.TITLE_TEXT_MAX_PX)
cashIcon.Parent = cashWallet

local cashAmount = Instance.new("TextLabel")
cashAmount.Name = "CashAmount"
cashAmount.Position = UDim2.fromScale(0.26, 0.1)
cashAmount.Size = UDim2.fromScale(0.7, 0.8)
cashAmount.BackgroundTransparency = 1
cashAmount.Text = "0"
cashAmount.TextColor3 = UiStyle.TEXT_COLOR
cashAmount.TextXAlignment = Enum.TextXAlignment.Left
cashAmount.TextScaled = true
cashAmount.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(cashAmount, UiStyle.BODY_TEXT_MIN_PX, 32)
cashAmount.Parent = cashWallet

-- Menu buttons, right edge, stacked
local menuButtons = Instance.new("Frame")
menuButtons.Name = "MenuButtons"
menuButtons.AnchorPoint = Vector2.new(1, 0.5)
menuButtons.Position = UDim2.fromScale(0.98, 0.5)
menuButtons.Size = UDim2.fromScale(0.12, 0.3)
addSizeBounds(menuButtons, Vector2.new(96, 150), Vector2.new(220, 330))
menuButtons.BackgroundTransparency = 1
menuButtons.Parent = gui

local menuLayout = Instance.new("UIListLayout")
menuLayout.FillDirection = Enum.FillDirection.Vertical
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
menuLayout.Padding = UDim.new(0.05, 0)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Parent = menuButtons

local menuButtonNames = {
	{ name = "StoreButton", text = "Store" },
	{ name = "LoadoutButton", text = "Loadout" },
	{ name = "DailyRewardsButton", text = "Daily Rewards" },
}
for order, entry in menuButtonNames do
	local button = Instance.new("TextButton")
	button.Name = entry.name
	button.LayoutOrder = order
	button.Size = UDim2.fromScale(1, 0.3)
	addAspect(button, 2.4)
	button.BackgroundColor3 = UiStyle.PANEL_COLOR
	button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(entry.text)
	button.TextColor3 = UiStyle.ACCENT_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(button, UiStyle.BODY_TEXT_MIN_PX, 28)
	button.Parent = menuButtons
	addCorner(button)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.Parent = button
end

-- Loadout strip, bottom center: a row of five square slot icons over a row
-- of labels, where one "Defense" label spans the three defense slots
-- (designer decision 2026-09-11). Widths: slot 0.18, gap 0.02, so the
-- Defense label is 3 * 0.18 + 2 * 0.02 wide.
local SLOT_WIDTH_SCALE = 0.18
local SLOT_GAP_SCALE = 0.02
local ICON_ROW_HEIGHT_SCALE = 0.74
local LABEL_ROW_HEIGHT_SCALE = 0.2

local loadoutStrip = Instance.new("Frame")
loadoutStrip.Name = "LoadoutStrip"
loadoutStrip.AnchorPoint = Vector2.new(0.5, 1)
loadoutStrip.Position = UDim2.fromScale(0.5, 0.97)
loadoutStrip.Size = UDim2.fromScale(0.4, 0.14)
-- the strip's aspect makes a square icon of ICON_ROW_HEIGHT exactly
-- SLOT_WIDTH wide, so the label row lines up with the icons above it
addSizeBounds(loadoutStrip, Vector2.new(280, 68), Vector2.new(640, 156))
addAspect(loadoutStrip, ICON_ROW_HEIGHT_SCALE / SLOT_WIDTH_SCALE)
loadoutStrip.BackgroundTransparency = 1
loadoutStrip.Parent = gui

local iconRow = Instance.new("Frame")
iconRow.Name = "IconRow"
iconRow.Size = UDim2.fromScale(1, ICON_ROW_HEIGHT_SCALE)
iconRow.BackgroundTransparency = 1
iconRow.Parent = loadoutStrip

local iconLayout = Instance.new("UIListLayout")
iconLayout.FillDirection = Enum.FillDirection.Horizontal
iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
iconLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
iconLayout.Padding = UDim.new(SLOT_GAP_SCALE, 0)
iconLayout.SortOrder = Enum.SortOrder.LayoutOrder
iconLayout.Parent = iconRow

local slots = {
	Enums.LoadoutSlot.WEAPON,
	Enums.LoadoutSlot.POST,
	Enums.LoadoutSlot.DEFENSE_1,
	Enums.LoadoutSlot.DEFENSE_2,
	Enums.LoadoutSlot.DEFENSE_3,
}
for order, slot in slots do
	local icon = Instance.new("ImageLabel")
	icon.Name = "Slot" .. Enums.getName(Enums.LoadoutSlot, slot)
	icon:SetAttribute("LoadoutSlot", slot)
	icon.LayoutOrder = order
	icon.Size = UDim2.fromScale(SLOT_WIDTH_SCALE, 1)
	addAspect(icon, 1)
	icon.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	icon.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	icon.BorderSizePixel = 0
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = iconRow
	addCorner(icon)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = UiStyle.PANEL_COLOR
	stroke.Parent = icon
end

local labelRow = Instance.new("Frame")
labelRow.Name = "LabelRow"
labelRow.AnchorPoint = Vector2.new(0, 1)
labelRow.Position = UDim2.fromScale(0, 1)
labelRow.Size = UDim2.fromScale(1, LABEL_ROW_HEIGHT_SCALE)
labelRow.BackgroundTransparency = 1
labelRow.Parent = loadoutStrip

local labelLayout = Instance.new("UIListLayout")
labelLayout.FillDirection = Enum.FillDirection.Horizontal
labelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
labelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
labelLayout.Padding = UDim.new(SLOT_GAP_SCALE, 0)
labelLayout.SortOrder = Enum.SortOrder.LayoutOrder
labelLayout.Parent = labelRow

local labels = {
	{ name = "WeaponLabel", text = Enums.getPublicName(Enums.LoadoutSlot, Enums.LoadoutSlot.WEAPON), slotSpan = 1 },
	{ name = "PostLabel", text = Enums.getPublicName(Enums.LoadoutSlot, Enums.LoadoutSlot.POST), slotSpan = 1 },
	{ name = "DefenseLabel", text = Enums.getPublicName(Enums.LoadoutSlot, Enums.LoadoutSlot.DEFENSE_1), slotSpan = 3 },
}
for order, entry in labels do
	local widthScale = entry.slotSpan * SLOT_WIDTH_SCALE + (entry.slotSpan - 1) * SLOT_GAP_SCALE
	local label = Instance.new("TextLabel")
	label.Name = entry.name
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(widthScale, 1)
	label.BackgroundColor3 = UiStyle.PANEL_COLOR
	label.BackgroundTransparency = 0.45
	label.BorderSizePixel = 0
	label.Text = entry.text
	label.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	label.TextScaled = true
	label.FontFace = UiStyle.BODY_FONT
	addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
	label.Parent = labelRow
	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX // 2)
	labelCorner.Parent = label
end

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("HUD gui")
return "HUD gui built"
