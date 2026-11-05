--!strict

-- The pure rules behind a class's Perks (the skill slots of GDD
-- "Classes"; CharacterRules until the Class Equip Menu of 2026-11-04,
-- when the gear rolls, Rank, and character slots went): a roll's draw and
-- price, the odds table Roblox's paid random items policy asks for, and
-- the codecs that carry the pricing, the skill catalogue, and the hat
-- catalogue to the client as GameMetadata JSON. No Roblox services beyond
-- HttpService's JSON, so every rule is unit tested.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local SkillRules = {}

export type RerollPricing = {
	skillPriceDiamonds: number,
	-- the roll into an empty skill slot costs nothing and applies at once
	isFirstSkillRollFree: boolean,
	-- the skill slots a class can open (the gacha opens them, M70), so the
	-- menu draws every row, the locked ones too
	maxSkillSlots: number,
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

export type HatCatalogueEntry = {
	name: string,
	assetId: number,
}

export type HatCatalogue = { [string]: HatCatalogueEntry }

-- one line of the odds table a reroll shows before it is bought (Roblox's
-- paid random items policy: every outcome's odds as a percentage, the
-- tiers totalling 100%, reachable before the purchase)
export type RarityOdds = {
	rarity: number,
	-- 0 to 100
	percent: number,
}

function SkillRules.rarityName(rarity: number): string
	return Enums.getPublicName(Enums.Rarity, rarity) or "?"
end

-- every skill in the catalogue is equally likely (placeholder odds until
-- the real 36 land, M56); ids sorted so a seeded Random is repeatable
function SkillRules.rollSkill(random: Random, catalogue: SkillCatalogue): SkillOffer?
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
function SkillRules.skillRollPrice(pricing: RerollPricing, isSlotEmpty: boolean): number
	if isSlotEmpty and pricing.isFirstSkillRollFree then
		return 0
	end
	return pricing.skillPriceDiamonds
end

-- a skill roll draws evenly over the catalogue, so a rarity's share is its
-- count over the whole; every rarity is listed, the absent ones at 0
function SkillRules.skillRarityOdds(catalogue: SkillCatalogue): { RarityOdds }
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

-- the order a cosmetics row shows its items in when it opens (designer,
-- 2026-10-13): the equipped one first, the rest by name; `nameOf` gives
-- the sort key of an id; `lastId` is pinned to the end whatever is
-- equipped (the hat row's NONE)
function SkillRules.cosmeticItemOrder(ids: { string }, equippedId: string?, nameOf: (string) -> string, lastId: string?): { string }
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
function SkillRules.percentText(percent: number): string
	local rounded = math.floor(percent * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d%%", math.floor(rounded))
	end
	return string.format("%.1f%%", rounded)
end

-- whether the printed shares add up to exactly 100, so the table can
-- carry the rounding note the policy asks for only when it needs one
function SkillRules.isOddsTotalExact(odds: { RarityOdds }): boolean
	local total = 0
	for _, line in odds do
		total += math.floor(line.percent * 10 + 0.5) / 10
	end
	return math.abs(total - 100) < 0.001
end

local function decodeJson(encoded: any): any
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess then
		return nil
	end
	return decoded
end

function SkillRules.encodeRerollPricing(pricing: RerollPricing): string
	return HttpService:JSONEncode(pricing)
end

function SkillRules.decodeRerollPricing(encoded: any): RerollPricing?
	local decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" or typeof(decoded.skillPriceDiamonds) ~= "number" or typeof(decoded.maxSkillSlots) ~= "number" then
		return nil
	end
	return {
		skillPriceDiamonds = decoded.skillPriceDiamonds,
		isFirstSkillRollFree = decoded.isFirstSkillRollFree == true,
		maxSkillSlots = decoded.maxSkillSlots,
	}
end

function SkillRules.encodeSkillCatalogue(catalogue: SkillCatalogue): string
	return HttpService:JSONEncode(catalogue)
end

function SkillRules.decodeSkillCatalogue(encoded: any): SkillCatalogue
	local catalogue: SkillCatalogue = {}
	local decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" then
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

function SkillRules.encodeHatCatalogue(catalogue: HatCatalogue): string
	return HttpService:JSONEncode(catalogue)
end

function SkillRules.decodeHatCatalogue(encoded: any): HatCatalogue
	local catalogue: HatCatalogue = {}
	local decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" then
		return catalogue
	end
	for id, entry in decoded do
		if typeof(id) == "string" and typeof(entry) == "table" and typeof(entry.name) == "string" and typeof(entry.assetId) == "number" then
			catalogue[id] = { name = entry.name, assetId = entry.assetId }
		end
	end
	return catalogue
end

return SkillRules
