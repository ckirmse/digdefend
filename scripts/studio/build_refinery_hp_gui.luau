-- Builds the "RefineryHp" ScreenGui under StarterGui (GDD "Wave Cycle",
-- M33): the night's counterpart to the day clock, in the same box top
-- centre. A rounded square on the left holds the compass home icon (the
-- Refinery's mark everywhere in the HUD), a bar to its right that
-- ClientRefineryHpManager fills with the Refinery's HP in the HP colours,
-- and "REFINERY HP" under it. The client slides it down from above when
-- night falls and back up at dawn. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.REFINERY_HP_*. Scale only, constraints
-- for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)

-- the day clock's Root box (build_day_clock_gui.luau), taken over at night
local CLOCK_POSITION = UDim2.fromScale(0.5, 0.012)
local CLOCK_SIZE_SCALE = Vector2.new(0.325, 0.10625)
local CLOCK_ASPECT_RATIO = 4.2
local CLOCK_MAX_SIZE = Vector2.new(525, 125)

ChangeHistoryService:SetWaypoint("Before RefineryHp gui")

local existing = StarterGui:FindFirstChild("RefineryHp")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RefineryHp"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- under the top bar like the day clock whose spot it takes
gui.IgnoreGuiInset = true
gui.Enabled = false

local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = CLOCK_POSITION
root.Size = UDim2.fromScale(CLOCK_SIZE_SCALE.X, CLOCK_SIZE_SCALE.Y)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = CLOCK_ASPECT_RATIO
rootAspect.DominantAxis = Enum.DominantAxis.Width
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = CLOCK_MAX_SIZE
rootSize.Parent = root
local rootPadding = Instance.new("UIPadding")
rootPadding.PaddingLeft = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingRight = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingTop = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingBottom = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.Parent = root
root.Parent = gui

-- the Refinery's mark: the white home icon on a black rounded square
-- (designer, 2026-10-06), the same shape and spot as the clock's phase
-- picture; the client flashes the square red while the Refinery is under attack
local icon = Instance.new("Frame")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.Position = UDim2.fromScale(0, 0.36)
icon.Size = UDim2.fromScale(0.17, 0.72)
icon.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
icon.BorderSizePixel = 0
icon.ZIndex = 2
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.2, 0)
iconCorner.Parent = icon
local iconStroke = Instance.new("UIStroke")
iconStroke.Thickness = UiStyle.STROKE_PX
iconStroke.Color = UiStyle.ACCENT_STROKE_COLOR
iconStroke.Parent = icon
local iconImage = Instance.new("ImageLabel")
iconImage.Name = "Image"
iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
iconImage.Position = UDim2.fromScale(0.5, 0.5)
iconImage.Size = UDim2.fromScale(0.85, 0.85)
iconImage.BackgroundTransparency = 1
iconImage.BorderSizePixel = 0
iconImage.Image = Icons.UI.COMPASS_HOME
-- untinted: the art carries its own colour (designer, 2026-09-30)
iconImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
iconImage.ScaleType = Enum.ScaleType.Fit
iconImage.Parent = icon
icon.Parent = root

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(1, 0.5)
bar.Position = UDim2.fromScale(1, 0.36)
bar.Size = UDim2.fromScale(0.85, 0.4)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0.4, 0)
barCorner.Parent = bar
local barStroke = Instance.new("UIStroke")
barStroke.Thickness = UiStyle.STROKE_PX
barStroke.Color = UiStyle.ACCENT_STROKE_COLOR
barStroke.Parent = bar
bar.Parent = root

-- anchored at the left so a shrinking width empties from the right
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.fromScale(0, 0.5)
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = UiStyle.HP_FULL_COLOR
fill.BorderSizePixel = 0
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0.4, 0)
fillCorner.Parent = fill
fill.Parent = bar

local label = Instance.new("TextLabel")
label.Name = "Label"
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.fromScale(1, 1)
label.Size = UDim2.fromScale(0.87, 0.35)
label.BackgroundTransparency = 1
label.FontFace = UiStyle.TITLE_SEMIBOLD_FONT
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.Text = UiStyle.formatTitle("Refinery HP")
label.TextXAlignment = Enum.TextXAlignment.Center
local labelTextSize = Instance.new("UITextSizeConstraint")
labelTextSize.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
labelTextSize.MaxTextSize = UiStyle.BODY_TEXT_MAX_PX
labelTextSize.Parent = label
local labelStroke = Instance.new("UIStroke")
labelStroke.Thickness = UiStyle.STROKE_PX
labelStroke.Color = UiStyle.ACCENT_STROKE_COLOR
labelStroke.Parent = label
label.Parent = root

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After RefineryHp gui")
print("build_refinery_hp_gui: built " .. gui:GetFullName())
