--!strict

-- Pure rules for the Mining Supplies Store (GDD "Mining Supplies Store"):
-- what each stand offers a player given their level, whether they can pay, and the catalogue codec the
-- server publishes as GameMetadata so the client can draw every stand
-- itself. Tuning is passed in from GameData so this stays unit testable.
local HttpService = game:GetService("HttpService")

local Attributes = require(script.Parent.Attributes)
local Enums = require(script.Parent.Enums)

local StoreRules = {}

-- an upgrade track: entry N is the price of reaching level N (entry 1 is
-- unused, everyone starts at level 1); the price list's length is the top
-- level. It travels in the catalogue so the client never needs GameData
export type UpgradeTrack = {
	priceByLevel: { number },
	-- true when level 1 is not having the item at all (Compass, Geiger
	-- Counter) rather than the starter everyone carries (Pick Axe): the
	-- first buy is then the item itself, shown by its bare name, and the
	-- player's level counts from there ("Geiger Counter 2" is the first upgrade)
	startsUnowned: boolean?,
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
	-- the number the stand shows after the name; nil for a bare name (a
	-- consumable, or the first buy of a track that starts unowned)
	nameLevel: number?,
	price: number?,
	-- true for a track with a single rung (the Compass): bought once, so
	-- the stand shows no level number and reads "Owned" afterwards
	isSinglePurchase: boolean?,
}

StoreRules.MAXED_TEXT = "Maxed out"
StoreRules.OWNED_TEXT = "Owned"

-- the private CurrentPlayer attribute carrying a player's level on each track
StoreRules.LEVEL_ATTRIBUTE_BY_ITEM = {
	[Enums.StoreItem.PICK_AXE] = Attributes.PICK_AXE_LEVEL,
	[Enums.StoreItem.BOOTS] = Attributes.BOOTS_LEVEL,
	[Enums.StoreItem.BACKPACK] = Attributes.BACKPACK_LEVEL,
	[Enums.StoreItem.JET_PACK] = Attributes.JET_PACK_LEVEL,
	[Enums.StoreItem.COMPASS] = Attributes.COMPASS_LEVEL,
	[Enums.StoreItem.GEIGER_COUNTER] = Attributes.GEIGER_COUNTER_LEVEL,
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

-- level 1 is owning nothing, so two entries are one buy and no upgrades
function StoreRules.isSinglePurchase(track: UpgradeTrack): boolean
	return track.startsUnowned == true and #track.priceByLevel == 2
end

function StoreRules.getUpgradeOffer(track: UpgradeTrack, ownedLevel: number): Offer
	local targetLevel = math.floor(ownedLevel) + 1
	local price = track.priceByLevel[targetLevel]
	local isSinglePurchase = StoreRules.isSinglePurchase(track)
	if price == nil then
		return {
			status = Enums.StoreOffer.MAXED,
			isSinglePurchase = isSinglePurchase,
		}
	end
	local nameLevel: number? = targetLevel
	if track.startsUnowned then
		nameLevel = if targetLevel > 2 then targetLevel - 1 else nil
	end
	return {
		status = Enums.StoreOffer.AVAILABLE,
		level = targetLevel,
		nameLevel = nameLevel,
		price = price,
		isSinglePurchase = isSinglePurchase,
	}
end

function StoreRules.getConsumableOffer(consumable: Consumable): Offer
	return {
		status = Enums.StoreOffer.AVAILABLE,
		price = consumable.price,
	}
end

-- what a stand shows a player: nil when the catalogue has no such item
function StoreRules.getOffer(catalog: Catalog, item: number, ownedLevel: number): Offer?
	local track = catalog.upgrades[item]
	if track then
		return StoreRules.getUpgradeOffer(track, ownedLevel)
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
-- consumables, and "Maxed out" (formatted by the caller) at the top; a
-- single purchase is its bare name, then "Owned"
function StoreRules.nameText(item: number, offer: Offer): string
	local name = Enums.getPublicName(Enums.StoreItem, item) or "?"
	if offer.status == Enums.StoreOffer.MAXED then
		return if offer.isSinglePurchase then StoreRules.OWNED_TEXT else StoreRules.MAXED_TEXT
	end
	if offer.nameLevel then
		return `{name} {offer.nameLevel}`
	end
	return name
end

-- JSON keys are strings, so numeric item keys are restored on decode. They
-- are written as strings on purpose: the encoder turns a table keyed 1..n
-- into a list and drops every other numeric key, which lost the Compass
-- (item 7) when the tracks were items 1 to 4 (2026-09-30)
function StoreRules.encodeCatalog(catalog: Catalog): string
	local upgrades: { [string]: UpgradeTrack } = {}
	for item, track in catalog.upgrades do
		upgrades[tostring(item)] = track
	end
	local consumables: { [string]: Consumable } = {}
	for item, consumable in catalog.consumables do
		consumables[tostring(item)] = consumable
	end
	return HttpService:JSONEncode({
		upgrades = upgrades,
		consumables = consumables,
	})
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
				startsUnowned = track.startsUnowned == true,
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
