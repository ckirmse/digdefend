-- Rebuilds the "ToolBar" ScreenGui under StarterGui: a bottom-centre row of
-- tool slots that ClientToolBarManager fills by cloning SlotTemplate (GDD
-- "Tool Bar System"). Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.TOOL_BAR_* / TOOL_SLOT_*. Layout follows the
-- GUI standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before ToolBar gui")

local existing = StarterGui:FindFirstChild("ToolBar")
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

local gui = Instance.new("ScreenGui")
gui.Name = "ToolBar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- the row: up to nine square slots, each at least 44 px so it is a touch
-- target, never above 96 px so a 4K screen does not get a giant bar
local SLOT_SCALE = 0.07
local slots = Instance.new("Frame")
slots.Name = "Slots"
slots.AnchorPoint = Vector2.new(0.5, 1)
slots.Position = UDim2.fromScale(0.5, 0.97)
slots.Size = UDim2.fromScale(0.7, SLOT_SCALE * 1.4)
local slotsSize = Instance.new("UISizeConstraint")
slotsSize.MinSize = Vector2.new(300, 56)
slotsSize.MaxSize = Vector2.new(1000, 110)
slotsSize.Parent = slots
slots.BackgroundTransparency = 1
slots.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0.012, 0)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = slots

local template = Instance.new("TextButton")
template.Name = "SlotTemplate"
template.Size = UDim2.fromScale(0.1, 1)
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.Parent = template
local templateSize = Instance.new("UISizeConstraint")
templateSize.MinSize = Vector2.new(44, 44)
templateSize.MaxSize = Vector2.new(96, 96)
templateSize.Parent = template
template.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
template.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
template.BorderSizePixel = 0
template.Text = ""
template.AutoButtonColor = true
template.Visible = false
template.Parent = slots
addCorner(template)
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX
stroke.Color = UiStyle.PANEL_COLOR
stroke.Parent = template

-- icon fills the slot once tool icons exist; until then the label carries the name
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.Position = UDim2.fromScale(0.1, 0.1)
icon.Size = UDim2.fromScale(0.8, 0.8)
icon.BackgroundTransparency = 1
icon.Image = ""
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = template

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Position = UDim2.fromScale(0.05, 0.3)
label.Size = UDim2.fromScale(0.9, 0.4)
label.BackgroundTransparency = 1
label.Text = "TOOL"
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.TextWrapped = true
label.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
label.Parent = template

-- keyboard hint, top-left corner; ClientToolBarManager hides it without a keyboard
local keyLabel = Instance.new("TextLabel")
keyLabel.Name = "KeyLabel"
keyLabel.Position = UDim2.fromScale(0.06, 0.04)
keyLabel.Size = UDim2.fromScale(0.3, 0.26)
keyLabel.BackgroundTransparency = 1
keyLabel.Text = "1"
keyLabel.TextColor3 = UiStyle.TEXT_MUTED_COLOR
keyLabel.TextScaled = true
keyLabel.TextXAlignment = Enum.TextXAlignment.Left
keyLabel.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(keyLabel, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
keyLabel.Parent = template

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ToolBar gui")
print("build_tool_bar_gui: built StarterGui.ToolBar")
