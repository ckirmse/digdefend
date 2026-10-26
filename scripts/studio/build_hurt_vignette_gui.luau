-- Rebuilds the "HurtVignette" ScreenGui under StarterGui (2026-10-26): the
-- red edge glow that fades in and out when the player takes a hit, the
-- StimVignette's shape in red. Four frames, one per screen edge, each
-- faded by a UIGradient from solid at the edge to clear inward;
-- ClientHurtManager enables the gui, tweens every frame from clear to its
-- authored transparency over the fade-in and back over the fade-out, then
-- disables it. Covers the notch and home-bar areas like the other
-- full-screen effects. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.HURT_VIGNETTE_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before HurtVignette gui")

local existing = StarterGui:FindFirstChild("HurtVignette")
if existing then
	existing:Destroy()
end

-- above the HUD, below the menus (ClientOverlayManager.MENU_DISPLAY_ORDER is 5)
local VIGNETTE_DISPLAY_ORDER = 2
-- how far in from each edge the glow reaches, as a share of the screen
local EDGE_SHARE = 0.25
-- how solid the glow is at the very edge when fully faded in
local EDGE_TRANSPARENCY = 0.2
local EDGE_COLOR = Color3.fromRGB(170, 0, 0)

local gui = Instance.new("ScreenGui")
gui.Name = "HurtVignette"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = VIGNETTE_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- one edge: a red frame along it, faded to clear toward the centre
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
ChangeHistoryService:SetWaypoint("After HurtVignette gui")
print("build_hurt_vignette_gui: built StarterGui.HurtVignette")
