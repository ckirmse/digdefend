--!strict

-- The single top-level orchestrator: requires every manager, wires them
-- together through init(), owns the player lifecycle, and assembles the full
-- network protocol in one place so it can be read top to bottom.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerControlData = require("@game/ServerScriptService/GameData/Control/Player")
local ProfileStore = require(script.Parent.Libs.ProfileStore)
local DevTools = require(script.Parent.DevTools)
local NetManager = require(script.Parent.NetManager)
local PlayerData = require(script.Parent.PlayerData)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.SplendidReplicationManager)

local GameController = {}
GameController.__index = GameController

export type GameController = typeof(setmetatable(
	{} :: {
		playerStore: any?,
		-- the single authoritative lifecycle table; a player is in here from
		-- LOADING until GONE and nowhere else
		playerDatas: { [Player]: PlayerData.PlayerData },
		pendingExitCount: number,
		netManager: typeof(NetManager),
		devTools: typeof(DevTools),
		playerFeedbackManager: typeof(PlayerFeedbackManager),
		splendidReplicationManager: typeof(SplendidReplicationManager),
	},
	GameController
))

type SequenceEntry = {
	manager: any?,
	step: ((player: Player) -> ())?,
	-- what the dev-tool reset does with the entry: "ready" repeats
	-- onPlayerReady, "reset" calls onPlayerReset instead, false skips it
	onReset: any,
}

-- DEV TOOL CONTRACT: resetPlayerState must leave a player indistinguishable
-- from a brand-new player, client and server side. If you add (a) a field to
-- PlayerSaveSchema, (b) a manager with per-player runtime state, or (c) new
-- per-player replication (M7), you MUST add it to both sequences below,
-- choosing its onReset behavior explicitly.
--
-- Ordered setup sequence for a player reaching Ready; order is load-bearing.
local PLAYER_READY_SEQUENCE: { SequenceEntry } = {
	-- first: every later entry may replicate into the tree it builds; reset
	-- rewrites the tree in place via resetPlayerTree instead
	{ manager = SplendidReplicationManager, onReset = false },
}

-- Ordered teardown sequence for a leaving player; order is load-bearing.
-- onReset = false skips the entry during a dev-tool reset.
local PLAYER_TEARDOWN_SEQUENCE: { SequenceEntry } = {
	-- last: the tree is reset in place, never destroyed
	{ manager = SplendidReplicationManager, onReset = false },
}

local function runReadySequence(player: Player, isReset: boolean)
	for _, entry in PLAYER_READY_SEQUENCE do
		if isReset and entry.onReset == false then
			continue
		end
		if isReset and entry.onReset == "reset" then
			entry.manager:onPlayerReset(player)
			continue
		end
		if entry.step then
			entry.step(player)
		else
			entry.manager:onPlayerReady(player)
		end
	end
end

local function runTeardownSequence(player: Player, isReset: boolean)
	for _, entry in PLAYER_TEARDOWN_SEQUENCE do
		if isReset and not entry.onReset then
			continue
		end
		entry.manager:onPlayerRemoved(player)
	end
end

local function getProfileKey(player: Player): string
	return PlayerControlData.PROFILE_KEY_PREFIX .. player.UserId
end

local function fetchIsAdmin(player: Player): boolean
	local isSuccess, rank = pcall(
		function()
			return player:GetRankInGroup(Constants.ADMIN_GROUP_ID)
		end
	)
	if not isSuccess then
		warn("GameController: GetRankInGroup failed for", player.Name, rank)
		return false
	end
	return rank >= Constants.ADMIN_MIN_RANK
end

-- nil unless the player is READY; the one question every other system asks
function GameController:getPlayerData(player: Player): PlayerData.PlayerData?
	local playerData = self.playerDatas[player]
	if playerData and playerData:isReady() then
		return playerData
	end
	return nil
end

function GameController:isPlayerReady(player: Player): boolean
	return self:getPlayerData(player) ~= nil
