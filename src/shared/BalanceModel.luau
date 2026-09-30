--!strict

-- The balance sheet (docs/balance-plan.md, 2026-09-28): a pure model of a
-- run, night by night, from the numbers GameData holds. Every day the
-- crew swings at rock for a share of the day, the HP it chews through is
-- turned into ore at the current zone's ore-per-HP, the ore refines, Gold
-- buys pick axe levels and Iron buys the towers with the best DPS per
-- Iron; every night the wave generator's budget becomes expected HP from
-- the kinds unlocked, and the crew's free weapons plus its towers are
-- measured against it. The output is a row per night and a list of
-- failures against the designer's targets, so a tuning change is judged
-- here before anyone plays it. The model never reads GameData or Roblox
-- services: BalanceAudit (gameplay server) feeds it, the spec feeds it
-- fixtures. Its guesses about how people play are the ASSUMPTIONS in
-- GameData/Control/Balance, to be corrected from run reports.
local WaveGenerator = require(script.Parent.WaveGenerator)

local BalanceModel = {}

export type Assumptions = {
	-- seconds of a day not spent mining or walking ore to the refinery:
	-- shopping, building, dusk
	DAY_OVERHEAD_SEC: number,
	ORE_SELECTIVITY: number,
	GOLD_SELECTIVITY: number,
	ZONE_ADVANCE_SHARE: number,
	TOWER_COVERAGE: number,
	WEAPON_UPTIME: number,
	CLEAR_SLACK_SEC: number,
	DEFENSE_IRON_SHARE: number,
	PICK_AXE_GOLD_SHARE: number,
	BACKPACK_GOLD_SHARE: number,
	BOOTS_GOLD_SHARE: number,
	URANIUM_SELECTIVITY: number,
	TOWER_NEEDED_SLACK: number,
	CREW_ADVANCE_EXPONENT: number,
	POST_GOLD_SHARE: number,
	POST_EFFECTIVENESS: number,
	WALL_WALK_SEC: number,
	WALL_SEGMENTS_HIT: number,
}

-- a post's upgrade ladder: each attribute climbs its own levels for the
-- same Gold prices, each level gated by the camp level
export type PostUpgrades = {
	priceByLevel: { number },
	requiredCampLevelByLevel: { number },
	damageBonusPerLevel: number,
	fireRateBonusPerLevel: number,
	-- the machine gun's Cooldown rung (2026-09-30): each level cuts the
	-- cooling time by this share of the authored one, so the gun fires a
	-- bigger share of the time. Absent for a post without heat
	cooldownBonusPerLevel: number?,
	heatFullSec: number?,
	heatCoolSec: number?,
}

export type MonsterStats = {
	DIFFICULTY_VALUE: number,
	MAX_HP: number,
	TRAVERSAL: number,
	-- damage per second it deals to whatever it stands at
	DPS: number,
}

export type TowerLevelStats = {
	DAMAGE: number?,
	FIRE_INTERVAL_SEC: number?,
	FLAME_SEC: number?,
	CHAIN_COUNT: number?,
	MAX_HP: number,
}

export type TowerBehavior = {
	ATTACK: number,
	TICK_INTERVAL_SEC: number?,
	REST_SEC: number?,
}

export type TowerData = {
	BUILD_PRICE_IRON: number,
	UPGRADE_PRICE_IRON_BY_LEVEL: { number },
	BEHAVIOR: TowerBehavior,
	STATS_BY_LEVEL: { TowerLevelStats },
}

-- the Enums.TowerAttack values, passed in so the model has no enum dependency
export type TowerAttackKinds = {
	SINGLE: number,
	CONE: number,
	CHAIN: number,
}

-- one zone as MineGenerator.preview reports it: expected ore by raw
-- resource and the HP a crew must chew through, plus where it sits so
-- the walk to the refinery can grow with it
export type ZoneSupply = {
	ore: { [number]: number },
	hp: number,
	depthStartBlocks: number,
	depthBlocks: number,
}

-- a mining upgrade ladder bought with Gold, camp-level gated
export type UpgradeLadder = {
	valueByLevel: { number },
	priceByLevel: { number },
	requiredCampLevelByLevel: { number },
}

