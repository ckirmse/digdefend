--!strict

-- Pure character rules (GDD "Characters", "Character Menu"): what the next
-- character slot costs, the pricing codec the lobby reads from
-- GameMetadata, and the placeholder Rank until M58 decides the formula.
-- No instances, so every rule is unit tested.
local HttpService = game:GetService("HttpService")

local CharacterSchema = require(script.Parent.CharacterSchema)
local Enums = require(script.Parent.Enums)

local CharacterRules = {}

export type SlotPricing = {
	-- slot index (the second character is slot 2) -> its Diamonds price;
	-- a slot without one is Robux only
	diamondPriceBySlot: { [number]: number },
	-- the Robux developer product for a slot; 0 when none exists yet
	robuxProductId: number,
	maxCharacters: number,
}

export type SlotOffer = {
	slot: number,
	currency: number,
	-- set for a Diamonds slot
	diamonds: number?,
	-- set for a Robux slot; 0 means the product does not exist yet
	productId: number?,
}

-- the next slot a player holding `ownedCount` characters can buy, or nil
-- at the cap
function CharacterRules.nextSlotOffer(ownedCount: number, pricing: SlotPricing): SlotOffer?
	local slot = ownedCount + 1
	if slot > pricing.maxCharacters or slot < 2 then
		return nil
	end
	local diamonds = pricing.diamondPriceBySlot[slot]
	if diamonds then
		return {
			slot = slot,
			currency = Enums.SlotCurrency.DIAMONDS,
			diamonds = diamonds,
		}
	end
	return {
		slot = slot,
		currency = Enums.SlotCurrency.ROBUX,
		productId = pricing.robuxProductId,
	}
end

-- the pricing travels to the lobby as one GameMetadata JSON attribute;
-- JSON keys are strings, so the slot numbers are written out and read back
function CharacterRules.encodePricing(pricing: SlotPricing): string
	local priceBySlotName: { [string]: number } = {}
	for slot, price in pricing.diamondPriceBySlot do
		priceBySlotName[tostring(slot)] = price
	end
	return HttpService:JSONEncode({
		diamondPriceBySlot = priceBySlotName,
		robuxProductId = pricing.robuxProductId,
		maxCharacters = pricing.maxCharacters,
	})
end

function CharacterRules.decodePricing(encoded: any): SlotPricing?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.maxCharacters) ~= "number" then
		return nil
	end
	local diamondPriceBySlot: { [number]: number } = {}
	if typeof(decoded.diamondPriceBySlot) == "table" then
		for slotName, price in decoded.diamondPriceBySlot do
			local slot = tonumber(slotName)
			if slot and typeof(price) == "number" then
				diamondPriceBySlot[slot] = price
			end
		end
	end
	return {
		diamondPriceBySlot = diamondPriceBySlot,
		robuxProductId = if typeof(decoded.robuxProductId) == "number" then decoded.robuxProductId else 0,
		maxCharacters = decoded.maxCharacters,
	}
end

-- Rank (GDD "Characters"; placeholder values until M58): every gear row
-- scores the points of the rarity its stars read as, every filled skill
-- slot the points of its rarity, and the baseline comes off so a new
-- character is Rank 1. Never reads what a skill does or Nights Survived
function CharacterRules.rankOf(gearStarsBySlot: { [number]: number }, skillRarities: { number }, pointsByRarity: { [number]: number }, baselinePoints: number): number
	local points = 0
	for _, stars in gearStarsBySlot do
		points += pointsByRarity[CharacterRules.rarityForStars(stars)] or 0
	end
	for _, rarity in skillRarities do
		points += pointsByRarity[rarity] or 0
	end
	return math.max(points - baselinePoints, 1)
end

-- the band a Rank falls in: the last band whose floor it reaches
function CharacterRules.rankBand(rank: number, bands: { RankBand }): number
	local rarity = Enums.Rarity.COMMON
	for _, band in bands do
		if rank >= band.minRank then
			rarity = band.rarity
		end
	end
	return rarity
end

