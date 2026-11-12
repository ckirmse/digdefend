--!strict

-- The group reward (M78, designer 2026-11-12): a member of the game's
-- Roblox group is paid Diamonds once per account (GameData/Store/
-- GroupReward). This manager is the one writer of the save's
-- hasClaimedGroupReward flag.
--
-- Whether a player is in the group is asked of Roblox off the claim's
-- thread (at Ready, and again when the client says a store menu opened)
-- and held here, published as the IsInRewardGroup CurrentPlayer
-- attribute. The claim itself (TryClaimGroupReward) never yields: it
-- reads the held answer and the save's flag, sets the flag, and pays,
-- all in one step. That is what makes it once only: two presses cannot
-- both find the flag unset. The client only ever asks; the amount and
-- the right to it are decided here.
local GroupService = game:GetService("GroupService")

local GroupRewardData = require("@game/ServerScriptService/GameData/Store/GroupReward")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local GroupRewardRules = require("@game/ReplicatedStorage/Shared/GroupRewardRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local GroupRewardManager = {}
GroupRewardManager.__index = GroupRewardManager

export type GroupRewardManager = typeof(setmetatable(
	{} :: {
		-- Roblox's latest answer per Ready player, when it was last asked
		-- (server time), and whether a question is out
		isInGroupByPlayer: { [Player]: boolean },
		checkTimeByPlayer: { [Player]: number },
		isCheckRunningByPlayer: { [Player]: boolean },
	},
	GroupRewardManager
))

local EMPTY_SHAPE = {}

GroupRewardManager.RESET_COMMAND = "resetGroupReward"

local FEEDBACK_NOT_IN_GROUP = "Join our group to claim this reward"

function GroupRewardManager:getNetHandlers()
	return {
		[NetEventNames.TRY_REFRESH_GROUP_REWARD] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:refreshMembershipIfNeeded(player)
			end,
		},
		[NetEventNames.TRY_CLAIM_GROUP_REWARD] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:claim(player)
			end,
		},
	}
end

function GroupRewardManager:isInGroup(player: Player): boolean
	return self.isInGroupByPlayer[player] == true
end

-- asks Roblox which groups the player is in (yields). GroupService is
-- asked rather than Player:IsInGroupAsync because that answer is cached
-- for the whole visit, so a player who joined the group a moment ago
-- would have to rejoin the game to be seen
function GroupRewardManager:refreshMembership(player: Player)
	if self.isCheckRunningByPlayer[player] then
		return
	end
	self.isCheckRunningByPlayer[player] = true
	self.checkTimeByPlayer[player] = workspace:GetServerTimeNow()
	local isSuccess, groups = pcall(
		function()
			return GroupService:GetGroupsAsync(player.UserId)
		end
	)
	-- gone or reset while Roblox answered
	if not self.isCheckRunningByPlayer[player] then
		return
	end
	self.isCheckRunningByPlayer[player] = nil
	if not GameController:getPlayerData(player) then
		return
	end
	if not isSuccess then
		-- the last answer stands; the next menu opening asks again
		warn(`GroupRewardManager: GroupService failed for {player.Name}; the last answer stands. {tostring(groups)}`)
		return
	end
	local isInGroup = false
	for _, group in groups :: { any } do
		if group.Id == GroupRewardData.GROUP_ID then
			isInGroup = true
			break
		end
	end
	self.isInGroupByPlayer[player] = isInGroup
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_IN_REWARD_GROUP, isInGroup)
end

-- the client's "a store menu opened": worth asking again only for a
-- player who could still earn the reward, and never more often than
-- RECHECK_SEC, so a client cannot make the server spam Roblox
function GroupRewardManager:refreshMembershipIfNeeded(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasClaimedGroupReward() or self:isInGroup(player) then
		return
	end
	local lastCheckTime = self.checkTimeByPlayer[player]
	if lastCheckTime and workspace:GetServerTimeNow() - lastCheckTime < GroupRewardData.RECHECK_SEC then
		return
	end
	self:refreshMembership(player)
end

-- the claim: nothing here yields, so the flag is set before a second
-- press can be read, and the save goes out with the Diamonds
function GroupRewardManager:claim(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasClaimedGroupReward() then
		return
	end
	if not GroupRewardRules.canClaim(self:isInGroup(player), false) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_IN_GROUP)
		return
	end
	playerData:setHasClaimedGroupReward(true)
	playerData:addDiamonds(GroupRewardData.REWARD_DIAMONDS)
	SplendidReplicationManager:replicateDiamonds(player)
	SplendidReplicationManager:replicateGroupReward(player)
	playerData:saveNow()
	print(`[GroupRewardManager] {player.Name} claimed the group reward: {GroupRewardData.REWARD_DIAMONDS} Diamonds`)
end

-- ready-sequence entry (registered through GameController:registerPlaceManager):
-- not in the group until Roblox says so, asked off the thread, and not
-- asked at all for an account that already has the reward
function GroupRewardManager:onPlayerReady(player: Player)
	self.isInGroupByPlayer[player] = false
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_IN_REWARD_GROUP, false)
	local playerData = GameController:getPlayerData(player)
	if playerData and not playerData:getHasClaimedGroupReward() then
		task.spawn(
			function()
				self:refreshMembership(player)
			end
		)
	end
end

-- teardown entry; also the dev-tool reset, after which Ready asks again
function GroupRewardManager:onPlayerRemoved(player: Player)
	self.isInGroupByPlayer[player] = nil
	self.checkTimeByPlayer[player] = nil
	self.isCheckRunningByPlayer[player] = nil
end

function GroupRewardManager:registerDevCommands()
	-- the reward unclaimed (the Diamonds it paid are kept) and the group
	-- asked about again, so the offer can be tested from either state
	DevTools:registerPlaceCommand(
		GroupRewardManager.RESET_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:setHasClaimedGroupReward(false)
			SplendidReplicationManager:replicateGroupReward(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Group reward reset")
			self:refreshMembership(player)
		end
	)
end

function GroupRewardManager:init()
	local reward = GroupRewardData.REWARD_DIAMONDS
	if typeof(reward) ~= "number" or reward <= 0 or reward % 1 ~= 0 then
		error("GroupRewardManager: GameData/Store/GroupReward.REWARD_DIAMONDS must be a positive whole number")
	end
	-- the amount every banner and the claim menu show
	SplendidReplicationManager:setGameMetadata(Attributes.GROUP_REWARD_DIAMONDS, reward)
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function GroupRewardManager.new(): GroupRewardManager
	local self = setmetatable({}, GroupRewardManager) :: GroupRewardManager
	self.isInGroupByPlayer = {}
	self.checkTimeByPlayer = {}
	self.isCheckRunningByPlayer = {}
	return self
end

return GroupRewardManager.new()
