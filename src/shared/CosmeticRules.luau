--!strict

-- The cosmetics catalogue's pure rules (M61 first pass, 2026-11-04): what
-- a well-formed catalogue is, the list the client draws it from, and the
-- codec that carries it as one GameMetadata JSON string. Hats stay in
-- GameData/Characters/Hats with their own loader; this catalogue holds
-- the skins made from the game's own templates (pick axes, jet packs,
-- later every Enums.CosmeticSlot), each named by the id a save stores and
-- the template under GameAssets/Cosmetics/<SLOT>/<template> it is drawn
-- from. No Roblox services beyond HttpService's JSON, so this is unit
-- tested.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local CosmeticRules = {}

export type Entry = {
	SLOT: number,
	NAME: string,
	TEMPLATE: string,
	-- a dial on the crate reveal's fitted size, 1 for the pose's own
	REVEAL_SCALE: number?,
}

export type Catalogue = { [string]: Entry }

-- one entry as the client sees it
export type PublishedEntry = {
	id: string,
	slot: number,
	name: string,
	templateName: string,
	revealScale: number,
}

-- the problems with a catalogue, in order; empty means well formed
function CosmeticRules.validateCatalogue(catalogue: Catalogue): { string }
	local problems = {}
	for id, entry in catalogue do
		if typeof(id) ~= "string" or id == "" then
			table.insert(problems, "an entry has no id")
			continue
		end
		if typeof(entry) ~= "table" then
			table.insert(problems, `{id} is not a table`)
			continue
		end
		if not Enums.isValidValue(Enums.CosmeticSlot, entry.SLOT) then
			table.insert(problems, `{id} has no Enums.CosmeticSlot`)
		end
		if typeof(entry.NAME) ~= "string" or entry.NAME == "" then
			table.insert(problems, `{id} has no NAME`)
		end
		if typeof(entry.TEMPLATE) ~= "string" or entry.TEMPLATE == "" then
			table.insert(problems, `{id} has no TEMPLATE`)
		end
		if entry.REVEAL_SCALE ~= nil and (typeof(entry.REVEAL_SCALE) ~= "number" or entry.REVEAL_SCALE <= 0) then
			table.insert(problems, `{id} has a REVEAL_SCALE that is not a positive number`)
		end
	end
	table.sort(problems)
	return problems
end

-- the catalogue as a list sorted by id, the order the client shows
function CosmeticRules.publish(catalogue: Catalogue): { PublishedEntry }
	local published: { PublishedEntry } = {}
	for id, entry in catalogue do
		table.insert(published, {
			id = id,
			slot = entry.SLOT,
			name = entry.NAME,
			templateName = entry.TEMPLATE,
			revealScale = entry.REVEAL_SCALE or 1,
		})
	end
	table.sort(
		published,
		function(a: PublishedEntry, b: PublishedEntry)
			return a.id < b.id
		end
	)
	return published
end

function CosmeticRules.encodeCatalogue(published: { PublishedEntry }): string
	return HttpService:JSONEncode(published)
end

function CosmeticRules.decodeCatalogue(encoded: any): { PublishedEntry }?
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
	local published: { PublishedEntry } = {}
	for _, entry in decoded do
		if
			typeof(entry) ~= "table"
			or typeof(entry.id) ~= "string"
			or typeof(entry.slot) ~= "number"
			or typeof(entry.name) ~= "string"
			or typeof(entry.templateName) ~= "string"
			or typeof(entry.revealScale) ~= "number"
		then
			return nil
		end
		table.insert(published, {
			id = entry.id,
			slot = entry.slot,
			name = entry.name,
			templateName = entry.templateName,
			revealScale = entry.revealScale,
		})
	end
	return published
end

function CosmeticRules.findEntry(published: { PublishedEntry }, id: string): PublishedEntry?
	for _, entry in published do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- whether a skin id may go in a slot: the stock art anywhere, else a
-- catalogue entry made for that slot
function CosmeticRules.isSkinForSlot(catalogue: Catalogue, defaultSkinId: string, slot: number, skinId: string): boolean
	if skinId == defaultSkinId then
		return true
	end
	local entry = catalogue[skinId]
	return entry ~= nil and entry.SLOT == slot
end

return CosmeticRules
