--!strict

-- The run report (docs/balance-plan.md, M34): a dev tool that writes to
-- the server Output what every player did each day and how each night
-- went, so the balance model's assumptions can be calibrated against real
-- play instead of memory. It listens to the managers that own the events
-- (the Refinery's payouts and spends, the Defense Table's spend, the
-- Hammer's repairs, the structures' and placements' damage, the pick axe's
-- swings, the monsters' deaths and the players', the wave's groups, the
-- run's dawns and nights) and keeps one row per day in Lua; the pure
-- RunReportRules holds the shapes and prints them. Where each player stood
-- is sampled every few seconds (the mine, a post, or camp). At every dawn
-- the day just closed is printed, and at the run's end (or on the dev
-- panel's button) the whole run with totals. Nothing here decides anything.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local RunReportRules = require("@game/ReplicatedStorage/Shared/RunReportRules")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local GameController = require(script.Parent.Parent.Server.GameController)
local MineManager = require(script.Parent.MineManager)
local MiningManager = require(script.Parent.MiningManager)
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterWaveManager = require(script.Parent.MonsterWaveManager)
local PlacementManager = require(script.Parent.PlacementManager)
local PostManager = require(script.Parent.PostManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)
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
		-- when the wave's last group arrived, for the clear time after it
		lastGroupQueuedTime: number?,
		lastCreditTimeByPlayer: { [Player]: number },
		snapshotByPlayer: { [Player]: StatsSnapshot },
		sampleAccumulatorSec: number,
	},
	RunReportManager
))

local DAWN_TITLE_FORMAT = "[RunReport] day %d closed"
local RUN_END_FORMAT = "[RunReport] run %s after %d day(s)"
local ON_DEMAND_TITLE = "[RunReport] so far"
-- how often each player's whereabouts are sampled; coarse is fine for a
-- share of a 320 s day
local SAMPLE_SEC = 2

local function monsterKindName(kind: number): string
	return Enums.getPublicName(Enums.MonsterKind, kind) or tostring(kind)
end

-- the closed rows and today's, for the run record; today's balances are
-- refreshed first so a record saved mid-day is not a day behind
function RunReportManager:getRowsSoFar(): { RunReportRules.DayRow }
	local rows = table.clone(self.report.rows)
	local current = self.current
	if current then
		self:takeStatDeltas(current)
		table.insert(rows, current)
	end
	return rows
end

function RunReportManager:getClosedRows(): { RunReportRules.DayRow }
	return self.report.rows
end

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

-- a spend the caller named is a purchase; the unnamed ones (repairs, the
-- Defense Table) already have their own columns
function RunReportManager:onSpent(player: Player, resource: number, amount: number, reason: string?)
	if not reason then
		return
	end
	local gold = if resource == Enums.RefinedResource.GOLD_BAR then amount else 0
	local iron = if resource == Enums.RefinedResource.IRON_BAR then amount else 0
	RunReportRules.recordPurchase(self:playerDay(player), reason, gold, iron)
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

function RunReportManager:onStructureDamaged(id: string, kind: number, amount: number, isDestroyed: boolean, attackerKind: number?)
	local row = self:getCurrent()
	if kind == Enums.StructureKind.REFINERY then
		row.refineryDamage += amount
	else
		row.wallDamage += amount
		if isDestroyed then
			row.wallsLost += 1
		end
	end
	RunReportRules.recordStructureDamage(row, id, amount, attackerKind)
end

function RunReportManager:onPlacementDamaged(isDestroyed: boolean)
	if isDestroyed then
		self:getCurrent().placementsLost += 1
	end
end

function RunReportManager:onStructureRepaired(player: Player, gained: number, cost: number)
	local entry = self:playerDay(player)
	entry.repairHp += gained
	entry.repairIron += cost
end

-- a swing that landed: stone or which ore, broken or not, and how deep
function RunReportManager:onRockHit(player: Player, depth: number, rock: number, isBroken: boolean)
	local definition = RockDefinitionsData.ROCKS[rock]
	local kindKey = if definition and definition.resource then definition.resource else RunReportRules.STONE_KEY
	RunReportRules.recordSwing(self:playerDay(player), kindKey, isBroken, depth, MineManager:getZoneIndexAt(depth) or 0)
end

function RunReportManager:onPlayerDamaged(player: Player, amount: number)
	self:playerDay(player).damageTaken += amount
end

function RunReportManager:onPlayerDied(player: Player)
	self:playerDay(player).deaths += 1
end

function RunReportManager:onPlayerRevived(player: Player)
	self:playerDay(player).revives += 1
end

function RunReportManager:onMonsterKilled()
	self:getCurrent().nightKills += 1
end

function RunReportManager:onGroupQueued(groupIndex: number, groupCount: number, targetDifficulty: number)
	local row = self:getCurrent()
	row.nightGroups = math.max(row.nightGroups, groupIndex, groupCount)
	row.nightTargetDifficulty = targetDifficulty
	self.lastGroupQueuedTime = workspace:GetServerTimeNow()
end

function RunReportManager:onNightChanged(isNight: boolean)
	if isNight then
		self.nightStartTime = workspace:GetServerTimeNow()
		self.lastGroupQueuedTime = nil
		return
	end
	local now = workspace:GetServerTimeNow()
	local startTime = self.nightStartTime
	local current = self.current
	if startTime and current then
		current.nightSec = now - startTime
		local lastGroupTime = self.lastGroupQueuedTime
		if lastGroupTime then
			current.clearAfterLastGroupSec = now - lastGroupTime
		end
	end
	self.nightStartTime = nil
	self.lastGroupQueuedTime = nil
