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
-- The same hold is what a wiped crew gets (M32, ReviveManager): each
-- holder names itself, and the run is paused while any holder holds it.
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
		-- who is holding the run still right now
		holders: { [string]: boolean },
		resumedHandlers: { ResumedHandler },
	},
	RunPauseManager
))

RunPauseManager.DEV_TOOL_HOLDER = "devTool"

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

function RunPauseManager:isHeldBy(holder: string): boolean
	return self.holders[holder] == true
end

-- the run is paused while any holder holds it; the dev tool is the
-- holder when none is named
function RunPauseManager:setPaused(isPaused: boolean, holder: string?)
	local wasPaused = self:isPaused()
	self.holders[holder or RunPauseManager.DEV_TOOL_HOLDER] = if isPaused then true else nil
	isPaused = next(self.holders) ~= nil
	if isPaused == wasPaused then
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
	self.holders = {}
	self.pauseStartTime = 0
	self:replicate()
end

function RunPauseManager:init()
	self:replicate()
end

function RunPauseManager.new(): RunPauseManager
	local self = setmetatable({}, RunPauseManager) :: RunPauseManager
	self.pauseStartTime = 0
	self.holders = {}
	self.resumedHandlers = {}
	return self
end

return RunPauseManager.new()
