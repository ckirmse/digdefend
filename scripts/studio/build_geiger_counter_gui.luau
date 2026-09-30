-- Builds the "GeigerCounter" ScreenGui under StarterGui (GDD "Geiger
-- Counter"): a round dial just right of the day clock, with the raw
-- uranium icon in the middle of three rings. ClientGeigerCounterManager
-- shows it in mining mode once the counter is owned and lights Ring1
-- (inner), Ring2, and Ring3 (outer) as the player closes on uranium; with
-- none in range no ring shows. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.GEIGER_COUNTER_*.
-- Scale only, constraints for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)
local Enums = require(game.ReplicatedStorage.Shared.Enums)

-- the day clock's Root box (build_day_clock_gui.luau): the Root here is the
-- same box, so the dial hung off its right edge follows the clock on every
-- screen
local CLOCK_POSITION = UDim2.fromScale(0.5, 0.012)
local CLOCK_SIZE = UDim2.fromScale(0.325, 0.10625)
local CLOCK_ASPECT_RATIO = 4.2
local CLOCK_MAX_SIZE = Vector2.new(525, 125)
-- the dial's diameter as a share of the clock's height, and the gap to the
-- clock's right edge as a share of its width
local DIAL_HEIGHT_SHARE = 0.95
local DIAL_GAP_SHARE = 0.03
-- each ring's diameter as a share of the dial, inner first
local RING_SCALES = { 0.56, 0.75, 0.94 }
local ICON_SCALE = 0.4
local RING_STROKE_PX = 3

ChangeHistoryService:SetWaypoint("Before GeigerCounter gui")

local existing = StarterGui:FindFirstChild("GeigerCounter")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GeigerCounter"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- under the top bar like the day clock it sits beside
gui.IgnoreGuiInset = true
gui.Enabled = false

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = CLOCK_POSITION
root.Size = CLOCK_SIZE
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = CLOCK_ASPECT_RATIO
rootAspect.DominantAxis = Enum.DominantAxis.Width
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = CLOCK_MAX_SIZE
rootSize.Parent = root
root.Parent = gui

-- a dark disc so the rings read against sky and rock alike
local dial = Instance.new("Frame")
dial.Name = "Dial"
dial.AnchorPoint = Vector2.new(0, 0.5)
dial.Position = UDim2.fromScale(1 + DIAL_GAP_SHARE, 0.5)
dial.Size = UDim2.fromScale(DIAL_HEIGHT_SHARE, DIAL_HEIGHT_SHARE)
dial.SizeConstraint = Enum.SizeConstraint.RelativeYY
dial.BackgroundColor3 = UiStyle.PANEL_COLOR
dial.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dial.BorderSizePixel = 0
local dialCorner = Instance.new("UICorner")
dialCorner.CornerRadius = UDim.new(0.5, 0)
dialCorner.Parent = dial
local dialStroke = Instance.new("UIStroke")
dialStroke.Thickness = UiStyle.STROKE_PX
dialStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dialStroke.Parent = dial
dial.Parent = root

-- hidden until lit
for index, scale in RING_SCALES do
	local ring = Instance.new("Frame")
	ring.Name = "Ring" .. index
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(scale, scale)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = RING_STROKE_PX
	ringStroke.Color = UiStyle.POSITIVE_COLOR
	ringStroke.Parent = ring
	ring.Parent = dial
end

local uraniumIconId = Icons.RAW_RESOURCE[Enums.RawResource.URANIUM_ORE]
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE)
icon.BackgroundTransparency = 1
icon.BorderSizePixel = 0
icon.Image = if Icons.isPlaceholder(uraniumIconId) then "" else uraniumIconId
icon.ScaleType = Enum.ScaleType.Fit
icon.ZIndex = 2
icon.Parent = dial

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After GeigerCounter gui")
print("build_geiger_counter_gui: built " .. gui:GetFullName())
