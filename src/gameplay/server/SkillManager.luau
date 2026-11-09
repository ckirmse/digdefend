--!strict

-- The skills in a run (GDD "Classes", M56; the 36 designed with the
-- designer 2026-11-09). A skill that multiplies a number rides the class
-- modifier axis through ClassManager:getModifier and needs nothing here.
-- This manager answers the rule skills: which skills a Ready player holds
-- (`has`), whether anyone in the crew holds a crew skill (`crewHas`, the
-- ones marked "(cannot stack)", applied once for everyone), and each
-- rule's numbers (`param`, from GameData/Characters/SkillEffects). It
-- also owns the few effects with no better home: the Gold Digger's bars
-- at the run's start, the Mother Lode's break count, the Last Stand's
-- fire rate multiple (published on CurrentPlayer so the clients pace
-- their triggers by it), and the walk and fuel providers the Boots and
-- the jet pack ask (the Long Haul, the Night Shift, the Deep Lungs). The
-- owning managers do the rest at their own hooks and ask here.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SkillEffectsData = require("@game/ServerScriptService/GameData/Characters/SkillEffects")
local StructuresData = require("@game/ServerScriptService/GameData/Camp/Structures")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local SkillEffectRules = require("@game/ReplicatedStorage/Shared/SkillEffectRules")
local ClassManager = require(script.Parent.Parent.Server.ClassManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local SkillManager = {}
SkillManager.__index = SkillManager

export type SkillManager = typeof(setmetatable(
	{} :: {
		-- the held skill set per Ready player, rebuilt on every change
		skillsByPlayer: { [Player]: { [string]: boolean } },
		-- the Mother Lode's count of rocks broken, per player, per run
		breakCountByPlayer: { [Player]: number },
		-- who the Gold Digger has paid this run
		goldGrantedByPlayer: { [Player]: boolean },
		-- the Last Stand's published multiple, to write only on change
		fireRateByPlayer: { [Player]: number },
		-- the Night Shift's last answer, to re-apply the boots on change
		isInCampByPlayer: { [Player]: boolean },
		stepAccumulatorSec: number,
		stepConnection: RBXScriptConnection?,
	},
	SkillManager
))

local runCycleManager: any -- prevent circular reference by not initializing here
local refineryManager: any
local backpackManager: any
local bootsManager: any
local jetPackManager: any
local reviveManager: any
local mapManager: any
local runManager: any

local SKILL_IDS = {
	LONG_HAUL = "LONG_HAUL",
	GOLD_DIGGER = "GOLD_DIGGER",
	MOTHER_LODE = "MOTHER_LODE",
	DEEP_LUNGS = "DEEP_LUNGS",
	LAST_STAND = "LAST_STAND",
	NIGHT_SHIFT = "NIGHT_SHIFT",
}
-- how often the conditional skills are re-judged (health, where a player stands)
local STEP_SEC = 0.5
local MINE_MONSTER_KINDS: { [number]: boolean } = {}
for _, kind in SkillEffectsData.MINE_MONSTER_KINDS do
	MINE_MONSTER_KINDS[kind] = true
end

-- read live from the class record, never from a cache: the other managers
-- react to the same class and skill change callbacks, in whatever order
-- they subscribed, and a cache here could be a step behind them
function SkillManager:has(player: Player, skillId: string): boolean
	if not GameController:isPlayerReady(player) then
		return false
	end
	return table.find(ClassManager:getSkillIds(player), skillId) ~= nil
end

-- a crew skill: held by anyone Ready, applied once for everyone
function SkillManager:crewHas(skillId: string): boolean
	for player in self.skillsByPlayer do
		if self:has(player, skillId) then
			return true
		end
	end
	return false
end

function SkillManager:param(skillId: string, key: string, fallback: number): number
	return SkillEffectRules.param(SkillEffectsData.BY_ID, skillId, key, fallback)
end

-- the multiple a holder's rule puts on an amount, 1 for everyone else
function SkillManager:multiplierFor(player: Player, skillId: string, key: string): number
	return if self:has(player, skillId) then self:param(skillId, key, 1) else 1
end

-- the crew's multiple the same way
function SkillManager:crewMultiplierFor(skillId: string, key: string): number
	return if self:crewHas(skillId) then self:param(skillId, key, 1) else 1
end

function SkillManager:isMineMonster(monsterKind: number?): boolean
	return monsterKind ~= nil and MINE_MONSTER_KINDS[monsterKind] == true
end

function SkillManager:isNight(): boolean
	return runCycleManager ~= nil and runCycleManager:isNight()
end

-- a rock broken by the player: whether the Mother Lode pays on this one
function SkillManager:countBreak(player: Player): boolean
	if not self:has(player, SKILL_IDS.MOTHER_LODE) then
		return false
	end
	local count = (self.breakCountByPlayer[player] or 0) + 1
	self.breakCountByPlayer[player] = count
	return SkillEffectRules.isNthBreak(count, self:param(SKILL_IDS.MOTHER_LODE, "EVERY_NTH_BREAK", 10))
end

-- the Last Stand's multiple on every weapon's fire rate for this player now
function SkillManager:getFireRateMultiplier(player: Player): number
	return self.fireRateByPlayer[player] or 1
end

function SkillManager:isInsideCamp(player: Player): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local camp = if mapManager then mapManager:getCamp() else nil
	local areaFolder = if camp then camp:FindFirstChild(Constants.CAMP_CAMP_AREA_FOLDER) else nil
	if not root or not root:IsA("BasePart") or not areaFolder then
		return false
	end
	for _, part in areaFolder:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local offset = part.CFrame:PointToObjectSpace(root.Position)
		if math.abs(offset.X) <= part.Size.X / 2 and math.abs(offset.Z) <= part.Size.Z / 2 then
			return true
		end
	end
	return false
end

-- the walk speed multiple the Boots ask for (the Long Haul with a full
-- backpack, the Night Shift inside the camp at night)
function SkillManager:getSpeedScale(player: Player): number
	local scale = 1
	if self:has(player, SKILL_IDS.LONG_HAUL) and backpackManager and backpackManager:isFull(player) then
		scale *= self:param(SKILL_IDS.LONG_HAUL, "FULL_BACKPACK_SPEED_MULTIPLIER", 1)
	end
	if self:has(player, SKILL_IDS.NIGHT_SHIFT) and self:isNight() and self.isInCampByPlayer[player] then
		scale *= self:param(SKILL_IDS.NIGHT_SHIFT, "CAMP_NIGHT_SPEED_MULTIPLIER", 1)
	end
	return scale
end

-- the fuel drain multiple the jet pack asks for (the Deep Lungs at night)
function SkillManager:getDrainScale(player: Player): number
	if self:has(player, SKILL_IDS.DEEP_LUNGS) and self:isNight() then
		return self:param(SKILL_IDS.DEEP_LUNGS, "NIGHT_FUEL_DRAIN_MULTIPLIER", 1)
	end
	return 1
end

-- the Gold Digger's bars, once per run, at the run's start or at Ready
-- for a player who arrives into a run
function SkillManager:grantStartingGoldIfNeeded(player: Player)
	if self.goldGrantedByPlayer[player] or not self:has(player, SKILL_IDS.GOLD_DIGGER) then
		return
	end
	if not runCycleManager or not runCycleManager:isRunOn() or not refineryManager then
		return
	end
	self.goldGrantedByPlayer[player] = true
	refineryManager:addGoldBars(player, self:param(SKILL_IDS.GOLD_DIGGER, "STARTING_GOLD_BARS", 0))
end

-- the Hammer's swing interval for this player, on CurrentPlayer so the
-- client paces its swings by it (the Quick Fix; the GameMetadata copy is
-- the base)
function SkillManager:publishHammerInterval(player: Player)
	local swingScale: number = ClassManager:getModifier(player, Enums.ClassModifier.HAMMER_SWING_SPEED)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.HAMMER_HIT_INTERVAL_SEC, StructuresData.HAMMER_HIT_INTERVAL_SEC / swingScale)
