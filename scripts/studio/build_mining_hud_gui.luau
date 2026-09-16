-- Rebuilds the "MiningHud" ScreenGui under StarterGui: the centre reticle dot
-- and, to its right, the target rock's name over a health bar with no
-- numbers (GDD "Mining Rock"; decided 2026-09-15). ClientMiningManager
-- enables it only while the pick axe is equipped. Run from the Studio command
-- bar (or the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. Names must match Constants.MINING_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before MiningHud gui")

local existing = StarterGui:FindFirstChild("MiningHud")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MiningHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- the reticle marks the true screen centre, which the top bar inset would shift
gui.IgnoreGuiInset = true
gui.Enabled = false

local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
-- a hairline dot, so offset is allowed here: scale would shrink it to
-- nothing on a phone
reticle.Size = UDim2.fromOffset(8, 8)
reticle.BackgroundColor3 = UiStyle.TEXT_COLOR
reticle.BorderSizePixel = 0
reticle.Parent = gui
local reticleCorner = Instance.new("UICorner")
reticleCorner.CornerRadius = UDim.new(0.5, 0)
reticleCorner.Parent = reticle
local reticleStroke = Instance.new("UIStroke")
reticleStroke.Thickness = 1
reticleStroke.Color = UiStyle.BACKGROUND_COLOR
reticleStroke.Parent = reticle

-- the rock's name to the right of the reticle, its health bar just under
local label = Instance.new("TextLabel")
label.Name = "TargetLabel"
label.AnchorPoint = Vector2.new(0, 1)
label.Position = UDim2.fromScale(0.515, 0.5)
label.Size = UDim2.fromScale(0.2, 0.035)
local labelSize = Instance.new("UISizeConstraint")
labelSize.MaxSize = Vector2.new(360, 34)
labelSize.Parent = label
label.BackgroundColor3 = UiStyle.PANEL_COLOR
label.BackgroundTransparency = 0.35
label.BorderSizePixel = 0
label.Text = "Rock"
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextTruncate = Enum.TextTruncate.AtEnd
label.FontFace = UiStyle.BODY_BOLD_FONT
label.Visible = false
label.Parent = gui
local labelText = Instance.new("UITextSizeConstraint")
labelText.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
labelText.MaxTextSize = UiStyle.BODY_TEXT_MAX_PX
labelText.Parent = label
local labelCorner = Instance.new("UICorner")
labelCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
labelCorner.Parent = label
local labelPadding = Instance.new("UIPadding")
labelPadding.PaddingLeft = UDim.new(0, 10)
labelPadding.PaddingRight = UDim.new(0, 10)
labelPadding.Parent = label

local bar = Instance.new("Frame")
bar.Name = "TargetBar"
bar.AnchorPoint = Vector2.new(0, 0)
bar.Position = UDim2.fromScale(0.515, 0.505)
bar.Size = UDim2.fromScale(0.2, 0.012)
local barSize = Instance.new("UISizeConstraint")
barSize.MaxSize = Vector2.new(360, 12)
barSize.Parent = bar
bar.BackgroundColor3 = UiStyle.PANEL_COLOR
bar.BackgroundTransparency = 0.35
bar.BorderSizePixel = 0
bar.Visible = false
bar.Parent = gui
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0.5, 0)
barCorner.Parent = bar
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = UiStyle.POSITIVE_COLOR
fill.BorderSizePixel = 0
fill.Parent = bar
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0.5, 0)
fillCorner.Parent = fill

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After MiningHud gui")
print("build_mining_hud_gui: built StarterGui.MiningHud")