export type Input = {
	assumptions: Assumptions,
	crew: number,
	nights: number,
	daySec: number,
	hitIntervalSec: number,
	pickDamageByLevel: { number },
	-- Gold to reach each level; [1] is 0
	pickPriceByLevel: { number },
	pickRequiredCampLevelByLevel: { number },
	-- ore units a player carries before walking back, by level
	backpack: UpgradeLadder,
	-- walk speed in studs a second, by level
	boots: UpgradeLadder,
	-- the refinery's grind, and the walk from it to the mine mouth
	refineSec: number,
	refineryToEntranceStuds: number,
	blockSizeStuds: number,
	-- Diamonds to reach the next camp level, one entry per step
	diamondsRequiredByLevel: { number },
	zones: { ZoneSupply },
	ironResource: number,
	goldResource: number,
	crystalResource: number,
	uraniumResource: number,
	refineRateByRaw: { [number]: number },
	oreYieldMultiplier: number,
	-- already scaled for the crew and the difficulty
	uraniumTarget: number,
	waveSettings: WaveGenerator.Settings,
	waveMultiplier: number,
	enemyHpMultiplier: number,
	monsterByKind: { [number]: MonsterStats },
	airTraversal: number,
	spawnWindowSec: number,
	-- the map's group rule times the crew's multiplier: a night makes one
	-- group for every this much of its budget
	minGroupDifficulty: number,
	-- a tier 1 wall segment's HP, the thing a night's leak beats on
	wallHp: number,
	-- sustained DPS of the handheld, and of a manned post before upgrades
	handheldDps: number,
	postDps: number,
	postUpgrades: PostUpgrades?,
	towerKinds: { number },
	towerByKind: { [number]: TowerData },
	towerAttackKinds: TowerAttackKinds,
	-- the camp's tower cap, shared by the crew
	maxTowers: number,
	-- the rescue's final wave is the next night's budget times this
	finalWaveMultiplier: number,
}

export type NightRow = {
	night: number,
	zone: number,
	pickLevel: number,
	campLevel: number,
	postLevel: number,
	backpackLevel: number,
	bootsLevel: number,
	-- seconds of the day spent swinging, after trips and overhead
	miningSec: number,
	ironPerPlayer: number,
	goldPerPlayer: number,
	uraniumTotal: number,
	budget: number,
	unlockedCount: number,
	waveHp: number,
	airHpShare: number,
	freeDps: number,
	towerDps: number,
	towerCount: number,
	requiredDps: number,
	slack: number,
	freeOnlySlack: number,
	clearSec: number,
	-- slack against the final wave a rescue called this day would bring
	finalWaveSlack: number,
	-- expected damage to the most-hit wall segment, as a share of its HP
	wallDamageShare: number,
}

export type Result = {
	rows: { NightRow },
	uraniumTarget: number,
	-- the day the target was refined, nil when the run never gets there
	uraniumNight: number?,
	-- the first night the free weapons alone fall under TOWER_NEEDED_SLACK
	firstTowerNight: number?,
	-- the first night the leak's expected wall damage reaches a wall's HP
	breachNight: number?,
}

type PlannedTower = {
	kind: number,
	level: number,
}

-- a magazine weapon: damage per shot over the shots plus the reload
function BalanceModel.magazineDps(damage: number, fireIntervalSec: number, magazineSize: number, reloadSec: number): number
	local cycleSec = magazineSize * fireIntervalSec + reloadSec
	if cycleSec <= 0 then
		return 0
	end
	return damage * magazineSize / cycleSec
end

-- a heat weapon: full rate until it overheats, silent while it cools
function BalanceModel.heatDps(damage: number, fireIntervalSec: number, fullSec: number, coolSec: number): number
	if fireIntervalSec <= 0 or fullSec + coolSec <= 0 then
		return 0
	end
	return damage / fireIntervalSec * fullSec / (fullSec + coolSec)
end

-- paper DPS of one tower at a level against a single target; a cone
-- burns for FLAME_SEC then rests, a chain hits its target and CHAIN_COUNT more
function BalanceModel.towerDps(data: TowerData, level: number, attackKinds: TowerAttackKinds): number
	local stats = data.STATS_BY_LEVEL[level]
	if stats == nil then
		return 0
	end
	local damage = stats.DAMAGE or 0
	local behavior = data.BEHAVIOR
	if behavior.ATTACK == attackKinds.CONE then
		local tickSec = behavior.TICK_INTERVAL_SEC or 0
		local flameSec = stats.FLAME_SEC or 0
		local restSec = behavior.REST_SEC or 0
		if tickSec <= 0 or flameSec + restSec <= 0 then
			return 0
		end
		return damage / tickSec * flameSec / (flameSec + restSec)
	end
	local intervalSec = stats.FIRE_INTERVAL_SEC or 0
	if intervalSec <= 0 then
		return 0
	end
	local perShot = damage / intervalSec
	if behavior.ATTACK == attackKinds.CHAIN then
		return perShot * (1 + (stats.CHAIN_COUNT or 0))
	end
	return perShot
