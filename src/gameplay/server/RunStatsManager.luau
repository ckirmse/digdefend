--!strict

-- One player's numbers for the run (GDD "Results Menu"), M32: Uranium,
-- Gold, and Iron refined, Diamonds earned, enemies killed, and damage given. Run state in
-- Lua, published as private CurrentPlayer attributes so the Results Menu
-- reads them like any other value; nights survived is not kept here, it
-- is the run's day less one (it is written on the grave). Each player's
-- place in the crew for every stat is published beside the numbers once a
-- second, for the menu's Group Rank column. Kills and damage arrive from the target
-- registry (DamageableManager), which names the attacker of every hit: a
-- player's weapon, their post, or a Tower or Trap they built. The
-- managers that pay out (RefineryManager, DiamondTapManager) report their own.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local RunStatsRules = require("@game/ReplicatedStorage/Shared/RunStatsRules")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)

local RunStatsManager = {}
RunStatsManager.__index = RunStatsManager

export type Stats = {
	-- uranium this player carried to the Refinery themselves (the run's
	-- count is shared; this is their part in it)
	uraniumRefined: number,
	diamondsEarned: number,
	goldRefined: number,
	ironRefined: number,
	enemiesKilled: number,
	damageGiven: number,
	-- damage is replicated in whole points at most this often, since a
	-- machine gun lands many hits a second
	isDamageDirty: boolean,
}

export type RunStatsManager = typeof(setmetatable(
	{} :: {
		statsByPlayer: { [Player]: Stats },
		-- the numbers of players who left the run: the crew they were part
		-- of is still ranked against them
		leaverStats: { Stats },
	},
	RunStatsManager
))

local DAMAGE_REPLICATE_INTERVAL_SEC = 1

-- the stats a player is placed in among the crew, and the attribute each place goes to
local RANKED_STATS: { { attribute: string, read: (stats: Stats) -> number } } = {
	{
		attribute = Attributes.RUN_STAT_RANK_URANIUM_REFINED,
		read = function(stats: Stats): number
			return stats.uraniumRefined
		end,
	},
	{
		attribute = Attributes.RUN_STAT_RANK_DIAMONDS_EARNED,
		read = function(stats: Stats): number
			return stats.diamondsEarned
		end,
	},
	{
		attribute = Attributes.RUN_STAT_RANK_GOLD_REFINED,
		read = function(stats: Stats): number
			return stats.goldRefined
		end,
	},
	{
		attribute = Attributes.RUN_STAT_RANK_IRON_REFINED,
		read = function(stats: Stats): number
			return stats.ironRefined
		end,
	},
	{
		attribute = Attributes.RUN_STAT_RANK_ENEMIES_KILLED,
		read = function(stats: Stats): number
			return stats.enemiesKilled
		end,
	},
	{
		attribute = Attributes.RUN_STAT_RANK_DAMAGE_GIVEN,
		read = function(stats: Stats): number
			return math.floor(stats.damageGiven)
		end,
	},
}

local function newStats(): Stats
	return {
		uraniumRefined = 0,
		diamondsEarned = 0,
		goldRefined = 0,
		ironRefined = 0,
		enemiesKilled = 0,
		damageGiven = 0,
		isDamageDirty = false,
	}
end

function RunStatsManager:getStats(player: Player): Stats?
	return self.statsByPlayer[player]
end

function RunStatsManager:replicate(player: Player)
	local stats = self.statsByPlayer[player]
	if not stats then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_URANIUM_REFINED, stats.uraniumRefined)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_DIAMONDS_EARNED, stats.diamondsEarned)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_GOLD_REFINED, stats.goldRefined)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_IRON_REFINED, stats.ironRefined)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_ENEMIES_KILLED, stats.enemiesKilled)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RUN_STAT_DAMAGE_GIVEN, math.floor(stats.damageGiven))
	stats.isDamageDirty = false
end

function RunStatsManager:addDiamondsEarned(player: Player, amount: number)
	local stats = self.statsByPlayer[player]
	if not stats or amount <= 0 then
		return
	end
	stats.diamondsEarned += amount
	self:replicate(player)
end

function RunStatsManager:addRefined(player: Player, ironBars: number, goldBars: number, uranium: number)
	local stats = self.statsByPlayer[player]
	if not stats then
		return
	end
	stats.uraniumRefined += math.max(0, uranium)
	stats.ironRefined += math.max(0, ironBars)
	stats.goldRefined += math.max(0, goldBars)
	self:replicate(player)
end

function RunStatsManager:onDamaged(attacker: Player, amount: number, isKill: boolean)
	local stats = self.statsByPlayer[attacker]
	if not stats then
		return
	end
	stats.damageGiven += amount
	stats.isDamageDirty = true
	if isKill then
		stats.enemiesKilled += 1
		self:replicate(attacker)
	end
end

function RunStatsManager:replicateDirtyDamage()
	for player, stats in self.statsByPlayer do
		if stats.isDamageDirty then
			self:replicate(player)
		end
	end
end

-- each player's place in the crew for every stat (the Group Rank column):
-- worked out for everyone together, since one player's number moves the
-- others' places. A player only ever receives their own places, never
-- another player's numbers
function RunStatsManager:replicateRanks()
	for _, ranked in RANKED_STATS do
		local values = {}
		for _, stats in self.statsByPlayer do
			table.insert(values, ranked.read(stats))
		end
		for _, stats in self.leaverStats do
			table.insert(values, ranked.read(stats))
		end
		for player, stats in self.statsByPlayer do
			SplendidReplicationManager:setCurrentPlayerAttribute(player, ranked.attribute, RunStatsRules.rank(ranked.read(stats), values))
		end
	end
end

-- a run (or a dev-tool restart) starts everyone's numbers over
-- whether more than one player has been in this run, here now or gone:
-- the Results Menu shows its Group Rank column from this, so a player left
-- alone by a crewmate still sees how they placed
function RunStatsManager:replicateIsGroup()
	local count = #self.leaverStats
	for _ in self.statsByPlayer do
		count += 1
	end
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_IS_GROUP, count > 1)
end

function RunStatsManager:onRunStarted()
	self.leaverStats = {}
	self:replicateIsGroup()
	for player in self.statsByPlayer do
		self.statsByPlayer[player] = newStats()
		self:replicate(player)
	end
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function RunStatsManager:onPlayerReady(player: Player)
	if not self.statsByPlayer[player] then
		self.statsByPlayer[player] = newStats()
	end
	self:replicate(player)
	self:replicateIsGroup()
	self:replicateRanks()
end

function RunStatsManager:init()
	GameController:registerPlaceManager(self)
	DamageableManager:subscribeDamaged(
		function(attacker: Player, amount: number, isKill: boolean)
			self:onDamaged(attacker, amount, isKill)
		end
	)
	-- not a teardown entry: a dev-tool reset must not wipe the run's numbers
	Players.PlayerRemoving:Connect(
		function(player: Player)
			local stats = self.statsByPlayer[player]
			self.statsByPlayer[player] = nil
			if stats then
				table.insert(self.leaverStats, stats)
			end
		end
	)
	task.spawn(
		function()
			while true do
				task.wait(DAMAGE_REPLICATE_INTERVAL_SEC)
				self:replicateDirtyDamage()
				self:replicateRanks()
			end
		end
	)
end

function RunStatsManager.new(): RunStatsManager
	local self = setmetatable({}, RunStatsManager) :: RunStatsManager
	self.statsByPlayer = {}
	self.leaverStats = {}
	return self
end

return RunStatsManager.new()
