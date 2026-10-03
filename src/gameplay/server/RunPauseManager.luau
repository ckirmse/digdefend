--!strict

-- The dev tool's pause (decided 2026-10-02): a full run is long, so a
-- tester who is called away can hold the whole run where it is and come
-- back to it. Every gameplay loop that moves the run along (the day and
-- night clock, the monster engine, the waves, Towers, Traps, status
-- effects, the rescue) asks isPaused at the top of its step and does
-- nothing while it is true; when the pause lifts, the listeners shift
-- their server-time deadlines by how long it lasted, so a day's end or a
-- group's spawn is as far off as it was. The pause start is published as
-- GameMetadata so the clients' clocks hold still too. Players themselves
-- are never frozen: a tester may still walk, mine, and build.
-- This module depends on nothing in gameplay so every loop can read it
-- without a circular require.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local RunPauseManager = {}
RunPauseManager.__index = RunPauseManager

export type ResumedHandler = (pausedSec: number) -> ()

export type RunPauseManager = typeof(setmetatable(
	{} :: {
		-- 0 while the run is running
		pauseStartTime: number,
		resumedHandlers: { ResumedHandler },
	},
	RunPauseManager
))

function RunPauseManager:isPaused(): boolean
	return self.pauseStartTime > 0
end

-- a listener is told how long the pause lasted when it lifts, to move
-- its deadlines by that much
function RunPauseManager:subscribeResumed(handler: ResumedHandler)
	table.insert(self.resumedHandlers, handler)
end

function RunPauseManager:replicate()
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_PAUSE_START_TIME, self.pauseStartTime)
end

function RunPauseManager:setPaused(isPaused: boolean)
	if isPaused == self:isPaused() then
		return
	end
	local now = workspace:GetServerTimeNow()
	if isPaused then
		self.pauseStartTime = now
		self:replicate()
		print("[RunPauseManager] run paused")
		return
	end
	local pausedSec = now - self.pauseStartTime
	self.pauseStartTime = 0
	self:replicate()
	for _, handler in self.resumedHandlers do
		handler(pausedSec)
	end
	print(string.format("[RunPauseManager] run resumed after %.1f s", pausedSec))
end

-- a fresh run is never paused
function RunPauseManager:onRunStarted()
	self.pauseStartTime = 0
	self:replicate()
end

function RunPauseManager:init()
	self:replicate()
end

function RunPauseManager.new(): RunPauseManager
	local self = setmetatable({}, RunPauseManager) :: RunPauseManager
	self.pauseStartTime = 0
	self.resumedHandlers = {}
	return self
end

return RunPauseManager.new()