end

-- expected HP per difficulty point when every unlocked kind is equally
-- likely, and the share of that HP that flies
function BalanceModel.expectedHpPerPoint(kinds: { number }, monsterByKind: { [number]: MonsterStats }, airTraversal: number): (number, number)
	if #kinds == 0 then
		return 0, 0
	end
	local total = 0
	local airTotal = 0
	for _, kind in kinds do
		local stats = monsterByKind[kind]
		if stats == nil or stats.DIFFICULTY_VALUE <= 0 then
			continue
		end
		local hpPerPoint = stats.MAX_HP / stats.DIFFICULTY_VALUE
		total += hpPerPoint
		if stats.TRAVERSAL == airTraversal then
			airTotal += hpPerPoint
		end
	end
	local mean = total / #kinds
	local airShare = if total > 0 then airTotal / total else 0
	return mean, airShare
end

-- the leak: a night spawns as a few groups, each a burst. The crew shoots
-- a group from the moment it spawns, so the walk to the wall kills
-- dps x walk of it; what is left arrives together and is killed off over
-- its HP / dps seconds, its HP falling evenly to nothing, so the
-- HP-seconds it spends beating on the wall are survivors squared over
-- twice the dps. Groups are taken one at a time (a group still standing
-- when the next arrives would only add to this)
function BalanceModel.wallHpSeconds(waveHp: number, groupCount: number, dps: number, walkSec: number): number
	if waveHp <= 0 then
		return 0
	end
	if dps <= 0 then
		return math.huge
	end
	local groups = math.max(math.floor(groupCount), 1)
	local groupHp = waveHp / groups
	local survivors = math.max(groupHp - dps * walkSec, 0)
	return groups * survivors * survivors / (2 * dps)
end

-- wall DPS per HP alive at the wall over the unlocked kinds that walk,
-- and the share of the wave's HP that walks (fliers pass the wall)
function BalanceModel.wallPressure(kinds: { number }, monsterByKind: { [number]: MonsterStats }, airTraversal: number): (number, number)
	local landHpPerPoint = 0
	local landDpsPerPoint = 0
	local allHpPerPoint = 0
	for _, kind in kinds do
		local stats = monsterByKind[kind]
		if stats == nil or stats.DIFFICULTY_VALUE <= 0 then
			continue
		end
		local hpPerPoint = stats.MAX_HP / stats.DIFFICULTY_VALUE
		allHpPerPoint += hpPerPoint
		if stats.TRAVERSAL ~= airTraversal then
			landHpPerPoint += hpPerPoint
			landDpsPerPoint += stats.DPS / stats.DIFFICULTY_VALUE
		end
	end
	if landHpPerPoint <= 0 or allHpPerPoint <= 0 then
		return 0, 0
	end
	return landDpsPerPoint / landHpPerPoint, landHpPerPoint / allHpPerPoint
end

-- how a crew spends an Iron budget on towers: every step takes the build
-- or upgrade with the most DPS per Iron it can afford, until nothing fits
function BalanceModel.planTowers(ironBudget: number, kinds: { number }, towerByKind: { [number]: TowerData }, maxTowers: number, attackKinds: TowerAttackKinds): (number, number, number)
	local towers: { PlannedTower } = {}
	local remaining = ironBudget
	local spent = 0
	while true do
		local bestGainPerIron = 0
		local bestCost = 0
		local bestBuildKind: number? = nil
		local bestUpgradeIndex: number? = nil
		if #towers < maxTowers then
			for _, kind in kinds do
				local data = towerByKind[kind]
				if data == nil then
					continue
				end
				local cost = data.BUILD_PRICE_IRON
				local gain = BalanceModel.towerDps(data, 1, attackKinds)
				if cost <= 0 or cost > remaining or gain <= 0 then
					continue
				end
				if gain / cost > bestGainPerIron then
					bestGainPerIron = gain / cost
					bestCost = cost
					bestBuildKind = kind
					bestUpgradeIndex = nil
				end
			end
		end
		for index, tower in towers do
			local data = towerByKind[tower.kind]
			local cost = data.UPGRADE_PRICE_IRON_BY_LEVEL[tower.level]
			if cost == nil or cost <= 0 or cost > remaining then
				continue
			end
			local gain = BalanceModel.towerDps(data, tower.level + 1, attackKinds) - BalanceModel.towerDps(data, tower.level, attackKinds)
			if gain <= 0 then
				continue
			end
			if gain / cost > bestGainPerIron then
				bestGainPerIron = gain / cost
				bestCost = cost
				bestBuildKind = nil
				bestUpgradeIndex = index
			end
		end
		if bestBuildKind == nil and bestUpgradeIndex == nil then
			break
		end
		if bestBuildKind ~= nil then
			table.insert(towers, { kind = bestBuildKind, level = 1 })
		else
			towers[bestUpgradeIndex :: number].level += 1
		end
		remaining -= bestCost
		spent += bestCost
	end
	local dps = 0
	for _, tower in towers do
		dps += BalanceModel.towerDps(towerByKind[tower.kind], tower.level, attackKinds)
	end
	return dps, #towers, spent
