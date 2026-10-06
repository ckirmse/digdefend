--!strict

-- Receives player feedback text from the server (NotifyPlayerFeedback) and from
-- client systems (the GivePlayerFeedbackLocal BindableEvent) and hands each
-- message to the Studio-authored PlayerFeedback ScreenGui and to any other
-- listener. There is one box (decided 2026-10-05; there were three):
-- announcements (announceLocal) turn it blue and alerts (alertLocal) turn
-- it red, and a message that matters more is never wiped by a lesser one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.ClientNetManager)

local ClientPlayerFeedbackManager = {}
ClientPlayerFeedbackManager.__index = ClientPlayerFeedbackManager

export type FeedbackListener = (message: string, displaySec: number) -> ()

-- a message may end with a resource icon (an Icons id), never a resource word

export type ClientPlayerFeedbackManager = typeof(setmetatable(
	{} :: {
		localEvent: BindableEvent?,
		listeners: { FeedbackListener },
		feedbackBox: Frame?,
		messageLabel: TextLabel?,
		icon: ImageLabel?,
		-- the label's authored position, which an icon shifts
		messagePosition: UDim2,
		-- the box's authored colour, for an ordinary message
		plainColor: Color3,
		-- what is showing now and until when, so a lesser message waits its turn
		shownStyle: number,
		shownUntilTime: number,
		isSuppressed: boolean,
		-- bumps per message so an older hide timer cannot clear a newer message
		showGeneration: number,
	},
	ClientPlayerFeedbackManager
))

local NOTIFY_PLAYER_FEEDBACK_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local DEFAULT_DISPLAY_SEC = 3
-- how much a message matters, least first; the box takes the colour
local STYLE_PLAIN = 1
local STYLE_ANNOUNCEMENT = 2
local STYLE_ALERT = 3
local COLOR_BY_STYLE: { [number]: Color3 } = {
	[STYLE_ANNOUNCEMENT] = UiStyle.ANNOUNCEMENT_COLOR,
	[STYLE_ALERT] = UiStyle.ALERT_COLOR,
}

function ClientPlayerFeedbackManager:addListener(listener: FeedbackListener)
	table.insert(self.listeners, listener)
end

-- the one box every message shows in (decided 2026-10-05, replacing the
-- three boxes): its colour says how much the message matters. A message
-- replaces what is showing unless what is showing matters more and its
-- time is not up, so a wall falling is never wiped by "Not enough Iron"
-- the icon sits right after the words, a gap this share of the box's
-- height away; the words slide left by half the pair's extra width
local ICON_GAP_SHARE_OF_HEIGHT = 0.3

function ClientPlayerFeedbackManager:placeIcon(iconId: string?)
	local icon = self.icon
	local messageLabel = self.messageLabel
	if not icon or not messageLabel then
		return
	end
	if not iconId then
		icon.Visible = false
		messageLabel.Position = self.messagePosition
		return
	end
	icon.Image = iconId
	-- the words' width is known only once the frame has laid them out
	task.defer(
		function()
			if not icon.Parent or icon.Image ~= iconId then
				return
			end
			local height = messageLabel.AbsoluteSize.Y
			local gap = height * ICON_GAP_SHARE_OF_HEIGHT
			local iconWidth = icon.AbsoluteSize.X
			local shift = (iconWidth + gap) / 2
			local textEnd = (messageLabel.AbsoluteSize.X + messageLabel.TextBounds.X) / 2 - shift
			messageLabel.Position = UDim2.new(self.messagePosition.X.Scale, self.messagePosition.X.Offset - shift, self.messagePosition.Y.Scale, self.messagePosition.Y.Offset)
			icon.Position = UDim2.new(0, math.ceil(textEnd + gap), 0.5, 0)
			icon.Visible = true
		end
	)
end

function ClientPlayerFeedbackManager:show(message: string, displaySec: number, style: number, iconId: string?)
	if self.isSuppressed then
		return
	end
	local feedbackBox = self.feedbackBox
	local messageLabel = self.messageLabel
	if not feedbackBox or not messageLabel then
		print(string.format("[PlayerFeedback] %s (%.1fs)", message, displaySec))
		return
	end
	local now = workspace:GetServerTimeNow()
	if style < self.shownStyle and now < self.shownUntilTime then
		return
	end
	self.shownStyle = style
	self.shownUntilTime = now + displaySec
	self.showGeneration += 1
	local generation = self.showGeneration
	messageLabel.Text = message
	self:placeIcon(iconId)
	feedbackBox.BackgroundColor3 = COLOR_BY_STYLE[style] or self.plainColor
	feedbackBox.Visible = true
	task.delay(
		displaySec,
		function()
			if self.showGeneration == generation then
				feedbackBox.Visible = false
			end
		end
	)
end

function ClientPlayerFeedbackManager:showInBox(message: string, displaySec: number, iconId: string?)
	self:show(message, displaySec, STYLE_PLAIN, iconId)
end

