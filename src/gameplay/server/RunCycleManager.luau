--!strict

-- The run's day and night loop (GDD "Wave Cycle", "Adjusting for Different
-- Player Counts"), M28. One state machine in Lua: Waiting while the crew
-- lands (the morning look, no clock), then PRE_DAY_SEC after the
-- helicopter leaves (ArrivalManager: everyone Ready, or the timeout) Day
-- 1 begins; Day for DAY_SEC, then Night until the night is cleared (a
-- dev tool, the placeholder length, and from M29 the last enemy dying),
-- then a dawn fade of DAWN_TRANSITION_SEC and the next Day, until the run
-- is Won (M31) or Lost (the Refinery destroyed, or the whole crew dead
-- with nobody revived: ReviveManager, M32, which may also start the
-- current day over for a Team Revive). The
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
local RunPauseManager = require(script.Parent.RunPauseManager)

local RunCycleManager = {}
RunCycleManager.__index = RunCycleManager

export type NightChangedHandler = (isNight: boolean) -> ()
export type DayStartedHandler = (day: number, scalingCount: number) -> ()
export type RunEndedHandler = (isWon: boolean, reason: number) -> ()
export type ScalingCountChangedHandler = (count: number) -> ()

export type RunCycleManager = typeof(setmetatable(
	{} :: {
		runState: number,
		-- the day share the sky holds through a rescue wait, -1 when none
		rescueHeldDayShare: number,
		day: number,
		phaseStartTime: number,
		-- 0 while a night's end is unknown
		phaseEndTime: number,
		scalingCount: number?,
		-- server time day 1 may begin, once the crew has landed; nil until then
		firstDayTime: number?,
		nightChangedHandlers: { NightChangedHandler },
		dayStartedHandlers: { DayStartedHandler },
		runEndedHandlers: { RunEndedHandler },
		scalingCountChangedHandlers: { ScalingCountChangedHandler },
	},
	RunCycleManager
))

local MAX_SCALING_COUNT = #PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT

function RunCycleManager:getRunState(): number
	return self.runState
end

function RunCycleManager:getPhaseEndTime(): number
	return self.phaseEndTime
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

-- the crew size behind every party multiplier just changed (a dawn sample
-- or a player leaving); the refinery republishes the uranium target
function RunCycleManager:subscribeScalingCountChanged(handler: ScalingCountChangedHandler)
	table.insert(self.scalingCountChangedHandlers, handler)
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
-- party, so the Ready count); every dawn and every departure samples the
-- Ready count, capped by the last sample, so it only ever goes down.
-- leavingPlayer is the one on the way out, not always gone from the Ready
-- list yet
function RunCycleManager:sampleScalingCount(leavingPlayer: Player?)
	local run = RunManager:getRun()
	local liveCount = 0
	for _, player in GameController:getReadyPlayers() do
		if player ~= leavingPlayer then
			liveCount += 1
		end
	end
	if self.scalingCount == nil and run and run.playerCount > 0 then
		liveCount = run.playerCount
	end
	local previous = self.scalingCount
	self.scalingCount = RunCycleRules.sampleScalingCount(previous, liveCount, MAX_SCALING_COUNT)
	if self.scalingCount ~= previous then
		self:replicate()
		for _, handler in self.scalingCountChangedHandlers do
			handler(self.scalingCount)
		end
	end
end

-- a crew member leaving mid-run shrinks the crew at once (decided
-- 2026-09-25), so the uranium target drops and the next night is built for
-- who is left; a night already under way keeps its wave. Teardown-sequence
-- entry (registered through GameController:registerPlaceManager)
function RunCycleManager:onPlayerRemoved(player: Player)
	if self.scalingCount == nil then
		return
	end
	if not self:isRunOn() then
		return
	end
	local before = self.scalingCount
	self:sampleScalingCount(player)
	if self.scalingCount ~= before then
		print(`[RunCycleManager] {player.Name} left; crew of {self.scalingCount}`)
	end
end

-- a day after a night starts after the dawn fade, so the morning look is
-- in before the clock runs; day 1 follows the landing wait and starts at once
-- the day's dusk, which grows with the run: the clock's share and the
-- song's lead are the same moment
function RunCycleManager:replicateDusk(day: number)
	local duskSec = RunCycleRules.duskSecForDay(day, RunCycleData.DUSK_START_SEC, RunCycleData.DUSK_STEP_SEC, RunCycleData.DUSK_MAX_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DUSK_SHARE, duskSec / RunCycleData.DAY_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DUSK_SONG_LEAD_SEC, duskSec)
