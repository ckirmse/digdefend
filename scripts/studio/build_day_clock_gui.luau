-- Builds the "DayClock" ScreenGui under StarterGui (GDD "Wave Cycle", M28):
-- a bar top centre, just under the announcement box, with a circle on the
-- left that ClientRunCycleManager fills with the day, dusk, or night
-- picture, a track whose Fill starts full at dawn and empties from right
-- to left until night, and "Day N" under the bar. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.DAY_CLOCK_*.
-- Scale only, constraints for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before DayClock gui")

local existing = StarterGui:FindFirstChild("DayClock")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DayClock"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- at the very top, respecting the top bar inset (GUI standard: only
-- full-screen overlays ignore it); the announcement box sits under it
-- (decided 2026-09-22), and the chat window is top-left so this is clear
-- a CanvasGroup so the whole clock fades as one at dusk and dawn
local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.fromScale(0.5, 0.012)
root.Size = UDim2.fromScale(0.26, 0.085)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = 4.2
rootAspect.DominantAxis = Enum.DominantAxis.Width
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = Vector2.new(420, 100)
rootSize.Parent = root
root.Parent = gui

-- the circle: a square image the height of the bar row, rounded fully
local icon = Instance.new("ImageLabel")
icon.Name = "PhaseIcon"
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.Position = UDim2.fromScale(0, 0.36)
icon.Size = UDim2.fromScale(0.17, 0.72)
icon.BackgroundColor3 = Color3.fromRGB(255, 220, 90)
icon.BorderSizePixel = 0
icon.Image = ""
icon.ScaleType = Enum.ScaleType.Fit
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.5, 0)
iconCorner.Parent = icon
local iconStroke = Instance.new("UIStroke")
iconStroke.Thickness = UiStyle.STROKE_PX
iconStroke.Color = UiStyle.ACCENT_STROKE_COLOR
iconStroke.Parent = icon
icon.Parent = root

-- the track, to the right of the circle
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(1, 0.5)
bar.Position = UDim2.fromScale(1, 0.36)
bar.Size = UDim2.fromScale(0.79, 0.4)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
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
fill.BackgroundColor3 = UiStyle.ACCENT_COLOR
fill.BorderSizePixel = 0
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
fillCorner.Parent = fill
fill.Parent = bar

local dayLabel = Instance.new("TextLabel")
dayLabel.Name = "DayLabel"
dayLabel.AnchorPoint = Vector2.new(0.5, 1)
dayLabel.Position = UDim2.fromScale(0.605, 1)
dayLabel.Size = UDim2.fromScale(0.79, 0.3)
dayLabel.BackgroundTransparency = 1
dayLabel.FontFace = UiStyle.BODY_BOLD_FONT
dayLabel.TextColor3 = UiStyle.TEXT_COLOR
dayLabel.TextScaled = true
dayLabel.Text = "Day 1"
dayLabel.TextXAlignment = Enum.TextXAlignment.Center
local dayTextSize = Instance.new("UITextSizeConstraint")
dayTextSize.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
dayTextSize.MaxTextSize = UiStyle.BODY_TEXT_MAX_PX
dayTextSize.Parent = dayLabel
local dayStroke = Instance.new("UIStroke")
dayStroke.Thickness = UiStyle.STROKE_PX
dayStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dayStroke.Parent = dayLabel
dayLabel.Parent = root

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After DayClock gui")
print("build_day_clock_gui: built " .. gui:GetFullName())
