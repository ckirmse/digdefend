--!strict

-- The run record (docs/balance-plan.md, M34, 2026-10-08): at every dawn
-- and at the run's end, the run report's rows are saved as one DataStore
-- entry per run, so the designer's runs and testers' runs alike can be
-- pulled later (scripts/studio/pull_run_records.luau) and averaged against
-- the balance sheet. The pure RunRecordRules builds the record and names
-- nobody in it: players are crew slots, never a UserId or a name, so the
-- store holds no personal data. The record is stamped with the place
-- version and a fingerprint of every GameData table (shared DataHash), so
-- runs on different tuning are never averaged together, and with the
-- count of dev commands used, so a forced night is visible.
--
-- This is the one DataStore writer besides PlayerData (decided
-- 2026-10-08): a separate, write-only store of run telemetry that never
-- touches a player's save. Writes are one SetAsync per dawn (about every
-- six minutes) and one at the end, far under the DataStore budget; a
-- record over MAX_RECORD_BYTES is refused with a warning rather than sent.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local DataHash = require("@game/ReplicatedStorage/Shared/DataHash")
local RunRecordRules = require("@game/ReplicatedStorage/Shared/RunRecordRules")
local RunReportRules = require("@game/ReplicatedStorage/Shared/RunReportRules")
local TelemetryData = require("@game/ServerScriptService/GameData/Control/Telemetry")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local MineManager = require(script.Parent.MineManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunReportManager = require(script.Parent.RunReportManager)

local RunRecordManager = {}
RunRecordManager.__index = RunRecordManager

export type RunRecordManager = typeof(setmetatable(
	{} :: {
		store: DataStore?,
		dataHash: string,
		header: RunRecordRules.Header?,
		key: string?,
		devCommands: number,
		isAdminSeen: boolean,
		-- a write in flight; a dawn that comes while one is running is
		-- skipped, since the next writes everything again
		isWriting: boolean,
		-- the last encoded size, for the dev panel and the Output
		lastBytes: number,
		random: Random,
	},
	RunRecordManager
))

local GAME_DATA_FOLDER = "GameData"

function RunRecordManager:getLastBytes(): number
	return self.lastBytes
end

function RunRecordManager:getDataHash(): string
	return self.dataHash
end

-- every GameData module's table under one fingerprint, by its path under
-- the folder so a renamed file changes it too
function RunRecordManager:computeDataHash(): string
	local folder = script.Parent.Parent:FindFirstChild(GAME_DATA_FOLDER)
	if not folder then
		warn("RunRecordManager: no GameData folder; the run record carries no data hash")
		return "none"
	end
	local tablesByName = {}
	for _, module in folder:GetDescendants() do
		if not module:IsA("ModuleScript") then
			continue
		end
		local isSuccess, result = pcall(require, module)
		if isSuccess then
			tablesByName[module:GetFullName()] = result
		else
			warn("RunRecordManager: GameData module", module:GetFullName(), "could not be required for the data hash:", result)
		end
	end
	return DataHash.hashNamed(tablesByName)
end

function RunRecordManager:isWriteEnabled(): boolean
	if not self.store or not self.header or not self.key then
		return false
	end
	if RunService:IsStudio() and not TelemetryData.IS_STUDIO_WRITE_ENABLED then
		return false
	end
	return true
end

function RunRecordManager:buildRecord(rows: { RunReportRules.DayRow }): RunRecordRules.Record?
	local header = self.header
	if not header then
		return nil
	end
	-- the flag is sticky: an admin who was in the crew at any point
	-- makes it the designer's run
	for _, player in GameController:getReadyPlayers() do
		if GameController:isPlayerAdmin(player) then
			self.isAdminSeen = true
		end
	end
	header.isAdminRun = self.isAdminSeen
	return RunRecordRules.build(header, rows, self.devCommands)
end

-- one SetAsync of the whole record, retried a few times; never blocks the
-- caller, since a dawn must not wait on the DataStore
function RunRecordManager:write(record: RunRecordRules.Record, label: string)
	local store = self.store
	local key = self.key
	if not store or not key or not self:isWriteEnabled() then
		return
	end
	local encoded = HttpService:JSONEncode(record)
	self.lastBytes = #encoded
	if not RunRecordRules.isWithinSize(#encoded, TelemetryData.MAX_RECORD_BYTES) then
		warn(`RunRecordManager: the run record is {#encoded} bytes, over the {TelemetryData.MAX_RECORD_BYTES} cap; not written`)
		return
	end
	if self.isWriting then
		return
	end
	self.isWriting = true
	task.spawn(
		function()
			for attempt = 1, TelemetryData.WRITE_ATTEMPTS do
				local isSuccess, err = pcall(
					function()
						store:SetAsync(key, record)
					end
				)
				if isSuccess then
					print(`[RunRecordManager] {label}: {#encoded} bytes written to {key} (data {record.dataHash}, place v{record.placeVersion})`)
					break
				end
				warn(`RunRecordManager: write {attempt} of {TelemetryData.WRITE_ATTEMPTS} failed: {err}`)
				if attempt < TelemetryData.WRITE_ATTEMPTS then
					task.wait(TelemetryData.WRITE_RETRY_SEC)
				end
			end
			self.isWriting = false
		end
	)
end

function RunRecordManager:onDayStarted(day: number)
	-- the first dawn has nothing closed yet
	if day <= 1 or #RunReportManager:getClosedRows() == 0 then
		return
	end
	local record = self:buildRecord(RunReportManager:getClosedRows())
	if record then
		self:write(record, `day {day - 1} closed`)
	end
end

function RunRecordManager:onRunEnded(isWon: boolean, reason: number)
	local record = self:buildRecord(RunReportManager:getRowsSoFar())
	if not record then
		return
	end
	RunRecordRules.markEnded(record, DateTime.now().UnixTimestamp, isWon, reason)
	self:write(record, if isWon then "run won" else "run lost")
end

function RunRecordManager:onRunStarted(map: number, difficulty: number)
	local startedAt = DateTime.now().UnixTimestamp
	self.header = {
		placeVersion = game.PlaceVersion,
		dataHash = self.dataHash,
		isStudio = RunService:IsStudio(),
		isAdminRun = false,
		map = map,
		difficulty = difficulty,
		mineSeed = MineManager:getSeed() or 0,
		startedAtUnix = startedAt,
	}
	-- Studio has no JobId; a random suffix keeps two Studio runs apart
	self.key = RunRecordRules.key(TelemetryData.RUN_RECORD_KEY_PREFIX, startedAt, game.JobId, string.format("%08x", self.random:NextInteger(0, 0xFFFFFFFF)))
	self.devCommands = 0
	self.isAdminSeen = false
	self.lastBytes = 0
	if self.store then
		print(`[RunRecordManager] run record key {self.key}; GameData hash {self.dataHash}`)
	end
end

function RunRecordManager:init()
	self.dataHash = self:computeDataHash()
	local isSuccess, result = pcall(
		function()
			return DataStoreService:GetDataStore(TelemetryData.RUN_RECORD_STORE_NAME)
		end
	)
	if isSuccess then
		self.store = result
	else
		warn("RunRecordManager: no DataStore access; run records are not saved:", result)
	end
	DevTools:subscribeCommandExecuted(
		function(_command: string)
			self.devCommands += 1
		end
	)
	RunCycleManager:subscribeDayStarted(
		function(day: number, _scalingCount: number)
			self:onDayStarted(day)
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(isWon: boolean, reason: number)
			self:onRunEnded(isWon, reason)
		end
	)
end

function RunRecordManager.new(): RunRecordManager
	local self = setmetatable({}, RunRecordManager) :: RunRecordManager
	self.store = nil
	self.dataHash = "none"
	self.header = nil
	self.key = nil
	self.devCommands = 0
	self.isAdminSeen = false
	self.isWriting = false
	self.lastBytes = 0
	self.random = Random.new()
	return self
end

return RunRecordManager.new()
