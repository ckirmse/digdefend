--!strict

-- Cash earned in a run (GDD "Earning Cash"), M32. Cash is the one
-- persistent currency, so every payout goes through PlayerData (the save's
-- owner), is replicated, counted in the run's stats for the Results Menu,
-- and saved at once so a run lost a minute later keeps it. Two taps are
-- built: a night milestone, paid to every player alive at the dawn after
-- that night (pure CashTapRules decides what a dawn owes, so a day
-- started over by the Team Revive pays nothing twice), and the rescue,
-- paid to everyone aboard when the helicopter leaves (RescueManager).
-- Amounts are GameData/Run/CashTaps.
local Players = game:GetService("Players")

local CashTapRules = require("@game/ReplicatedStorage/Shared/CashTapRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local CashTapsData = require("@game/ServerScriptService/GameData/Run/CashTaps")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local RunStatsManager = require(script.Parent.RunStatsManager)

local CashTapManager = {}
CashTapManager.__index = CashTapManager

export type CashTapManager = typeof(setmetatable(
	{} :: {
		-- the last night whose milestones this player has been paid for
		lastPaidNightByPlayer: { [Player]: number },
	},
	CashTapManager
))

local NIGHT_MILESTONE_CASH: { [number]: number } = CashTapsData.NIGHT_MILESTONE_CASH
local RESCUE_CASH_BY_DIFFICULTY: { [number]: number } = CashTapsData.RESCUE_CASH_BY_DIFFICULTY

-- the one payout path: the save, the HUD, the run's stats, and the toast
function CashTapManager:pay(player: Player, amount: number, reason: string)
	local playerData = GameController:getPlayerData(player)
	if not playerData or amount <= 0 then
		return
	end
	playerData:addCash(amount)
	SplendidReplicationManager:replicateCash(player)
	RunStatsManager:addCashEarned(player, amount)
	playerData:saveNow()
	print(`[CashTapManager] {player.Name} earned {amount} Cash ({reason})`)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_CASH_EARNED, {
		amount = amount,
		reason = reason,
	})
end

-- a night is survived by a player who is alive at its dawn: a player
-- dead when day breaks is paid nothing for it, and never for it later
-- either, since the night is marked as passed for them (2026-10-05)
function CashTapManager:payNightMilestones(day: number)
	local nightsSurvived = CashTapRules.nightsSurvived(day)
	for _, player in GameController:getReadyPlayers() do
		local lastPaidNight = self.lastPaidNightByPlayer[player] or 0
		local amount, paidNight = CashTapRules.unpaidMilestoneCash(NIGHT_MILESTONE_CASH, lastPaidNight, nightsSurvived)
		self.lastPaidNightByPlayer[player] = paidNight
		if amount > 0 and not ReviveManager:isDead(player) then
			self:pay(player, amount, string.format(CashTapsData.NIGHT_MILESTONE_REASON_FORMAT, nightsSurvived))
		end
	end
end

-- a player aboard the departing rescue helicopter
function CashTapManager:payRescue(player: Player)
	local difficulty = RunManager:getDifficulty()
	local amount = if difficulty then RESCUE_CASH_BY_DIFFICULTY[difficulty] else nil
	if amount then
		self:pay(player, amount, CashTapsData.RESCUE_REASON)
	end
end

-- a run (or a dev-tool restart) may pay its milestones again
function CashTapManager:onRunStarted()
	self.lastPaidNightByPlayer = {}
end

function CashTapManager:init()
	RunCycleManager:subscribeDayStarted(
		function(day: number, _scalingCount: number)
			self:payNightMilestones(day)
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.lastPaidNightByPlayer[player] = nil
		end
	)
end

function CashTapManager.new(): CashTapManager
	local self = setmetatable({}, CashTapManager) :: CashTapManager
	self.lastPaidNightByPlayer = {}
	return self
end

return CashTapManager.new()
