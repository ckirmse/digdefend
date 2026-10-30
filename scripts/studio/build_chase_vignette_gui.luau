-- Rebuilds the "ChaseVignette" ScreenGui under StarterGui (M68, 2026-10-26):
-- the black edges that close in on the screen as the Chase nears, the
-- StimVignette's shape in black and reaching further. Four frames, one per
-- screen edge, each faded by a UIGradient from solid at the edge to clear
-- inward; ClientChaseVignetteManager scales every frame's reach and
-- transparency between nothing and these authored values by how close the
-- nearest Chase is, every frame. Covers the notch and home-bar areas like the
-- other full-screen effects, and sits under the hurt vignette. Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay place;
-- it replaces any existing copy. Names must match Constants.CHASE_VIGNETTE_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before ChaseVignette gui")

local existing = StarterGui:FindFirstChild("ChaseVignette")
if existing then
	existing:Destroy()
end

-- above the HUD, under the hurt vignette (2) and the menus (5)
local VIGNETTE_DISPLAY_ORDER = 1
-- how far in from each edge the dark reaches at its fullest, as a share of
-- the screen (0.75 and 0.625 were tried and were too much, 2026-10-26)
local EDGE_SHARE = 0.5
-- how solid the dark is at the very edge at its fullest
local EDGE_TRANSPARENCY = 0.05
local EDGE_COLOR = Color3.new(0, 0, 0)

local gui = Instance.new("ScreenGui")
gui.Name = "ChaseVignette"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = VIGNETTE_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- one edge: a black frame along it, faded to clear toward the centre
local function makeEdge(name, anchor, position, size, gradientRotation)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = EDGE_COLOR
	frame.BackgroundTransparency = EDGE_TRANSPARENCY
	frame.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = gradientRotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	frame.Parent = gui
	return frame
end

-- the gradient runs left to right at 0 degrees; each edge turns it to run inward
makeEdge("Top", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, EDGE_SHARE), 90)
makeEdge("Bottom", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, EDGE_SHARE), -90)
makeEdge("Left", Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(EDGE_SHARE, 1), 0)
makeEdge("Right", Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(EDGE_SHARE, 1), 180)

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ChaseVignette gui")
print("build_chase_vignette_gui: built StarterGui.ChaseVignette")
