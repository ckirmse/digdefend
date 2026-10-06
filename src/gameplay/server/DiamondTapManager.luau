--!strict

-- Diamonds earned in a run (GDD "Earning Diamonds"), M32. Diamonds is the one
-- persistent currency, so every payout goes through PlayerData (the save's
-- owner), is replicated, counted in the run's stats for the Results Menu,
-- and saved at once so a run lost a minute later keeps it. Two taps are
-- built: a night milestone, paid to every player alive at the dawn after
-- that night (pure DiamondTapRules decides what a dawn owes, so a day
-- started over by the Team Revive pays nothing twice), and the rescue,
-- paid to everyone aboard when the helicopter leaves (RescueManager).
-- Amounts are GameData/Run/DiamondTaps.
local Players = game:GetService("Players")

local DiamondTapRules = require("@game/ReplicatedStorage/Shared/DiamondTapRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local DiamondTapsData = require("@game/ServerScriptService/GameData/Run/DiamondTaps")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local RunStatsManager = require(script.Parent.RunStatsManager)

local DiamondTapManager = {}
DiamondTapManager.__index = DiamondTapManager

export type DiamondTapManager = typeof(setmetatable(
	{} :: {
		-- the last night whose milestones this player has been paid for
		lastPaidNightByPlayer: { [Player]: number },
	},
	DiamondTapManager
))

local NIGHT_MILESTONE_DIAMONDS: { [number]: number } = DiamondTapsData.NIGHT_MILESTONE_DIAMONDS
local RESCUE_DIAMONDS_BY_DIFFICULTY: { [number]: number } = DiamondTapsData.RESCUE_DIAMONDS_BY_DIFFICULTY

-- the one payout path: the save, the HUD, the run's stats, and the toast
function DiamondTapManager:pay(player: Player, amount: number, reason: string)
	local playerData = GameController:getPlayerData(player)
	if not playerData or amount <= 0 then
		return
	end
	playerData:addDiamonds(amount)
	SplendidReplicationManager:replicateDiamonds(player)
	RunStatsManager:addDiamondsEarned(player, amount)
	playerData:saveNow()
	print(`[DiamondTapManager] {player.Name} earned {amount} Diamonds ({reason})`)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_DIAMONDS_EARNED, {
		amount = amount,
		reason = reason,
	})
end

-- a night is survived by a player who is alive at its dawn: a player
-- dead when day breaks is paid nothing for it, and never for it later
-- either, since the night is marked as passed for them (2026-10-05)
function DiamondTapManager:payNightMilestones(day: number)
	local nightsSurvived = DiamondTapRules.nightsSurvived(day)
	for _, player in GameController:getReadyPlayers() do
		local lastPaidNight = self.lastPaidNightByPlayer[player] or 0
		local amount, paidNight = DiamondTapRules.unpaidMilestoneDiamonds(NIGHT_MILESTONE_DIAMONDS, lastPaidNight, nightsSurvived)
		self.lastPaidNightByPlayer[player] = paidNight
		if amount > 0 and not ReviveManager:isDead(player) then
			self:pay(player, amount, string.format(DiamondTapsData.NIGHT_MILESTONE_REASON_FORMAT, day))
		end
	end
end

-- a player aboard the departing rescue helicopter
function DiamondTapManager:payRescue(player: Player)
	local difficulty = RunManager:getDifficulty()
	local amount = if difficulty then RESCUE_DIAMONDS_BY_DIFFICULTY[difficulty] else nil
	if amount then
		self:pay(player, amount, DiamondTapsData.RESCUE_REASON)
	end
end

-- a run (or a dev-tool restart) may pay its milestones again
function DiamondTapManager:onRunStarted()
	self.lastPaidNightByPlayer = {}
end

function DiamondTapManager:init()
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

function DiamondTapManager.new(): DiamondTapManager
	local self = setmetatable({}, DiamondTapManager) :: DiamondTapManager
	self.lastPaidNightByPlayer = {}
	return self
end

return DiamondTapManager.new()
