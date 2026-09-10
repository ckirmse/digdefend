--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local NetworkData = require("@game/ServerScriptService/GameData/Control/Network")
local TokenBucket = require(script.Parent.TokenBucket)

local NetManager = {}
NetManager.__index = NetManager

export type NetHandler = (player: Player, payload: { [string]: any }) -> ()

export type NetHandlerEntry = {
	shape: { [string]: any },
	handler: NetHandler,
	cost: number?,
}

export type NetHandlers = { [string]: NetHandlerEntry }

type PlayerBudget = {
	bucket: TokenBucket.TokenBucket,
	droppedCount: number,
	lastDropWarnTime: number,
	rejectedCount: number,
	lastRejectWarnTime: number,
}

export type NetManager = typeof(setmetatable(
	{} :: {
		handlers: NetHandlers,
		remoteEvent: RemoteEvent?,
		budgetByPlayer: { [Player]: PlayerBudget },
	},
	NetManager
))

local gameController: any -- prevent circular reference by not initializing here

function NetManager:getBudget(player: Player, now: number): PlayerBudget
	local budget = self.budgetByPlayer[player]
	if not budget then
		budget = {
			bucket = TokenBucket.new(NetworkData.RATE_LIMIT_CAPACITY, NetworkData.RATE_LIMIT_REFILL_PER_SEC, now),
			droppedCount = 0,
			lastDropWarnTime = 0,
			rejectedCount = 0,
			lastRejectWarnTime = 0,
		}
		self.budgetByPlayer[player] = budget
	end
	return budget
end

-- rejections are the visibility the single-RemoteEvent design is built on, but
-- one warn per bad message hands an exploiter a free log flood; report the
-- newest reason with a count of everything suppressed since the last report
function NetManager:warnRejection(player: Player, message: string)
	local now = workspace:GetServerTimeNow()
	local budget = self:getBudget(player, now)
	budget.rejectedCount += 1
	if now - budget.lastRejectWarnTime < NetworkData.RATE_LIMIT_WARN_INTERVAL_SEC then
		return
	end
	warn(
		string.format(
			"NetManager: %s from %s (%d message(s) rejected since last warning)",
			message,
			player.Name,
			budget.rejectedCount
		)
	)
	budget.lastRejectWarnTime = now
	budget.rejectedCount = 0
end

function NetManager:takeBudget(player: Player, eventName: string, cost: number): boolean
	local now = workspace:GetServerTimeNow()
	local budget = self:getBudget(player, now)
	if budget.bucket:tryTake(cost, now) then
		return true
	end
	budget.droppedCount += 1
	if now - budget.lastDropWarnTime >= NetworkData.RATE_LIMIT_WARN_INTERVAL_SEC then
		warn(
			string.format(
				"NetManager: rate limited %s on %s (%d message(s) dropped since last warning)",
				player.Name,
				eventName,
				budget.droppedCount
			)
		)
		budget.lastDropWarnTime = now
		budget.droppedCount = 0
	end
	return false
end

function NetManager:onPlayerRemoved(player: Player)
	self.budgetByPlayer[player] = nil
end

function NetManager:onServerEvent(player: Player, eventName: any, payload: any)
	-- charged before every other check so that malformed and unknown-event
	-- floods, whose rejection warns are themselves the abuse vector, are capped
	local entry = if typeof(eventName) == "string" then self.handlers[eventName] else nil
	local cost = if entry and entry.cost then entry.cost else NetworkData.RATE_LIMIT_DEFAULT_COST
	if not self:takeBudget(player, tostring(eventName), cost) then
		return
	end

	if not gameController:isPlayerReady(player) then
		self:warnRejection(player, string.format("message %s from non-Ready player", tostring(eventName)))
		return
	end

	if typeof(eventName) ~= "string" then
		self:warnRejection(player, string.format("non-string event name %s", tostring(eventName)))
		return
	end

	if not entry then
		self:warnRejection(player, string.format("unhandled event %s", eventName))
		return
	end

	local isValid, err = Validate.isTableShape(payload, entry.shape)
	if not isValid then
		self:warnRejection(player, string.format("invalid payload for %s (%s)", eventName, tostring(err)))
		return
	end

	-- an error partway through a handler can leave state half-mutated; isolate
	-- it so one bad message cannot take down the dispatch loop, and make it visible
	local isSuccess, handlerErr = pcall(entry.handler, player, payload)
	if not isSuccess then
		warn(string.format("NetManager: handler error for %s from %s: %s", eventName, player.Name, tostring(handlerErr)))
	end
end

function NetManager:notifyClient(player: Player, eventName: string, payload: { [string]: any })
	local remoteEvent = self.remoteEvent
	if not remoteEvent then
		warn("NetManager: notifyClient before init", eventName)
		return
	end
	remoteEvent:FireClient(player, eventName, payload)
end

function NetManager:notifyAllClients(eventName: string, payload: { [string]: any })
	local remoteEvent = self.remoteEvent
	if not remoteEvent then
		warn("NetManager: notifyAllClients before init", eventName)
		return
	end
	remoteEvent:FireAllClients(eventName, payload)
end

function NetManager:init(gameControllerIn: any, handlers: NetHandlers)
	gameController = gameControllerIn
	self.handlers = handlers

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = Constants.REMOTE_EVENT_NAME
	remoteEvent.Parent = ReplicatedStorage
	self.remoteEvent = remoteEvent

	remoteEvent.OnServerEvent:Connect(
		function(player: Player, eventName: any, payload: any)
			self:onServerEvent(player, eventName, payload)
		end
	)

	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:onPlayerRemoved(player)
		end
	)
end

function NetManager.new(): NetManager
	local self = setmetatable({}, NetManager) :: NetManager
	self.handlers = {}
	self.remoteEvent = nil
	self.budgetByPlayer = {}
	return self
end

return NetManager.new()
