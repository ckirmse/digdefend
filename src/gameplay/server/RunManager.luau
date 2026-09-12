--!strict

-- The record of truth for this gameplay server's run: the join data the lobby
-- sent with the party teleport (map, difficulty, player count, host, member
-- ids), read once from the first arriving player. Clients see map, difficulty,
-- and player count as GameMetadata attributes. A Studio play session has no
-- join data; the run then uses GameData/Run/StudioDefaults and the "start run
-- as" dev tool can switch it. Everything that depends on the map (loading it,
-- placing the helicopter, generating the mine) subscribes to run start and
-- runs in registration order.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local StudioDefaultsData = require("@game/ServerScriptService/GameData/Run/StudioDefaults")
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local RunManager = {}
RunManager.__index = RunManager

export type RunStartedHandler = (map: number, difficulty: number) -> ()

export type RunManager = typeof(setmetatable(
	{} :: {
		run: PartyRules.JoinData?,
		map: number?,
		difficulty: number?,
		runStartedHandlers: { RunStartedHandler },
	},
	RunManager
))

function RunManager:getRun(): PartyRules.JoinData?
	return self.run
end

function RunManager:getMap(): number?
	return self.map
end

function RunManager:getDifficulty(): number?
	return self.difficulty
end

function RunManager:hasStarted(): boolean
	return self.map ~= nil
end

function RunManager:isExpectedMember(userId: number): boolean
	local run = self.run
	return run ~= nil and table.find(run.memberUserIds, userId) ~= nil
end

-- handlers run in registration order every time a run starts, including a
-- dev-tool restart
function RunManager:subscribeRunStarted(handler: RunStartedHandler)
	table.insert(self.runStartedHandlers, handler)
end

function RunManager:startRun(map: number, difficulty: number)
	self.map = map
	self.difficulty = difficulty
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_MAP, map)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DIFFICULTY, difficulty)
	print(`[RunManager] run started: map {Enums.getName(Enums.Map, map)} difficulty {Enums.getName(Enums.Difficulty, difficulty)}`)
	for _, handler in self.runStartedHandlers do
		handler(map, difficulty)
	end
end

-- the first valid join data seen defines the run; later arrivals must match it
function RunManager:recordFromPlayer(player: Player)
	if self:hasStarted() then
		return
	end
	local joinData = player:GetJoinData()
	local teleportData = if joinData then joinData.TeleportData else nil
	local isValid = Validate.isTableShape(teleportData, PartyRules.JOIN_DATA_SHAPE)
	if not isValid then
		if RunService:IsStudio() then
			self:startRun(StudioDefaultsData.MAP, StudioDefaultsData.DIFFICULTY)
		end
		return
	end
	local run = teleportData :: PartyRules.JoinData
	self.run = run
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_PLAYER_COUNT, run.playerCount)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_HOST_USER_ID, run.hostUserId)
	print(`[RunManager] join data: players {run.playerCount} host {run.hostUserId} pad {run.padIndex}`)
	self:startRun(run.map, run.difficulty)
end

-- dev tool: restart the run as another map or difficulty without leaving Play
function RunManager:restartAs(map: number, difficulty: number)
	self:startRun(map, difficulty)
end

function RunManager:init()
end

function RunManager.new(): RunManager
	local self = setmetatable({}, RunManager) :: RunManager
	self.run = nil
	self.map = nil
	self.difficulty = nil
	self.runStartedHandlers = {}
	return self
end

return RunManager.new()
