--!strict

-- Runs each night's wave (GDD "Creating Waves", "Wave Spawn Locations"),
-- M29. When night falls it takes the wave authored for that night in the
-- map's GameData/Waves file (a night without one replays the latest before
-- it; the generator is M30) and spawns its groups in time order, each
-- SPAWN_TIME_SEC after night fall, scattered within the map's
-- SPAWN_RADIUS_STUDS of its numbered spawn. Whenever every monster is dead
-- and a group is still waiting, every remaining group moves up by the same
-- amount so the next one comes at once (pure WaveRules). Once every group
-- has spawned and the last monster is dead, the night is cleared. A spawn
-- the alive limit refuses waits and is retried, so a big night is never
-- cut short.
local RunService = game:GetService("RunService")

local WaveRules = require("@game/ReplicatedStorage/Shared/WaveRules")
local WaveRegistryData = require("@game/ServerScriptService/GameData/Waves/Registry")
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)

local MonsterWaveManager = {}
MonsterWaveManager.__index = MonsterWaveManager

type PendingSpawn = {
	kind: number,
	position: Vector3,
}

export type MonsterWaveManager = typeof(setmetatable(
	{} :: {
		isActive: boolean,
		groups: { WaveRules.Group },
		nextGroupIndex: number,
		nightStartTime: number,
		shiftSec: number,
		pending: { PendingSpawn },
		random: Random,
	},
	MonsterWaveManager
))

function MonsterWaveManager:getMapWaves(): any?
	local map = RunManager:getMap()
	return if map then (WaveRegistryData :: any)[map] else nil
end

function MonsterWaveManager:isRunning(): boolean
	return self.isActive
end

-- queues every monster of a group, scattered round its spawn
function MonsterWaveManager:queueGroup(group: WaveRules.Group)
	local mapWaves = self:getMapWaves()
	local radius = if mapWaves then mapWaves.SPAWN_RADIUS_STUDS else 0
	local center = MonsterPathManager:getSpawnPosition(group.SPAWN_LOCATION)
	if not center then
		warn(`MonsterWaveManager: the camp has no monster spawn {group.SPAWN_LOCATION}; that group is skipped`)
		return
	end
	for _, kind in WaveRules.groupKinds(group) do
		table.insert(self.pending, {
			kind = kind,
			position = WaveRules.scatter(center, radius, self.random),
		})
	end
end

-- spawns what the alive limit allows, keeping the rest for later
function MonsterWaveManager:spawnPending()
	if #self.pending == 0 then
		return
	end
	local waiting = {}
	for _, spawn in self.pending do
		if #waiting > 0 or not MonsterManager:spawnMonster(spawn.kind, spawn.position) then
			table.insert(waiting, spawn)
		end
	end
	self.pending = waiting
end

-- also used by the dev tool: queues a group now, outside any wave
function MonsterWaveManager:spawnGroupNow(kind: number, count: number, spawnNumber: number)
	self:queueGroup({
		ENEMIES = {
			{
				KIND = kind,
				COUNT = count,
			},
		},
		SPAWN_LOCATION = spawnNumber,
		SPAWN_TIME_SEC = 0,
	})
	self:spawnPending()
end

function MonsterWaveManager:startNight(night: number)
	local mapWaves = self:getMapWaves()
	local wave = if mapWaves then WaveRules.waveForNight(mapWaves.WAVES, night) else nil
	self.isActive = true
	self.groups = if wave then WaveRules.orderedGroups(wave) else {}
	self.nextGroupIndex = 1
	self.nightStartTime = workspace:GetServerTimeNow()
	self.shiftSec = 0
	self.pending = {}
	if not wave then
		warn(`MonsterWaveManager: no wave for night {night} on this map; the night ends when the field is clear`)
	end
	print(`[MonsterWaveManager] night {night}: {#self.groups} group(s)`)
end

function MonsterWaveManager:stop()
	self.isActive = false
	self.groups = {}
	self.pending = {}
end

function MonsterWaveManager:step()
	if not self.isActive then
		return
	end
	local now = workspace:GetServerTimeNow()
	local nextGroup = self.groups[self.nextGroupIndex]
	if nextGroup and #self.pending == 0 and MonsterManager:getAliveCount() == 0 then
		self.shiftSec += WaveRules.shiftForEmptyField(WaveRules.dueTime(nextGroup, self.nightStartTime, self.shiftSec), now)
	end
	while nextGroup and now >= WaveRules.dueTime(nextGroup, self.nightStartTime, self.shiftSec) do
		self:queueGroup(nextGroup)
		self.nextGroupIndex += 1
		nextGroup = self.groups[self.nextGroupIndex]
	end
	self:spawnPending()
	if not nextGroup and #self.pending == 0 and MonsterManager:getAliveCount() == 0 then
		print("[MonsterWaveManager] the wave is beaten")
		self:stop()
		RunCycleManager:clearNight()
	end
end

function MonsterWaveManager:onRunStarted()
	self:stop()
end

function MonsterWaveManager:init()
	RunCycleManager:subscribeNightChanged(
		function(isNight: boolean)
			if isNight then
				self:startNight(RunCycleManager:getDay())
				return
			end
			-- a dawn forced early (the dev tool) sweeps what is left
			self:stop()
			MonsterManager:killAll()
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(_isWon: boolean)
			self:stop()
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function MonsterWaveManager.new(): MonsterWaveManager
	local self = setmetatable({}, MonsterWaveManager) :: MonsterWaveManager
	self.isActive = false
	self.groups = {}
	self.nextGroupIndex = 1
	self.nightStartTime = 0
	self.shiftSec = 0
	self.pending = {}
	self.random = Random.new()
	return self
end

return MonsterWaveManager.new()