end

function RunCycleManager:startDay()
	self:beginDay(self.day + 1)
end

-- the Team Revive (M32): the same day number begins again from dawn, from
-- a day, a night, or the rescue, so the same night comes a second time
function RunCycleManager:restartDay()
	if not self:isRunOn() then
		return
	end
	print(`[RunCycleManager] day {self.day} starts over`)
	self:beginDay(math.max(self.day, 1))
end

function RunCycleManager:beginDay(day: number)
	local now = workspace:GetServerTimeNow()
	local wasNight = self.runState == Enums.RunState.NIGHT
		or self.runState == Enums.RunState.RESCUE
		or (self.runState == Enums.RunState.RESCUE_WAIT and self.rescueHeldDayShare < 0)
	self.day = day
	self.runState = Enums.RunState.DAY
	self:setRescueHeldDayShare(-1)
	self.phaseStartTime = if wasNight then now + RunCycleData.LIGHTING_DAWN_TRANSITION_SEC else now
	self.phaseEndTime = self.phaseStartTime + RunCycleData.DAY_SEC
	self:sampleScalingCount()
	self:replicateDusk(self.day)
	self:replicate()
	local count = self:getScalingCount()
	local message = RunCycleRules.dayStartMessage(
		RunCycleData.DAY_START_FORMAT,
		self.day,
		count,
		RunCycleRules.multiplierFor(PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT, count),
		RunCycleRules.multiplierFor(PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT, count),
		RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, count)
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

-- the share of the day the sky holds through the rescue wait; -1 is none
-- (the call came at night, or no wait is on)
function RunCycleManager:setRescueHeldDayShare(share: number)
	self.rescueHeldDayShare = share
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_RESCUE_HELD_DAY_SHARE, share)
end

-- the rescue is called (M31, the wait added 2026-10-07): the clock stops
-- where it is and the run holds in Rescue Wait until the final wave is
-- due (the phase end), the sky standing where the day was, or night going
-- on if it was night
function RunCycleManager:startRescueWait(waveStartTime: number)
	local state = self.runState
	if state ~= Enums.RunState.DAY and state ~= Enums.RunState.NIGHT then
		return
	end
	local now = workspace:GetServerTimeNow()
	local heldShare = if state == Enums.RunState.DAY then RunCycleRules.dayShareLeft(self.phaseStartTime, self.phaseEndTime, now) else -1
	self:setRescueHeldDayShare(heldShare)
	self.runState = Enums.RunState.RESCUE_WAIT
	self.phaseStartTime = now
	self.phaseEndTime = waveStartTime
	self:replicate()
	print("[RunCycleManager] the rescue is called; the final wave is due in " .. string.format("%.0f", waveStartTime - now) .. " s")
end

-- the final wave is here: the run holds in its Rescue state until the
-- helicopter leaves. From a day (or a wait that began by day) this is a
-- dusk (the gate shuts, the night look comes in); from a night the night
-- simply goes on. The phase end is the landing time, so every clock
-- counts down to it
function RunCycleManager:startRescue(landingTime: number)
	local state = self.runState
	if state ~= Enums.RunState.DAY and state ~= Enums.RunState.NIGHT and state ~= Enums.RunState.RESCUE_WAIT then
		return
	end
	local wasDay = state == Enums.RunState.DAY or (state == Enums.RunState.RESCUE_WAIT and self.rescueHeldDayShare >= 0)
	self:setRescueHeldDayShare(-1)
	self.runState = Enums.RunState.RESCUE
	self.phaseStartTime = workspace:GetServerTimeNow()
	self.phaseEndTime = landingTime
	self:replicate()
	print("[RunCycleManager] the final wave arrives")
	if wasDay then
		self:fireNightChanged(true)
		NetManager:notifyAllClients(NetEventNames.NOTIFY_RUN_NIGHT_STARTED, {
			day = self.day,
		})
	end
end

-- the helicopter has landed: the phase end becomes the boarding deadline
function RunCycleManager:setRescueEnd(endTime: number)
	if self.runState ~= Enums.RunState.RESCUE then
		return
	end
	self.phaseEndTime = endTime
	self:replicate()
end

