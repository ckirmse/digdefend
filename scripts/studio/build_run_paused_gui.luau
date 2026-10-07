-- Builds the "RunPaused" ScreenGui under StarterGui (2026-10-07): one big
-- PAUSED word across the centre of the screen, shown by
-- ClientRunCycleManager while the dev tool holds the run, so a tester
-- cannot forget the run is paused. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.RUN_PAUSED_*. Scale only, a max text
-- size, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before RunPaused gui")

local existing = StarterGui:FindFirstChild("RunPaused")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RunPaused"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Enabled = false

local label = Instance.new("TextLabel")
label.Name = "Label"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(0.8, 0.18)
label.BackgroundTransparency = 1
label.FontFace = UiStyle.TITLE_FONT
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.Text = UiStyle.formatTitle("Paused")
label.TextXAlignment = Enum.TextXAlignment.Center
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.TITLE_TEXT_MIN_PX
textSize.MaxTextSize = UiStyle.TITLE_TEXT_MAX_PX
textSize.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX * 2
stroke.Color = UiStyle.ACCENT_STROKE_COLOR
stroke.Parent = label
label.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After RunPaused gui")
print("build_run_paused_gui: built " .. gui:GetFullName())