-- "Rank 5 - Uncommon"
function CharacterRules.rankText(rank: number, bands: { RankBand }): string
	return string.format("Rank %d - %s", rank, CharacterRules.rarityName(CharacterRules.rankBand(rank, bands)))
end

-- the pricing JSON must be decoded to number keys for the points table
function CharacterRules.rankOfPricing(gearStarsBySlot: { [number]: number }, skillRarities: { number }, pricing: RerollPricing): number
	return CharacterRules.rankOf(gearStarsBySlot, skillRarities, pricing.rankPointsByRarity, pricing.rankBaselinePoints)
end

-- what the sheet needs to price and explain a roll, published once as
-- GameMetadata JSON
export type RerollPricing = {
	gearPriceDiamonds: number,
	skillPriceDiamonds: number,
	-- the roll into an empty skill slot costs nothing and applies at once
	isFirstSkillRollFree: boolean,
	minStars: number,
	maxStars: number,
	bonusPerStar: number,
	-- Nights Survived per skill slot, so a locked row can name its threshold
	skillSlotUnlockNights: { number },
	-- the Rank formula's inputs (GameData/Characters/Rank), so the sheet
	-- can show a roll's Rank before and after
	rankPointsByRarity: { [number]: number },
	rankBaselinePoints: number,
	-- the Rank bands in rising order (GameData/Characters/Rank.BANDS)
	rankBands: { RankBand },
}

export type RankBand = {
	minRank: number,
	rarity: number,
}

export type SkillCatalogueEntry = {
	family: number,
	rarity: number,
	name: string,
	description: string,
}

export type SkillCatalogue = { [string]: SkillCatalogueEntry }

export type SkillOffer = {
	skillId: string,
	rarity: number,
}

export type GearOffer = {
	kind: number,
	stars: number,
}

export type HatCatalogueEntry = {
	name: string,
	assetId: number,
}

export type HatCatalogue = { [string]: HatCatalogueEntry }

local ROMAN_NUMERALS = { "I", "II", "III", "IV", "V" }

-- the star count as a numeral ("III"), the roll screen's flipping badge
function CharacterRules.starNumeral(stars: number): string
	return ROMAN_NUMERALS[stars] or tostring(stars)
end

-- a gear row's stars read as the rarity ladder (designer, 2026-10-12: the
-- sheet says Common to Legendary, never a star rating); the ladder has one
-- rung per star count
function CharacterRules.rarityForStars(stars: number): number
	return math.clamp(stars, Enums.Rarity.COMMON, Enums.Rarity.LEGENDARY)
end

function CharacterRules.rarityName(rarity: number): string
	return Enums.getPublicName(Enums.Rarity, rarity) or ""
end

-- placeholder odds (M37): every star count in range is equally likely,
-- the current one included (a roll may come back the same); the player
-- keeps or undoes the result, so a roll never makes a character worse
function CharacterRules.rollStars(random: Random, pricing: RerollPricing): number
	return random:NextInteger(pricing.minStars, pricing.maxStars)
end