-- a beat nobody should miss (a new tier, the rescue's lines): blue
function ClientPlayerFeedbackManager:announceLocal(message: string, displaySec: number?)
	self:show(message, displaySec or DEFAULT_DISPLAY_SEC, STYLE_ANNOUNCEMENT)
end

-- danger (a wall down, the Refinery under attack, a crewmate dead): red
function ClientPlayerFeedbackManager:alertLocal(message: string, displaySec: number?)
	self:show(message, displaySec or DEFAULT_DISPLAY_SEC, STYLE_ALERT)
end

-- no messages at all while this is on (a dead player looking at the Game
-- Over screen or the Results Menu); whatever is showing goes away
function ClientPlayerFeedbackManager:setSuppressed(isSuppressed: boolean)
	if isSuppressed == self.isSuppressed then
		return
	end
	self.isSuppressed = isSuppressed
	if isSuppressed then
		self.showGeneration += 1
		self.shownUntilTime = 0
		if self.feedbackBox then
			self.feedbackBox.Visible = false
		end
	end
end

function ClientPlayerFeedbackManager:dispatch(message: string, displaySec: number, iconId: string?)
	self:showInBox(message, displaySec, iconId)
	for _, listener in self.listeners do
		listener(message, displaySec)
	end
end

-- client systems call this instead of firing the BindableEvent by hand
function ClientPlayerFeedbackManager:giveLocal(message: string, displaySec: number?, iconId: string?)
	local localEvent = self.localEvent
	if not localEvent then
		warn("ClientPlayerFeedbackManager: giveLocal before init")
		return
	end
	localEvent:Fire(message, displaySec or DEFAULT_DISPLAY_SEC, iconId)
end

function ClientPlayerFeedbackManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(Constants.PLAYER_FEEDBACK_GUI_NAME)
	if not gui then
		warn(`ClientPlayerFeedbackManager: no {Constants.PLAYER_FEEDBACK_GUI_NAME} ScreenGui; messages will print`)
		return
	end
	local feedbackBox = gui:FindFirstChild(Constants.PLAYER_FEEDBACK_BOX)
	local messageLabel = if feedbackBox then feedbackBox:FindFirstChild(Constants.PLAYER_FEEDBACK_LABEL) else nil
	if not feedbackBox or not feedbackBox:IsA("Frame") or not messageLabel or not messageLabel:IsA("TextLabel") then
		warn(`ClientPlayerFeedbackManager: {gui:GetFullName()} is missing {Constants.PLAYER_FEEDBACK_BOX}.{Constants.PLAYER_FEEDBACK_LABEL}`)
		return
	end
	if gui:IsA("ScreenGui") then
		gui.ResetOnSpawn = false
		gui.Enabled = true
	end
	feedbackBox.Visible = false
	self.feedbackBox = feedbackBox
	self.messageLabel = messageLabel
	self.messagePosition = messageLabel.Position
	local icon = feedbackBox:FindFirstChild(Constants.PLAYER_FEEDBACK_ICON)
	if icon and icon:IsA("ImageLabel") then
		icon.Visible = false
		self.icon = icon
	else
		warn(`ClientPlayerFeedbackManager: {feedbackBox:GetFullName()} has no {Constants.PLAYER_FEEDBACK_ICON}; run scripts/studio/build_player_feedback_gui.luau`)
	end
	self.plainColor = feedbackBox.BackgroundColor3
end

function ClientPlayerFeedbackManager:init()
	self:findGui()
	local localEvent = Instance.new("BindableEvent")
	localEvent.Name = Constants.PLAYER_FEEDBACK_LOCAL_EVENT_NAME
	localEvent.Parent = ReplicatedStorage
	self.localEvent = localEvent

	localEvent.Event:Connect(
		function(message: any, displaySec: any, iconId: any)
			if not Validate.isString(message) or not Validate.isFiniteNumber(displaySec) or displaySec <= 0 or (iconId ~= nil and not Validate.isString(iconId)) then
				warn("ClientPlayerFeedbackManager: bad local feedback", tostring(message), tostring(displaySec))
				return
			end
			self:dispatch(message, displaySec, iconId)
		end
	)

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PLAYER_FEEDBACK,
		function(payload: any)
			local isValid, err = Validate.isTableShape(payload, NOTIFY_PLAYER_FEEDBACK_SHAPE)
			if not isValid then
				warn("ClientPlayerFeedbackManager: bad NotifyPlayerFeedback payload", tostring(err))
				return
			end
			self:dispatch(payload.message, payload.displaySec)
		end
	)
end

function ClientPlayerFeedbackManager.new(): ClientPlayerFeedbackManager
	local self = setmetatable({}, ClientPlayerFeedbackManager) :: ClientPlayerFeedbackManager
	self.localEvent = nil
	self.listeners = {}
	self.feedbackBox = nil
	self.messageLabel = nil
	self.icon = nil
	self.messagePosition = UDim2.fromScale(0, 0)
	self.plainColor = UiStyle.PANEL_COLOR
	self.shownStyle = STYLE_PLAIN
	self.shownUntilTime = 0
	self.isSuppressed = false
	self.showGeneration = 0
	return self
end

return ClientPlayerFeedbackManager.new()
