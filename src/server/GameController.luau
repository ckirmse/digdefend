--!strict

-- The single top-level orchestrator: requires every manager, wires them
-- together through init(), owns player join/leave, and assembles the full
-- network protocol in one place so it can be read top to bottom.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DevTools = require(script.Parent.DevTools)
local NetManager = require(script.Parent.NetManager)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local GameController = {}
GameController.__index = GameController

export type GameController = typeof(setmetatable(
	{} :: {
		isAdminByPlayer: { [Player]: boolean },
		netManager: typeof(NetManager),
		devTools: typeof(DevTools),
		playerFeedbackManager: typeof(PlayerFeedbackManager),
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
-- persistent player data (M6), (b) a manager with per-player runtime state, or
-- (c) new per-player replication (M7), you MUST add it to both sequences
-- below, choosing its onReset behavior explicitly.
--
-- Ordered setup sequence for a player reaching Ready; order is load-bearing.
local PLAYER_READY_SEQUENCE: { SequenceEntry } = {}

-- Ordered teardown sequence for a leaving player; order is load-bearing.
-- onReset = false skips the entry during a dev-tool reset.
local PLAYER_TEARDOWN_SEQUENCE: { SequenceEntry } = {}

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

-- Until the player lifecycle lands (M6) every connected player counts as Ready.
function GameController:isPlayerReady(player: Player): boolean
	return player.Parent == Players
end

function GameController:isPlayerAdmin(player: Player): boolean
	return self.isAdminByPlayer[player] == true
end

function GameController:processPlayerAdd(player: Player)
	if self.isAdminByPlayer[player] ~= nil then
		warn("GameController: duplicate PlayerAdded for", player.Name)
		return
	end

	local isAdmin = fetchIsAdmin(player)
	if player.Parent ~= Players then
		return
	end
	self.isAdminByPlayer[player] = isAdmin
	-- the client reads this to decide whether to load the dev tools; the server
	-- re-checks isPlayerAdmin on every command so the attribute is not the gate
	player:SetAttribute(Attributes.IS_ADMIN, isAdmin)

	runReadySequence(player, false)
	print("[GameController] Ready:", player.Name, if isAdmin then "(admin)" else "")
end

function GameController:processPlayerRemove(player: Player)
	if self.isAdminByPlayer[player] == nil then
		return
	end
	runTeardownSequence(player, false)
	self.isAdminByPlayer[player] = nil
	print("[GameController] Gone:", player.Name)
end

-- the reset contract lives on PLAYER_READY_SEQUENCE / PLAYER_TEARDOWN_SEQUENCE
-- (see the DEV TOOL CONTRACT comment above them)
function GameController:resetPlayerState(player: Player)
	if self.isAdminByPlayer[player] == nil then
		warn("GameController: resetPlayerState on unknown player", player.Name)
		return
	end
	print("[GameController] Resetting player state:", player.Name)
	runTeardownSequence(player, true)
	runReadySequence(player, true)
	print("[GameController] Reset complete:", player.Name)
end

function GameController:init()
	self.devTools = DevTools
	DevTools:init(self)

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
	self.isAdminByPlayer = {}
	self.netManager = NetManager
	self.devTools = DevTools
	self.playerFeedbackManager = PlayerFeedbackManager
	return self
end

local gameController = GameController.new()
gameController:init()

return gameController
