--!strict

-- The record of truth for this gameplay server's run: the join data the lobby
-- sent with the party teleport (map, difficulty, player count, host, member
-- ids), read once from the first arriving player. Clients see map, difficulty,
-- and player count as GameMetadata attributes. A Studio play session has no
-- join data; the run then stays unknown and systems fall back to "everyone
-- here".
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local RunManager = {}
RunManager.__index = RunManager

export type RunManager = typeof(setmetatable(
	{} :: {
		run: PartyRules.JoinData?,
	},
	RunManager
))

function RunManager:getRun(): PartyRules.JoinData?
	return self.run
end

function RunManager:isExpectedMember(userId: number): boolean
	local run = self.run
	return run ~= nil and table.find(run.memberUserIds, userId) ~= nil
end

-- the first valid join data seen defines the run; later arrivals must match it
function RunManager:recordFromPlayer(player: Player)
	if self.run then
		return
	end
	local joinData = player:GetJoinData()
	local teleportData = if joinData then joinData.TeleportData else nil
	local isValid = Validate.isTableShape(teleportData, PartyRules.JOIN_DATA_SHAPE)
	if not isValid then
		return
	end
	local run = teleportData :: PartyRules.JoinData
	self.run = run
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_MAP, run.map)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DIFFICULTY, run.difficulty)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_PLAYER_COUNT, run.playerCount)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_HOST_USER_ID, run.hostUserId)
	print(`[RunManager] run: map {run.map} difficulty {run.difficulty} players {run.playerCount} host {run.hostUserId} pad {run.padIndex}`)
end

function RunManager:init()
end

function RunManager.new(): RunManager
	local self = setmetatable({}, RunManager) :: RunManager
	self.run = nil
	return self
end

return RunManager.new()
