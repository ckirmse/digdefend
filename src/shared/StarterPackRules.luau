--!strict

-- The Starter Pack's shapes and its one rule (M79): what GameData must
-- hold, the offer as the client draws it (the StarterPack GameMetadata
-- JSON), and which class the pack's class card is for a given account.
-- Pure, so the server's payout and the menu's card pick the same class.
local HttpService = game:GetService("HttpService")

local GachaRules = require(script.Parent.GachaRules)

local StarterPackRules = {}

-- GameData/Store/StarterPack
export type Definition = {
	GAME_PASS_ID: number,
	VALUE_ROBUX: number,
	CLASS_PRIORITY: { number },
	DIAMONDS: number,
	COSMETIC_ID: string,
}

-- priceRobux is 0 until Roblox has answered. The class priority travels
-- with the two gacha numbers the pick needs, so the client can show the
-- card this account would get
export type Offer = {
	classPriority: { number },
	maxSkillSlots: number,
	keysPerCompleteClass: number,
	diamonds: number,
	cosmeticId: string,
	valueRobux: number,
	priceRobux: number,
}

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number" and value > 0 and value == math.floor(value)
end

-- the problems with the definition, in order; empty means the pack can
-- be sold and paid. The two questions are answered by the class roster
-- and the cosmetics catalogue
function StarterPackRules.validate(definition: Definition, isKnownClass: (classKind: number) -> boolean, isKnownCosmetic: (cosmeticId: string) -> boolean): { string }
	local problems = {}
	if not isPositiveInteger(definition.GAME_PASS_ID) then
		table.insert(problems, "GAME_PASS_ID must be a positive whole number")
	end
	if not isPositiveInteger(definition.VALUE_ROBUX) then
		table.insert(problems, "VALUE_ROBUX must be a positive whole number")
	end
	if not isPositiveInteger(definition.DIAMONDS) then
		table.insert(problems, "DIAMONDS must be a positive whole number")
	end
	local priority = definition.CLASS_PRIORITY
	if typeof(priority) ~= "table" or #priority == 0 then
		table.insert(problems, "CLASS_PRIORITY must list at least one class")
	else
		local seen: { [number]: boolean } = {}
		for index, classKind in priority do
			if typeof(classKind) ~= "number" or not isKnownClass(classKind) then
				table.insert(problems, `CLASS_PRIORITY entry {index} is not a class in the Supply Crate's pool`)
			elseif seen[classKind] then
				table.insert(problems, `CLASS_PRIORITY entry {index} repeats a class`)
			end
			seen[classKind] = true
		end
	end
	if typeof(definition.COSMETIC_ID) ~= "string" or not isKnownCosmetic(definition.COSMETIC_ID) then
		table.insert(problems, "COSMETIC_ID is not in the cosmetics catalogue")
	end
	return problems
end

-- the class the pack's card is for this account (designer, 2026-11-12):
-- the first class in the priority the player does not own; with every
-- one owned, the first that is not maxed (its next tier); nil when every
-- one is maxed, and the card then pays its worth in Keys
function StarterPackRules.pickClassKind(priority: { number }, progress: GachaRules.Progress, maxSkillSlots: number): number?
	for _, classKind in priority do
		if not GachaRules.isClassOwned(progress, classKind) then
			return classKind
		end
	end
	for _, classKind in priority do
		if GachaRules.openSkillSlots(progress, classKind, maxSkillSlots) < maxSkillSlots then
			return classKind
		end
	end
	return nil
end

function StarterPackRules.buildOffer(definition: Definition, maxSkillSlots: number, keysPerCompleteClass: number, priceRobux: number?): Offer
	return {
		classPriority = table.clone(definition.CLASS_PRIORITY),
		maxSkillSlots = maxSkillSlots,
		keysPerCompleteClass = keysPerCompleteClass,
		diamonds = definition.DIAMONDS,
		cosmeticId = definition.COSMETIC_ID,
		valueRobux = definition.VALUE_ROBUX,
		priceRobux = priceRobux or 0,
	}
end

function StarterPackRules.encodeOffer(offer: Offer): string
	return HttpService:JSONEncode(offer)
end

-- nil for anything that is not a well-formed offer
function StarterPackRules.decodeOffer(encoded: any): Offer?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if
		not isSuccess
		or typeof(decoded) ~= "table"
		or typeof(decoded.classPriority) ~= "table"
		or typeof(decoded.maxSkillSlots) ~= "number"
		or typeof(decoded.keysPerCompleteClass) ~= "number"
		or typeof(decoded.diamonds) ~= "number"
		or typeof(decoded.cosmeticId) ~= "string"
		or typeof(decoded.valueRobux) ~= "number"
		or typeof(decoded.priceRobux) ~= "number"
	then
		return nil
	end
	local classPriority: { number } = {}
	for _, classKind in decoded.classPriority do
		if typeof(classKind) ~= "number" then
			return nil
		end
		table.insert(classPriority, classKind)
	end
	return {
		classPriority = classPriority,
		maxSkillSlots = decoded.maxSkillSlots,
		keysPerCompleteClass = decoded.keysPerCompleteClass,
		diamonds = decoded.diamonds,
		cosmeticId = decoded.cosmeticId,
		valueRobux = decoded.valueRobux,
		priceRobux = decoded.priceRobux,
	}
end

return StarterPackRules
