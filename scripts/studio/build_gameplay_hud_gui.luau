-- Rebuilds the "GameplayHud" ScreenGui under StarterGui: the backpack button
-- (icon, "taken/total", and the "Backpack full" label) that
-- ClientBackpackManager shows while the pick axe is held (GDD "Mining
-- Rock"); the balance rows top left that ClientRefineryManager keeps
-- current (GDD "Refining Ore"); and the FlyLayer
-- its icons travel across. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.GAMEPLAY_HUD_* / HUD_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local Enums = require(game.ReplicatedStorage.Shared.Enums)

ChangeHistoryService:SetWaypoint("Before GameplayHud gui")

local existing = StarterGui:FindFirstChild("GameplayHud")
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
gui.Name = "GameplayHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- bottom-right, clear of the tool bar in the centre
local button = Instance.new("TextButton")
button.Name = "BackpackButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.fromScale(0.98, 0.97)
button.Size = UDim2.fromScale(0.11, 0.08)
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 2.2
aspect.Parent = button
local size = Instance.new("UISizeConstraint")
size.MinSize = Vector2.new(110, 50)
size.MaxSize = Vector2.new(260, 118)
size.Parent = button
button.BackgroundColor3 = UiStyle.PANEL_COLOR
button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = true
button.Visible = false
button.Parent = gui
addCorner(button)

-- placeholder icon until art: a bag glyph
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Position = UDim2.fromScale(0.05, 0.12)
icon.Size = UDim2.fromScale(0.28, 0.76)
icon.BackgroundTransparency = 1
icon.Text = "🎒"
icon.TextScaled = true
icon.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(icon, UiStyle.BODY_TEXT_MIN_PX, 40)
icon.Parent = button

local count = Instance.new("TextLabel")
count.Name = "CountLabel"
count.Position = UDim2.fromScale(0.36, 0.12)
count.Size = UDim2.fromScale(0.6, 0.5)
count.BackgroundTransparency = 1
count.Text = "0/15"
count.TextColor3 = UiStyle.TEXT_COLOR
count.TextScaled = true
count.TextXAlignment = Enum.TextXAlignment.Left
count.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(count, UiStyle.BODY_TEXT_MIN_PX, 32)
count.Parent = button

local full = Instance.new("TextLabel")
full.Name = "FullLabel"
full.Position = UDim2.fromScale(0.36, 0.6)
full.Size = UDim2.fromScale(0.6, 0.3)
full.BackgroundTransparency = 1
full.Text = "Backpack full"
full.TextColor3 = UiStyle.NEGATIVE_COLOR
full.TextScaled = true
full.TextXAlignment = Enum.TextXAlignment.Left
full.FontFace = UiStyle.BODY_FONT
full.Visible = false
addTextSizeBounds(full, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.LABEL_TEXT_MAX_PX)
full.Parent = button

-- balances, top left, one row per resource; the icon comes from Icons, with
-- a coloured disc for any entry still at the placeholder
local balances = Instance.new("Frame")
balances.Name = "Balances"
balances.AnchorPoint = Vector2.new(0, 0)
-- below the open chat window, which owns the top-left corner
balances.Position = UDim2.fromScale(0.015, 0.4)
balances.Size = UDim2.fromScale(0.18, 0.32)
balances.BackgroundTransparency = 1
local balancesSize = Instance.new("UISizeConstraint")
balancesSize.MinSize = Vector2.new(170, 192)
balancesSize.MaxSize = Vector2.new(420, 480)
balancesSize.Parent = balances
local balancesLayout = Instance.new("UIListLayout")
balancesLayout.FillDirection = Enum.FillDirection.Vertical
balancesLayout.SortOrder = Enum.SortOrder.LayoutOrder
balancesLayout.Padding = UDim.new(0.04, 0)
balancesLayout.Parent = balances
balances.Parent = gui

local ROWS = {
	{ name = "IronRow", image = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR], color = Color3.fromRGB(160, 165, 175), text = "0" },
	{ name = "GoldRow", image = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR], color = Color3.fromRGB(240, 200, 60), text = "0" },
	{ name = "UraniumRow", image = Icons.REFINED_RESOURCE[Enums.RefinedResource.URANIUM], color = Color3.fromRGB(120, 240, 90), text = "0 / 0" },
}
for order, spec in ROWS do
	local row = Instance.new("Frame")
	row.Name = spec.name
	row.LayoutOrder = order
	row.Size = UDim2.fromScale(1, 0.3)
	row.BackgroundColor3 = UiStyle.PANEL_COLOR
	row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	addCorner(row)
	local isImage = not Icons.isPlaceholder(spec.image)
	local rowIcon = Instance.new("ImageLabel")
	rowIcon.Name = "Icon"
	rowIcon.AnchorPoint = Vector2.new(0, 0.5)
	rowIcon.Position = UDim2.fromScale(0.05, 0.5)
	rowIcon.Size = UDim2.fromScale(0.7, 0.7)
	rowIcon.Image = if isImage then spec.image else ""
	rowIcon.ScaleType = Enum.ScaleType.Fit
	rowIcon.BackgroundColor3 = spec.color
	rowIcon.BackgroundTransparency = if isImage then 1 else 0
	rowIcon.BorderSizePixel = 0
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = rowIcon
	if not isImage then
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0.5, 0)
		iconCorner.Parent = rowIcon
	end
	rowIcon.Parent = row
	local value = Instance.new("TextLabel")
	value.Name = "ValueLabel"
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.fromScale(0.3, 0.5)
	value.Size = UDim2.fromScale(0.66, 0.8)
	value.BackgroundTransparency = 1
	value.Text = spec.text
	value.TextColor3 = UiStyle.TEXT_COLOR
	value.TextScaled = true
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.FontFace = UiStyle.BODY_BOLD_FONT
	addTextSizeBounds(value, UiStyle.BODY_TEXT_MIN_PX, 30)
	value.Parent = row
	row.Parent = balances
end

-- the layer flying icons cross; above everything else in this gui
local flyLayer = Instance.new("Frame")
flyLayer.Name = "FlyLayer"
flyLayer.Size = UDim2.fromScale(1, 1)
flyLayer.BackgroundTransparency = 1
flyLayer.ZIndex = 10
flyLayer.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GameplayHud gui")
print("build_gameplay_hud_gui: built StarterGui.GameplayHud")
