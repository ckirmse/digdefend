--!strict

-- The balance audit (docs/balance-plan.md, 2026-09-28): the one place that
-- knows where BalanceModel's numbers come from. It reads GameData for a
-- map, a difficulty, and a crew size, runs the model, and checks the
-- result against GameData/Control/Balance. At gameplay startup it audits
-- every map and difficulty at every AUDIT_CREW_SIZES and warns per
-- failure, so a tuning edit that breaks a target is seen the moment the
-- server boots; the dev tool prints the full sheet for the current run.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local BalanceModel = require("@game/ReplicatedStorage/Shared/BalanceModel")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local RefineryRules = require("@game/ReplicatedStorage/Shared/RefineryRules")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local BalanceData = require("@game/ServerScriptService/GameData/Control/Balance")
local DifficultyData = require("@game/ServerScriptService/GameData/Control/Difficulty")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local RunCycleData = require("@game/ServerScriptService/GameData/Control/RunCycle")
local StructuresData = require("@game/ServerScriptService/GameData/Camp/Structures")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local LevelData = require("@game/ServerScriptService/GameData/Camp/Level")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local MinesRegistryData = require("@game/ServerScriptService/GameData/Mines/Registry")
local GenerationData = require("@game/ServerScriptService/GameData/Mines/Generation")
local BackpackData = require("@game/ServerScriptService/GameData/Mining/Backpack")
local BootsData = require("@game/ServerScriptService/GameData/Mining/Boots")
local PickAxeData = require("@game/ServerScriptService/GameData/Mining/PickAxe")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local RosterData = require("@game/ServerScriptService/GameData/Monsters/Roster")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local RefineryData = require("@game/ServerScriptService/GameData/Refinery/Refinery")
local RescueData = require("@game/ServerScriptService/GameData/Run/Rescue")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local WeightsData = require("@game/ServerScriptService/GameData/Rocks/Weights")
local MiningSuppliesData = require("@game/ServerScriptService/GameData/Store/MiningSupplies")
local WavesRegistryData = require("@game/ServerScriptService/GameData/Waves/Registry")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")

local BalanceAudit = {}
BalanceAudit.__index = BalanceAudit

type Result = BalanceModel.Result

export type BalanceAudit = typeof(setmetatable({} :: {}, BalanceAudit))

local TOWER_ATTACK_KINDS: BalanceModel.TowerAttackKinds = {
	SINGLE = Enums.TowerAttack.SINGLE,
	CONE = Enums.TowerAttack.CONE,
	CHAIN = Enums.TowerAttack.CHAIN,
}

local function label(map: number, difficulty: number, crew: number): string
	return string.format("%s %s, crew of %s", Enums.getPublicName(Enums.Map, map) or "?", Enums.getPublicName(Enums.Difficulty, difficulty) or "?", tostring(crew))
end

-- the handheld's sustained DPS and the default post's before upgrades
function BalanceAudit:handheldDps(): number
	local rifle = HandheldData.BY_KIND[HandheldData.DEFAULT_WEAPON]
	return BalanceModel.magazineDps(rifle.DAMAGE, rifle.FIRE_INTERVAL_SEC, rifle.MAGAZINE_SIZE, rifle.RELOAD_SEC)
end

function BalanceAudit:postDps(): number
	local post = PostWeaponsData.BY_KIND[PostWeaponsData.DEFAULT_POST_WEAPON]
	if post.HEAT then
		return BalanceModel.heatDps(post.DAMAGE, post.FIRE_INTERVAL_SEC, post.HEAT.FULL_SEC, post.HEAT.COOL_SEC)
	end
	return post.DAMAGE / post.FIRE_INTERVAL_SEC
end

