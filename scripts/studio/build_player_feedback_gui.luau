-- Rebuilds the "PlayerFeedback" ScreenGui under StarterGui. Run from the Studio
-- command bar (or the MCP execute_luau tool) in either place; it replaces any
-- existing copy. Names must match Constants.PLAYER_FEEDBACK_*. Three boxes:
-- the feedback box at the bottom for ordinary messages, the announcement box
-- at the top centre, blue, for the beats nobody should miss (the Camp Level
-- rising; decided 2026-09-16), and the alert box under it, red, for danger
-- (a wall down, the Refinery under attack; 2026-09-25). Layout follows the
-- GUI standard in CLAUDE.md.
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

local function makeBox(name, anchorPoint, position, backgroundColor)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = anchorPoint
	box.Position = position
	box.Size = UDim2.fromScale(0.4, 0.075)
	local boxSize = Instance.new("UISizeConstraint")
	boxSize.MaxSize = Vector2.new(640, 64)
	boxSize.Parent = box
	box.BackgroundColor3 = backgroundColor
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
	return box
end

-- ordinary feedback, low on the screen where the eye rests on the action
makeBox("FeedbackBox", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.85), UiStyle.PANEL_COLOR)
-- announcements, top centre under the top bar: clear of the chat window on
-- the left and the right-edge panels, per the reserved-regions rule
-- under the day clock (M28, decided 2026-09-22), which owns the very top
makeBox("AnnouncementBox", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.115), UiStyle.ANNOUNCEMENT_COLOR)
-- alerts, red, just under the announcement so both can show at once
makeBox("AlertBox", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2), UiStyle.ALERT_COLOR)

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("PlayerFeedback gui")
return "PlayerFeedback gui built"
