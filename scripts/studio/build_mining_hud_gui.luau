-- Rebuilds the "MiningHud" ScreenGui under StarterGui: the centre reticle dot
-- and the target label to its right (GDD "Mining Rock"). ClientMiningManager
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
reticle.Size = UDim2.fromScale(0.008, 0.008)
local reticleAspect = Instance.new("UIAspectRatioConstraint")
reticleAspect.AspectRatio = 1
reticleAspect.Parent = reticle
local reticleSize = Instance.new("UISizeConstraint")
reticleSize.MinSize = Vector2.new(6, 6)
reticleSize.MaxSize = Vector2.new(12, 12)
reticleSize.Parent = reticle
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

-- "Iron 3  45/60" to the right of the reticle
local label = Instance.new("TextLabel")
label.Name = "TargetLabel"
label.AnchorPoint = Vector2.new(0, 0.5)
label.Position = UDim2.fromScale(0.515, 0.5)
label.Size = UDim2.fromScale(0.2, 0.035)
local labelSize = Instance.new("UISizeConstraint")
labelSize.MinSize = Vector2.new(120, 18)
labelSize.MaxSize = Vector2.new(360, 34)
labelSize.Parent = label
label.BackgroundColor3 = UiStyle.PANEL_COLOR
label.BackgroundTransparency = 0.35
label.BorderSizePixel = 0
label.Text = "Rock  10/10"
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

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After MiningHud gui")
print("build_mining_hud_gui: built StarterGui.MiningHud")
