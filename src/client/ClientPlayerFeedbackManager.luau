--!strict

-- Receives player feedback text from the server (NotifyPlayerFeedback) and from
-- client systems (the GivePlayerFeedbackLocal BindableEvent) and hands each
-- message to whoever is listening. The PlayerFeedback ScreenGui (M9) is the
-- intended listener; until then messages are printed.
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

function ClientPlayerFeedbackManager:dispatch(message: string, displaySec: number)
	if #self.listeners == 0 then
		print(string.format("[PlayerFeedback] %s (%.1fs)", message, displaySec))
		return
	end
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

function ClientPlayerFeedbackManager:init()
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
	return self
end

return ClientPlayerFeedbackManager.new()
