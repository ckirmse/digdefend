--!strict

-- The Diamonds packs' pure rules (M40, 2026-11-03): what a well-formed
-- pack list is, and the codec that carries the catalogue to the client
-- as one GameMetadata JSON string. The server fills the Robux prices in
-- from Roblox; the client only draws what arrives. No Roblox services
-- beyond HttpService's JSON, so this is unit tested.
local HttpService = game:GetService("HttpService")

local DiamondStoreRules = {}

export type Pack = {
	id: string,
	diamonds: number,
	productId: number,
	banner: string?,
}

-- one card as the client sees it; priceRobux is 0 until Roblox has
-- answered, and a productId of 0 is a pack not yet on sale
export type PublishedPack = {
	index: number,
	id: string,
	diamonds: number,
	productId: number,
	priceRobux: number,
	banner: string?,
}

-- the problems with a pack list, in order; empty means well formed
function DiamondStoreRules.validatePacks(packs: { Pack }): { string }
	local problems = {}
	if #packs == 0 then
		table.insert(problems, "no packs")
		return problems
	end
	local seenIds: { [string]: boolean } = {}
	local seenProductIds: { [number]: boolean } = {}
	local lastDiamonds = 0
	for index, pack in packs do
		if typeof(pack.id) ~= "string" or pack.id == "" then
			table.insert(problems, `pack {index} has no id`)
		elseif seenIds[pack.id] then
			table.insert(problems, `pack id {pack.id} is used twice`)
		else
			seenIds[pack.id] = true
		end
		if typeof(pack.diamonds) ~= "number" or pack.diamonds <= 0 or pack.diamonds % 1 ~= 0 then
			table.insert(problems, `pack {index} needs a positive whole Diamonds amount`)
		elseif pack.diamonds <= lastDiamonds then
			table.insert(problems, `pack {index} must hold more Diamonds than the pack before it`)
		else
			lastDiamonds = pack.diamonds
		end
		if typeof(pack.productId) ~= "number" or pack.productId < 0 or pack.productId % 1 ~= 0 then
			table.insert(problems, `pack {index} needs a whole product id (0 for none yet)`)
		elseif pack.productId ~= 0 then
			if seenProductIds[pack.productId] then
				table.insert(problems, `product id {pack.productId} is used twice`)
			end
			seenProductIds[pack.productId] = true
		end
		if pack.banner ~= nil and (typeof(pack.banner) ~= "string" or pack.banner == "") then
			table.insert(problems, `pack {index} has a banner that is not a non-empty string`)
		end
	end
	return problems
end

-- the pack a product id belongs to, for the receipt handler
function DiamondStoreRules.findPackByProductId(packs: { Pack }, productId: number): Pack?
	if productId == 0 then
		return nil
	end
	for _, pack in packs do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

function DiamondStoreRules.publish(packs: { Pack }, priceByProductId: { [number]: number }): { PublishedPack }
	local published = {}
	for index, pack in packs do
		table.insert(published, {
			index = index,
			id = pack.id,
			diamonds = pack.diamonds,
			productId = pack.productId,
			priceRobux = priceByProductId[pack.productId] or 0,
			banner = pack.banner,
		})
	end
	return published
end

function DiamondStoreRules.encodeCatalogue(published: { PublishedPack }): string
	return HttpService:JSONEncode(published)
end

function DiamondStoreRules.decodeCatalogue(encoded: any): { PublishedPack }?
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
	local published: { PublishedPack } = {}
	for _, entry in decoded do
		if
			typeof(entry) ~= "table"
			or typeof(entry.index) ~= "number"
			or typeof(entry.id) ~= "string"
			or typeof(entry.diamonds) ~= "number"
			or typeof(entry.productId) ~= "number"
			or typeof(entry.priceRobux) ~= "number"
		then
			return nil
		end
		table.insert(published, {
			index = entry.index,
			id = entry.id,
			diamonds = entry.diamonds,
			productId = entry.productId,
			priceRobux = entry.priceRobux,
			banner = if typeof(entry.banner) == "string" then entry.banner else nil,
		})
	end
	table.sort(
		published,
		function(a, b)
			return a.index < b.index
		end
	)
	return published
end

-- whether a card can be bought at all: the product exists on Roblox
function DiamondStoreRules.isOnSale(pack: PublishedPack): boolean
	return pack.productId ~= 0
end

-- the pack to offer a player short of Diamonds: the smallest on-sale one
-- that covers the shortfall, else the largest on sale (something is
-- always offered while any pack is), nil when nothing is on sale or the
-- player is not short at all
function DiamondStoreRules.packForShortfall(published: { PublishedPack }, priceDiamonds: number, balance: number): PublishedPack?
	local shortfall = priceDiamonds - balance
	if shortfall <= 0 then
		return nil
	end
	local largest: PublishedPack? = nil
	for _, pack in published do
		if not DiamondStoreRules.isOnSale(pack) then
			continue
		end
		if pack.diamonds >= shortfall then
			return pack
		end
		if not largest or pack.diamonds > largest.diamonds then
			largest = pack
		end
	end
	return largest
end

return DiamondStoreRules