end

-- where a living player is right now: manning a post, inside the mine's
-- grid, or anywhere else in camp
function RunReportManager:samplePlayer(player: Player, seconds: number)
	local entry = self:playerDay(player)
	if PostManager:getMannedPost(player) then
		entry.postSec += seconds
		return
	end
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	local position = MiningManager:getPlayerPosition(player)
	if space and grid and position then
		local depth, height, width = MineSpace.worldToCell(space, position)
		if depth >= 0 and depth < grid.depth and height >= 0 and height < grid.height and width >= 0 and width < grid.width then
			entry.mineSec += seconds
			return
		end
	end
	entry.campSec += seconds
end

function RunReportManager:step(deltaSec: number)
	-- a paused run is nobody's time (2026-10-08: a 286 s break read as
	-- 343 s in camp)
	if not RunCycleManager:isRunOn() or RunPauseManager:isPaused() then
		return
	end
	self.sampleAccumulatorSec += deltaSec
	if self.sampleAccumulatorSec < SAMPLE_SEC then
		return
	end
	local elapsed = self.sampleAccumulatorSec
	self.sampleAccumulatorSec = 0
	for _, player in GameController:getReadyPlayers() do
		if ReviveManager:isDead(player) then
			continue
		end
		self:samplePlayer(player, elapsed)
	end
end

-- a dawn closes the day before it: its share of the run counters is
-- taken, it is printed, and a new row opens for the day that begins
function RunReportManager:onDayStarted(day: number, scalingCount: number)
	local current = self.current
	if current and current.day ~= day then
		self:takeStatDeltas(current)
		table.insert(self.report.rows, current)
		self:printLines({ string.format(DAWN_TITLE_FORMAT, current.day) }, RunReportRules.formatDay(current, monsterKindName))
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
	self:printLines({}, RunReportRules.formatReport(self.report, string.format(RUN_END_FORMAT, if isWon then "won" else "lost", #self.report.rows), monsterKindName))
end

-- the dev panel's button: everything so far, today included
function RunReportManager:printNow()
	local rows = table.clone(self.report.rows)
	local current = self.current
	if current then
		self:takeStatDeltas(current)
		table.insert(rows, current)
	end
	self:printLines({}, RunReportRules.formatReport({ rows = rows }, ON_DEMAND_TITLE, monsterKindName))
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
	self.lastGroupQueuedTime = nil
	self.lastCreditTimeByPlayer = {}
	self.snapshotByPlayer = {}
	self.sampleAccumulatorSec = 0
end

function RunReportManager:init()
	RefineryManager:subscribeCredited(
		function(player: Player, refined: { [number]: number })
			self:onCredited(player, refined)
		end
	)
	RefineryManager:subscribeSpent(
		function(player: Player, resource: number, amount: number, reason: string?)
			self:onSpent(player, resource, amount, reason)
		end
	)
	PlacementManager:subscribePlacementSpent(
		function(player: Player, action: number, placementKind: number, _typeKind: number, iron: number)
			self:onPlacementSpent(player, action, placementKind, iron)
		end
	)
	PlacementManager:subscribePlacementDamaged(
		function(_id: string, _placementKind: number, _typeKind: number, _amount: number, isDestroyed: boolean, _attackerKind: number?)
			self:onPlacementDamaged(isDestroyed)
		end
	)
	StructureManager:subscribeStructureDamaged(
		function(id: string, kind: number, amount: number, isDestroyed: boolean, attackerKind: number?)
			self:onStructureDamaged(id, kind, amount, isDestroyed, attackerKind)
		end
	)
	StructureManager:subscribeStructureRepaired(
		function(player: Player, _id: string, gained: number, cost: number)
			self:onStructureRepaired(player, gained, cost)
		end
	)
	MiningManager:subscribeHit(
		function(player: Player, depth: number, _height: number, _width: number, rock: number, isBroken: boolean)
			self:onRockHit(player, depth, rock, isBroken)
		end
	)
	ReviveManager:subscribeDamaged(
		function(player: Player, amount: number, _attackerKind: number?)
			self:onPlayerDamaged(player, amount)
		end
	)
	ReviveManager:subscribeDied(
		function(player: Player)
			self:onPlayerDied(player)
		end
	)
	ReviveManager:subscribeRevived(
		function(player: Player, _reviveKind: number)
			self:onPlayerRevived(player)
		end
	)
	MonsterManager:subscribeKilled(
		function(_kind: number)
			self:onMonsterKilled()
		end
	)
	MonsterWaveManager:subscribeGroupQueued(
		function(groupIndex: number, groupCount: number, targetDifficulty: number)
			self:onGroupQueued(groupIndex, groupCount, targetDifficulty)
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
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function RunReportManager.new(): RunReportManager
	local self = setmetatable({}, RunReportManager) :: RunReportManager
	self.report = { rows = {} }
	self.current = nil
	self.nightStartTime = nil
	self.lastGroupQueuedTime = nil
	self.lastCreditTimeByPlayer = {}
	self.snapshotByPlayer = {}
	self.sampleAccumulatorSec = 0
	return self
end

return RunReportManager.new()