-- the mine as the designer's balance sheet sees it, no grid built
function BalanceAudit:zoneSupplies(map: number, difficulty: number): { BalanceModel.ZoneSupply }?
	local mine = MinesRegistryData[map]
	if mine == nil then
		return nil
	end
	local config: MineGenerator.GeneratorConfig = {
		rockTable = RockDefinitionsData,
		spread = WeightsData.SPREAD,
		minCenter = WeightsData.MIN_CENTER,
		maxCenter = WeightsData.MAX_CENTER,
		hardnessShift = DifficultyData.HARDNESS_SHIFT,
		difficultyValue = DifficultyData.DIFFICULTY_VALUE[difficulty],
		veinDivisor = DifficultyData.VEIN_DIVISOR[difficulty],
		uraniumVeinDivisor = DifficultyData.URANIUM_VEIN_DIVISOR[difficulty],
		tierMinDepthBlocks = WeightsData.TIER_MIN_DEPTH_BLOCKS,
		pickaxeReachBlocks = GenerationData.PICKAXE_REACH_BLOCKS,
		isClimbingEnabled = GenerationData.IS_CLIMBING_ENABLED,
		maxPartyUraniumTargetMultiplier = 1,
	}
	local zones, errors = MineGenerator.preview(mine, config)
	if zones == nil then
		warn("BalanceAudit: mine preview failed:", table.concat(errors, "; "))
		return nil
	end
	local supplies = {}
	local depthStart = mine.entranceDepth or 0
	for index, zone in zones do
		local authored = mine.zones[index]
		local depth = if authored and authored.depth then authored.depth else 0
		table.insert(supplies, {
			ore = zone.requestedOre,
			hp = zone.expectedHp,
			depthStartBlocks = depthStart,
			depthBlocks = depth,
		})
		depthStart += depth
	end
	return supplies
end

