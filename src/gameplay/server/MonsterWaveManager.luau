--!strict

-- Runs each night's wave (GDD "Creating Waves", "Wave Spawn Locations"),
-- M29 and M30. When night falls it takes the wave authored for that night
-- in the map's GameData/Waves file, its counts scaled to the crew, or
-- generates one (pure WaveGenerator) from the map's settings for the run's
-- difficulty, the night, and the crew's wave multiplier (PartyScaling,
-- sampled at dawn); the crew's enemy HP multiplier is set on
-- MonsterManager at the same time. It spawns the groups in time order, each
-- SPAWN_TIME_SEC after night fall, scattered within the map's
-- SPAWN_RADIUS_STUDS of its numbered spawn. Whenever every monster is dead
-- and a group is still waiting, every remaining group moves up by the same
-- amount so the next one comes at once (pure WaveRules). Once every group
-- has spawned and the last monster is dead, the night is cleared. A spawn
-- the alive limit refuses waits and is retried, so a big night is never
-- cut short.
local RunService = game:GetService("RunService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local WaveGenerator = require("@game/ReplicatedStorage/Shared/WaveGenerator")
local WaveRules = require("@game/ReplicatedStorage/Shared/WaveRules")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local RosterData = require("@game/ServerScriptService/GameData/Monsters/Roster")
local GenerationData = require("@game/ServerScriptService/GameData/Waves/Generation")
local WaveRegistryData = require("@game/ServerScriptService/GameData/Waves/Registry")
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local RunPauseManager = require(script.Parent.RunPauseManager)

local MonsterWaveManager = {}
MonsterWaveManager.__index = MonsterWaveManager

-- typed once here so every wave read is checked against WaveRules
local WAVES_BY_MAP: { [number]: WaveRules.MapWaves } = WaveRegistryData

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
		-- GameData/Monsters/Roster DIFFICULTY_VALUE by kind, for the generator
		difficultyValueByKind: { [number]: number },
		-- the generator's target for the wave being fought, 0 for an authored one
		targetDifficulty: number,
		-- a group just arrived: which of how many, and the wave's target
		-- (the run report, M34)
		groupQueuedHandlers: { (groupIndex: number, groupCount: number, targetDifficulty: number) -> () },
	},
	MonsterWaveManager
))

function MonsterWaveManager:getMapWaves(): WaveRules.MapWaves?
	local map = RunManager:getMap()
	return if map then WAVES_BY_MAP[map] else nil
end

function MonsterWaveManager:isRunning(): boolean
	return self.isActive
end

function MonsterWaveManager:subscribeGroupQueued(handler: (groupIndex: number, groupCount: number, targetDifficulty: number) -> ())
	table.insert(self.groupQueuedHandlers, handler)
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

-- the night's wave: the authored one scaled to the crew, else generated;
-- nil with the reason when the map has neither
-- `scale` multiplies the wave beyond the crew's multiplier (the final wave)
function MonsterWaveManager:buildWave(night: number, scale: number?): (WaveGenerator.Result?, string?)
	local mapWaves = self:getMapWaves()
	local difficulty = RunManager:getDifficulty()
	if not mapWaves or not difficulty then
		return nil, "no run"
	end
	local crew = RunCycleManager:getScalingCount()
	local crewMultiplier = RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, crew)
	local waveMultiplier = crewMultiplier * (scale or 1)
	local authored = WaveRules.waveForNight(mapWaves.WAVES, night)
	if authored then
		local scaled = WaveRules.scaleWave(authored, waveMultiplier)
		local total = WaveGenerator.waveDifficulty(scaled, self.difficultyValueByKind)
		return {
			wave = scaled,
			targetDifficulty = total,
			totalDifficulty = total,
		}, nil
	end
	local settings = mapWaves.GENERATOR[difficulty]
	if not settings then
		return nil, `no GENERATOR entry for difficulty {Enums.getName(Enums.Difficulty, difficulty)}`
	end
	return WaveGenerator.generate({
		settings = settings,
		tuning = GenerationData,
		night = night,
		difficultyMultiplier = waveMultiplier,
		difficultyValueByKind = self.difficultyValueByKind,
		spawnNumbers = MonsterPathManager:getSpawnNumbers(),
		-- groups grow with the crew instead of multiplying (2026-09-25) and
		-- with the night (2026-10-01); the final wave's extra scale still
		-- adds groups. Late nights also bunch their groups closer
		minGroupDifficulty = WaveRules.minGroupDifficultyFor(mapWaves, night, crewMultiplier),
		spawnWindowSec = mapWaves.WAVE_SPAWN_LENGTH_SEC,
		maxGapSec = WaveRules.maxGapFor(mapWaves, night),
		random = self.random,
	}), nil
end

