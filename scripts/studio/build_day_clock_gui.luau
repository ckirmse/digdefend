-- Builds the "DayClock" ScreenGui under StarterGui (GDD "Wave Cycle", M28):
-- a bar top centre, just under the announcement box, with a badge on the
-- left that ClientRunCycleManager fills with the day, dusk, or night
-- picture, a track whose Fill starts full at dawn and empties from right
-- to left until night, and "Day N" under the bar. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.DAY_CLOCK_*.
-- Scale only, constraints for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)

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
-- sits under the top bar by designer decision (2026-09-25), an exception to
-- the HUD rule; check the top bar buttons clear it on each device preset
gui.IgnoreGuiInset = true
gui.Enabled = false

-- at the very top, ignoring the top bar inset; the announcement box sits under it
-- (decided 2026-09-22), and the chat window is top-left so this is clear
-- a CanvasGroup so the whole clock fades as one at dusk and dawn
local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.fromScale(0.5, 0.014)
root.Size = UDim2.fromScale(0.325, 0.10625)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = 4.2
rootAspect.DominantAxis = Enum.DominantAxis.Width
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = Vector2.new(525, 125)
rootSize.Parent = root
-- a CanvasGroup clips to its own bounds and a UIStroke draws outward, so
-- the flush icon and bar lost their outer stroke; pad by the stroke (hairline)
local rootPadding = Instance.new("UIPadding")
rootPadding.PaddingLeft = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingRight = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingTop = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.PaddingBottom = UDim.new(0, UiStyle.STROKE_PX)
rootPadding.Parent = root
root.Parent = gui

-- the phase badge: a translucent white square at the row's height with the
-- designer's black frame picture drawn a little larger behind the phase
-- pictures; one picture and one gradient per phase sit under it and
-- ClientRunCycleManager shows the pair for the current phase (a white
-- rounded Frame before 2026-10-29; designer-authored)
local icon = Instance.new("Frame")
icon.Name = "PhaseIcon"
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.Position = UDim2.fromScale(0.01, 0.5)
icon.Size = UDim2.fromScale(0.95, 0.95)
icon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
icon.BackgroundTransparency = 0.45
icon.BorderSizePixel = 0
-- above the bar so the badge overlaps the bar end
icon.ZIndex = 2
local iconAspect = Instance.new("UIAspectRatioConstraint")
iconAspect.AspectRatio = 1
iconAspect.DominantAxis = Enum.DominantAxis.Height
iconAspect.Parent = icon
local iconFrame = Instance.new("ImageLabel")
iconFrame.Name = "Frame"
iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
iconFrame.Position = UDim2.fromScale(0.5, 0.5)
iconFrame.Size = UDim2.fromScale(1.1, 1.1)
iconFrame.BackgroundTransparency = 1
iconFrame.BorderSizePixel = 0
iconFrame.Image = Icons.UI.CLOCK_FRAME
iconFrame.ImageColor3 = Color3.fromRGB(0, 0, 0)
iconFrame.ScaleType = Enum.ScaleType.Stretch
iconFrame.ZIndex = 1
iconFrame.Parent = icon