function BalanceAudit:buildInput(map: number, difficulty: number, crew: number, nights: number): BalanceModel.Input?
	local defaultPost = PostWeaponsData.BY_KIND[PostWeaponsData.DEFAULT_POST_WEAPON]
	local zones = self:zoneSupplies(map, difficulty)
	local waves = WavesRegistryData[map]
	local settings = if waves then waves.GENERATOR[difficulty] else nil
	if zones == nil or settings == nil then
		return nil
	end
	local monsterByKind: { [number]: BalanceModel.MonsterStats } = {}
	for kind, stats in RosterData.BY_KIND do
		monsterByKind[kind] = {
			DIFFICULTY_VALUE = stats.DIFFICULTY_VALUE,
			MAX_HP = stats.MAX_HP,
			TRAVERSAL = stats.TRAVERSAL,
			DPS = stats.DAMAGE / (stats.ATTACK_INTERVAL_SEC or BehaviorData.DEFAULT_ATTACK_INTERVAL_SEC),
		}
	end
	local towerKinds = {}
	for kind in TowersData.BY_KIND do
		table.insert(towerKinds, kind)
	end
	table.sort(towerKinds)
	local mine = MinesRegistryData[map]
	return {
		assumptions = BalanceData.ASSUMPTIONS,
		crew = crew,
		nights = nights,
		daySec = RunCycleData.DAY_SEC,
		hitIntervalSec = PickAxeData.HIT_INTERVAL_SEC,
		pickDamageByLevel = PickAxeData.DAMAGE_BY_LEVEL,
		pickPriceByLevel = MiningSuppliesData.UPGRADES[Enums.StoreItem.PICK_AXE].priceByLevel,
		pickRequiredCampLevelByLevel = LevelData.MINING_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
		backpack = {
			valueByLevel = BackpackData.CAPACITY_BY_LEVEL,
			priceByLevel = MiningSuppliesData.UPGRADES[Enums.StoreItem.BACKPACK].priceByLevel,
			requiredCampLevelByLevel = LevelData.MINING_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
		},
		boots = {
			valueByLevel = BootsData.WALK_SPEED_BY_LEVEL,
			priceByLevel = MiningSuppliesData.UPGRADES[Enums.StoreItem.BOOTS].priceByLevel,
			requiredCampLevelByLevel = LevelData.MINING_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
		},
		refineSec = RefineryData.REFINE_DURATION_SEC,
		refineryToEntranceStuds = BalanceData.ASSUMPTIONS.REFINERY_TO_ENTRANCE_STUDS,
		blockSizeStuds = Constants.MINE_BLOCK_SIZE_STUDS,
		diamondsRequiredByLevel = LevelData.DIAMONDS_REQUIRED_BY_LEVEL,
		zones = zones,
		ironResource = Enums.RawResource.IRON_ORE,
		goldResource = Enums.RawResource.GOLD_ORE,
		crystalResource = Enums.RawResource.CRYSTAL,
		uraniumResource = Enums.RawResource.URANIUM_ORE,
		refineRateByRaw = RefineryData.RATE_BY_RAW,
		oreYieldMultiplier = RunCycleRules.multiplierFor(PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT, crew),
		uraniumTarget = RefineryRules.uraniumTarget(mine.uraniumTarget, crew, PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT, DifficultyData.URANIUM_TARGET_MULTIPLIER[difficulty]),
		waveSettings = settings,
		waveMultiplier = RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, crew),
		enemyHpMultiplier = RunCycleRules.multiplierFor(PartyScalingData.ENEMY_HP_MULTIPLIER_BY_PLAYER_COUNT, crew),
		monsterByKind = monsterByKind,
		airTraversal = Enums.MonsterTraversal.AIR,
		spawnWindowSec = waves.WAVE_SPAWN_LENGTH_SEC,
		minGroupDifficulty = waves.MIN_GROUP_DIFFICULTY * RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, crew),
		minGroupDifficultyPerNight = waves.MIN_GROUP_DIFFICULTY_PER_NIGHT * RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, crew),
		wallHp = StructuresData.BY_KIND[Enums.StructureKind.WALL].MAX_HP_BY_TIER[1],
		handheldDps = self:handheldDps(),
		postDps = self:postDps(),
		postUpgrades = {
			priceByLevel = PostWeaponsData.UPGRADE_PRICE_BY_LEVEL,
			requiredCampLevelByLevel = LevelData.POST_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
			damageBonusPerLevel = PostWeaponsData.BONUS_PER_LEVEL_BY_ATTRIBUTE[Enums.PostAttribute.DAMAGE],
			fireRateBonusPerLevel = PostWeaponsData.BONUS_PER_LEVEL_BY_ATTRIBUTE[Enums.PostAttribute.FIRE_RATE],
			cooldownBonusPerLevel = if defaultPost.HEAT then PostWeaponsData.BONUS_PER_LEVEL_BY_ATTRIBUTE[Enums.PostAttribute.COOLDOWN] else nil,
			heatFullSec = if defaultPost.HEAT then defaultPost.HEAT.FULL_SEC else nil,
			heatCoolSec = if defaultPost.HEAT then defaultPost.HEAT.COOL_SEC else nil,
		},
		towerKinds = towerKinds,
		towerByKind = TowersData.BY_KIND,
		towerAttackKinds = TOWER_ATTACK_KINDS,
		maxTowers = TowersData.MAX_ACTIVE_TOWERS_CAMP,
		finalWaveMultiplier = RescueData.FINAL_WAVE_MULTIPLIER,
	}
end

function BalanceAudit:auditNights(): number
	local longest = 0
	for _, nights in BalanceData.TARGET_NIGHTS do
		longest = math.max(longest, nights)
	end
	return longest + BalanceData.AUDIT_EXTRA_NIGHTS
end