end

-- how much of a mining window is spent swinging when every backpack
-- load is walked to the refinery and back: ore arrives at `orePerSec`
-- while swinging, a trip takes `tripSec` every `capacity` ore, so the
-- swinging time m solves m + m x orePerSec / capacity x tripSec = window
function BalanceModel.miningSeconds(windowSec: number, orePerSec: number, capacity: number, tripSec: number): number
	if windowSec <= 0 then
		return 0
	end
	if capacity <= 0 or orePerSec <= 0 or tripSec <= 0 then
		return windowSec
	end
	return windowSec / (1 + orePerSec / capacity * tripSec)
end

-- a mining ladder's level for the Gold, one level at a time, camp gated;
-- the pick axe, the backpack, and the boots all climb this way
function BalanceModel.affordableLadderLevel(goldSpendable: number, priceByLevel: { number }, requiredCampLevelByLevel: { number }, campLevel: number): (number, number)
	return BalanceModel.affordablePickLevel(goldSpendable, priceByLevel, requiredCampLevelByLevel, campLevel)
end

-- the pick axe level a player's Gold buys, one level at a time, each
-- gated by the camp level
function BalanceModel.affordablePickLevel(goldSpendable: number, priceByLevel: { number }, requiredCampLevelByLevel: { number }, campLevel: number): (number, number)
	local level = 1
	local spent = 0
	while priceByLevel[level + 1] ~= nil do
		local price = priceByLevel[level + 1]
		local required = requiredCampLevelByLevel[level + 1] or 1
		if spent + price > goldSpendable or required > campLevel then
			break
		end
		spent += price
		level += 1
	end
	return level, spent
end

-- how many post upgrade levels a player's Gold buys, damage and fire
-- rate alternating so both climb, each level gated by the camp level;
-- returns the damage level, the fire rate level, and the Gold spent
-- the post's rungs bought in turn, damage first, then fire rate, then (for
-- a gun with heat) cooldown, each round taking the cheapest next rung
function BalanceModel.affordablePostLevels(goldSpendable: number, upgrades: PostUpgrades, campLevel: number): (number, number, number, number)
	local levels = { 0, 0, 0 }
	local attributeCount = if upgrades.cooldownBonusPerLevel then 3 else 2
	local spent = 0
	while true do
		local lowest = 1
		for index = 2, attributeCount do
			if levels[index] < levels[lowest] then
				lowest = index
			end
		end
		local nextLevel = levels[lowest] + 1
		local price = upgrades.priceByLevel[nextLevel]
		local required = upgrades.requiredCampLevelByLevel[nextLevel] or 1
		if price == nil or spent + price > goldSpendable or required > campLevel then
			break
		end
		spent += price
		levels[lowest] += 1
	end
	return levels[1], levels[2], spent, levels[3]
end

-- how much more a gun with heat fires once its cooling time is cut by the
-- Cooldown rungs: the new firing share over the authored one
function BalanceModel.cooldownFactor(upgrades: PostUpgrades, cooldownLevel: number): number
	local fullSec = upgrades.heatFullSec
	local coolSec = upgrades.heatCoolSec
	local bonus = upgrades.cooldownBonusPerLevel
	if not fullSec or not coolSec or not bonus or fullSec + coolSec <= 0 then
		return 1
	end
	local cooledSec = math.max(coolSec * (1 - bonus * cooldownLevel), 0)
	return (fullSec / (fullSec + cooledSec)) / (fullSec / (fullSec + coolSec))
end

-- the camp level a shared Diamond total has reached, each step costing
-- its own entry
function BalanceModel.campLevelFor(diamonds: number, requiredByLevel: { number }): number
	local level = 1
	local remaining = diamonds
	for _, required in requiredByLevel do
		if remaining < required then
			break
		end
		remaining -= required
		level += 1
	end
	return level
end

