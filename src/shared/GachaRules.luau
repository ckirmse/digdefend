--!strict

-- Pure rules for the class gacha (GDD "Class Unlock System", M70): what a
-- roll draws from the pool, what that draw turns into against the player's
-- progress (a new class, its next skill slot, a cosmetic, or Keys), the
-- odds the menu shows, and the codecs for the config in GameMetadata and
-- the progress on CurrentPlayer. No instances and no GameData, so every
-- rule is unit tested; GachaManager (lobby server) spends and saves.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local GachaRules = {}

-- what the pool holds and how its three kinds weigh against each other
export type Pool = {
	classKinds: { number },
	cosmeticIds: { string },
	classWeight: number,
	cosmeticWeight: number,
	keysWeight: number,
}

-- Enums.ClassKind key name -> skill slots unlocked (0 to maxSkillSlots);
-- a class with an entry is owned, one without is locked
export type Progress = { [string]: number }

-- cosmetic id -> true for every cosmetic the account owns
export type OwnedCosmetics = { [string]: boolean }

export type Config = {
	maxSkillSlots: number,
	keysPerKeysResult: number,
	keysPerCompleteClass: number,
	keysPerDuplicateCosmetic: number,
}

-- the raw pick, before the player's progress is looked at: kind is the
-- pool's category (CLASS, COSMETIC, or KEYS of Enums.GachaResultKind)
export type Draw = {
	kind: number,
	classKind: number?,
	cosmeticId: string?,
}

-- what the player gets: kind says which (CLASS, SKILL_SLOT, COSMETIC, or
-- KEYS); classKind rides on a class or skill slot result, skillSlot on a
-- skill slot one, cosmeticId on a cosmetic one, and keys is paid on a
-- KEYS result only (the other kinds pay 0)
export type Result = {
	kind: number,
	classKind: number?,
	skillSlot: number?,
	cosmeticId: string?,
	keys: number,
	-- set when a class or cosmetic draw was converted to Keys, so the
	-- reveal can say what was rolled
	convertedFromKind: number?,
	convertedClassKind: number?,
	convertedCosmeticId: string?,
}

