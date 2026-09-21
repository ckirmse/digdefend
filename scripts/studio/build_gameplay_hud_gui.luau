-- Rebuilds the "GameplayHud" ScreenGui under StarterGui: the right-edge
-- stack (the backpack button with icon, "taken/total", and the "Backpack
-- full" label, always shown, and the jet pack fuel bar under it, GDD
-- "Mining Rock" and "Jet Pack"); the balance rows top left that
-- ClientRefineryManager keeps current (GDD "Refining Ore"); and the FlyLayer
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

-- the right-edge stack, centred vertically (decided 2026-09-16): clear of
-- the top-left chat window, and above the jet pack and jump buttons in the
-- bottom-right corner. Backpack button, then the jet pack bar under it; a
-- list layout keeps them stacked at every aspect. Scale only, no pixel
-- minimum: a minimum would override scale on exactly the small screens it
-- was meant to help (GUI standard, 2026-09-16)
local stack = Instance.new("Frame")
stack.Name = "RightStack"
stack.AnchorPoint = Vector2.new(1, 0.5)
-- a little above centre so a phone's jet button sits under it (2026-09-16)
stack.Position = UDim2.fromScale(0.985, 0.4)
stack.Size = UDim2.fromScale(0.11, 0.16)
local stackAspect = Instance.new("UIAspectRatioConstraint")
stackAspect.AspectRatio = 1.5
stackAspect.DominantAxis = Enum.DominantAxis.Width
stackAspect.Parent = stack
local stackSize = Instance.new("UISizeConstraint")
stackSize.MaxSize = Vector2.new(260, 180)
stackSize.Parent = stack
stack.BackgroundTransparency = 1
local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Padding = UDim.new(0.05, 0)
stackLayout.Parent = stack
stack.Parent = gui

local button = Instance.new("TextButton")
button.Name = "BackpackButton"
button.LayoutOrder = 1
button.Size = UDim2.fromScale(1, 0.6)
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 2.2
aspect.Parent = button
local size = Instance.new("UISizeConstraint")
size.MaxSize = Vector2.new(260, 118)
size.Parent = button
button.BackgroundColor3 = UiStyle.PANEL_COLOR
button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = true
button.Visible = true
button.Parent = stack
addCorner(button)

-- the backpack picture (Icons.UI.BACKPACK, set by ClientBackpackManager)
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.Position = UDim2.fromScale(0.05, 0.12)
icon.Size = UDim2.fromScale(0.28, 0.76)
icon.BackgroundTransparency = 1
icon.Image = if Icons.isPlaceholder(Icons.UI.BACKPACK) then "" else Icons.UI.BACKPACK
icon.ScaleType = Enum.ScaleType.Fit
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.Parent = icon
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
balances.AnchorPoint = Vector2.new(0, 0.5)
-- left edge, centred vertically (decided 2026-09-16): below the chat window,
-- which owns the top-left corner, and small enough to stay above a phone's
-- thumbstick; the aspect keeps the rows the same shape at every screen size
-- a little above centre, where the left thumb rests on a phone (2026-09-16)
balances.Position = UDim2.fromScale(0.015, 0.45)
balances.Size = UDim2.fromScale(0.14, 0.3)
balances.BackgroundTransparency = 1
local balancesAspect = Instance.new("UIAspectRatioConstraint")
balancesAspect.AspectRatio = 0.9
balancesAspect.DominantAxis = Enum.DominantAxis.Width
balancesAspect.Parent = balances
local balancesSize = Instance.new("UISizeConstraint")
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

