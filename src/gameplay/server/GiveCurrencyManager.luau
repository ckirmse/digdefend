--!strict

-- Give Currency (M32): one player sends Gold Bars and Iron Bars to
-- another. The prompt on each other player and the menu are the client's
-- (ClientGiveCurrencyManager); this is the one request behind the menu's
-- Confirm. The balances are RefineryManager's run state, so the transfer
-- is a spend from one and an add to the other there, and both players
-- hear the result as feedback text. Pure GiveCurrencyRules checks the
-- amounts, the same rules the menu clamps with. The prompt's words and
-- reach and the step of the plus and minus buttons are published as
-- GameMetadata, since the client never requires GameData.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GiveCurrencyRules = require("@game/ReplicatedStorage/Shared/GiveCurrencyRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local GiveCurrencyData = require("@game/ServerScriptService/GameData/Run/GiveCurrency")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ReviveManager = require(script.Parent.ReviveManager)

local GiveCurrencyManager = {}
GiveCurrencyManager.__index = GiveCurrencyManager

export type GiveCurrencyManager = typeof(setmetatable({} :: {}, GiveCurrencyManager))

-- a user id is any whole number: Studio's local test players have
-- negative ones, and a positive-only check silently refused every gift
-- in a two-player test (2026-10-05)
local TRY_GIVE_CURRENCY_SHAPE = {
	targetUserId = "integer",
	goldBars = "nonnegativeInteger",
	ironBars = "nonnegativeInteger",
}

local REJECTION_FEEDBACK: { [string]: string } = {
	[GiveCurrencyRules.REJECT_NOTHING] = GiveCurrencyData.NOTHING_FEEDBACK,
	[GiveCurrencyRules.REJECT_BALANCE] = GiveCurrencyData.BALANCE_FEEDBACK,
}

function GiveCurrencyManager:handleTryGiveCurrency(sender: Player, payload: { [string]: any })
	local target = Players:GetPlayerByUserId(payload.targetUserId)
	if not target or target == sender or not GameController:isPlayerReady(target) or ReviveManager:isDead(target) or ReviveManager:isDead(sender) then
		PlayerFeedbackManager:give(sender, GiveCurrencyData.UNAVAILABLE_FEEDBACK, GiveCurrencyData.FEEDBACK_DISPLAY_SEC)
		return
	end
	local goldBars: number = payload.goldBars
	local ironBars: number = payload.ironBars
	local rejection = GiveCurrencyRules.getRejection(goldBars, ironBars, RefineryManager:getGoldBars(sender), RefineryManager:getIronBars(sender))
	if rejection then
		PlayerFeedbackManager:give(sender, REJECTION_FEEDBACK[rejection], GiveCurrencyData.FEEDBACK_DISPLAY_SEC)
		return
	end
	-- both spends were just checked against the balances, so neither can fail
	RefineryManager:spendGoldBars(sender, goldBars)
	RefineryManager:spendIronBars(sender, ironBars)
	RefineryManager:addGoldBars(target, goldBars)
	RefineryManager:addIronBars(target, ironBars)
	local amounts = GiveCurrencyRules.describeAmounts(
		goldBars,
		ironBars,
		Enums.getPublicName(Enums.RefinedResource, Enums.RefinedResource.GOLD_BAR) or "Gold Bar",
		Enums.getPublicName(Enums.RefinedResource, Enums.RefinedResource.IRON_BAR) or "Iron Bar"
	)
	print(`[GiveCurrencyManager] {sender.Name} sent {amounts} to {target.Name}`)
	-- everyone sees the bars fly from one player to the other
	NetManager:notifyAllClients(NetEventNames.NOTIFY_CURRENCY_GIVEN, {
		senderUserId = sender.UserId,
		targetUserId = target.UserId,
		goldBars = goldBars,
		ironBars = ironBars,
	})
	PlayerFeedbackManager:give(target, string.format(GiveCurrencyData.RECEIVED_FORMAT, sender.DisplayName, amounts), GiveCurrencyData.FEEDBACK_DISPLAY_SEC)
	PlayerFeedbackManager:give(sender, string.format(GiveCurrencyData.SENT_FORMAT, amounts, target.DisplayName), GiveCurrencyData.FEEDBACK_DISPLAY_SEC)
end

function GiveCurrencyManager:getNetHandlers()
	return {
		[NetEventNames.TRY_GIVE_CURRENCY] = {
			shape = TRY_GIVE_CURRENCY_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryGiveCurrency(player, payload)
			end,
		},
	}
end

function GiveCurrencyManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.GIVE_CURRENCY_STEP, GiveCurrencyData.STEP)
	SplendidReplicationManager:setGameMetadata(Attributes.GIVE_CURRENCY_PROMPT_ACTION_TEXT, GiveCurrencyData.PROMPT_ACTION_TEXT)
	SplendidReplicationManager:setGameMetadata(Attributes.GIVE_CURRENCY_PROMPT_MAX_DISTANCE_STUDS, GiveCurrencyData.PROMPT_MAX_DISTANCE_STUDS)
	GameController:registerPlaceManager(self)
end

function GiveCurrencyManager.new(): GiveCurrencyManager
	local self = setmetatable({}, GiveCurrencyManager) :: GiveCurrencyManager
	return self
end

return GiveCurrencyManager.new()
