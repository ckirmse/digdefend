--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local ClientNetManager = {}
ClientNetManager.__index = ClientNetManager

export type NotifyHandler = (payload: any) -> ()

export type ClientNetManager = typeof(setmetatable(
	{} :: {
		remoteEvent: RemoteEvent?,
		handlers: { [string]: NotifyHandler },
	},
	ClientNetManager
))

function ClientNetManager:fireServer(eventName: string, payload: { [string]: any })
	local remoteEvent = self.remoteEvent
	if not remoteEvent then
		warn("ClientNetManager: fireServer before init", eventName)
		return
	end
	remoteEvent:FireServer(eventName, payload)
end

function ClientNetManager:registerHandler(eventName: string, handler: NotifyHandler)
	if self.handlers[eventName] then
		warn("ClientNetManager: replacing handler for", eventName)
	end
	self.handlers[eventName] = handler
end

function ClientNetManager:onClientEvent(eventName: any, payload: any)
	local handler = if typeof(eventName) == "string" then self.handlers[eventName] else nil
	if not handler then
		warn("ClientNetManager: unhandled event", tostring(eventName))
		return
	end
	local isSuccess, err = pcall(handler, payload)
	if not isSuccess then
		warn(string.format("ClientNetManager: handler error for %s: %s", tostring(eventName), tostring(err)))
	end
end

function ClientNetManager:init()
	local remoteEvent = ReplicatedStorage:WaitForChild(Constants.REMOTE_EVENT_NAME) :: RemoteEvent
	self.remoteEvent = remoteEvent

	remoteEvent.OnClientEvent:Connect(
		function(eventName: any, payload: any)
			self:onClientEvent(eventName, payload)
		end
	)
end

function ClientNetManager.new(): ClientNetManager
	local self = setmetatable({}, ClientNetManager) :: ClientNetManager
	self.remoteEvent = nil
	self.handlers = {}
	return self
end

return ClientNetManager.new()
