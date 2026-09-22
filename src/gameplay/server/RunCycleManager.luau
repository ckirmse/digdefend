--!strict

-- The run's day and night loop (GDD "Wave Cycle", "Adjusting for Different
-- Player Counts"), M28. One state machine in Lua: Waiting while the crew
-- lands (the morning look, no clock), then PRE_DAY_SEC after the
-- helicopter leaves (ArrivalManager: everyone Ready, or the timeout) Day
-- 1 begins; Day for DAY_SEC, then Night until the night is cleared (a
-- dev tool, the placeholder length, and from M29 the last enemy dying),
-- then a dawn fade of DAWN_TRANSITION_SEC and the next Day, until the run
-- is Won (M31) or Lost (the Refinery destroyed, or every player down). The
-- state, the day number, when the phase began and ends, and the crew
-- size the run is scaled by are GameMetadata attributes, so every client
-- draws the same clock from server time. The crew size is sampled once at
-- run start (the party that boarded) and again at every dawn, and only
-- ever goes down (RunCycleRules); ore yield and the uranium target read
-- it here. Other managers subscribe: StructureManager shuts the gate on
-- night changes, and its Refinery-destroyed signal is wired to loseRefinery
-- in main.server. The day-start line and the loss go to the announcement
-- box through notifies.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local RunCycleData = require("@game/ServerScriptService/GameData/Control/RunCycle")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local ArrivalManager = require(script.Parent.ArrivalManager)
local RunManager = require(script.Parent.RunManager)

local RunCycleManager = {}
RunCycleManager.__index = RunCycleManager

export type NightChangedHandler = (isNight: boolean) -> ()
export type DayStartedHandler = (day: number, scalingCount: number) -> ()
export type RunEndedHandler = (isWon: boolean) -> ()

export type RunCycleManager = typeof(setmetatable(
	{} :: {
		runState: number,
		day: number,
		phaseStartTime: number,
		-- 0 while a night's end is unknown
		phaseEndTime: number,
		scalingCount: number?,
		-- server time day 1 may begin, once the crew has landed; nil until then
		firstDayTime: number?,
		lastDeathCheckTime: number,
		nightChangedHandlers: { NightChangedHandler },
		dayStartedHandlers: { DayStartedHandler },
		runEndedHandlers: { RunEndedHandler },
	},
	RunCycleManager
))

-- everyone down is checked this often, not every frame
local DEATH_CHECK_INTERVAL_SEC = 1
local MAX_SCALING_COUNT = #PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT

function RunCycleManager:getRunState(): number
	return self.runState
end

function RunCycleManager:getDay(): number
	return self.day
end

function RunCycleManager:isNight(): boolean
	return self.runState == Enums.RunState.NIGHT
end

-- the one crew size everything scales by; 1 before the run starts
function RunCycleManager:getScalingCount(): number
	return self.scalingCount or 1
end

function RunCycleManager:subscribeNightChanged(handler: NightChangedHandler)
	table.insert(self.nightChangedHandlers, handler)
end

function RunCycleManager:subscribeDayStarted(handler: DayStartedHandler)
	table.insert(self.dayStartedHandlers, handler)
end

function RunCycleManager:subscribeRunEnded(handler: RunEndedHandler)
	table.insert(self.runEndedHandlers, handler)
end

function RunCycleManager:replicate()
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_STATE, self.runState)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DAY, self.day)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_PHASE_START_TIME, self.phaseStartTime)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_PHASE_END_TIME, self.phaseEndTime)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_SCALING_COUNT, self:getScalingCount())
end

function RunCycleManager:fireNightChanged(isNight: boolean)
	for _, handler in self.nightChangedHandlers do
		handler(isNight)
	end
end

-- the crew size at run start is the party that boarded (Studio has no
-- party, so the Ready count); every dawn samples the Ready count, capped
-- by the last sample
function RunCycleManager:sampleScalingCount()
	local run = RunManager:getRun()
	local liveCount = #GameController:getReadyPlayers()
	if self.scalingCount == nil and run and run.playerCount > 0 then
		liveCount = run.playerCount
	end
	self.scalingCount = RunCycleRules.sampleScalingCount(self.scalingCount, liveCount, MAX_SCALING_COUNT)
end

-- a day after a night starts after the dawn fade, so the morning look is
-- in before the clock runs; day 1 follows the landing wait and starts at once
function RunCycleManager:startDay()
	local now = workspace:GetServerTimeNow()
	local wasNight = self.runState == Enums.RunState.NIGHT
	self.day += 1
	self.runState = Enums.RunState.DAY
	self.phaseStartTime = if wasNight then now + RunCycleData.LIGHTING_DAWN_TRANSITION_SEC else now
	self.phaseEndTime = self.phaseStartTime + RunCycleData.DAY_SEC
	self:sampleScalingCount()
	self:replicate()
	local count = self:getScalingCount()
	local message = RunCycleRules.dayStartMessage(
		RunCycleData.DAY_START_FORMAT,
		self.day,
		count,
		RunCycleRules.multiplierFor(PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT, count),
		RunCycleRules.multiplierFor(PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT, count)
	)
	print(`[RunCycleManager] {message}`)
	if wasNight then
		self:fireNightChanged(false)
	end
	for _, handler in self.dayStartedHandlers do
		handler(self.day, count)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RUN_DAY_STARTED, {
		day = self.day,
		message = message,
		displaySec = RunCycleData.DAY_START_DISPLAY_SEC,
	})
end