-- a gear roll draws the kind and the stars together (designer,
-- 2026-10-12: a roll of a slot rolls every item of that slot's type), each
-- kind equally likely; nil only for a slot with no kind enum
function CharacterRules.rollGear(random: Random, gearSlot: number, pricing: RerollPricing): GearOffer?
	local gearEnum = CharacterSchema.getGearEnum(gearSlot)
	if not gearEnum then
		return nil
	end
	local kinds = Enums.getAllValues(gearEnum)
	table.sort(kinds)
	return {
		kind = kinds[random:NextInteger(1, #kinds)],
		stars = CharacterRules.rollStars(random, pricing),
	}
end

-- placeholder odds (M37): one skill drawn evenly from the whole
-- catalogue, the one the slot holds included, with the catalogue's
-- rarity; nil only for an empty catalogue
function CharacterRules.rollSkill(random: Random, catalogue: SkillCatalogue): SkillOffer?
	local ids: { string } = {}
	for id in catalogue do
		table.insert(ids, id)
	end
	if #ids == 0 then
		return nil
	end
	table.sort(ids)
	local id = ids[random:NextInteger(1, #ids)]
	return { skillId = id, rarity = catalogue[id].rarity }
end

-- what a skill roll costs for this slot: nothing for the roll that fills
-- an empty slot when the first roll is free
function CharacterRules.skillRollPrice(pricing: RerollPricing, isSlotEmpty: boolean): number
	if isSlotEmpty and pricing.isFirstSkillRollFree then
		return 0
	end
	return pricing.skillPriceDiamonds
end

-- one line of the odds table a reroll shows before it is bought (Roblox's
-- paid random items policy: every outcome's odds as a percentage, the
-- tiers totalling 100%, reachable before the purchase)
export type RarityOdds = {
	rarity: number,
	-- 0 to 100
	percent: number,
}

-- a gear roll draws its stars evenly, and each star count is one rarity
-- rung, so every rarity in range has the same share; a rarity outside
-- the roll's range is listed at 0 so the table always names them all
function CharacterRules.gearRarityOdds(pricing: RerollPricing): { RarityOdds }
	local odds: { RarityOdds } = {}
	local count = pricing.maxStars - pricing.minStars + 1
	for _, rarity in Enums.getAllValues(Enums.Rarity) do
		local stars = rarity
		local isInRange = stars >= pricing.minStars and stars <= pricing.maxStars
		table.insert(odds, { rarity = rarity, percent = if isInRange and count > 0 then 100 / count else 0 })
	end
	table.sort(
		odds,
		function(a: RarityOdds, b: RarityOdds)
			return a.rarity < b.rarity
		end
	)
	return odds
end

-- a skill roll draws evenly from the whole catalogue, so a rarity's share
-- is how many skills carry it
function CharacterRules.skillRarityOdds(catalogue: SkillCatalogue): { RarityOdds }
	local countByRarity: { [number]: number } = {}
	local total = 0
	for _, entry in catalogue do
		countByRarity[entry.rarity] = (countByRarity[entry.rarity] or 0) + 1
		total += 1
	end
	local odds: { RarityOdds } = {}
	for _, rarity in Enums.getAllValues(Enums.Rarity) do
		local count = countByRarity[rarity] or 0
		table.insert(odds, { rarity = rarity, percent = if total > 0 then count / total * 100 else 0 })
	end
	table.sort(
		odds,
		function(a: RarityOdds, b: RarityOdds)
			return a.rarity < b.rarity
		end
	)
	return odds
end

-- the order a COSMETICS row shows its items in when the sheet opens
-- (designer, 2026-10-13): the equipped one first, the rest by name; the
-- row keeps this order while the sheet stays open, so a tap equips
-- without shuffling the strip. `nameOf` gives the sort key of an id;
-- `lastId` is pinned to the end whatever is equipped (the hat row's NONE,
-- designer, 2026-10-13)
function CharacterRules.cosmeticItemOrder(ids: { string }, equippedId: string?, nameOf: (string) -> string, lastId: string?): { string }
	local ordered = table.clone(ids)
	table.sort(
		ordered,
		function(a: string, b: string)
			if a == lastId or b == lastId then
				return b == lastId
			end
			if a == equippedId or b == equippedId then
				return a == equippedId
			end
			local nameA, nameB = nameOf(a), nameOf(b)
			if nameA == nameB then
				return a < b
			end
			return nameA < nameB
		end
	)
	return ordered
end

-- a share as the table prints it: whole when it is, else one decimal
function CharacterRules.percentText(percent: number): string
	local rounded = math.floor(percent * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d%%", math.floor(rounded))
	end
	return string.format("%.1f%%", rounded)
end

-- whether the printed shares add up to exactly 100, so the table can
-- carry the rounding note the policy asks for only when it needs one
function CharacterRules.isOddsTotalExact(odds: { RarityOdds }): boolean
	local total = 0
	for _, line in odds do
		total += math.floor(line.percent * 10 + 0.5) / 10
	end
	return math.abs(total - 100) < 0.001
end

-- the odds line for the kind a gear roll draws
function CharacterRules.describeKindOdds(gearSlot: number): string
	local gearEnum = CharacterSchema.getGearEnum(gearSlot)
	local count = if gearEnum then Enums.getCount(gearEnum) else 0
	if count <= 1 then
		return "Only one kind exists so far"
	end
	return string.format("Each of the %d kinds has a %d%% chance", count, math.floor(100 / count + 0.5))
end

-- JSON keys are strings, so the points table is written out by rarity
-- value and read back
function CharacterRules.encodeRerollPricing(pricing: RerollPricing): string
	local pointsByName: { [string]: number } = {}
	for rarity, points in pricing.rankPointsByRarity do
		pointsByName[tostring(rarity)] = points
	end
	local encoded = table.clone(pricing) :: any
	encoded.rankPointsByRarity = pointsByName
	return HttpService:JSONEncode(encoded)
end

function CharacterRules.decodeRerollPricing(encoded: any): RerollPricing?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.gearPriceDiamonds) ~= "number" then
		return nil
	end
	local pointsByRarity: { [number]: number } = {}
	if typeof(decoded.rankPointsByRarity) == "table" then
		for name, points in decoded.rankPointsByRarity do
			local rarity = tonumber(name)
			if rarity and typeof(points) == "number" then
				pointsByRarity[rarity] = points
			end
		end
	end
	decoded.rankPointsByRarity = pointsByRarity
	if typeof(decoded.rankBaselinePoints) ~= "number" then
		decoded.rankBaselinePoints = 0
	end
	local bands: { RankBand } = {}
	if typeof(decoded.rankBands) == "table" then
		for _, band in decoded.rankBands do
			if typeof(band) == "table" and typeof(band.minRank) == "number" and typeof(band.rarity) == "number" then
				table.insert(bands, { minRank = band.minRank, rarity = band.rarity })
			end
		end
	end
	decoded.rankBands = bands
	return decoded :: RerollPricing
end

function CharacterRules.encodeSkillCatalogue(catalogue: SkillCatalogue): string
	return HttpService:JSONEncode(catalogue)
end

function CharacterRules.decodeSkillCatalogue(encoded: any): SkillCatalogue
	local catalogue: SkillCatalogue = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return catalogue
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return catalogue
	end
	for id, entry in decoded do
		if typeof(id) == "string" and typeof(entry) == "table" and typeof(entry.name) == "string" then
			catalogue[id] = {
				family = if typeof(entry.family) == "number" then entry.family else 0,
				rarity = if typeof(entry.rarity) == "number" then entry.rarity else 0,
				name = entry.name,
				description = if typeof(entry.description) == "string" then entry.description else "",
			}
		end
	end
	return catalogue
end

function CharacterRules.encodeHatCatalogue(catalogue: HatCatalogue): string
	return HttpService:JSONEncode(catalogue)
end

function CharacterRules.decodeHatCatalogue(encoded: any): HatCatalogue
	local catalogue: HatCatalogue = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return catalogue
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return catalogue
	end
	for id, entry in decoded do
		if typeof(id) == "string" and typeof(entry) == "table" and typeof(entry.name) == "string" and typeof(entry.assetId) == "number" then
			catalogue[id] = { name = entry.name, assetId = entry.assetId }
		end
	end
	return catalogue
end

function CharacterRules.rankOfRecord(record: CharacterSchema.CharacterSave, pointsByRarity: { [number]: number }, baselinePoints: number): number
	local starsBySlot: { [number]: number } = {}
	for _, gearSlot in Enums.getAllValues(Enums.GearSlot) do
		local _, stars = CharacterSchema.getGear(record, gearSlot)
		starsBySlot[gearSlot] = stars
	end
	local skillRarities: { number } = {}
	for _, skill in record.skills do
		table.insert(skillRarities, skill.rarity)
	end
	return CharacterRules.rankOf(starsBySlot, skillRarities, pointsByRarity, baselinePoints)
end

return CharacterRules