-- the night is over (the last enemy died at M29; a dev tool or the
-- placeholder length until then): dawn
function RunCycleManager:clearNight()
	if self.runState ~= Enums.RunState.NIGHT then
		return
	end
	self:startDay()
end

-- a dev tool's switch: the coming night is night `day`; only by day
function RunCycleManager:setDay(day: number)
	if self.runState ~= Enums.RunState.DAY then
		return
	end
	self.day = math.max(1, math.floor(day))
	self:replicate()
	print(`[RunCycleManager] day set to {self.day}`)
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

function RunCycleManager:endRun(isWon: boolean, message: string, reason: number)
	if RunCycleRules.isRunOver(self.runState) then
		return
	end
	-- before the state, so a client that sees the run end already knows why
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_END_REASON, reason)
	self.runState = if isWon then Enums.RunState.WON else Enums.RunState.LOST
	self.phaseStartTime = workspace:GetServerTimeNow()
	self.phaseEndTime = 0
	self:replicate()
	print(`[RunCycleManager] run over: {message}`)
	for _, handler in self.runEndedHandlers do
		handler(isWon, reason)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RUN_ENDED, {
		isWon = isWon,
		message = message,
		displaySec = RunCycleData.LOST_DISPLAY_SEC,
	})
end

function RunCycleManager:loseRefinery()
	self:endRun(false, RunCycleData.LOST_REFINERY_MESSAGE, Enums.RunEndReason.REFINERY_DESTROYED)
end

-- the whole crew dead and nobody revived in time (ReviveManager, M32)
function RunCycleManager:loseAllDead()
	self:endRun(false, RunCycleData.LOST_ALL_DEAD_MESSAGE, Enums.RunEndReason.CREW_DEAD)
end

-- a day, a night, or the rescue (its wait included): the states a player
-- can die and be revived in
function RunCycleManager:isRunOn(): boolean
	local state = self.runState
	return state == Enums.RunState.DAY
		or state == Enums.RunState.NIGHT
		or state == Enums.RunState.RESCUE
		or state == Enums.RunState.RESCUE_WAIT
end

function RunCycleManager:step()
	if RunCycleRules.isRunOver(self.runState) or RunPauseManager:isPaused() then
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
end

-- a run (or a dev-tool restart) begins waiting for the crew to land, in
-- the morning look with the clock still; day 1 is PRE_DAY_SEC after the
-- helicopter leaves
function RunCycleManager:onRunStarted()
	self.day = 0
	self.scalingCount = nil
	self.firstDayTime = nil
	self.runState = Enums.RunState.WAITING
	self.rescueHeldDayShare = -1
	local now = workspace:GetServerTimeNow()
	self.phaseStartTime = now
	self.phaseEndTime = 0
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_END_REASON, 0)
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

-- the dev tool's pause lifted: every deadline moves on by the pause, so
-- the day ends as far off as it was and the clients' clocks pick up
-- where they held
function RunCycleManager:onResumed(pausedSec: number)
	self.phaseStartTime += pausedSec
	if self.phaseEndTime > 0 then
		self.phaseEndTime += pausedSec
	end
	if self.firstDayTime then
		self.firstDayTime += pausedSec
	end
	self:replicate()
end

function RunCycleManager:init()
	RunPauseManager:subscribeResumed(
		function(pausedSec: number)
			self:onResumed(pausedSec)
		end
	)
	self:replicateDusk(1)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DUSK_SONG_FADE_SEC, RunCycleData.DUSK_SONG_FADE_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_DUSK_SONG_FADE_LEAD_SEC, RunCycleData.DUSK_SONG_FADE_LEAD_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_NIGHT_SPAWN_SEC, RunCycleData.NIGHT_SPAWN_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_LIGHTING_DUSK_TRANSITION_SEC, RunCycleData.LIGHTING_DUSK_TRANSITION_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_LIGHTING_DAWN_TRANSITION_SEC, RunCycleData.LIGHTING_DAWN_TRANSITION_SEC)
	self:replicate()
	GameController:registerPlaceManager(self)
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
	self.rescueHeldDayShare = -1
	self.day = 0
	self.phaseStartTime = 0
	self.phaseEndTime = 0
	self.scalingCount = nil
	self.firstDayTime = nil
	self.nightChangedHandlers = {}
	self.dayStartedHandlers = {}
	self.runEndedHandlers = {}
	self.scalingCountChangedHandlers = {}
	return self
end

return RunCycleManager.new()