end

function SkillManager:publishFireRate(player: Player, multiplier: number)
	if self.fireRateByPlayer[player] == multiplier then
		return
	end
	self.fireRateByPlayer[player] = multiplier
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.FIRE_RATE_MULTIPLIER, multiplier)
end

-- re-reads the held skills and puts every published number right
function SkillManager:refresh(player: Player)
	if not GameController:isPlayerReady(player) then
		return
	end
	local skills: { [string]: boolean } = {}
	for _, skillId in ClassManager:getSkillIds(player) do
		skills[skillId] = true
	end
	self.skillsByPlayer[player] = skills
	ClassManager:replicateModifiers(player)
	self:publishHammerInterval(player)
	if bootsManager then
		bootsManager:apply(player)
	end
	if backpackManager then
		backpackManager:replicate(player)
	end
	if jetPackManager then
		jetPackManager:replicate(player, workspace:GetServerTimeNow())
	end
	self:grantStartingGoldIfNeeded(player)
	self:judgeConditions(player)
end

-- the conditions that change under a standing player: health for the
-- Last Stand, the camp's area for the Night Shift
function SkillManager:judgeConditions(player: Player)
	local fireRate = 1
	if self:has(player, SKILL_IDS.LAST_STAND) and reviveManager then
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			fireRate = SkillEffectRules.fireRateMultiplier(
				humanoid.Health,
				reviveManager:getMaxHealth(player),
				true,
				self:param(SKILL_IDS.LAST_STAND, "HEALTH_SHARE_BELOW", 0.25),
				self:param(SKILL_IDS.LAST_STAND, "FIRE_RATE_MULTIPLIER", 1)
			)
		end
	end
	self:publishFireRate(player, fireRate)
	if self:has(player, SKILL_IDS.NIGHT_SHIFT) then
		local isInCamp = self:isInsideCamp(player)
		if self.isInCampByPlayer[player] ~= isInCamp then
			self.isInCampByPlayer[player] = isInCamp
			if bootsManager then
				bootsManager:apply(player)
			end
		end
	end