-- the target for each of the first `nights` nights, so a tuning change
-- can be read as a column of numbers rather than guessed from the formula
function MonsterWaveManager:describeCurve(nights: number): { string }
	local mapWaves = self:getMapWaves()
	local difficulty = RunManager:getDifficulty()
	local settings = if mapWaves and difficulty then mapWaves.GENERATOR[difficulty] else nil
	if not settings then
		return { "No wave settings for this run" }
	end
	local crew = RunCycleManager:getScalingCount()
	local waveMultiplier = RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, crew)
	local lines = {
		string.format("%s, crew of %d (waves %.2fx): start %d, +%d a night, growth %d%%, a group per %d (+%d a night), groups at most %d s apart (-%d s a night, floor %d s)", Enums.getPublicName(Enums.Difficulty, difficulty) or "?", crew, waveMultiplier, settings.STARTING_DIFFICULTY, settings.DIFFICULTY_INCREASE_PER_WAVE, math.round(settings.GROWTH_PER_WAVE * 100), math.round(mapWaves.MIN_GROUP_DIFFICULTY * waveMultiplier), math.round(mapWaves.MIN_GROUP_DIFFICULTY_PER_NIGHT * waveMultiplier), mapWaves.MAX_TIME_BETWEEN_GROUPS_SEC, mapWaves.GROUP_GAP_SHRINK_SEC_PER_NIGHT, mapWaves.MIN_TIME_BETWEEN_GROUPS_SEC),
	}
	for night = 1, nights do
		local target = WaveGenerator.targetDifficulty(settings, night, waveMultiplier)
		local unlocked = WaveGenerator.unlockedKinds(settings, night, self.difficultyValueByKind)
		local newest = unlocked[#unlocked]
		local minGroupDifficulty = WaveRules.minGroupDifficultyFor(mapWaves, night, waveMultiplier)
		local groups = WaveGenerator.groupCount(target, minGroupDifficulty)
		table.insert(lines, string.format("  night %2d: target %4d, %d group(s) of %d+, at most %d s apart, %d kind(s) unlocked, strongest %s", night, math.round(target), groups, math.round(minGroupDifficulty), math.round(WaveRules.maxGapFor(mapWaves, night)), #unlocked, if newest then Enums.getPublicName(Enums.MonsterKind, newest) or "?" else "none"))
	end
	return lines
end

-- the wave in words, for the dev tool and the Output
function MonsterWaveManager:describeWave(result: WaveGenerator.Result): { string }
	return WaveGenerator.describe(
		result,
		self.difficultyValueByKind,
		function(kind: number): string
			return Enums.getPublicName(Enums.MonsterKind, kind) or tostring(kind)
		end
	)
end

function MonsterWaveManager:startNight(night: number)
	local crew = RunCycleManager:getScalingCount()
	MonsterManager:setHpMultiplier(RunCycleRules.multiplierFor(PartyScalingData.ENEMY_HP_MULTIPLIER_BY_PLAYER_COUNT, crew))
	local result, reason = self:buildWave(night)
	self.isActive = true
	self.groups = if result then WaveRules.orderedGroups(result.wave) else {}
	self.targetDifficulty = if result then result.targetDifficulty else 0
	self.nextGroupIndex = 1
	self.nightStartTime = workspace:GetServerTimeNow()
	self.shiftSec = 0
	self.pending = {}
	if not result then
		warn(`MonsterWaveManager: no wave for night {night} ({reason}); the night ends when the field is clear`)
		return
	end
	if #self.groups == 0 then
		warn(`MonsterWaveManager: night {night} generated no groups (nothing unlocked, or no spawns); the night ends when the field is clear`)
	end
	print("[MonsterWaveManager] " .. table.concat(self:describeWave(result), "\n"))
end

-- the rescue's final wave (M31): the next night's wave, scaled up, over
-- the flight in; whatever was alive stays. When it is beaten nothing more
-- comes, and the night is never cleared: the run ends with the helicopter
function MonsterWaveManager:startFinalWave(night: number, scale: number)
	local result, reason = self:buildWave(night, scale)
	self.isActive = true
	self.groups = if result then WaveRules.orderedGroups(result.wave) else {}
	self.targetDifficulty = if result then result.targetDifficulty else 0
	self.nextGroupIndex = 1
	self.nightStartTime = workspace:GetServerTimeNow()
	self.shiftSec = 0
	if not result then
		warn(`MonsterWaveManager: no final wave ({reason})`)
		return
	end
	print("[MonsterWaveManager] final wave, " .. table.concat(self:describeWave(result), "\n"))
end

function MonsterWaveManager:stop()
	self.isActive = false
	self.groups = {}
	self.pending = {}
end

function MonsterWaveManager:step()
	if not self.isActive or RunPauseManager:isPaused() then
		return
	end
	local now = workspace:GetServerTimeNow()
	local nextGroup = self.groups[self.nextGroupIndex]
	if nextGroup and #self.pending == 0 and MonsterManager:getAliveCount() == 0 then
		self.shiftSec += WaveRules.shiftForEmptyField(WaveRules.dueTime(nextGroup, self.nightStartTime, self.shiftSec), now)
	end
	while nextGroup and now >= WaveRules.dueTime(nextGroup, self.nightStartTime, self.shiftSec) do
		self:queueGroup(nextGroup)
		for _, handler in self.groupQueuedHandlers do
			handler(self.nextGroupIndex, #self.groups, self.targetDifficulty)
		end
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
				-- a rescue called by day is a dusk too, but its wave is the final one
				if RunCycleManager:getRunState() ~= Enums.RunState.RESCUE then
					self:startNight(RunCycleManager:getDay())
				end
				return
			end
			-- a dawn forced early (the dev tool) sweeps what is left of the
			-- wave; a lurker in the mine stays
			self:stop()
			MonsterManager:killWave()
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(_isWon: boolean)
			self:stop()
		end
	)
	-- a pause moves the night's spawn schedule on by its length
	RunPauseManager:subscribeResumed(
		function(pausedSec: number)
			self.nightStartTime += pausedSec
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
	self.targetDifficulty = 0
	self.groupQueuedHandlers = {}
	self.difficultyValueByKind = {}
	for kind, data in RosterData.BY_KIND :: { [number]: { DIFFICULTY_VALUE: number } } do
		self.difficultyValueByKind[kind] = data.DIFFICULTY_VALUE
	end
	return self
end

return MonsterWaveManager.new()
