--!strict

-- The run report (docs/balance-plan.md, M34): a dev tool that writes to
-- the server Output what every player did each day and how each night
-- went, so the balance model's assumptions can be calibrated against real
-- play instead of memory. It listens to the managers that own the events
-- (the Refinery's payouts, the Defense Table's spend, the Hammer's
-- repairs, the structures' damage, the monsters' deaths, the run's dawns
-- and nights) and keeps one row per day in Lua; the pure RunReportRules
-- holds the shapes and prints them. At every dawn the day just closed is
-- printed, and at the run's end (or on the dev panel's button) the whole
-- run with totals. Nothing here decides anything.
local Players = game:GetService("Players")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local RunReportRules = require("@game/ReplicatedStorage/Shared/RunReportRules")
local MonsterManager = require(script.Parent.MonsterManager)
local PlacementManager = require(script.Parent.PlacementManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunStatsManager = require(script.Parent.RunStatsManager)
local StructureManager = require(script.Parent.StructureManager)

local RunReportManager = {}
RunReportManager.__index = RunReportManager

-- the per-player numbers RunStatsManager already keeps for the whole run;
-- the report takes each day's share as the difference since the last dawn
type StatsSnapshot = {
	enemiesKilled: number,
	damageGiven: number,
	diamondsEarned: number,
}

export type RunReportManager = typeof(setmetatable(
	{} :: {
		report: RunReportRules.Report,
		-- the row being filled: today, closed at the next dawn
		current: RunReportRules.DayRow?,
		nightStartTime: number?,
		lastCreditTimeByPlayer: { [Player]: number },
		snapshotByPlayer: { [Player]: StatsSnapshot },
	},
	RunReportManager
))

local DAWN_TITLE_FORMAT = "[RunReport] day %d closed"
local RUN_END_FORMAT = "[RunReport] run %s after %d day(s)"
local ON_DEMAND_TITLE = "[RunReport] so far"

function RunReportManager:getCurrent(): RunReportRules.DayRow
	local current = self.current
	if not current then
		current = RunReportRules.newDayRow(RunCycleManager:getDay(), RunCycleManager:getScalingCount())
		self.current = current
	end
	return current
end

function RunReportManager:playerDay(player: Player): RunReportRules.PlayerDay
	return RunReportRules.playerDay(self:getCurrent(), player.UserId, player.Name)
end

function RunReportManager:snapshot(player: Player): StatsSnapshot
	local stats = RunStatsManager:getStats(player)
	return {
		enemiesKilled = if stats then stats.enemiesKilled else 0,
		damageGiven = if stats then stats.damageGiven else 0,
		diamondsEarned = if stats then stats.diamondsEarned else 0,
	}
end

-- the day's share of the run-long counters, then a fresh baseline; and
-- what every player holds as the day closes, so each one gets a line
function RunReportManager:takeStatDeltas(row: RunReportRules.DayRow)
	for _, player in Players:GetPlayers() do
		local before = self.snapshotByPlayer[player] or { enemiesKilled = 0, damageGiven = 0, diamondsEarned = 0 }
		local now = self:snapshot(player)
		local entry = RunReportRules.playerDay(row, player.UserId, player.Name)
		entry.enemiesKilled += now.enemiesKilled - before.enemiesKilled
		entry.damageGiven += now.damageGiven - before.damageGiven
		entry.diamondsEarned += now.diamondsEarned - before.diamondsEarned
		entry.goldHeld = RefineryManager:getGoldBars(player)
		entry.ironHeld = RefineryManager:getIronBars(player)
		self.snapshotByPlayer[player] = now
	end
end

function RunReportManager:onCredited(player: Player, refined: { [number]: number })
	local entry = self:playerDay(player)
	entry.ironRefined += refined[Enums.RefinedResource.IRON_BAR] or 0
	entry.goldRefined += refined[Enums.RefinedResource.GOLD_BAR] or 0
	entry.uraniumRefined += refined[Enums.RefinedResource.URANIUM] or 0
	entry.trips += 1
	local now = workspace:GetServerTimeNow()
	local last = self.lastCreditTimeByPlayer[player]
	if last then
		entry.tripSecTotal += now - last
	end
	self.lastCreditTimeByPlayer[player] = now
end

function RunReportManager:onPlacementSpent(player: Player, action: number, placementKind: number, iron: number)
	local entry = self:playerDay(player)
	if action == Enums.PlacementAction.BUILT then
		entry.towersBuilt += 1
		entry.placementIronSpent += iron
	elseif action == Enums.PlacementAction.UPGRADED then
		entry.towersUpgraded += 1
		entry.placementIronSpent += iron
	elseif action == Enums.PlacementAction.SOLD then
		entry.placementIronSpent -= iron
	end
end

function RunReportManager:onStructureDamaged(kind: number, amount: number, isDestroyed: boolean)
	local row = self:getCurrent()
	if kind == Enums.StructureKind.REFINERY then
		row.refineryDamage += amount
	else
		row.wallDamage += amount
		if isDestroyed then
			row.wallsLost += 1
		end
	end
end

function RunReportManager:onStructureRepaired(player: Player, gained: number, cost: number)
	local entry = self:playerDay(player)
	entry.repairHp += gained
	entry.repairIron += cost
end

function RunReportManager:onMonsterKilled()
	self:getCurrent().nightKills += 1
end

function RunReportManager:onNightChanged(isNight: boolean)
	if isNight then
		self.nightStartTime = workspace:GetServerTimeNow()
		return
	end
	local startTime = self.nightStartTime
	local current = self.current
	if startTime and current then
		current.nightSec = workspace:GetServerTimeNow() - startTime
	end
	self.nightStartTime = nil
end

-- a dawn closes the day before it: its share of the run counters is
-- taken, it is printed, and a new row opens for the day that begins
function RunReportManager:onDayStarted(day: number, scalingCount: number)
	local current = self.current
	if current and current.day ~= day then
		self:takeStatDeltas(current)
		table.insert(self.report.rows, current)
		self:printLines({ string.format(DAWN_TITLE_FORMAT, current.day) }, RunReportRules.formatDay(current))
		-- a trip that spans a night is not a trip
		self.lastCreditTimeByPlayer = {}
	end
	if not current or current.day ~= day then
		self.current = RunReportRules.newDayRow(day, scalingCount)
	end
end

function RunReportManager:onRunEnded(isWon: boolean)
	local current = self.current
	if current then
		self:takeStatDeltas(current)
		table.insert(self.report.rows, current)
		self.current = nil
	end
	self:printLines({}, RunReportRules.formatReport(self.report, string.format(RUN_END_FORMAT, if isWon then "won" else "lost", #self.report.rows)))
end

-- the dev panel's button: everything so far, today included
function RunReportManager:printNow()
	local rows = table.clone(self.report.rows)
	local current = self.current
	if current then
		self:takeStatDeltas(current)
		table.insert(rows, current)
	end
	self:printLines({}, RunReportRules.formatReport({ rows = rows }, ON_DEMAND_TITLE))
end

function RunReportManager:printLines(head: { string }, lines: { string })
	for _, line in head do
		print(line)
	end
	for _, line in lines do
		print(line)
	end
end

function RunReportManager:onRunStarted()
	self.report = { rows = {} }
	self.current = nil
	self.nightStartTime = nil
	self.lastCreditTimeByPlayer = {}
	self.snapshotByPlayer = {}
end

function RunReportManager:init()
	RefineryManager:subscribeCredited(
		function(player: Player, refined: { [number]: number })
			self:onCredited(player, refined)
		end
	)
	PlacementManager:subscribePlacementSpent(
		function(player: Player, action: number, placementKind: number, _typeKind: number, iron: number)
			self:onPlacementSpent(player, action, placementKind, iron)
		end
	)
	StructureManager:subscribeStructureDamaged(
		function(_id: string, kind: number, amount: number, isDestroyed: boolean)
			self:onStructureDamaged(kind, amount, isDestroyed)
		end
	)
	StructureManager:subscribeStructureRepaired(
		function(player: Player, _id: string, gained: number, cost: number)
			self:onStructureRepaired(player, gained, cost)
		end
	)
	MonsterManager:subscribeKilled(
		function(_kind: number)
			self:onMonsterKilled()
		end
	)
	RunCycleManager:subscribeNightChanged(
		function(isNight: boolean)
			self:onNightChanged(isNight)
		end
	)
	RunCycleManager:subscribeDayStarted(
		function(day: number, scalingCount: number)
			self:onDayStarted(day, scalingCount)
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(isWon: boolean, _reason: number)
			self:onRunEnded(isWon)
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.lastCreditTimeByPlayer[player] = nil
			self.snapshotByPlayer[player] = nil
		end
	)
end

function RunReportManager.new(): RunReportManager
	local self = setmetatable({}, RunReportManager) :: RunReportManager
	self.report = { rows = {} }
	self.current = nil
	self.nightStartTime = nil
	self.lastCreditTimeByPlayer = {}
	self.snapshotByPlayer = {}
	return self
end

return RunReportManager.new()
