-- Rebuilds the "PlayerFeedback" ScreenGui under StarterGui. Run from the Studio
-- command bar (or the MCP execute_luau tool) in either place; it replaces any
-- existing copy. Names must match Constants.PLAYER_FEEDBACK_*. One box
-- (decided 2026-10-05; there were three), low on the screen above the
-- tool bar. ClientPlayerFeedbackManager colours it by what the message
-- is: its own colour for ordinary feedback, UiStyle.ANNOUNCEMENT_COLOR
-- for the beats nobody should miss, UiStyle.ALERT_COLOR for danger (a
-- wall down, the Refinery under attack, a crewmate dead). Layout follows
-- the GUI standard in CLAUDE.md.
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

	-- a resource icon a message can end with ("+5 [diamond]", M33): the
	-- client puts it right after the words and shifts them left to stay
	-- centred as a pair; hidden for a plain message
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = box
	return box
end

-- low on the screen where the eye rests on the action, its bottom edge
-- clear of the tool bar's top (the tool bar's Slots end at 0.93 and are
-- 0.098 tall)
makeBox("FeedbackBox", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.81), UiStyle.PANEL_COLOR)

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("PlayerFeedback gui")
return "PlayerFeedback gui built"
