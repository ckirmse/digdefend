-- Rebuilds the "Backpack" ScreenGui under StarterGui: the contents menu
-- ClientBackpackManager opens from the HUD button (GDD "Collecting Ore"),
-- one row per ore carried cloned from RowTemplate. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.BACKPACK_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before Backpack gui")

local existing = StarterGui:FindFirstChild("Backpack")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5

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

local function makeLabel(name, text, font, color, minPx, maxPx)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = font
	label.TextTruncate = Enum.TextTruncate.AtEnd
	addTextSizeBounds(label, minPx, maxPx)
	return label
end

local gui = Instance.new("ScreenGui")
gui.Name = "Backpack"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.Size = UDim2.fromScale(0.3, 0.5)
local dialogAspect = Instance.new("UIAspectRatioConstraint")
dialogAspect.AspectRatio = 0.85
dialogAspect.Parent = dialog
addSizeBounds(dialog, Vector2.new(240, 280), Vector2.new(480, 560))
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)
local dialogStroke = Instance.new("UIStroke")
dialogStroke.Thickness = UiStyle.STROKE_PX
dialogStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dialogStroke.Parent = dialog

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.06, 0)
padding.PaddingRight = UDim.new(0.06, 0)
padding.PaddingTop = UDim.new(0.03, 0)
padding.PaddingBottom = UDim.new(0.03, 0)
padding.Parent = dialog

local rows = Instance.new("UIListLayout")
rows.FillDirection = Enum.FillDirection.Vertical
rows.HorizontalAlignment = Enum.HorizontalAlignment.Center
rows.VerticalAlignment = Enum.VerticalAlignment.Top
rows.Padding = UDim.new(0.015, 0)
rows.SortOrder = Enum.SortOrder.LayoutOrder
rows.Parent = dialog

local title = makeLabel("Title", UiStyle.formatTitle("Backpack"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 48)
title.LayoutOrder = 1
title.Size = UDim2.fromScale(1, 0.12)
title.Parent = dialog

local list = Instance.new("Frame")
list.Name = "List"
list.LayoutOrder = 2
list.Size = UDim2.fromScale(1, 0.66)
list.BackgroundTransparency = 1
list.Parent = dialog

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Padding = UDim.new(0.02, 0)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local row = Instance.new("Frame")
row.Name = "RowTemplate"
row.Size = UDim2.fromScale(1, 0.14)
addSizeBounds(row, Vector2.new(200, 28), Vector2.new(440, 56))
row.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
row.BorderSizePixel = 0
row.Visible = false
row.Parent = list
addCorner(row)
local rowPadding = Instance.new("UIPadding")
rowPadding.PaddingLeft = UDim.new(0, 12)
rowPadding.PaddingRight = UDim.new(0, 12)
rowPadding.Parent = row

local nameLabel = makeLabel("NameLabel", "Iron Ore", UiStyle.BODY_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
nameLabel.Position = UDim2.fromScale(0, 0.1)
nameLabel.Size = UDim2.fromScale(0.65, 0.8)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = row

local amountLabel = makeLabel("AmountLabel", "0", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
amountLabel.Position = UDim2.fromScale(0.65, 0.1)
amountLabel.Size = UDim2.fromScale(0.35, 0.8)
amountLabel.TextXAlignment = Enum.TextXAlignment.Right
amountLabel.Parent = row

local emptyLabel = makeLabel("EmptyLabel", "Nothing in your backpack yet", UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
emptyLabel.LayoutOrder = 3
emptyLabel.Size = UDim2.fromScale(1, 0.08)
emptyLabel.Parent = dialog

local close = Instance.new("TextButton")
close.Name = "CloseButton"
close.LayoutOrder = 4
close.Size = UDim2.fromScale(0.6, 0.11)
addSizeBounds(close, Vector2.new(120, 44), Vector2.new(320, 80))
close.BackgroundColor3 = UiStyle.ACCENT_COLOR
close.BorderSizePixel = 0
close.Text = UiStyle.formatTitle("Close")
close.TextColor3 = UiStyle.ACCENT_STROKE_COLOR
close.TextScaled = true
close.FontFace = UiStyle.TITLE_FONT
close.AutoButtonColor = true
addTextSizeBounds(close, UiStyle.BODY_TEXT_MIN_PX, 34)
close.Parent = dialog
addCorner(close)

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After Backpack gui")
print("build_backpack_menu_gui: built StarterGui.Backpack")
