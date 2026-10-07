-- Builds the "RescueCountdown" ScreenGui under StarterGui (2026-10-07): one
-- line of title text in the day clock's spot, top centre, that
-- ClientRescueManager slides down once the radio is used and the clock
-- has slid away: "FINAL WAVE ARRIVES IN: 00:30", then "HELICOPTER
-- ARRIVES IN: 01:00", then "THE HELICOPTER HAS ARRIVED. BOARD IT NOW!".
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy. Names must match
-- Constants.RESCUE_COUNTDOWN_*. Scale only, a max size, no pixel minimums
-- (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

-- the day clock's Root box (build_day_clock_gui.luau), taken over
local CLOCK_POSITION = UDim2.fromScale(0.5, 0.012)
local CLOCK_SIZE_SCALE = Vector2.new(0.325, 0.10625)
local CLOCK_MAX_SIZE = Vector2.new(525, 125)

ChangeHistoryService:SetWaypoint("Before RescueCountdown gui")

local existing = StarterGui:FindFirstChild("RescueCountdown")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RescueCountdown"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- under the top bar like the day clock whose spot it takes
gui.IgnoreGuiInset = true
gui.Enabled = false

local label = Instance.new("TextLabel")
label.Name = "Label"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = CLOCK_POSITION
label.Size = UDim2.fromScale(CLOCK_SIZE_SCALE.X * 1.6, CLOCK_SIZE_SCALE.Y * 0.5)
label.BackgroundTransparency = 1
label.FontFace = UiStyle.TITLE_FONT
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.Text = UiStyle.formatTitle("Final Wave Arrives In: 00:30")
label.TextXAlignment = Enum.TextXAlignment.Center
local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(CLOCK_MAX_SIZE.X * 1.6, CLOCK_MAX_SIZE.Y * 0.5)
sizeConstraint.Parent = label
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.TITLE_TEXT_MIN_PX
textSize.MaxTextSize = UiStyle.TITLE_TEXT_MAX_PX
textSize.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX
stroke.Color = UiStyle.ACCENT_STROKE_COLOR
stroke.Parent = label
label.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After RescueCountdown gui")
print("build_rescue_countdown_gui: built " .. gui:GetFullName())