local PHASE_LOOKS = {
	{
		iconName = "IconDay",
		gradientName = "UIGradientDay",
		image = Icons.UI.CLOCK_DAY,
		imageColor = Color3.fromRGB(255, 213, 5),
		imageScale = 0.9,
		gradientTop = Color3.fromRGB(0, 98, 255),
		gradientBottom = Color3.fromRGB(0, 255, 255),
	},
	{
		iconName = "IconDusk",
		gradientName = "UIGradientDusk",
		image = Icons.UI.CLOCK_DUSK,
		imageColor = Color3.fromRGB(255, 213, 5),
		imageScale = 0.9,
		gradientTop = Color3.fromRGB(255, 119, 0),
		gradientBottom = Color3.fromRGB(170, 0, 255),
	},
	{
		iconName = "IconNight",
		gradientName = "UIGradientNight",
		image = Icons.UI.CLOCK_NIGHT,
		imageColor = Color3.fromRGB(255, 246, 142),
		imageScale = 0.85,
		gradientTop = Color3.fromRGB(32, 0, 58),
		gradientBottom = Color3.fromRGB(170, 0, 255),
	},
}
-- everything hidden at build time; the client shows the phase's pair
for _, look in PHASE_LOOKS do
	local phaseImage = Instance.new("ImageLabel")
	phaseImage.Name = look.iconName
	phaseImage.AnchorPoint = Vector2.new(0.5, 0.5)
	phaseImage.Position = UDim2.fromScale(0.5, 0.5)
	phaseImage.Size = UDim2.fromScale(look.imageScale, look.imageScale)
	phaseImage.BackgroundTransparency = 1
	phaseImage.BorderSizePixel = 0
	phaseImage.Image = look.image
	phaseImage.ImageColor3 = look.imageColor
	phaseImage.ScaleType = Enum.ScaleType.Fit
	-- above the Frame picture at 1
	phaseImage.ZIndex = 2
	phaseImage.Visible = false
	phaseImage.Parent = icon
	local gradient = Instance.new("UIGradient")
	gradient.Name = look.gradientName
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(look.gradientTop, look.gradientBottom)
	gradient.Enabled = false
	gradient.Parent = icon
end
icon.Parent = root

-- the track, to the right of the badge: the designer's pill picture in
-- black (a Frame with a pill corner and stroke before 2026-10-29)
local bar = Instance.new("ImageLabel")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(1, 0.5)
bar.Position = UDim2.fromScale(1, 0.4)
bar.Size = UDim2.fromScale(0.77, 0.4)
bar.BackgroundTransparency = 1
bar.BorderSizePixel = 0
bar.Image = Icons.UI.CLOCK_BAR
bar.ImageColor3 = Color3.fromRGB(0, 0, 0)
bar.ImageTransparency = 0.45
bar.ScaleType = Enum.ScaleType.Stretch
bar.Parent = root

-- the same pill in the fill colour, exactly over the bar so the two pictures
-- stay registered; the client hides the spent part through the Mask
-- gradient's transparency, so the fill never moves or resizes
local fill = Instance.new("ImageLabel")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0)
fill.Position = UDim2.fromScale(0, 0)
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundTransparency = 1
fill.BorderSizePixel = 0
fill.Image = Icons.UI.CLOCK_BAR
fill.ImageColor3 = Color3.fromRGB(245, 200, 80)
fill.ScaleType = Enum.ScaleType.Stretch
local fillMask = Instance.new("UIGradient")
fillMask.Name = "Mask"
fillMask.Transparency = NumberSequence.new(0)
fillMask.Parent = fill
fill.Parent = bar

local dayLabel = Instance.new("TextLabel")
dayLabel.Name = "DayLabel"
dayLabel.AnchorPoint = Vector2.new(1, 1)
-- a little below the row's bottom, into the padding (designer, 2026-10-29)
dayLabel.Position = UDim2.fromScale(1, 1.1)
dayLabel.Size = UDim2.fromScale(0.87, 0.45)
dayLabel.BackgroundTransparency = 1
dayLabel.BorderSizePixel = 0
dayLabel.FontFace = UiStyle.TITLE_SEMIBOLD_FONT
dayLabel.TextColor3 = UiStyle.TEXT_COLOR
dayLabel.TextScaled = true
dayLabel.Text = UiStyle.formatTitle("Day 1")
dayLabel.TextXAlignment = Enum.TextXAlignment.Center
local dayTextSize = Instance.new("UITextSizeConstraint")
dayTextSize.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
dayTextSize.MaxTextSize = UiStyle.BODY_TEXT_MAX_PX
dayTextSize.Parent = dayLabel
dayLabel.Parent = root

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After DayClock gui")
print("build_day_clock_gui: built " .. gui:GetFullName())