end

function GameController:isPlayerAdmin(player: Player): boolean
	local playerData = self:getPlayerData(player)
	return playerData ~= nil and playerData:getIsAdmin()
end

function GameController:getReadyPlayers(): { Player }
	local readyPlayers = {}
	for player, playerData in self.playerDatas do
		if playerData:isReady() then
			table.insert(readyPlayers, player)
		end
	end
	return readyPlayers
end

function GameController:abandonLoad(player: Player, playerData: PlayerData.PlayerData, profile: any?)
	if profile then
		profile:EndSession()
	end
	playerData:setLifecycle(Enums.PlayerLifecycle.GONE)
	self.playerDatas[player] = nil
end

function GameController:processPlayerAdd(player: Player)
	if self.playerDatas[player] then
		warn("GameController: duplicate PlayerAdded for", player.Name)
		return
	end

	local playerData = PlayerData.new(player)
	self.playerDatas[player] = playerData
	print("[GameController] Loading:", player.Name)
	player:SetAttribute(Attributes.LOAD_STATUS, Enums.LoadStatus.LOADING_DATA)

	-- passing Cancel disables ProfileStore's own session timeout, so the retry
	-- loop must be bounded here or a DataStore outage strands the player on
	-- the loading screen forever
	local loadStartedAt = workspace:GetServerTimeNow()
	local profile = self.playerStore:StartSessionAsync(
		getProfileKey(player),
		{
			Cancel = function()
				if player.Parent ~= Players then
					return true
				end
				return workspace:GetServerTimeNow() - loadStartedAt >= PlayerControlData.DATA_LOAD_TIMEOUT_SEC
			end,
		}
	)

	if profile == nil then
		player:Kick("Couldn't load your data. Check your connection and rejoin.")
		self:abandonLoad(player, playerData, nil)
		return
	end

	if player.Parent ~= Players then
		self:abandonLoad(player, playerData, profile)
		return
	end

	profile:Reconcile()
	profile:AddUserId(player.UserId)

	profile.OnSessionEnd:Connect(
		function()
			if self.playerDatas[player] then
				player:Kick("Your session ended. Please rejoin.")
			end
		end
	)

	profile.OnSave:Connect(
		function()
			if playerData:shouldSaveOnExit() then
				profile.Data = playerData:getSaveData()
			end
		end
	)

	playerData:setProfile(profile)
	playerData:loadSaveData(playerData:validate(profile.Data))
	playerData:setIsAdmin(fetchIsAdmin(player))

	if player.Parent ~= Players then
		self:abandonLoad(player, playerData, profile)
		return
	end

	playerData:setLifecycle(Enums.PlayerLifecycle.READY)
	player:SetAttribute(Attributes.LOAD_STATUS, Enums.LoadStatus.READY)
	runReadySequence(player, false)
	print("[GameController] Ready:", player.Name, if playerData:getIsAdmin() then "(admin)" else "")
end

function GameController:processPlayerRemove(player: Player)
	local playerData = self.playerDatas[player]
	if playerData == nil then
		return
	end
	local lifecycle = playerData:getLifecycle()
	if lifecycle == Enums.PlayerLifecycle.GONE or lifecycle == Enums.PlayerLifecycle.LEAVING then
		return
	end
	if lifecycle == Enums.PlayerLifecycle.LOADING then
		-- processPlayerAdd notices player.Parent == nil at its next checkpoint
		-- and abandons the load itself
		return
	end

	playerData:setLifecycle(Enums.PlayerLifecycle.LEAVING)
	self.pendingExitCount += 1
	print("[GameController] Leaving:", player.Name)

	runTeardownSequence(player, false)
	self.playerDatas[player] = nil

	local profile = playerData:getProfile()
	if profile then
		if playerData:shouldSaveOnExit() then
			profile.Data = playerData:getSaveData()
		end
		profile:EndSession()
	end
	playerData:destroy()

	self.pendingExitCount -= 1
	playerData:setLifecycle(Enums.PlayerLifecycle.GONE)
	print("[GameController] Gone:", player.Name)
