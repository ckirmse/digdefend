-- Rebuilds the "PlayerFeedback" ScreenGui under StarterGui. Run from the Studio
-- command bar (or the MCP execute_luau tool) in either place; it replaces any
-- existing copy. Names must match Constants.PLAYER_FEEDBACK_*. Layout rule:
-- scale for position and size, UISizeConstraint / UITextSizeConstraint to keep
-- phones readable and 4K sane, offset only for hairlines. Colours are
-- provisional until M10.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before PlayerFeedback gui")

local existing = StarterGui:FindFirstChild("PlayerFeedback")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "PlayerFeedback"
gui.ResetOnSpawn = false
gui.DisplayOrder = 500
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

local box = Instance.new("Frame")
box.Name = "FeedbackBox"
box.AnchorPoint = Vector2.new(0.5, 1)
box.Position = UDim2.fromScale(0.5, 0.85)
box.Size = UDim2.fromScale(0.4, 0.075)
local boxSize = Instance.new("UISizeConstraint")
boxSize.MinSize = Vector2.new(240, 40)
boxSize.MaxSize = Vector2.new(640, 64)
boxSize.Parent = box
box.BackgroundColor3 = UiStyle.PANEL_COLOR
box.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
box.BorderSizePixel = 0
box.Visible = false
box.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
corner.Parent = box

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.Parent = box

local message = Instance.new("TextLabel")
message.Name = "Message"
message.Size = UDim2.fromScale(1, 1)
message.BackgroundTransparency = 1
message.TextScaled = true
message.TextTruncate = Enum.TextTruncate.AtEnd
local messageTextSize = Instance.new("UITextSizeConstraint")
messageTextSize.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
messageTextSize.MaxTextSize = UiStyle.BODY_TEXT_MAX_PX
messageTextSize.Parent = message
message.Text = "Feedback message"
message.TextColor3 = UiStyle.TEXT_COLOR
message.FontFace = UiStyle.BODY_FONT
message.Parent = box

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("PlayerFeedback gui")
return "PlayerFeedback gui built"