-- one thing the pool can land on, with its own share of rolls: what the
-- odds list and the reveal strip draw (every entry of a kind is equally
-- likely, so an entry's odds are its kind's share over the kind's count)
export type Prize = {
	-- "CLASS:2", "COSMETIC:HARD_HAT", "KEYS": the strip's stable tile name
	key: string,
	kind: number,
	classKind: number?,
	cosmeticId: string?,
	odds: number,
}

-- the config the lobby menu reads from one GameMetadata JSON attribute
export type Config_Published = {
	rollPriceDiamonds: number,
	directClassPriceDiamonds: number,
	-- share of rolls per kind (0 to 1), the empty kinds left out
	odds: { [string]: number },
	-- every class the pool may roll, so the menu can list them
	poolClassKinds: { number },
	-- every entry the pool may land on, most likely first
	prizes: { Prize },
	maxSkillSlots: number,
}

export type Odds = { [string]: number }

local KIND_NAMES = {
	[Enums.GachaResultKind.CLASS] = "CLASS",
	[Enums.GachaResultKind.COSMETIC] = "COSMETIC",
	[Enums.GachaResultKind.KEYS] = "KEYS",
}

-- the kinds that can be drawn, with their weights, in a fixed order so a
-- seeded Random is reproducible; a kind with nothing to draw drops out
local function drawableKinds(pool: Pool): { { kind: number, weight: number } }
	local kinds = {}
	if #pool.classKinds > 0 and pool.classWeight > 0 then
		table.insert(kinds, { kind = Enums.GachaResultKind.CLASS, weight = pool.classWeight })
	end
	if #pool.cosmeticIds > 0 and pool.cosmeticWeight > 0 then
		table.insert(kinds, { kind = Enums.GachaResultKind.COSMETIC, weight = pool.cosmeticWeight })
	end
	if pool.keysWeight > 0 then
		table.insert(kinds, { kind = Enums.GachaResultKind.KEYS, weight = pool.keysWeight })
	end
	return kinds
end

-- the share of rolls each kind takes, keyed by its name ("CLASS" = 0.6)
function GachaRules.odds(pool: Pool): Odds
	local kinds = drawableKinds(pool)
	local total = 0
	for _, entry in kinds do
		total += entry.weight
	end
	local odds: Odds = {}
	if total <= 0 then
		return odds
	end
	for _, entry in kinds do
		odds[KIND_NAMES[entry.kind]] = entry.weight / total
	end
	return odds
end

function GachaRules.prizeKey(kind: number, classKind: number?, cosmeticId: string?): string
	if kind == Enums.GachaResultKind.CLASS then
		return "CLASS:" .. tostring(classKind)
	elseif kind == Enums.GachaResultKind.COSMETIC then
		return "COSMETIC:" .. tostring(cosmeticId)
	end
	return "KEYS"
end

-- every entry with its own odds, most likely first and then by key so the
-- order is stable; the Roblox rule for paid random items is that a
-- player can see each prize's chance, and this is that list
function GachaRules.prizeList(pool: Pool): { Prize }
	local odds = GachaRules.odds(pool)
	local prizes: { Prize } = {}
	local classShare = odds.CLASS
	if classShare then
		for _, classKind in pool.classKinds do
			table.insert(prizes, {
				key = GachaRules.prizeKey(Enums.GachaResultKind.CLASS, classKind, nil),
				kind = Enums.GachaResultKind.CLASS,
				classKind = classKind,
				odds = classShare / #pool.classKinds,
			})
		end
	end
	local cosmeticShare = odds.COSMETIC
	if cosmeticShare then
		for _, cosmeticId in pool.cosmeticIds do
			table.insert(prizes, {
				key = GachaRules.prizeKey(Enums.GachaResultKind.COSMETIC, nil, cosmeticId),
				kind = Enums.GachaResultKind.COSMETIC,
				cosmeticId = cosmeticId,
				odds = cosmeticShare / #pool.cosmeticIds,
			})
		end
	end
	if odds.KEYS then
		table.insert(prizes, {
			key = GachaRules.prizeKey(Enums.GachaResultKind.KEYS, nil, nil),
			kind = Enums.GachaResultKind.KEYS,
			odds = odds.KEYS,
		})
	end
	table.sort(
		prizes,
		function(a, b)
			if a.odds ~= b.odds then
				return a.odds > b.odds
			end
			return a.key < b.key
		end
	)
	return prizes
end

-- 0.5 -> "50%", 0.045 -> "4.5%", 0.0005 -> "0.05%": the detail grows as the
-- chance shrinks, so a rare entry never reads as 0% (the reference game's
-- GachaOddsFormat)
function GachaRules.formatOddsPercent(fraction: number): string
	local percent = fraction * 100
	local text
	if percent >= 10 then
		text = string.format("%.0f", percent)
	elseif percent >= 1 then
		text = string.format("%.1f", percent)
	else
		text = string.format("%.2f", percent)
	end
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text .. "%"
end

-- one pick from the pool: a kind by weight, then an entry of that kind,
-- every entry equally likely. nil only for an empty pool
function GachaRules.draw(random: Random, pool: Pool): Draw?
	local kinds = drawableKinds(pool)
	local total = 0
	for _, entry in kinds do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = random:NextNumber() * total
	local picked = kinds[#kinds].kind
	local cursor = 0
	for _, entry in kinds do
		cursor += entry.weight
		if roll < cursor then
			picked = entry.kind
			break
		end
	end
	if picked == Enums.GachaResultKind.CLASS then
		return {
			kind = picked,
			classKind = pool.classKinds[random:NextInteger(1, #pool.classKinds)],
		}
	elseif picked == Enums.GachaResultKind.COSMETIC then
		return {
			kind = picked,
			cosmeticId = pool.cosmeticIds[random:NextInteger(1, #pool.cosmeticIds)],
		}
	end
	return { kind = Enums.GachaResultKind.KEYS }
end

function GachaRules.isClassOwned(progress: Progress, classKind: number): boolean
	local className = Enums.getName(Enums.ClassKind, classKind)
	return className ~= nil and progress[className] ~= nil
end

-- how many skill slots the class has open: none for a class not owned,
-- never more than the cap
function GachaRules.openSkillSlots(progress: Progress, classKind: number, maxSkillSlots: number): number
	local className = Enums.getName(Enums.ClassKind, classKind)
	local slots = if className then progress[className] else nil
	if slots == nil then
		return 0
	end
	return math.clamp(slots, 0, maxSkillSlots)
end

-- the next step a class roll grants (GDD table): the class itself when
-- locked, then skill slots in order, then Keys once complete
function GachaRules.resolve(draw: Draw, progress: Progress, ownedCosmetics: OwnedCosmetics, config: Config): Result
	if draw.kind == Enums.GachaResultKind.CLASS and draw.classKind then
		local classKind = draw.classKind
		if not GachaRules.isClassOwned(progress, classKind) then
			return { kind = Enums.GachaResultKind.CLASS, classKind = classKind, keys = 0 }
		end
		local open = GachaRules.openSkillSlots(progress, classKind, config.maxSkillSlots)
		if open < config.maxSkillSlots then
			return { kind = Enums.GachaResultKind.SKILL_SLOT, classKind = classKind, skillSlot = open + 1, keys = 0 }
		end
		return {
			kind = Enums.GachaResultKind.KEYS,
			keys = config.keysPerCompleteClass,
			convertedFromKind = Enums.GachaResultKind.CLASS,
			convertedClassKind = classKind,
		}
	elseif draw.kind == Enums.GachaResultKind.COSMETIC and draw.cosmeticId then
		local cosmeticId = draw.cosmeticId
		if not ownedCosmetics[cosmeticId] then
			return { kind = Enums.GachaResultKind.COSMETIC, cosmeticId = cosmeticId, keys = 0 }
		end
		return {
			kind = Enums.GachaResultKind.KEYS,
			keys = config.keysPerDuplicateCosmetic,
			convertedFromKind = Enums.GachaResultKind.COSMETIC,
			convertedCosmeticId = cosmeticId,
		}
	end
	return { kind = Enums.GachaResultKind.KEYS, keys = config.keysPerKeysResult }
end

-- writes a result into the progress and cosmetics tables in place and
-- returns the Keys to pay; the manager then saves and replicates
function GachaRules.applyResult(progress: Progress, ownedCosmetics: OwnedCosmetics, result: Result): number
	if result.kind == Enums.GachaResultKind.CLASS and result.classKind then
		local className = Enums.getName(Enums.ClassKind, result.classKind)
		if className then
			progress[className] = 0
		end
	elseif result.kind == Enums.GachaResultKind.SKILL_SLOT and result.classKind and result.skillSlot then
		local className = Enums.getName(Enums.ClassKind, result.classKind)
		if className then
			progress[className] = result.skillSlot
		end
	elseif result.kind == Enums.GachaResultKind.COSMETIC and result.cosmeticId then
		ownedCosmetics[result.cosmeticId] = true
	end
	return result.keys
end

-- the classes the pool may hold: every class but the excluded ones
function GachaRules.poolClassKinds(allClassKinds: { number }, excludedKinds: { number }): { number }
	local isExcluded: { [number]: boolean } = {}
	for _, kind in excludedKinds do
		isExcluded[kind] = true
	end
	local kinds = {}
	for _, kind in allClassKinds do
		if not isExcluded[kind] then
			table.insert(kinds, kind)
		end
	end
	table.sort(kinds)
	return kinds
end

function GachaRules.encodeConfig(config: Config_Published): string
	return HttpService:JSONEncode(config)
end

function GachaRules.decodeConfig(encoded: any): Config_Published?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.rollPriceDiamonds) ~= "number" then
		return nil
	end
	local odds: Odds = {}
	if typeof(decoded.odds) == "table" then
		for name, share in decoded.odds do
			if typeof(name) == "string" and typeof(share) == "number" then
				odds[name] = share
			end
		end
	end
	local poolClassKinds: { number } = {}
	if typeof(decoded.poolClassKinds) == "table" then
		for _, kind in decoded.poolClassKinds do
			if typeof(kind) == "number" then
				table.insert(poolClassKinds, kind)
			end
		end
	end
	local prizes: { Prize } = {}
	if typeof(decoded.prizes) == "table" then
		for _, prize in decoded.prizes do
			if typeof(prize) == "table" and typeof(prize.key) == "string" and typeof(prize.kind) == "number" and typeof(prize.odds) == "number" then
				table.insert(prizes, {
					key = prize.key,
					kind = prize.kind,
					classKind = if typeof(prize.classKind) == "number" then prize.classKind else nil,
					cosmeticId = if typeof(prize.cosmeticId) == "string" then prize.cosmeticId else nil,
					odds = prize.odds,
				})
			end
		end
	end
	return {
		rollPriceDiamonds = decoded.rollPriceDiamonds,
		directClassPriceDiamonds = if typeof(decoded.directClassPriceDiamonds) == "number" then decoded.directClassPriceDiamonds else 0,
		odds = odds,
		poolClassKinds = poolClassKinds,
		prizes = prizes,
		maxSkillSlots = if typeof(decoded.maxSkillSlots) == "number" then decoded.maxSkillSlots else 0,
	}
end

-- the progress map travels as one JSON attribute on CurrentPlayer
function GachaRules.encodeProgress(progress: Progress): string
	return HttpService:JSONEncode(progress)
end

function GachaRules.decodeProgress(encoded: any): Progress
	local progress: Progress = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return progress
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return progress
	end
	for className, slots in decoded do
		if typeof(className) == "string" and typeof(slots) == "number" then
			progress[className] = slots
		end
	end
	return progress
end

-- the owned cosmetics travel as a JSON list of ids (a JSON object with
-- only true values would do, but a list reads better in the Explorer)
function GachaRules.encodeOwnedCosmetics(ownedCosmetics: OwnedCosmetics): string
	local ids = {}
	for id in ownedCosmetics do
		table.insert(ids, id)
	end
	table.sort(ids)
	return HttpService:JSONEncode(ids)
end

function GachaRules.decodeOwnedCosmetics(encoded: any): OwnedCosmetics
	local owned: OwnedCosmetics = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return owned
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return owned
	end
	for _, id in decoded do
		if typeof(id) == "string" and id ~= "" then
			owned[id] = true
		end
	end
	return owned
end

return GachaRules