end

-- the reset contract lives on PLAYER_READY_SEQUENCE / PLAYER_TEARDOWN_SEQUENCE
-- (see the DEV TOOL CONTRACT comment above them)
function GameController:resetPlayerState(player: Player)
	local playerData = self.playerDatas[player]
	if playerData == nil or not playerData:isReady() then
		warn("GameController: resetPlayerState on non-Ready player", player.Name)
		return
	end

	print("[GameController] Resetting player state:", player.Name)

	-- LOADING fences net handlers and everything else that asks getPlayerData
	playerData:setLifecycle(Enums.PlayerLifecycle.LOADING)

	runTeardownSequence(player, true)
	playerData:resetToNewPlayer()

	-- overwrite the live profile so a server crash cannot resurrect old data
	local profile = playerData:getProfile()
	if profile then
		profile.Data = playerData:getSaveData()
	end

	playerData:setLifecycle(Enums.PlayerLifecycle.READY)
	SplendidReplicationManager:resetPlayerTree(player)
	runReadySequence(player, true)

	print("[GameController] Reset complete:", player.Name)
end

function GameController:init()
	self.splendidReplicationManager = SplendidReplicationManager
	SplendidReplicationManager:init(self)

	self.devTools = DevTools
	DevTools:init(self, SplendidReplicationManager)

	self.playerFeedbackManager = PlayerFeedbackManager

	-- the full network protocol, assembled in one place; managers that handle
	-- client messages expose getNetHandlers() and are listed here
	local netHandlers: NetManager.NetHandlers = {}
	local handlerOwners: { any } = {
		DevTools,
	}
	for _, manager in handlerOwners do
		for eventName, entry in manager:getNetHandlers() do
			if netHandlers[eventName] then
				error("GameController: duplicate net handler for " .. eventName)
			end
			netHandlers[eventName] = entry
		end
	end

	self.netManager = NetManager
	NetManager:init(self, netHandlers)

	self.playerStore = ProfileStore.New(PlayerControlData.PROFILE_STORE_NAME, PlayerData.getDefaultSaveData())
	ProfileStore.OnError:Connect(
		function(message: string, storeName: string, profileKey: string)
			warn("ProfileStore error:", message, storeName, profileKey)
			for player, playerData in self.playerDatas do
				if getProfileKey(player) ~= profileKey then
					continue
				end
				if playerData:getLifecycle() == Enums.PlayerLifecycle.LOADING then
					player:SetAttribute(Attributes.LOAD_STATUS, Enums.LoadStatus.RETRYING)
				end
			end
		end
	)

	game:BindToClose(
		function()
			local elapsed = 0
			while self.pendingExitCount > 0 and elapsed < PlayerControlData.BIND_TO_CLOSE_TIMEOUT_SEC do
				task.wait(0.1)
				elapsed += 0.1
			end
			for player in self.playerDatas do
				self:processPlayerRemove(player)
			end
		end
	)

	Players.PlayerAdded:Connect(
		function(player: Player)
			task.spawn(
				function()
					self:processPlayerAdd(player)
				end
			)
		end
	)

	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:processPlayerRemove(player)
		end
	)

	for _, player in Players:GetPlayers() do
		task.spawn(
			function()
				self:processPlayerAdd(player)
			end
		)
	end
end

function GameController.new(): GameController
	local self = setmetatable({}, GameController) :: GameController
	self.playerStore = nil
	self.playerDatas = {}
	self.pendingExitCount = 0
	self.netManager = NetManager
	self.devTools = DevTools
	self.playerFeedbackManager = PlayerFeedbackManager
	self.splendidReplicationManager = SplendidReplicationManager
	return self
end

local gameController = GameController.new()
gameController:init()

return gameController