-- the sheet for one run configuration, as Output lines
function BalanceAudit:describe(map: number, difficulty: number, crew: number): { string }
	local built = self:buildInput(map, difficulty, crew, self:auditNights())
	if built == nil then
		return { "No balance sheet: the map has no mine or no wave settings for this difficulty" }
	end
	local input = built :: BalanceModel.Input
	local result = BalanceModel.simulate(input)
	local lines = { label(map, difficulty, crew) .. string.format(" (waves %.2fx, enemy HP %.2fx, ore %.2fx, target night %d)", input.waveMultiplier, input.enemyHpMultiplier, input.oreYieldMultiplier, BalanceData.TARGET_NIGHTS[difficulty] or 0) }
	for _, line in BalanceModel.formatRows(result) do
		table.insert(lines, line)
	end
	local failures = BalanceModel.checkTargets(label(map, difficulty, crew), result, BalanceData.TARGET_NIGHTS[difficulty] or 0, nil, if crew == 1 then BalanceData.TARGET_NIGHT_TOLERANCE else BalanceData.CREW_TARGET_NIGHT_TOLERANCE)
	if crew == 1 then
		for _, failure in BalanceModel.checkWallPressure(label(map, difficulty, crew), result, BalanceData.BREACH_NIGHT[difficulty], BalanceData.MAX_WALL_DAMAGE_SHARE, BalanceData.TARGET_NIGHTS[difficulty]) do
			table.insert(failures, failure)
		end
		for _, failure in BalanceModel.checkGold(label(map, difficulty, crew), result, BalanceData.GOLD_BY_NIGHT_1) do
			table.insert(failures, failure)
		end
	end
	if #failures == 0 then
		table.insert(lines, "on target")
	end
	for _, failure in failures do
		table.insert(lines, "MISS: " .. failure)
	end
	return lines
end

-- every map, difficulty, and audited crew size against the targets; the
-- failures, empty when the data is on target
function BalanceAudit:auditAll(): { string }
	local failures = {}
	local nights = self:auditNights()
	local difficulties = Enums.getAllValues(Enums.Difficulty)
	table.sort(difficulties)
	for _, map in BalanceData.AUDITED_MAPS do
		local soloByDifficulty: { Result } = {}
		local labels = {}
		local targetNights = {}
		for _, difficulty in difficulties do
			local solo: BalanceModel.Result? = nil
			for _, crew in BalanceData.AUDIT_CREW_SIZES do
				local input = self:buildInput(map, difficulty, crew, nights)
				if input == nil then
					table.insert(failures, label(map, difficulty, crew) .. " has no mine or no wave settings")
					continue
				end
				local result = BalanceModel.simulate(input)
				local runLabel = label(map, difficulty, crew)
				for _, failure in BalanceModel.checkTargets(runLabel, result, BalanceData.TARGET_NIGHTS[difficulty] or 0, nil, if crew == 1 then BalanceData.TARGET_NIGHT_TOLERANCE else BalanceData.CREW_TARGET_NIGHT_TOLERANCE) do
					table.insert(failures, failure)
				end
				if crew == 1 then
					for _, failure in BalanceModel.checkWallPressure(runLabel, result, BalanceData.BREACH_NIGHT[difficulty], BalanceData.MAX_WALL_DAMAGE_SHARE, BalanceData.TARGET_NIGHTS[difficulty]) do
						table.insert(failures, failure)
					end
					for _, failure in BalanceModel.checkGold(runLabel, result, BalanceData.GOLD_BY_NIGHT_1) do
						table.insert(failures, failure)
					end
				end
				if crew == 1 then
					solo = result
				elseif solo ~= nil then
					for _, failure in BalanceModel.checkCrewParity(runLabel, solo, result, BalanceData.CREW_PARITY_NIGHTS) do
						table.insert(failures, failure)
					end
				end
			end
			if solo ~= nil then
				table.insert(soloByDifficulty, solo)
				table.insert(labels, (Enums.getPublicName(Enums.Map, map) or "?") .. " " .. (Enums.getPublicName(Enums.Difficulty, difficulty) or "?"))
				table.insert(targetNights, BalanceData.TARGET_NIGHTS[difficulty] or 0)
			end
		end
		for _, failure in BalanceModel.checkMonotonic(labels, soloByDifficulty, targetNights) do
			table.insert(failures, failure)
		end
	end
	return failures
end

function BalanceAudit:init()
	local failures = self:auditAll()
	if #failures == 0 then
		print("[BalanceAudit] every map and difficulty is on target")
		return
	end
	warn(string.format("[BalanceAudit] %d balance target(s) missed (docs/balance-plan.md):\n  %s", #failures, table.concat(failures, "\n  ")))
end

function BalanceAudit.new(): BalanceAudit
	local self = setmetatable({}, BalanceAudit) :: BalanceAudit
	return self
end

return BalanceAudit.new()