function BalanceModel.simulate(input: Input): Result
	local assumptions = input.assumptions
	local crew = math.max(input.crew, 1)
	local rows: { NightRow } = {}
	local zoneIndex = 1
	local minedInZone = 0
	local oreLeftInZone: { [number]: number } = table.clone(input.zones[1].ore)
	local ironTotal = 0
	local goldTotal = 0
	local diamondsTotal = 0
	local uraniumTotal = 0
	local uraniumNight: number? = nil
	local firstTowerNight: number? = nil
	local breachNight: number? = nil
	local pickLevel = 1
	local backpackLevel = 1
	local bootsLevel = 1
	local campLevel = 1
	local difficultyValueByKind: { [number]: number } = {}
	for kind, stats in input.monsterByKind do
		difficultyValueByKind[kind] = stats.DIFFICULTY_VALUE
	end
	local rateOf = function(resource: number): number
		return input.refineRateByRaw[resource] or 1
	end

	for night = 1, input.nights do
		-- the day: the crew swings for what is left of the day after the
		-- overhead and the trips. Each backpack load walks from the tunnel
		-- front (the zone's depth so far) to the refinery and back; the
		-- front is deeper and the loads are the same size, so trips eat
		-- more of the day as the run goes on unless the backpack grows
		local frontZone = input.zones[zoneIndex]
		local frontProgress = if frontZone.hp > 0 then math.min(minedInZone / (frontZone.hp * assumptions.ZONE_ADVANCE_SHARE), 1) else 0
		local frontDepthStuds = (frontZone.depthStartBlocks + frontZone.depthBlocks * frontProgress) * input.blockSizeStuds
		local walkStuds = input.refineryToEntranceStuds + frontDepthStuds
		local walkSpeed = input.boots.valueByLevel[bootsLevel]
		local tripSec = 2 * walkStuds / math.max(walkSpeed, 1) + input.refineSec
		local pickDps = input.pickDamageByLevel[pickLevel] / input.hitIntervalSec
		local oreOfFront = 0
		for resource, amount in frontZone.ore do
			local selectivity = if resource == input.uraniumResource then assumptions.URANIUM_SELECTIVITY elseif resource == input.goldResource then assumptions.GOLD_SELECTIVITY else assumptions.ORE_SELECTIVITY
			oreOfFront += amount * selectivity
		end
		local orePerSec = if frontZone.hp > 0 then pickDps * oreOfFront / frontZone.hp else 0
		local miningSec = BalanceModel.miningSeconds(input.daySec - assumptions.DAY_OVERHEAD_SEC, orePerSec, input.backpack.valueByLevel[backpackLevel], tripSec)
		-- HP mined becomes ore at the zone's density. A crew strips a zone
		-- more than it advances the tunnel front: the front moves with the
		-- crew's HP to CREW_ADVANCE_EXPONENT, the ore comes from all of it
		-- (capped by what the zone holds)
		local hpMined = crew * miningSec * pickDps
		local frontShare = crew ^ (assumptions.CREW_ADVANCE_EXPONENT - 1)
		local frontRemaining = hpMined * frontShare
		local dayOre: { [number]: number } = {}
		while frontRemaining > 0 do
			local zone = input.zones[zoneIndex]
			local isLastZone = zoneIndex >= #input.zones
			local capacity = if isLastZone then zone.hp else zone.hp * assumptions.ZONE_ADVANCE_SHARE
			local available = capacity - minedInZone
			if available <= 0 then
				if isLastZone then
					break
				end
				zoneIndex += 1
				minedInZone = 0
				oreLeftInZone = table.clone(input.zones[zoneIndex].ore)
				continue
			end
			local frontTake = math.min(frontRemaining, available)
			local hpTake = frontTake / frontShare
			for resource, amount in zone.ore do
				if zone.hp <= 0 then
					continue
				end
				-- uranium hums, so a crew hunts it harder than the ore it sees;
				-- gold is taken as it comes while the crew digs for Iron
				local selectivity = if resource == input.uraniumResource then assumptions.URANIUM_SELECTIVITY elseif resource == input.goldResource then assumptions.GOLD_SELECTIVITY else assumptions.ORE_SELECTIVITY
				local gained = math.min(hpTake / zone.hp * amount * selectivity, oreLeftInZone[resource] or 0)
				oreLeftInZone[resource] = (oreLeftInZone[resource] or 0) - gained
				dayOre[resource] = (dayOre[resource] or 0) + gained
			end
			minedInZone += frontTake
			frontRemaining -= frontTake
			if isLastZone and minedInZone >= capacity then
				break
			end
		end
		ironTotal += (dayOre[input.ironResource] or 0) * input.oreYieldMultiplier * rateOf(input.ironResource)
		goldTotal += (dayOre[input.goldResource] or 0) * input.oreYieldMultiplier * rateOf(input.goldResource)
		diamondsTotal += (dayOre[input.crystalResource] or 0) * rateOf(input.crystalResource)
		uraniumTotal += (dayOre[input.uraniumResource] or 0) * rateOf(input.uraniumResource)
		if uraniumNight == nil and uraniumTotal >= input.uraniumTarget then
			uraniumNight = night
		end

		-- the shops: Diamonds raise the camp, Gold raises the pick axe and
		-- the player's post
		campLevel = BalanceModel.campLevelFor(diamondsTotal, input.diamondsRequiredByLevel)
		local goldPerPlayer = goldTotal / crew
		pickLevel = BalanceModel.affordablePickLevel(goldPerPlayer * assumptions.PICK_AXE_GOLD_SHARE, input.pickPriceByLevel, input.pickRequiredCampLevelByLevel, campLevel)
		backpackLevel = BalanceModel.affordableLadderLevel(goldPerPlayer * assumptions.BACKPACK_GOLD_SHARE, input.backpack.priceByLevel, input.backpack.requiredCampLevelByLevel, campLevel)
		bootsLevel = BalanceModel.affordableLadderLevel(goldPerPlayer * assumptions.BOOTS_GOLD_SHARE, input.boots.priceByLevel, input.boots.requiredCampLevelByLevel, campLevel)
		local postDps = input.postDps
		local postLevel = 0
		local postUpgrades = input.postUpgrades
		if postUpgrades ~= nil then
			local damageLevel, rateLevel, _, cooldownLevel = BalanceModel.affordablePostLevels(goldPerPlayer * assumptions.POST_GOLD_SHARE, postUpgrades, campLevel)
			postDps *= (1 + postUpgrades.damageBonusPerLevel * damageLevel) * (1 + postUpgrades.fireRateBonusPerLevel * rateLevel) * BalanceModel.cooldownFactor(postUpgrades, cooldownLevel)
			postLevel = damageLevel + rateLevel + cooldownLevel
		end
		-- the post's paper DPS assumes every shot lands and the trigger is
		-- released the instant it would overheat; a player manages less
		local freeDpsPerPlayer = math.max(input.handheldDps, postDps * assumptions.POST_EFFECTIVENESS)

		-- the night: budget to HP, HP against DPS
		local budget = WaveGenerator.targetDifficulty(input.waveSettings, night, input.waveMultiplier)
		local unlocked = WaveGenerator.unlockedKinds(input.waveSettings, night, difficultyValueByKind)
		local hpPerPoint, airShare = BalanceModel.expectedHpPerPoint(unlocked, input.monsterByKind, input.airTraversal)
		local waveHp = budget * hpPerPoint * input.enemyHpMultiplier
		local freeDps = crew * freeDpsPerPlayer * assumptions.WEAPON_UPTIME
		local towerDps, towerCount = BalanceModel.planTowers(ironTotal * assumptions.DEFENSE_IRON_SHARE, input.towerKinds, input.towerByKind, input.maxTowers, input.towerAttackKinds)
		towerDps *= assumptions.TOWER_COVERAGE
		local clearWindowSec = input.spawnWindowSec + assumptions.CLEAR_SLACK_SEC
		local requiredDps = waveHp / clearWindowSec
		local availableDps = freeDps + towerDps
		local slack = if requiredDps > 0 then availableDps / requiredDps else math.huge
		local freeOnlySlack = if requiredDps > 0 then freeDps / requiredDps else math.huge
		if firstTowerNight == nil and freeOnlySlack < assumptions.TOWER_NEEDED_SLACK then
			firstTowerNight = night
		end
		local wallDpsPerHp, landShare = BalanceModel.wallPressure(unlocked, input.monsterByKind, input.airTraversal)
		local groupCount = WaveGenerator.groupCount(budget, input.minGroupDifficulty)
		local wallDamage = BalanceModel.wallHpSeconds(waveHp, groupCount, availableDps, assumptions.WALL_WALK_SEC) * landShare * wallDpsPerHp
		-- the leak spreads over a few segments and the gate; the breach is
		-- the one that takes its share
		local wallDamageShare = if input.wallHp > 0 then wallDamage / (input.wallHp * math.max(assumptions.WALL_SEGMENTS_HIT, 1)) else 0
		if breachNight == nil and wallDamageShare >= 1 then
			breachNight = night
		end
		table.insert(rows, {
			night = night,
			zone = zoneIndex,
			pickLevel = pickLevel,
			campLevel = campLevel,
			postLevel = postLevel,
			backpackLevel = backpackLevel,
			bootsLevel = bootsLevel,
			miningSec = miningSec,
			ironPerPlayer = ironTotal / crew,
			goldPerPlayer = goldPerPlayer,
			uraniumTotal = uraniumTotal,
			budget = budget,
			unlockedCount = #unlocked,
			waveHp = waveHp,
			airHpShare = airShare,
			freeDps = freeDps,
			towerDps = towerDps,
			towerCount = towerCount,
			requiredDps = requiredDps,
			slack = slack,
			freeOnlySlack = freeOnlySlack,
			clearSec = if availableDps > 0 then waveHp / availableDps else math.huge,
			finalWaveSlack = math.huge,
			wallDamageShare = wallDamageShare,
		})
	end
	-- the final wave: a rescue called on day N brings night N + 1's wave
	-- scaled up, fought with day N's defenses
	for index, row in rows do
		local nextRow = rows[index + 1]
		if nextRow == nil then
			continue
		end
		local finalRequired = nextRow.requiredDps * input.finalWaveMultiplier
		row.finalWaveSlack = if finalRequired > 0 then (row.freeDps + row.towerDps) / finalRequired else math.huge
	end
	return {
		rows = rows,
		uraniumTarget = input.uraniumTarget,
		uraniumNight = uraniumNight,
		firstTowerNight = firstTowerNight,
		breachNight = breachNight,
	}
end

-- the leak should leave a wall standing two nights before the breach
-- night, nearly break one the night before, and break one on it; and on
-- no night up to targetNight may it exceed maxWallDamageShare of a wall,
-- since a breach of several walls' worth reaches the Refinery (2026-09-30)
function BalanceModel.checkWallPressure(label: string, result: Result, breachNight: number, maxWallDamageShare: number?, targetNight: number?): { string }
	local failures = {}
	if maxWallDamageShare then
		for _, row in result.rows do
			if targetNight and row.night > targetNight then
				break
			end
			if row.wallDamageShare > maxWallDamageShare then
				table.insert(failures, string.format("%s night %d leaks %.0f%% of a wall, over the %.0f%% a breach may do", label, row.night, row.wallDamageShare * 100, maxWallDamageShare * 100))
			end
		end
	end
	local dent = result.rows[breachNight - 2]
	local near = result.rows[breachNight - 1]
	if dent ~= nil and dent.wallDamageShare >= 0.9 then
		table.insert(failures, string.format("%s night %d should leave a wall standing (under 90%%), the leak does %.0f%%", label, breachNight - 2, dent.wallDamageShare * 100))
	end
	-- a breach on night 2 asks nothing of night 1: the free weapons alone
	-- clear a first night on every difficulty
	if near ~= nil and breachNight - 1 >= 2 and (near.wallDamageShare < 0.5 or near.wallDamageShare >= 1) then
		table.insert(failures, string.format("%s night %d should nearly break a wall (50%% to 100%%), the leak does %.0f%%", label, breachNight - 1, near.wallDamageShare * 100))
	end
	if result.breachNight == nil then
		table.insert(failures, string.format("%s never breaks a wall in %d nights; night %d should", label, #result.rows, breachNight))
	elseif result.breachNight ~= breachNight then
		table.insert(failures, string.format("%s first breaks a wall on night %d, not night %d", label, result.breachNight, breachNight))
	end
	return failures
end

-- every difficulty's budget must be at least the easier one's on every
-- night the easier one is meant to reach (its target night), or the
-- labels lie; past that the easier run is over and its curve is moot
function BalanceModel.checkMonotonic(labels: { string }, resultsInOrder: { Result }, targetNights: { number }): { string }
	local failures = {}
	for index = 2, #resultsInOrder do
		local easier = resultsInOrder[index - 1]
		local harder = resultsInOrder[index]
		for night, row in harder.rows do
			local easierRow = easier.rows[night]
			if easierRow == nil or night > (targetNights[index - 1] or math.huge) then
				continue
			end
			if row.budget < easierRow.budget then
				table.insert(failures, string.format("%s night %d budget %.0f is below %s's %.0f", labels[index], night, row.budget, labels[index - 1], easierRow.budget))
			end
			if row.unlockedCount < easierRow.unlockedCount then
				table.insert(failures, string.format("%s night %d has %d kinds unlocked, fewer than %s's %d", labels[index], night, row.unlockedCount, labels[index - 1], easierRow.unlockedCount))
			end
		end
	end
	return failures
end

-- the run must be survivable up to the target night, need towers from
-- the chosen night on, and refine the target by the target night
function BalanceModel.checkTargets(label: string, result: Result, targetNight: number, towersNeededNight: number?, targetTolerance: number): { string }
	local failures = {}
	for _, row in result.rows do
		if row.night > targetNight then
			break
		end
		if row.slack < 1 then
			table.insert(failures, string.format("%s night %d is not clearable on time: %.0f DPS against %.0f needed (slack %.2f)", label, row.night, row.freeDps + row.towerDps, row.requiredDps, row.slack))
		end
	end
	local targetRow = result.rows[targetNight]
	if targetRow ~= nil and targetRow.finalWaveSlack < 1 then
		table.insert(failures, string.format("%s cannot hold the final wave on day %d: %.0f DPS gives slack %.2f", label, targetNight, targetRow.freeDps + targetRow.towerDps, targetRow.finalWaveSlack))
	end
	local firstTowerNight = result.firstTowerNight
	if towersNeededNight == nil then
		-- a crew's free weapons outgrow the early nights; only solo is held to it
	elseif firstTowerNight == nil then
		table.insert(failures, string.format("%s never needs a tower up to night %d", label, #result.rows))
	elseif firstTowerNight < towersNeededNight then
		table.insert(failures, string.format("%s needs a tower on night %d, before night %d", label, firstTowerNight, towersNeededNight))
	elseif firstTowerNight > towersNeededNight then
		table.insert(failures, string.format("%s first needs a tower on night %d, after night %d", label, firstTowerNight, towersNeededNight))
	end
	local uraniumNight = result.uraniumNight
	if uraniumNight == nil then
		table.insert(failures, string.format("%s never refines %d uranium in %d nights", label, result.uraniumTarget, #result.rows))
	elseif math.abs(uraniumNight - targetNight) > targetTolerance then
		table.insert(failures, string.format("%s refines the uranium target on day %d, the target is day %d", label, uraniumNight, targetNight))
	end
	return failures
end

-- a player should hold this much Gold by the end of night 1, enough for
-- a first mining or post upgrade
function BalanceModel.checkGold(label: string, result: Result, goldByNight1: number): { string }
	local first = result.rows[1]
	if first ~= nil and first.goldPerPlayer < goldByNight1 then
		return { string.format("%s ends night 1 with %.0f Gold a player, under %d", label, first.goldPerPlayer, goldByNight1) }
	end
	return {}
end

-- a crew of any size should reach the target within a night of solo
function BalanceModel.checkCrewParity(label: string, solo: Result, crewResult: Result, parityNights: number): { string }
	local soloNight = solo.uraniumNight
	local crewNight = crewResult.uraniumNight
	if soloNight == nil or crewNight == nil then
		return {}
	end
	if math.abs(crewNight - soloNight) > parityNights then
		return { string.format("%s refines the target on day %d, solo on day %d", label, crewNight, soloNight) }
	end
	return {}
end

function BalanceModel.formatRows(result: Result): { string }
	local lines = {
		"night zone pick pack boot  mine s camp post  iron/p  gold/p  uran   budget kinds   waveHp  freeDps towerDps towers  needDps  slack  final  clear  wall%",
	}
	for _, row in result.rows do
		table.insert(lines, string.format(
			"%5d %4d %4d %4d %4d %7.0f %4d %4d %7.0f %7.0f %5.0f %8.0f %5d %8.0f %8.0f %8.0f %6d %8.0f %6.2f %6.2f %6.0f %6.0f",
			row.night,
			row.zone,
			row.pickLevel,
			row.backpackLevel,
			row.bootsLevel,
			row.miningSec,
			row.campLevel,
			row.postLevel,
			row.ironPerPlayer,
			row.goldPerPlayer,
			row.uraniumTotal,
			row.budget,
			row.unlockedCount,
			row.waveHp,
			row.freeDps,
			row.towerDps,
			row.towerCount,
			row.requiredDps,
			row.slack,
			math.min(row.finalWaveSlack, 99),
			row.clearSec,
			math.min(row.wallDamageShare * 100, 9999)
		))
	end
	table.insert(lines, string.format(
		"uranium target %d reached on day %s; towers first needed on night %s; first wall breach on night %s",
		result.uraniumTarget,
		if result.uraniumNight then tostring(result.uraniumNight) else "never",
		if result.firstTowerNight then tostring(result.firstTowerNight) else "never",
		if result.breachNight then tostring(result.breachNight) else "never"
	))
	return lines
end

return BalanceModel
