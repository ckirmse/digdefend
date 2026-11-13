--!strict

-- Badges in a run (M69): this manager only listens. It subscribes to the
-- hooks of the managers that own each fact (mining, kills, refining,
-- repairs, damage, nights, the rescue) and tells the common BadgeManager
-- what a player did; BadgeManager and pure BadgeRules decide what that
-- earns, pay it, and save it. Nothing here changes the run.
--
-- Lifetime badges are counters handed straight on (addProgress). The
-- rest are judged from a little state about the current run, kept here
-- and forgotten at the next run's start:
--   per player: whether they have taken damage (Not a Scratch) and their
--     kills this night (One-Man Army)
--   for the crew: the most players the run has held (Full Crew, Lone
--     Miner), whether the Refinery was ever damaged, and, per night,
--     whether any wall, gate, or the Refinery was damaged (Quiet Week)
--     and whether anyone fired a handheld or Post Weapon (Architect)
-- A night is judged at the dawn after it, for the players alive then.
local Players = game:GetService("Players")

local BadgeRules = require("@game/ReplicatedStorage/Shared/BadgeRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local BadgeManager = require(script.Parent.Parent.Server.BadgeManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local ChaseManager = require(script.Parent.ChaseManager)
local DamageableManager = require(script.Parent.DamageableManager)
local GiveCurrencyManager = require(script.Parent.GiveCurrencyManager)
local MiningManager = require(script.Parent.MiningManager)
local MiningStoreManager = require(script.Parent.MiningStoreManager)
local PostManager = require(script.Parent.PostManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RescueManager = require(script.Parent.RescueManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local StructureManager = require(script.Parent.StructureManager)
local ToolManager = require(script.Parent.ToolManager)
local WeaponManager = require(script.Parent.WeaponManager)

local BadgeTrackerManager = {}
BadgeTrackerManager.__index = BadgeTrackerManager

export type BadgeTrackerManager = typeof(setmetatable(
	{} :: {
		hasTakenDamageByPlayer: { [Player]: boolean },
		nightKillsByPlayer: { [Player]: number },
		maxCrewSize: number,
		isRefineryDamaged: boolean,
		-- since the last dusk
		isStructureDamagedThisNight: boolean,
		isWeaponFiredThisNight: boolean,
		isNight: boolean,
		quietStreak: number,
		-- the last night whose dawn was judged, so a day started over
		-- (the Team Revive) never counts its night twice
		lastJudgedNight: number,
	},
	BadgeTrackerManager
))

function BadgeTrackerManager:resetRun()
	self.hasTakenDamageByPlayer = {}
	self.nightKillsByPlayer = {}
	self.maxCrewSize = 0
	self.isRefineryDamaged = false
	self.isStructureDamagedThisNight = false
	self.isWeaponFiredThisNight = false
	self.isNight = false
	self.quietStreak = 0
	self.lastJudgedNight = 0
end

function BadgeTrackerManager:noteCrewSize()
	self.maxCrewSize = math.max(self.maxCrewSize, #GameController:getReadyPlayers())
end

-- Buddy System: a Roblox friend is in the crew. Asked off the thread
-- (Roblox is asked per pair), and both friends earn it
function BadgeTrackerManager:checkFriends(player: Player)
	task.spawn(
		function()
			for _, other in GameController:getReadyPlayers() do
				if other == player then
					continue
				end
				local isSuccess, isFriend = pcall(
					function()
						return player:IsFriendsWithAsync(other.UserId)
					end
				)
				if isSuccess and isFriend then
					BadgeManager:award(player, Enums.BadgeKind.BUDDY_SYSTEM)
					BadgeManager:award(other, Enums.BadgeKind.BUDDY_SYSTEM)
				end
			end
		end
	)
end

function BadgeTrackerManager:onRunStarted()
	self:resetRun()
	self:noteCrewSize()
	for _, player in GameController:getReadyPlayers() do
		self:checkFriends(player)
	end
end

-- ready-sequence entry: a player arriving into the run
function BadgeTrackerManager:onPlayerReady(player: Player)
	self:noteCrewSize()
	self:checkFriends(player)
end

function BadgeTrackerManager:onPlayerRemoved(player: Player)
	self.hasTakenDamageByPlayer[player] = nil
	self.nightKillsByPlayer[player] = nil
end

function BadgeTrackerManager:onNightChanged(isNight: boolean)
	self.isNight = isNight
	if isNight then
		self.isStructureDamagedThisNight = false
		self.isWeaponFiredThisNight = false
		self.nightKillsByPlayer = {}
	end
end

-- the dawn after a night: the survival badges, Architect, and Quiet
-- Week, for every player alive to see it
function BadgeTrackerManager:onDayStarted(day: number)
	local night = day - 1
	if night < 1 or night <= self.lastJudgedNight then
		return
	end
	self.lastJudgedNight = night
	local rules = BadgeManager:getRules()
	self.quietStreak = BadgeRules.nextQuietStreak(self.quietStreak, self.isStructureDamagedThisNight)
	local nightKinds = BadgeRules.kindsForNight(BadgeManager:getDefinitions(), night)
	for _, player in GameController:getReadyPlayers() do
		if ReviveManager:isDead(player) then
			continue
		end
		BadgeManager:awardAll(player, nightKinds)
		if not self.isWeaponFiredThisNight then
			BadgeManager:award(player, Enums.BadgeKind.ARCHITECT)
		end
		if self.quietStreak >= rules.QUIET_WEEK_NIGHTS then
			BadgeManager:award(player, Enums.BadgeKind.QUIET_WEEK)
		end
	end
end

function BadgeTrackerManager:onWeaponFired()
	if self.isNight then
		self.isWeaponFiredThisNight = true
	end
end

function BadgeTrackerManager:onKill(attacker: Player)
	BadgeManager:addProgress(attacker, Enums.BadgeCounter.MONSTERS_KILLED, 1)
	if not self.isNight then
		return
	end
	local kills = (self.nightKillsByPlayer[attacker] or 0) + 1
	self.nightKillsByPlayer[attacker] = kills
	if kills >= BadgeManager:getRules().ONE_MAN_ARMY_KILLS then
		BadgeManager:award(attacker, Enums.BadgeKind.ONE_MAN_ARMY)
	end
end

function BadgeTrackerManager:onRefined(player: Player, refined: { [number]: number })
	BadgeManager:addProgress(player, Enums.BadgeCounter.URANIUM_REFINED, refined[Enums.RefinedResource.URANIUM] or 0)
	BadgeManager:addProgress(player, Enums.BadgeCounter.GOLD_REFINED, refined[Enums.RefinedResource.GOLD_BAR] or 0)
end

function BadgeTrackerManager:onStructureDamaged(kind: number, amount: number)
	if amount <= 0 then
		return
	end
	if kind == Enums.StructureKind.REFINERY then
		self.isRefineryDamaged = true
	end
	-- every structure StructureManager owns is a wall, the gate, or the
	-- Refinery; placed Towers and Traps are PlacementManager's and do
	-- not count (designer, 2026-11-12)
	self.isStructureDamagedThisNight = true
end

function BadgeTrackerManager:onPickAxeLevelChanged(player: Player, level: number)
	local offer = StoreRules.getOffer(MiningStoreManager:getCatalog(), Enums.StoreItem.PICK_AXE, level)
	if offer and offer.status == Enums.StoreOffer.MAXED then
		BadgeManager:award(player, Enums.BadgeKind.HOLY_PICK_AXE)
	end
end

-- a player aboard the rescue helicopter as it leaves: the win badges by
-- what this tracker knows of the run, and one more rescue on the counter
function BadgeTrackerManager:onRescued(player: Player)
	local summary: BadgeRules.RescueSummary = {
		difficulty = RunManager:getDifficulty() or Enums.Difficulty.NORMAL,
		crewSize = math.max(self.maxCrewSize, 1),
		day = RunCycleManager:getDay(),
		hasTakenDamage = self.hasTakenDamageByPlayer[player] == true,
		isRefineryDamaged = self.isRefineryDamaged,
	}
	BadgeManager:awardAll(player, BadgeRules.kindsForRescue(summary, BadgeManager:getRules()))
	BadgeManager:addProgress(player, Enums.BadgeCounter.RESCUES, 1)
end

-- after every manager it listens to
function BadgeTrackerManager:init()
	RunManager:subscribeRunStarted(
		function(_map: number, _difficulty: number)
			self:onRunStarted()
		end
	)
	RunCycleManager:subscribeNightChanged(
		function(isNight: boolean)
			self:onNightChanged(isNight)
		end
	)
	RunCycleManager:subscribeDayStarted(
		function(day: number, _scalingCount: number)
			self:onDayStarted(day)
		end
	)
	MiningManager:subscribeHit(
		function(player: Player, _depth: number, _height: number, _width: number, _rock: number, isBroken: boolean)
			if isBroken then
				BadgeManager:addProgress(player, Enums.BadgeCounter.BLOCKS_BROKEN, 1)
			end
		end
	)
	DamageableManager:subscribeDamaged(
		function(attacker: Player, _amount: number, isKill: boolean)
			if isKill and attacker and attacker.Parent == Players then
				self:onKill(attacker)
			end
		end
	)
	RefineryManager:subscribeCredited(
		function(player: Player, refined: { [number]: number })
			self:onRefined(player, refined)
		end
	)
	StructureManager:subscribeStructureRepaired(
		function(player: Player, _id: string, _gained: number, _cost: number)
			BadgeManager:addProgress(player, Enums.BadgeCounter.HAMMER_SWINGS, 1)
		end
	)
	StructureManager:subscribeStructureDamaged(
		function(_id: string, kind: number, amount: number, _isDestroyed: boolean, _attackerKind: number?)
			self:onStructureDamaged(kind, amount)
		end
	)
	ReviveManager:subscribeDamaged(
		function(player: Player, amount: number, _attackerKind: number?)
			if amount > 0 then
				self.hasTakenDamageByPlayer[player] = true
			end
		end
	)
	WeaponManager:subscribeFired(
		function(_player: Player)
			self:onWeaponFired()
		end
	)
	PostManager:subscribeFired(
		function(_player: Player)
			self:onWeaponFired()
		end
	)
	ToolManager:subscribePickAxeLevelChanged(
		function(player: Player, level: number)
			self:onPickAxeLevelChanged(player, level)
		end
	)
	GiveCurrencyManager:subscribeGiven(
		function(sender: Player)
			BadgeManager:award(sender, Enums.BadgeKind.TEAM_PLAYER)
		end
	)
	ChaseManager:subscribeEscaped(
		function(player: Player)
			BadgeManager:award(player, Enums.BadgeKind.GHOST_MINER)
		end
	)
	RescueManager:subscribeRescued(
		function(player: Player)
			self:onRescued(player)
		end
	)
	GameController:registerPlaceManager(self)
end

function BadgeTrackerManager.new(): BadgeTrackerManager
	local self = setmetatable({}, BadgeTrackerManager) :: BadgeTrackerManager
	self:resetRun()
	return self
end

return BadgeTrackerManager.new()