end

function SkillManager:step(deltaSec: number)
	self.stepAccumulatorSec += deltaSec
	if self.stepAccumulatorSec < STEP_SEC then
		return
	end
	self.stepAccumulatorSec = 0
	for player in self.skillsByPlayer do
		self:judgeConditions(player)
	end
end

-- a run (or a dev-tool restart) starts the per-run counts over and pays
-- the Gold Diggers who are here
function SkillManager:onRunStarted()
	self.breakCountByPlayer = {}
	self.goldGrantedByPlayer = {}
	for player in self.skillsByPlayer do
		self:grantStartingGoldIfNeeded(player)
	end
end

-- ready-sequence entry: the skill set is read at Ready and again on every
-- class or skill change; a dev-tool reset replays it harmlessly
function SkillManager:onPlayerReady(player: Player)
	self:refresh(player)
end

function SkillManager:onPlayerRemoved(player: Player)
	self.skillsByPlayer[player] = nil
	self.breakCountByPlayer[player] = nil
	self.goldGrantedByPlayer[player] = nil
	self.fireRateByPlayer[player] = nil
	self.isInCampByPlayer[player] = nil
end

function SkillManager:init(runCycleManagerIn: any, refineryManagerIn: any, backpackManagerIn: any, bootsManagerIn: any, jetPackManagerIn: any, reviveManagerIn: any, mapManagerIn: any, runManagerIn: any)
	runCycleManager = runCycleManagerIn
	refineryManager = refineryManagerIn
	backpackManager = backpackManagerIn
	bootsManager = bootsManagerIn
	jetPackManager = jetPackManagerIn
	reviveManager = reviveManagerIn
	mapManager = mapManagerIn
	runManager = runManagerIn
	GameController:registerPlaceManager(self)
	bootsManager:setSpeedScaleProvider(
		function(player: Player)
			return self:getSpeedScale(player)
		end
	)
	jetPackManager:setDrainScaleProvider(
		function(player: Player)
			return self:getDrainScale(player)
		end
	)
	ClassManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			self:refresh(player)
		end
	)
	ClassManager:subscribeSkillsChanged(
		function(player: Player)
			self:refresh(player)
		end
	)
	-- the Long Haul's speed follows the backpack filling and emptying
	backpackManager:subscribeChanged(
		function(player: Player)
			if self:has(player, SKILL_IDS.LONG_HAUL) then
				bootsManager:apply(player)
			end
		end
	)
	-- the Night Shift and the Deep Lungs follow the night
	runCycleManager:subscribeNightChanged(
		function(_isNight: boolean)
			for player in self.skillsByPlayer do
				if self:has(player, SKILL_IDS.NIGHT_SHIFT) then
					bootsManager:apply(player)
				end
			end
		end
	)
	runManager:subscribeRunStarted(
		function(_map: number, _difficulty: number)
			self:onRunStarted()
		end
	)
	self.stepConnection = RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:onPlayerRemoved(player)
		end
	)
end

function SkillManager.new(): SkillManager
	local self = setmetatable({}, SkillManager) :: SkillManager
	self.skillsByPlayer = {}
	self.breakCountByPlayer = {}
	self.goldGrantedByPlayer = {}
	self.fireRateByPlayer = {}
	self.isInCampByPlayer = {}
	self.stepAccumulatorSec = 0
	self.stepConnection = nil
	return self
end

return SkillManager.new()
