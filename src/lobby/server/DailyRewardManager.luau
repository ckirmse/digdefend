--!strict

-- Daily Rewards (GDD "Daily Rewards Menu", M39; the format of Lucky
-- Squares). The tiles are GameData/Store/DailyRewards; the rules are pure
-- DailyRewardRules; the record of truth is PlayerData's dailyReward
-- (lastClaimedDay, nextClaimTime), which this manager is the one writer
-- of and which the client already reads as two CurrentPlayer attributes
-- (replicateDailyReward).
--
-- Nothing happens on the server when a day opens: the client works out
-- from nextClaimTime, on the shared server clock, that a tile is ready.
-- TryClaimDailyReward { tileIndex } is checked against the same rules,
-- paid, saved at once, and answered with NotifyDailyRewardClaimed so the
-- menu can show what landed. Nothing in the claim yields, so two presses
-- cannot both find the day unclaimed.
local CosmeticCatalogueData = require("@game/ServerScriptService/GameData/Cosmetics/Catalogue")
local DailyRewardsData = require("@game/ServerScriptService/GameData/Store/DailyRewards")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local DailyRewardRules = require("@game/ReplicatedStorage/Shared/DailyRewardRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerData = require(script.Parent.Parent.Server.PlayerData)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local DailyRewardManager = {}
DailyRewardManager.__index = DailyRewardManager

export type DailyRewardManager = typeof(setmetatable({} :: {}, DailyRewardManager))

local CLAIM_SHAPE = {
	tileIndex = "positiveInteger",
}

-- the next day opens now (the wait skipped), and the whole record back
-- to a new account's
DailyRewardManager.ADVANCE_COMMAND = "advanceDailyReward"
DailyRewardManager.RESET_COMMAND = "resetDailyReward"

function DailyRewardManager:getNetHandlers()
	return {
		[NetEventNames.TRY_CLAIM_DAILY_REWARD] = {
			shape = CLAIM_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:claim(player, payload.tileIndex)
			end,
		},
	}
end

-- pays one tile into the save and says what was paid, for the notify. A
-- cosmetic already owned pays its duplicate Diamonds
function DailyRewardManager:grant(player: Player, playerData: PlayerData.PlayerData, reward: DailyRewardRules.Reward): { [string]: any }
	local kind = reward.KIND
	if kind == Enums.DailyRewardKind.KEYS then
		local amount = reward.AMOUNT or 0
		playerData:addKeys(amount)
		SplendidReplicationManager:replicateGacha(player)
		return { kind = kind, amount = amount }
	end
	if kind == Enums.DailyRewardKind.COSMETIC then
		local cosmeticId = reward.COSMETIC_ID or ""
		if not playerData:getOwnedCosmetics()[cosmeticId] then
			playerData:addOwnedCosmetic(cosmeticId)
			SplendidReplicationManager:replicateGacha(player)
			return { kind = kind, amount = 0, cosmeticId = cosmeticId }
		end
		local duplicateDiamonds = reward.DUPLICATE_DIAMONDS or 0
		playerData:addDiamonds(duplicateDiamonds)
		SplendidReplicationManager:replicateDiamonds(player)
		return { kind = Enums.DailyRewardKind.DIAMONDS, amount = duplicateDiamonds, cosmeticId = cosmeticId, isDuplicate = true }
	end
	local amount = reward.AMOUNT or 0
	playerData:addDiamonds(amount)
	SplendidReplicationManager:replicateDiamonds(player)
	return { kind = Enums.DailyRewardKind.DIAMONDS, amount = amount }
end

function DailyRewardManager:claim(player: Player, tileIndex: number)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	local rewards = DailyRewardsData.REWARDS :: { DailyRewardRules.Reward }
	local state = playerData:getDailyReward()
	local now = workspace:GetServerTimeNow()
	local claimableDay = DailyRewardRules.getClaimableDay(state, now)
	-- a stale or made-up tile is dropped without a word: the menu only
	-- ever offers the ready one
	if not claimableDay or DailyRewardRules.getTileForDay(claimableDay, #rewards) ~= tileIndex then
		return
	end
	local claimed = DailyRewardRules.applyClaim(state, now, DailyRewardsData.CLAIM_INTERVAL_SEC)
	state.lastClaimedDay = claimed.lastClaimedDay
	state.nextClaimTime = claimed.nextClaimTime
	local result = self:grant(player, playerData, rewards[tileIndex])
	SplendidReplicationManager:replicateDailyReward(player)
	playerData:saveNow()
	result.tileIndex = tileIndex
	NetManager:notifyClient(player, NetEventNames.NOTIFY_DAILY_REWARD_CLAIMED, result)
	print(`[DailyRewardManager] {player.Name} claimed day {claimed.lastClaimedDay} (tile {tileIndex})`)
end

function DailyRewardManager:registerDevCommands()
	DevTools:registerPlaceCommand(
		DailyRewardManager.ADVANCE_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:getDailyReward().nextClaimTime = 0
			SplendidReplicationManager:replicateDailyReward(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Daily reward ready")
		end
	)
	DevTools:registerPlaceCommand(
		DailyRewardManager.RESET_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			local state = playerData:getDailyReward()
			state.lastClaimedDay = 0
			state.nextClaimTime = 0
			SplendidReplicationManager:replicateDailyReward(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Daily rewards reset to day 1")
		end
	)
end

function DailyRewardManager:init()
	local rewards = DailyRewardsData.REWARDS :: { DailyRewardRules.Reward }
	local problems = DailyRewardRules.validate(
		rewards,
		function(cosmeticId: string): boolean
			return (CosmeticCatalogueData.BY_ID :: { [string]: any })[cosmeticId] ~= nil
		end
	)
	if #problems > 0 then
		error("DailyRewardManager: GameData/Store/DailyRewards is malformed: " .. table.concat(problems, "; "))
	end
	-- the tiles the menu draws; a cosmetic's name and picture come from
	-- the Key Store's list, already published
	SplendidReplicationManager:setGameMetadata(Attributes.DAILY_REWARD_CATALOGUE, DailyRewardRules.encodeCatalogue(DailyRewardRules.publish(rewards)))
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function DailyRewardManager.new(): DailyRewardManager
	local self = setmetatable({}, DailyRewardManager) :: DailyRewardManager
	return self
end

return DailyRewardManager.new()
