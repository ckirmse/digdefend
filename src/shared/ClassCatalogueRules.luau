--!strict

-- The class catalogue the Class Menu draws from (GDD "Classes", the Class
-- Equip Menu of 2026-11-04): one entry per class the menu lists, with the
-- kit kinds from the roster and the words from GameData/Classes/
-- Descriptions already resolved, carried to the client as one GameMetadata
-- JSON string so the client never requires GameData. Pure and unit tested.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local ClassCatalogueRules = {}

export type Kit = {
	weapon: number,
	post: number,
	tower: number,
	gadget: number,
}

export type KitDescriptions = {
	weapon: string,
	post: string,
	tower: string,
	gadget: string,
}

export type Entry = {
	kind: number,
	description: string,
	kit: Kit,
	kitDescriptions: KitDescriptions,
}

export type Catalogue = { Entry }

-- the roster row shape this module reads (GameData/Classes/Roster.BY_KIND)
export type RosterRow = {
	KIT: {
		WEAPON: number,
		POST: number,
		TOWER: number,
		GADGET: number,
	},
}

export type Descriptions = {
	BY_CLASS_KIND: { [number]: string },
	BY_KIT_SLOT: { [number]: { [number]: string } },
	BY_GADGET_KIND: { [number]: string },
}

-- the launch classes in enum order (the ones a save may hold whether or
-- not they are built yet); every class not in `excludedKinds`
function ClassCatalogueRules.listedKinds(excludedKinds: { number }): { number }
	local isExcluded: { [number]: boolean } = {}
	for _, kind in excludedKinds do
		isExcluded[kind] = true
	end
	local kinds = {}
	for _, kind in Enums.getAllValues(Enums.ClassKind) do
		if not isExcluded[kind] then
			table.insert(kinds, kind)
		end
	end
	table.sort(kinds)
	return kinds
end

local function describeKit(descriptions: Descriptions, gearSlot: number, kind: number): string
	local bySlot = descriptions.BY_KIT_SLOT[gearSlot]
	return if bySlot then (bySlot[kind] or "") else ""
end

function ClassCatalogueRules.publish(roster: { [number]: RosterRow }, descriptions: Descriptions, kinds: { number }): Catalogue
	local catalogue: Catalogue = {}
	for _, kind in kinds do
		local row = roster[kind]
		if not row then
			continue
		end
		local kit = row.KIT
		table.insert(catalogue, {
			kind = kind,
			description = descriptions.BY_CLASS_KIND[kind] or "",
			kit = {
				weapon = kit.WEAPON,
				post = kit.POST,
				tower = kit.TOWER,
				gadget = kit.GADGET,
			},
			kitDescriptions = {
				weapon = describeKit(descriptions, Enums.GearSlot.WEAPON, kit.WEAPON),
				post = describeKit(descriptions, Enums.GearSlot.POST, kit.POST),
				tower = describeKit(descriptions, Enums.GearSlot.TOWER_1, kit.TOWER),
				gadget = descriptions.BY_GADGET_KIND[kit.GADGET] or "",
			},
		})
	end
	return catalogue
end

function ClassCatalogueRules.encode(catalogue: Catalogue): string
	return HttpService:JSONEncode(catalogue)
end

local function isKit(kit: any): boolean
	return typeof(kit) == "table"
		and typeof(kit.weapon) == "number"
		and typeof(kit.post) == "number"
		and typeof(kit.tower) == "number"
		and typeof(kit.gadget) == "number"
end

local function kitDescriptionsOf(decoded: any): KitDescriptions
	local source = if typeof(decoded) == "table" then decoded else {}
	local function text(value: any): string
		return if typeof(value) == "string" then value else ""
	end
	return {
		weapon = text(source.weapon),
		post = text(source.post),
		tower = text(source.tower),
		gadget = text(source.gadget),
	}
end

function ClassCatalogueRules.decode(encoded: any): Catalogue
	local catalogue: Catalogue = {}
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
	for _, entry in decoded do
		if typeof(entry) ~= "table" or not Enums.isValidValue(Enums.ClassKind, entry.kind) or not isKit(entry.kit) then
			continue
		end
		table.insert(catalogue, {
			kind = entry.kind,
			description = if typeof(entry.description) == "string" then entry.description else "",
			kit = {
				weapon = entry.kit.weapon,
				post = entry.kit.post,
				tower = entry.kit.tower,
				gadget = entry.kit.gadget,
			},
			kitDescriptions = kitDescriptionsOf(entry.kitDescriptions),
		})
	end
	return catalogue
end

function ClassCatalogueRules.findEntry(catalogue: Catalogue, kind: number): Entry?
	for _, entry in catalogue do
		if entry.kind == kind then
			return entry
		end
	end
	return nil
end

-- the Class Menu's list order (designer, 2026-11-05): the class in play
-- first, then the owned classes, then the locked ones, each group in the
-- catalogue's own order. Taken once when the menu opens, so an equip
-- never reshuffles the list under the player's finger
function ClassCatalogueRules.sortForMenu(catalogue: Catalogue, activeKind: number?, isOwnedByKind: { [number]: boolean }): Catalogue
	local function rankOf(entry: Entry): number
		if entry.kind == activeKind then
			return 1
		end
		if isOwnedByKind[entry.kind] then
			return 2
		end
		return 3
	end
	local indexByEntry: { [Entry]: number } = {}
	local sorted: Catalogue = {}
	for index, entry in catalogue do
		indexByEntry[entry] = index
		table.insert(sorted, entry)
	end
	table.sort(
		sorted,
		function(left, right)
			local leftRank = rankOf(left)
			local rightRank = rankOf(right)
			if leftRank ~= rightRank then
				return leftRank < rightRank
			end
			return indexByEntry[left] < indexByEntry[right]
		end
	)
	return sorted
end

return ClassCatalogueRules
