--!strict

-- Pure rules for the Mining Supplies Store (GDD "Mining Supplies Store",
-- "Camp Level"): what each stand offers a player given their level and the
-- crew's Camp Level, whether they can pay, and the catalogue codec the
-- server publishes as GameMetadata so the client can draw every stand
-- itself. Tuning is passed in from GameData so this stays unit testable.
local HttpService = game:GetService("HttpService")

local Attributes = require(script.Parent.Attributes)
local Enums = require(script.Parent.Enums)

local StoreRules = {}

-- an upgrade track: entry N is the price of reaching level N and the Camp
-- Level that buy needs (entry 1 is unused, everyone starts at level 1); the
-- price list's length is the top level. The camp level table comes from
-- GameData/Camp/Level (M22) and travels in the catalogue so the client
-- never needs GameData
export type UpgradeTrack = {
	priceByLevel: { number },
	requiredCampLevelByLevel: { number },
}

-- a consumable: one buy grants `amount` of `tool`
export type Consumable = {
	tool: number,
	price: number,
	amount: number,
}

export type Catalog = {
	upgrades: { [number]: UpgradeTrack },
	consumables: { [number]: Consumable },
}

export type Offer = {
	status: number,
	-- the level the buy would reach, nil for consumables and when maxed
	level: number?,
	price: number?,
	-- the Camp Level an upgrade offer needs, met or not; nil otherwise
	requiredCampLevel: number?,
}

StoreRules.MAXED_TEXT = "Maxed out"
StoreRules.LOCKED_FORMAT = "Camp Level %d required"

-- the Camp Level an upgrade offer needs, whether or not it is met; nil for
-- consumables and maxed stands, which show no requirement
function StoreRules.requiredCampLevelForOffer(offer: Offer): number?
	return offer.requiredCampLevel
end

-- the private CurrentPlayer attribute carrying a player's level on each track
StoreRules.LEVEL_ATTRIBUTE_BY_ITEM = {
	[Enums.StoreItem.PICK_AXE] = Attributes.PICK_AXE_LEVEL,
	[Enums.StoreItem.BOOTS] = Attributes.BOOTS_LEVEL,
	[Enums.StoreItem.BACKPACK] = Attributes.BACKPACK_LEVEL,
	[Enums.StoreItem.JET_PACK] = Attributes.JET_PACK_LEVEL,
}

-- "PickAxeStand" from "PICK_AXE": the Studio model name of a stand, for
-- any enum key (the Defense Store's Trap stands use the same rule)
function StoreRules.standNameFromKey(key: string): string
	local pascal = ""
	for word in string.gmatch(string.lower(key), "[^_]+") do
		pascal ..= string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end
	return pascal .. "Stand"
end

function StoreRules.standNameForItem(item: number): string?
	local key = Enums.getName(Enums.StoreItem, item)
	if not key then
		return nil
	end
	return StoreRules.standNameFromKey(key)
end

-- the track's table decides (GameData/Camp/Level); a level the table does
-- not mention is never gated, so a short table loosens rather than locks
function StoreRules.requiredCampLevel(track: UpgradeTrack, targetLevel: number): number
	local required = track.requiredCampLevelByLevel[targetLevel]
	return if typeof(required) == "number" then required else 1
end

function StoreRules.getUpgradeOffer(track: UpgradeTrack, ownedLevel: number, campLevel: number): Offer
	local targetLevel = math.floor(ownedLevel) + 1
	local price = track.priceByLevel[targetLevel]
	if price == nil then
		return { status = Enums.StoreOffer.MAXED }
	end
	local required = StoreRules.requiredCampLevel(track, targetLevel)
	return {
		status = if campLevel < required then Enums.StoreOffer.LOCKED else Enums.StoreOffer.AVAILABLE,
		level = targetLevel,
		price = price,
		requiredCampLevel = required,
	}
end

function StoreRules.getConsumableOffer(consumable: Consumable): Offer
	return {
		status = Enums.StoreOffer.AVAILABLE,
		price = consumable.price,
	}
end

-- what a stand shows a player: nil when the catalogue has no such item
function StoreRules.getOffer(catalog: Catalog, item: number, ownedLevel: number, campLevel: number): Offer?
	local track = catalog.upgrades[item]
	if track then
		return StoreRules.getUpgradeOffer(track, ownedLevel, campLevel)
	end
	local consumable = catalog.consumables[item]
	if consumable then
		return StoreRules.getConsumableOffer(consumable)
	end
	return nil
end

function StoreRules.canAfford(gold: number, price: number): boolean
	return gold >= price
end

-- the stand's headline: "PICK AXE 3" for the next level, the item name for
-- consumables, and "Maxed out" (formatted by the caller) at the top
function StoreRules.nameText(item: number, offer: Offer): string
	local name = Enums.getPublicName(Enums.StoreItem, item) or "?"
	if offer.status == Enums.StoreOffer.MAXED then
		return StoreRules.MAXED_TEXT
	end
	if offer.level then
		return `{name} {offer.level}`
	end
	return name
end

-- JSON keys are strings, so numeric item keys are restored on decode
function StoreRules.encodeCatalog(catalog: Catalog): string
	return HttpService:JSONEncode(catalog)
end

function StoreRules.decodeCatalog(encoded: any): Catalog?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" then
		return nil
	end
	local catalog: Catalog = { upgrades = {}, consumables = {} }
	for key, track in (decoded.upgrades or {}) :: { [any]: any } do
		local item = tonumber(key)
		if item and typeof(track) == "table" and typeof(track.priceByLevel) == "table" then
			catalog.upgrades[item] = {
				priceByLevel = track.priceByLevel,
				requiredCampLevelByLevel = if typeof(track.requiredCampLevelByLevel) == "table" then track.requiredCampLevelByLevel else {},
			}
		end
	end
	for key, consumable in (decoded.consumables or {}) :: { [any]: any } do
		local item = tonumber(key)
		if item and typeof(consumable) == "table" and typeof(consumable.price) == "number" then
			catalog.consumables[item] = {
				tool = consumable.tool,
				price = consumable.price,
				amount = consumable.amount,
			}
		end
	end
	return catalog
end

return StoreRules