-- jet pack fuel bar under the backpack button, always shown: an icon on the
-- left so it reads as the jet pack, and the fill track beside it
local jetBar = Instance.new("Frame")
jetBar.Name = "JetPackBar"
jetBar.LayoutOrder = 2
jetBar.Size = UDim2.fromScale(1, 0.3)
local jetAspectBar = Instance.new("UIAspectRatioConstraint")
jetAspectBar.AspectRatio = 4.4
jetAspectBar.Parent = jetBar
local jetBarSize = Instance.new("UISizeConstraint")
jetBarSize.MaxSize = Vector2.new(260, 59)
jetBarSize.Parent = jetBar
jetBar.BackgroundColor3 = UiStyle.PANEL_COLOR
jetBar.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
jetBar.BorderSizePixel = 0
jetBar.Visible = true
jetBar.Parent = stack
addCorner(jetBar)
-- the jet pack picture (Icons.UI.JET_PACK, set by ClientJetPackManager)
local jetIcon = Instance.new("ImageLabel")
jetIcon.Name = "Icon"
jetIcon.Position = UDim2.fromScale(0.05, 0.1)
jetIcon.Size = UDim2.fromScale(0.2, 0.8)
jetIcon.BackgroundTransparency = 1
jetIcon.Image = if Icons.isPlaceholder(Icons.UI.JET_PACK) then "" else Icons.UI.JET_PACK
jetIcon.ScaleType = Enum.ScaleType.Fit
local jetIconAspect = Instance.new("UIAspectRatioConstraint")
jetIconAspect.AspectRatio = 1
jetIconAspect.Parent = jetIcon
jetIcon.Parent = jetBar
local jetTrack = Instance.new("Frame")
jetTrack.Name = "Track"
jetTrack.AnchorPoint = Vector2.new(0, 0.5)
jetTrack.Position = UDim2.fromScale(0.3, 0.5)
jetTrack.Size = UDim2.fromScale(0.65, 0.4)
jetTrack.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
jetTrack.BorderSizePixel = 0
jetTrack.Parent = jetBar
addCorner(jetTrack)
local jetFill = Instance.new("Frame")
jetFill.Name = "Fill"
jetFill.Size = UDim2.fromScale(1, 1)
jetFill.BackgroundColor3 = UiStyle.ACCENT_COLOR
jetFill.BorderSizePixel = 0
jetFill.Parent = jetTrack
addCorner(jetFill)

