--!strict

-- Receives player feedback text from the server (NotifyPlayerFeedback) and from
-- client systems (the GivePlayerFeedbackLocal BindableEvent) and hands each
-- message to the Studio-authored PlayerFeedback ScreenGui (a single box that a
-- newer message replaces) and to any other listener. Announcements
-- (announceLocal) take the second, top-centre box instead, so a beat like the
-- Camp Level rising is never missed under the action (decided 2026-09-16).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
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
		announcementBox: Frame?,
		announcementLabel: TextLabel?,
		-- the red box for danger (2026-09-25)
		alertBox: Frame?,
		alertLabel: TextLabel?,
		-- bumps per message so an older hide timer cannot clear a newer message
		showGeneration: number,
		announceGeneration: number,
		alertGeneration: number,
	},
	ClientPlayerFeedbackManager
))

local NOTIFY_PLAYER_FEEDBACK_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local DEFAULT_DISPLAY_SEC = 3

function ClientPlayerFeedbackManager:addListener(listener: FeedbackListener)
	table.insert(self.listeners, listener)
end

function ClientPlayerFeedbackManager:showInBox(message: string, displaySec: number)
	local feedbackBox = self.feedbackBox
	local messageLabel = self.messageLabel
	if not feedbackBox or not messageLabel then
		print(string.format("[PlayerFeedback] %s (%.1fs)", message, displaySec))
		return
	end
	self.showGeneration += 1
	local generation = self.showGeneration
	messageLabel.Text = message
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

-- the top-centre box; falls back to the ordinary box if the gui predates it
function ClientPlayerFeedbackManager:announceLocal(message: string, displaySec: number?)
	local box = self.announcementBox
	local label = self.announcementLabel
	local seconds = displaySec or DEFAULT_DISPLAY_SEC
	if not box or not label then
		self:showInBox(message, seconds)
		return
	end
	self.announceGeneration += 1
	local generation = self.announceGeneration
	label.Text = message
	box.Visible = true
	task.delay(
		seconds,
		function()
			if self.announceGeneration == generation then
				box.Visible = false
			end
		end
	)
end

-- the red box under the announcement: danger everyone must see (a wall
-- down, the Refinery under attack); falls back to the announcement box
function ClientPlayerFeedbackManager:alertLocal(message: string, displaySec: number?)
	local box = self.alertBox
	local label = self.alertLabel
	local seconds = displaySec or DEFAULT_DISPLAY_SEC
	if not box or not label then
		self:announceLocal(message, seconds)
		return
	end
	self.alertGeneration += 1
	local generation = self.alertGeneration
	label.Text = message
	box.Visible = true
	task.delay(
		seconds,
		function()
			if self.alertGeneration == generation then
				box.Visible = false
			end
		end
	)
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
	local announcementBox = gui:FindFirstChild(Constants.PLAYER_FEEDBACK_ANNOUNCEMENT_BOX)
	local announcementLabel = if announcementBox then announcementBox:FindFirstChild(Constants.PLAYER_FEEDBACK_LABEL) else nil
	if announcementBox and announcementBox:IsA("Frame") and announcementLabel and announcementLabel:IsA("TextLabel") then
		announcementBox.Visible = false
		self.announcementBox = announcementBox
		self.announcementLabel = announcementLabel
	else
		warn(`ClientPlayerFeedbackManager: {gui:GetFullName()} is missing {Constants.PLAYER_FEEDBACK_ANNOUNCEMENT_BOX}; run scripts/studio/build_player_feedback_gui.luau`)
	end
	local alertBox = gui:FindFirstChild(Constants.PLAYER_FEEDBACK_ALERT_BOX)
	local alertLabel = if alertBox then alertBox:FindFirstChild(Constants.PLAYER_FEEDBACK_LABEL) else nil
	if alertBox and alertBox:IsA("Frame") and alertLabel and alertLabel:IsA("TextLabel") then
		alertBox.Visible = false
		self.alertBox = alertBox
		self.alertLabel = alertLabel
	else
		warn(`ClientPlayerFeedbackManager: {gui:GetFullName()} is missing {Constants.PLAYER_FEEDBACK_ALERT_BOX}; run scripts/studio/build_player_feedback_gui.luau`)
	end
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
	self.showGeneration = 0
	self.announceGeneration = 0
	self.announcementBox = nil
	self.announcementLabel = nil
	self.alertBox = nil
	self.alertLabel = nil
	self.alertGeneration = 0
	return self
end

return ClientPlayerFeedbackManager.new()