function RunCycleManager:startNight()
	local now = workspace:GetServerTimeNow()
	self.runState = Enums.RunState.NIGHT
	self.phaseStartTime = now
	self.phaseEndTime = 0
	self:replicate()
	print(`[RunCycleManager] night {self.day} falls`)
	self:fireNightChanged(true)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RUN_NIGHT_STARTED, {
		day = self.day,
	})
end

-- the night is over (the last enemy died at M29; a dev tool or the
-- placeholder length until then): dawn
function RunCycleManager:clearNight()
	if self.runState ~= Enums.RunState.NIGHT then
		return
	end
	self:startDay()
end

-- a dev tool's switch: dusk soon (the rest of the day runs down over
-- FORCED_DUSK_SEC so the sky blends rather than snaps), or dawn now
function RunCycleManager:forceNight(isNight: boolean)
	if RunCycleRules.isRunOver(self.runState) then
		return
	end
	if isNight and self.runState == Enums.RunState.DAY then
		local now = workspace:GetServerTimeNow()
		local endTime = now + RunCycleData.FORCED_DUSK_SEC
		if endTime < self.phaseEndTime then
			-- keep the bar's slope: the day is rescaled to end at endTime
			local shareLeft = RunCycleRules.dayShareLeft(self.phaseStartTime, self.phaseEndTime, now)
			self.phaseStartTime = if shareLeft > 0 then endTime - RunCycleData.FORCED_DUSK_SEC / shareLeft else now
			self.phaseEndTime = endTime
			self:replicate()
		end
	elseif not isNight and self.runState == Enums.RunState.NIGHT then
		self:startDay()
	end
end

function RunCycleManager:endRun(isWon: boolean, message: string)
	if RunCycleRules.isRunOver(self.runState) then
		return
	end
	self.runState = if isWon then Enums.RunState.WON else Enums.RunState.LOST
	self.phaseStartTime = workspace:GetServerTimeNow()
	self.phaseEndTime = 0
	self:replicate()
	print(`[RunCycleManager] run over: {message}`)
	for _, handler in self.runEndedHandlers do
		handler(isWon)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RUN_ENDED, {
		isWon = isWon,
		message = message,
		displaySec = RunCycleData.LOST_DISPLAY_SEC,
	})
end

function RunCycleManager:loseRefinery()
	self:endRun(false, RunCycleData.LOST_REFINERY_MESSAGE)
end

-- every Ready player's character down at once loses the run; nobody
-- Ready yet (the crew still landing) is not a loss
function RunCycleManager:isEveryoneDown(): boolean
	local readyPlayers = GameController:getReadyPlayers()
	if #readyPlayers == 0 then
		return false
	end
	for _, player in readyPlayers do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			return false
		end
	end
	return true
end

function RunCycleManager:step()
	if RunCycleRules.isRunOver(self.runState) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if self.runState == Enums.RunState.WAITING then
		if self.firstDayTime and now >= self.firstDayTime then
			self:startDay()
		end
		return
	end
	if self.runState == Enums.RunState.DAY and now >= self.phaseEndTime then
		self:startNight()
	elseif self.runState == Enums.RunState.NIGHT and RunCycleRules.isNightOver(self.phaseStartTime, now, RunCycleData.NIGHT_SPAWN_SEC, RunCycleData.NIGHT_PLACEHOLDER_SEC) then
		self:startDay()
	end
	if now - self.lastDeathCheckTime >= DEATH_CHECK_INTERVAL_SEC then
		self.lastDeathCheckTime = now
		if self:isEveryoneDown() then
			self:endRun(false, RunCycleData.LOST_ALL_DEAD_MESSAGE)
		end
	end
end

-- a run (or a dev-tool restart) begins waiting for the crew to land, in
-- the morning look with the clock still; day 1 is PRE_DAY_SEC after the
-- helicopter leaves
function RunCycleManager:onRunStarted()
	self.day = 0
	self.scalingCount = nil
	self.firstDayTime = nil
	self.runState = Enums.RunState.WAITING
	local now = workspace:GetServerTimeNow()
	self.phaseStartTime = now
	self.phaseEndTime = 0
	self:replicate()
	print("[RunCycleManager] waiting for the crew to land")
end

function RunCycleManager:onCrewLanded()
	if self.runState ~= Enums.RunState.WAITING or self.firstDayTime then
		return
	end
	self.firstDayTime = workspace:GetServerTimeNow() + RunCycleData.PRE_DAY_SEC
	print(`[RunCycleManager] crew landed; day 1 in {RunCycleData.PRE_DAY_SEC} s`)
end

function RunCycleManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DUSK_SHARE, RunCycleData.DUSK_SHARE)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_NIGHT_SPAWN_SEC, RunCycleData.NIGHT_SPAWN_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_LIGHTING_DUSK_TRANSITION_SEC, RunCycleData.LIGHTING_DUSK_TRANSITION_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_LIGHTING_DAWN_TRANSITION_SEC, RunCycleData.LIGHTING_DAWN_TRANSITION_SEC)
	self:replicate()
	ArrivalManager:subscribeLaunched(
		function()
			self:onCrewLanded()
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function RunCycleManager.new(): RunCycleManager
	local self = setmetatable({}, RunCycleManager) :: RunCycleManager
	self.runState = Enums.RunState.WAITING
	self.day = 0
	self.phaseStartTime = 0
	self.phaseEndTime = 0
	self.scalingCount = nil
	self.firstDayTime = nil
	self.lastDeathCheckTime = 0
	self.nightChangedHandlers = {}
	self.dayStartedHandlers = {}
	self.runEndedHandlers = {}
	return self
end

return RunCycleManager.new()
