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

export type ClientPlayerFeedbackManager = typeof(setmetatable(
	{} :: {
		localEvent: BindableEvent?,
		listeners: { FeedbackListener },
		feedbackBox: Frame?,
		messageLabel: TextLabel?,
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
function ClientPlayerFeedbackManager:show(message: string, displaySec: number, style: number)
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

function ClientPlayerFeedbackManager:showInBox(message: string, displaySec: number)
	self:show(message, displaySec, STYLE_PLAIN)
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

function ClientPlayerFeedbackManager:dispatch(message: string, displaySec: number)
	self:showInBox(message, displaySec)
	for _, listener in self.listeners do
		listener(message, displaySec)
	end
end

-- client systems call this instead of firing the BindableEvent by hand
function ClientPlayerFeedbackManager:giveLocal(message: string, displaySec: number?)
	local localEvent = self.localEvent
	if not localEvent then
		warn("ClientPlayerFeedbackManager: giveLocal before init")
		return
	end
	localEvent:Fire(message, displaySec or DEFAULT_DISPLAY_SEC)
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
	self.plainColor = feedbackBox.BackgroundColor3
end

function ClientPlayerFeedbackManager:init()
	self:findGui()
	local localEvent = Instance.new("BindableEvent")
	localEvent.Name = Constants.PLAYER_FEEDBACK_LOCAL_EVENT_NAME
	localEvent.Parent = ReplicatedStorage
	self.localEvent = localEvent

	localEvent.Event:Connect(
		function(message: any, displaySec: any)
			if not Validate.isString(message) or not Validate.isFiniteNumber(displaySec) or displaySec <= 0 then
				warn("ClientPlayerFeedbackManager: bad local feedback", tostring(message), tostring(displaySec))
				return
			end
			self:dispatch(message, displaySec)
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
	self.plainColor = UiStyle.PANEL_COLOR
	self.shownStyle = STYLE_PLAIN
	self.shownUntilTime = 0
	self.isSuppressed = false
	self.showGeneration = 0
	return self
end

return ClientPlayerFeedbackManager.new()
