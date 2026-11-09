-- Builds the "ControlsPanel" ScreenGui under StarterGui (both places,
-- 2026-11-09): a dark plate in the bottom right corner listing the keys
-- that do something right now, one row per control with the key in the
-- accent and the action beside it, a CONTROLS title with a collapse
-- button, and a small CONTROLS tab that stands in while it is collapsed.
-- ClientControlsPanelManager fills the rows from ControlsRules, sizes the
-- plate to the row count, and shows it for keyboard and gamepad players
-- only. Run from the Studio command bar (or the MCP execute_luau tool) in
-- each place; it replaces any existing copy. Names must match
-- Constants.CONTROLS_PANEL_*. Scale only, constraints for the max, no
-- pixel minimums (GUI standard); the corner is the touch jump button's,
-- which is fine since a touch device never shows this.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

-- the title and up to eight rows share the Root's height
local MAX_ROWS = 8
local ROW_SHARE = 1 / (MAX_ROWS + 1)
local ROOT_POSITION = UDim2.fromScale(0.99, 0.985)
local ROOT_SIZE = UDim2.fromScale(0.19, 0.34)
local ROOT_MAX_SIZE = Vector2.new(300, 380)
local KEY_WIDTH_SHARE = 0.42

ChangeHistoryService:SetWaypoint("Before ControlsPanel gui")

local existing = StarterGui:FindFirstChild("ControlsPanel")
if existing then
	existing:Destroy()
end

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

local function addPadding(parent, share)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(share, 0)
	padding.PaddingRight = UDim.new(share, 0)
	padding.Parent = parent
end

local gui = Instance.new("ScreenGui")
gui.Name = "ControlsPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the corner box every piece sits in; transparent, so the plate and the
-- tab are what shows
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(1, 1)
root.Position = ROOT_POSITION
root.Size = ROOT_SIZE
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = ROOT_MAX_SIZE
rootSize.Parent = root
root.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.fromScale(1, 1)
panel.Size = UDim2.fromScale(1, 4 * ROW_SHARE)
panel.BackgroundColor3 = UiStyle.PANEL_COLOR
panel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
panel.BorderSizePixel = 0
addCorner(panel)
local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel
panel.Parent = root

-- the title row: CONTROLS on the left, the collapse button on the right
local title = Instance.new("Frame")
title.Name = "Title"
title.LayoutOrder = 1
title.Size = UDim2.fromScale(1, 0.25)
title.BackgroundTransparency = 1
title.BorderSizePixel = 0
addPadding(title, 0.06)
title.Parent = panel

local titleText = Instance.new("TextLabel")
titleText.Name = "Text"
titleText.AnchorPoint = Vector2.new(0, 0.5)
titleText.Position = UDim2.fromScale(0, 0.5)
titleText.Size = UDim2.fromScale(0.75, 0.7)
titleText.BackgroundTransparency = 1
titleText.Text = UiStyle.formatTitle("Controls")
titleText.TextColor3 = UiStyle.TEXT_MUTED_COLOR
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextScaled = true
titleText.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(titleText, UiStyle.LABEL_TEXT_MAX_PX)
titleText.Parent = title

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.fromScale(1, 0.5)
toggleButton.Size = UDim2.fromScale(0.8, 0.8)
toggleButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
toggleButton.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
toggleButton.BorderSizePixel = 0
toggleButton.Text = "-"
toggleButton.TextColor3 = UiStyle.TEXT_COLOR
toggleButton.TextScaled = true
toggleButton.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(toggleButton, UiStyle.BODY_TEXT_MAX_PX)
addCorner(toggleButton)
toggleButton.Parent = title

local rows = Instance.new("Frame")
rows.Name = "Rows"
rows.LayoutOrder = 2
rows.Size = UDim2.fromScale(1, 0.75)
rows.BackgroundTransparency = 1
rows.BorderSizePixel = 0
local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = rows
rows.Parent = panel

-- one row: the key in the accent on the left, the action in body text
local rowTemplate = Instance.new("Frame")
rowTemplate.Name = "RowTemplate"
rowTemplate.Size = UDim2.fromScale(1, 1 / 3)
rowTemplate.BackgroundTransparency = 1
rowTemplate.BorderSizePixel = 0
rowTemplate.Visible = false
addPadding(rowTemplate, 0.06)
rowTemplate.Parent = rows

local key = Instance.new("TextLabel")
key.Name = "Key"
key.AnchorPoint = Vector2.new(0, 0.5)
key.Position = UDim2.fromScale(0, 0.5)
key.Size = UDim2.fromScale(KEY_WIDTH_SHARE, 0.7)
key.BackgroundTransparency = 1
key.Text = "LMB"
key.TextColor3 = UiStyle.ACCENT_COLOR
key.TextXAlignment = Enum.TextXAlignment.Left
key.TextScaled = true
key.FontFace = UiStyle.TITLE_SEMIBOLD_FONT
addTextSizeBounds(key, UiStyle.LABEL_TEXT_MAX_PX)
key.Parent = rowTemplate

local action = Instance.new("TextLabel")
action.Name = "Action"
action.AnchorPoint = Vector2.new(1, 0.5)
action.Position = UDim2.fromScale(1, 0.5)
action.Size = UDim2.fromScale(1 - KEY_WIDTH_SHARE - 0.02, 0.7)
action.BackgroundTransparency = 1
action.Text = "Swing pick axe"
action.TextColor3 = UiStyle.TEXT_COLOR
action.TextXAlignment = Enum.TextXAlignment.Left
action.TextScaled = true
action.TextTruncate = Enum.TextTruncate.AtEnd
action.FontFace = UiStyle.BODY_FONT
addTextSizeBounds(action, UiStyle.LABEL_TEXT_MAX_PX)
action.Parent = rowTemplate

-- the tab that stands in while the panel is collapsed
local collapsedTab = Instance.new("TextButton")
collapsedTab.Name = "CollapsedTab"
collapsedTab.AnchorPoint = Vector2.new(1, 1)
collapsedTab.Position = UDim2.fromScale(1, 1)
collapsedTab.Size = UDim2.fromScale(0.55, ROW_SHARE)
collapsedTab.BackgroundColor3 = UiStyle.PANEL_COLOR
collapsedTab.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
collapsedTab.BorderSizePixel = 0
collapsedTab.Text = UiStyle.formatTitle("Controls") .. " +"
collapsedTab.TextColor3 = UiStyle.TEXT_MUTED_COLOR
collapsedTab.TextScaled = true
collapsedTab.FontFace = UiStyle.TITLE_FONT
collapsedTab.Visible = false
addTextSizeBounds(collapsedTab, UiStyle.LABEL_TEXT_MAX_PX)
addCorner(collapsedTab)
addPadding(collapsedTab, 0.06)
collapsedTab.Parent = root

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ControlsPanel gui")
print("build_controls_panel_gui: built " .. gui:GetFullName())