-- touch-only jet pack button just above Roblox's jump button (bottom
-- right); this position is only the fallback, ClientTouchLayoutManager
-- re-places it against the live jump button. Keyboard and gamepad players
-- double-tap Jump instead
local jetButton = Instance.new("TextButton")
jetButton.Name = "JetPackButton"
jetButton.AnchorPoint = Vector2.new(1, 1)
jetButton.Position = UDim2.fromScale(0.98, 0.76)
jetButton.Size = UDim2.fromScale(0.08, 0.08)
local jetAspect = Instance.new("UIAspectRatioConstraint")
jetAspect.AspectRatio = 1
jetAspect.Parent = jetButton
-- the one minimum in this gui: a touch target never drops under 44 points
local jetButtonSize = Instance.new("UISizeConstraint")
jetButtonSize.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
jetButtonSize.MaxSize = Vector2.new(130, 130)
jetButtonSize.Parent = jetButton
jetButton.BackgroundColor3 = UiStyle.PANEL_COLOR
jetButton.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
jetButton.BorderSizePixel = 0
jetButton.Text = "JET"
jetButton.TextColor3 = UiStyle.TEXT_COLOR
jetButton.TextScaled = true
jetButton.FontFace = UiStyle.TITLE_FONT
jetButton.AutoButtonColor = true
jetButton.Visible = false
addTextSizeBounds(jetButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
jetButton.Parent = gui
local jetCorner = Instance.new("UICorner")
jetCorner.CornerRadius = UDim.new(0.5, 0)
jetCorner.Parent = jetButton

-- touch-only action button left of the jump button (fallback position;
-- ClientTouchLayoutManager re-places it against the live jump button): the
-- equipped tool's one action (swing, throw, place). Until tool icons exist
-- the label carries the tool name, like the tool bar slots
local actionButton = Instance.new("TextButton")
actionButton.Name = "ActionButton"
actionButton.AnchorPoint = Vector2.new(1, 1)
actionButton.Position = UDim2.fromScale(0.86, 0.9)
actionButton.Size = UDim2.fromScale(0.11, 0.11)
local actionAspect = Instance.new("UIAspectRatioConstraint")
actionAspect.AspectRatio = 1
actionAspect.Parent = actionButton
local actionSize = Instance.new("UISizeConstraint")
actionSize.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
actionSize.MaxSize = Vector2.new(130, 130)
actionSize.Parent = actionButton
actionButton.BackgroundColor3 = UiStyle.PANEL_COLOR
actionButton.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
actionButton.BorderSizePixel = 0
actionButton.Text = ""
actionButton.AutoButtonColor = true
actionButton.Visible = false
actionButton.Parent = gui
local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0.5, 0)
actionCorner.Parent = actionButton
local actionIcon = Instance.new("ImageLabel")
actionIcon.Name = "Icon"
actionIcon.Position = UDim2.fromScale(0.15, 0.15)
actionIcon.Size = UDim2.fromScale(0.7, 0.7)
actionIcon.BackgroundTransparency = 1
actionIcon.Image = ""
actionIcon.ScaleType = Enum.ScaleType.Fit
actionIcon.Parent = actionButton
local actionLabel = Instance.new("TextLabel")
actionLabel.Name = "Label"
actionLabel.Position = UDim2.fromScale(0.1, 0.3)
actionLabel.Size = UDim2.fromScale(0.8, 0.4)
actionLabel.BackgroundTransparency = 1
actionLabel.Text = "PICK AXE"
actionLabel.TextColor3 = UiStyle.TEXT_COLOR
actionLabel.TextScaled = true
actionLabel.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(actionLabel, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
actionLabel.Parent = actionButton

-- the layer flying icons cross; above everything else in this gui
local flyLayer = Instance.new("Frame")
flyLayer.Name = "FlyLayer"
flyLayer.Size = UDim2.fromScale(1, 1)
flyLayer.BackgroundTransparency = 1
flyLayer.ZIndex = 10
flyLayer.Parent = gui

-- the icon ClientIconFlightManager clones for every flight: a square that
-- keeps between 72 and 176 px; as a coloured disc (no image) it shows the
-- corner and hairline, which the code switches off when an image is set
local flyIcon = Instance.new("ImageLabel")
flyIcon.Name = "FlyIconTemplate"
flyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
flyIcon.Position = UDim2.fromScale(0.5, 0.5)
flyIcon.Size = UDim2.fromScale(0.12, 0.12)
flyIcon.ScaleType = Enum.ScaleType.Fit
flyIcon.BackgroundColor3 = UiStyle.ACCENT_COLOR
flyIcon.BackgroundTransparency = 0
flyIcon.BorderSizePixel = 0
flyIcon.ZIndex = flyLayer.ZIndex + 1
flyIcon.Visible = false
local flyIconAspect = Instance.new("UIAspectRatioConstraint")
flyIconAspect.AspectRatio = 1
flyIconAspect.Parent = flyIcon
local flyIconSize = Instance.new("UISizeConstraint")
flyIconSize.MinSize = Vector2.new(72, 72)
flyIconSize.MaxSize = Vector2.new(176, 176)
flyIconSize.Parent = flyIcon
local flyIconCorner = Instance.new("UICorner")
flyIconCorner.CornerRadius = UDim.new(0.5, 0)
flyIconCorner.Parent = flyIcon
local flyIconStroke = Instance.new("UIStroke")
flyIconStroke.Color = UiStyle.BACKGROUND_COLOR
flyIconStroke.Thickness = 1
flyIconStroke.Parent = flyIcon
flyIcon.Parent = flyLayer

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GameplayHud gui")
print("build_gameplay_hud_gui: built StarterGui.GameplayHud")
