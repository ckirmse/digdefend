-- Builds the "Compass" ScreenGui under StarterGui (GDD "Compass"): a
-- locator bar hung directly under the day clock. ClientCompassManager
-- slides the HomeIcon (the Refinery) and one clone of PlayerDotTemplate per
-- crewmate along the Markers frame, and shows a marker's ArrowUp or
-- ArrowDown when its target is above or below. Run from the Studio command
-- bar (or the MCP execute_luau tool) in the gameplay place; it replaces
-- any existing copy. Names must match Constants.COMPASS_*.
-- Scale only, constraints for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)

-- the day clock's Root box (build_day_clock_gui.luau); the compass Root is
-- the same box made taller by ROOT_HEIGHT_SHARE, so its top part overlays
-- the clock exactly on every screen and the bar hangs in the extra strip
local CLOCK_POSITION = UDim2.fromScale(0.5, 0.012)
local CLOCK_SIZE_SCALE = Vector2.new(0.325, 0.10625)
local CLOCK_ASPECT_RATIO = 4.2
local CLOCK_MAX_SIZE = Vector2.new(525, 125)
local ROOT_HEIGHT_SHARE = 1.4
-- the bar's height as a share of the Root
local BAR_HEIGHT_SHARE = 0.14
-- where the bar's bottom edge sits in the Root; its top stays at 0.8, the
-- gap under the clock it had before it was thinned by 30% (designer, 2026-09-30)
local BAR_BOTTOM_SHARE = 0.94
-- marker sizes as a share of the bar's height
local HOME_ICON_SCALE = 2.43
local PLAYER_DOT_SCALE = 1.29

ChangeHistoryService:SetWaypoint("Before Compass gui")

local existing = StarterGui:FindFirstChild("Compass")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Compass"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- under the top bar like the day clock it hangs from
gui.IgnoreGuiInset = true
gui.Enabled = false

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = CLOCK_POSITION
root.Size = UDim2.fromScale(CLOCK_SIZE_SCALE.X, CLOCK_SIZE_SCALE.Y * ROOT_HEIGHT_SHARE)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = CLOCK_ASPECT_RATIO / ROOT_HEIGHT_SHARE
rootAspect.DominantAxis = Enum.DominantAxis.Width
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = Vector2.new(CLOCK_MAX_SIZE.X, CLOCK_MAX_SIZE.Y * ROOT_HEIGHT_SHARE)
rootSize.Parent = root
root.Parent = gui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.fromScale(0.5, BAR_BOTTOM_SHARE)
bar.Size = UDim2.fromScale(1, BAR_HEIGHT_SHARE)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
bar.BorderSizePixel = 0
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0.5, 0)
barCorner.Parent = bar
local barStroke = Instance.new("UIStroke")
barStroke.Thickness = UiStyle.STROKE_PX
barStroke.Color = UiStyle.ACCENT_STROKE_COLOR
barStroke.Parent = bar
bar.Parent = root

-- narrower than the bar so a marker at either end stays inside the pill
local markers = Instance.new("Frame")
markers.Name = "Markers"
markers.AnchorPoint = Vector2.new(0.5, 0.5)
markers.Position = UDim2.fromScale(0.5, 0.5)
markers.Size = UDim2.fromScale(0.92, 1)
markers.BackgroundTransparency = 1
markers.BorderSizePixel = 0
markers.Parent = bar

local function addArrow(parent, name, text, anchorY, positionY)
	local arrow = Instance.new("TextLabel")
	arrow.Name = name
	arrow.AnchorPoint = Vector2.new(0.5, anchorY)
	arrow.Position = UDim2.fromScale(0.5, positionY)
	-- wider than its marker so the glyph reads at phone size
	arrow.Size = UDim2.fromScale(1.6, 0.9)
	arrow.BackgroundTransparency = 1
	arrow.FontFace = UiStyle.BODY_BOLD_FONT
	arrow.Text = text
	arrow.TextColor3 = UiStyle.TEXT_COLOR
	arrow.TextScaled = true
	arrow.Visible = false
	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
	textSize.MaxTextSize = UiStyle.LABEL_TEXT_MAX_PX
	textSize.Parent = arrow
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = UiStyle.ACCENT_STROKE_COLOR
	stroke.Parent = arrow
	arrow.Parent = parent
end

local function addArrows(parent)
	addArrow(parent, "ArrowUp", "▲", 1, 0)
	addArrow(parent, "ArrowDown", "▼", 0, 1)
end

-- the Refinery; drawn over the dots
local homeIcon = Instance.new("ImageLabel")
homeIcon.Name = "HomeIcon"
homeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
homeIcon.Position = UDim2.fromScale(0.5, 0.5)
homeIcon.Size = UDim2.fromScale(HOME_ICON_SCALE, HOME_ICON_SCALE)
homeIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
homeIcon.BackgroundTransparency = 1
homeIcon.BorderSizePixel = 0
homeIcon.Image = Icons.UI.COMPASS_HOME
-- untinted: the art carries its own colour (designer, 2026-09-30)
homeIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
homeIcon.ScaleType = Enum.ScaleType.Fit
homeIcon.ZIndex = 3
addArrows(homeIcon)
homeIcon.Parent = markers

-- cloned per crewmate; the client colours it and sizes it by distance
local dot = Instance.new("Frame")
dot.Name = "PlayerDotTemplate"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromScale(PLAYER_DOT_SCALE, PLAYER_DOT_SCALE)
dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
dot.BackgroundColor3 = UiStyle.COMPASS_PLAYER_COLORS[1]
dot.BorderSizePixel = 0
dot.ZIndex = 2
dot.Visible = false
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(0.5, 0)
dotCorner.Parent = dot
local dotStroke = Instance.new("UIStroke")
dotStroke.Thickness = UiStyle.STROKE_PX
dotStroke.Color = UiStyle.TEXT_COLOR
dotStroke.Parent = dot
addArrows(dot)
dot.Parent = markers

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After Compass gui")
print("build_compass_gui: built " .. gui:GetFullName())
