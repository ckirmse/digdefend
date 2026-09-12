-- Rebuilds the "GameplayHud" ScreenGui under StarterGui: the backpack button
-- (icon, "taken/total", and the "Backpack full" label) that
-- ClientBackpackManager shows while the pick axe is held (GDD "Mining
-- Rock"). Later milestones add the resource balances. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.GAMEPLAY_HUD_* /
-- HUD_BACKPACK_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

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
count.Text = "0/50"
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

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GameplayHud gui")
print("build_gameplay_hud_gui: built StarterGui.GameplayHud")
