--!strict

-- The Key Store's pure rules (GDD "Class Unlock System", Keys; M61,
-- 2026-11-05): the one list of everything Keys buy, built from the two
-- cosmetic catalogues (the skins of GameData/Cosmetics/Catalogue and the
-- hats of GameData/Characters/Hats), what a well-formed price is, whether
-- a player may buy an entry, and the codec that carries the list as one
-- GameMetadata JSON string. A hat's picture is Roblox's own thumbnail of
-- the accessory; a skin's is the icon Icons.COSMETIC_SKIN names, which the
-- server resolves before publishing so the client needs no catalogue of
-- its own. No Roblox services beyond HttpService's JSON, so this is unit
-- tested.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local KeyStoreRules = {}

-- a skin as GameData/Cosmetics/Catalogue writes it (CosmeticRules.Entry
-- with the price this store needs)
export type SkinEntry = {
	SLOT: number,
	NAME: string,
	PRICE_KEYS: number?,
}

-- a hat as GameData/Characters/Hats writes it
export type HatEntry = {
	ASSET_ID: number,
	NAME: string,
	PRICE_KEYS: number?,
}

-- one item as the client draws it
export type Entry = {
	id: string,
	slot: number,
	name: string,
	priceKeys: number,
	iconId: string,
}

export type Owned = { [string]: boolean }

-- why a buy is refused; nil means it may go ahead
export type BuyRefusal = "owned" | "unknown" | "short"

-- Roblox's own render of an accessory, the hat catalogue's picture
local HAT_THUMBNAIL_FORMAT = "rbxthumb://type=Asset&id=%d&w=150&h=150"

local function isValidPrice(price: any): boolean
	return typeof(price) == "number" and price > 0 and price == math.floor(price)
end

-- the problems with the two catalogues' prices, in order; empty means
-- every entry can be sold
function KeyStoreRules.validate(skins: { [string]: SkinEntry }, hats: { [string]: HatEntry }): { string }
	local problems = {}
	for id, entry in skins do
		if not isValidPrice(entry.PRICE_KEYS) then
			table.insert(problems, `{id} has no PRICE_KEYS (a positive whole number of Keys)`)
		end
	end
	for id, entry in hats do
		if not isValidPrice(entry.PRICE_KEYS) then
			table.insert(problems, `{id} has no PRICE_KEYS (a positive whole number of Keys)`)
		end
	end
	table.sort(problems)
	return problems
end

function KeyStoreRules.hatIconId(assetId: number): string
	return string.format(HAT_THUMBNAIL_FORMAT, assetId)
end

-- the store's list: every skin and every hat, sorted by slot then name so
-- a slot's items sit together in the order the enum lists the slots
function KeyStoreRules.build(skins: { [string]: SkinEntry }, hats: { [string]: HatEntry }, skinIcons: { [string]: string }, placeholderIconId: string): { Entry }
	local entries: { Entry } = {}
	for id, entry in skins do
		table.insert(entries, {
			id = id,
			slot = entry.SLOT,
			name = entry.NAME,
			priceKeys = entry.PRICE_KEYS or 0,
			iconId = skinIcons[id] or placeholderIconId,
		})
	end
	for id, entry in hats do
		table.insert(entries, {
			id = id,
			slot = Enums.CosmeticSlot.HELMET,
			name = entry.NAME,
			priceKeys = entry.PRICE_KEYS or 0,
			iconId = KeyStoreRules.hatIconId(entry.ASSET_ID),
		})
	end
	table.sort(
		entries,
		function(a: Entry, b: Entry)
			if a.slot ~= b.slot then
				return a.slot < b.slot
			end
			if a.name ~= b.name then
				return a.name < b.name
			end
			return a.id < b.id
		end
	)
	return entries
end

function KeyStoreRules.findEntry(entries: { Entry }, id: string): Entry?
	for _, entry in entries do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- whether the player may buy an item now, and if not why: it is already
-- theirs, it is not in the store, or the Keys do not cover it
function KeyStoreRules.buyRefusal(entries: { Entry }, owned: Owned, keys: number, id: string): BuyRefusal?
	local entry = KeyStoreRules.findEntry(entries, id)
	if not entry then
		return "unknown"
	end
	if owned[id] then
		return "owned"
	end
	if keys < entry.priceKeys then
		return "short"
	end
	return nil
end

function KeyStoreRules.encode(entries: { Entry }): string
	return HttpService:JSONEncode(entries)
end

function KeyStoreRules.decode(encoded: any): { Entry }?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return nil
	end
	local entries: { Entry } = {}
	for _, entry in decoded do
		if
			typeof(entry) ~= "table"
			or typeof(entry.id) ~= "string"
			or typeof(entry.slot) ~= "number"
			or typeof(entry.name) ~= "string"
			or typeof(entry.priceKeys) ~= "number"
			or typeof(entry.iconId) ~= "string"
		then
			return nil
		end
		table.insert(entries, {
			id = entry.id,
			slot = entry.slot,
			name = entry.name,
			priceKeys = entry.priceKeys,
			iconId = entry.iconId,
		})
	end
	return entries
end

return KeyStoreRules
