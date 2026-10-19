--!strict

-- Pure rules for gadget upgrades (M67): a gadget that scales has one
-- level like a Tower, bought with Iron at the Post & Gadget Upgrades
-- table, each level raising every number in the gadget's STATS_BY_LEVEL.
-- Only a gadget with a price list is upgradable, so the four that fight
-- (Auto Turret, Grounding Net, Storm Rod, Remote Charge) show a row and
-- the utility gadgets never do. The server publishes the price lists as
-- one GameMetadata JSON catalogue and the menu reads it back here.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local GadgetRules = {}

export type Catalog = {
	-- Enums.GadgetKind -> Iron price of each upgrade; level 1 is the start
	pricesByKind: { [number]: { number } },
}

export type Offer = {
	-- Enums.StoreOffer
	status: number,
	-- the level the buy reaches, nil when maxed
	level: number?,
	price: number?,
}

GadgetRules.STARTING_LEVEL = 1

function GadgetRules.isUpgradable(catalog: Catalog, gadgetKind: number): boolean
	local prices = catalog.pricesByKind[gadgetKind]
	return prices ~= nil and #prices > 0
end

-- the top level: the start plus one per price
function GadgetRules.levelCap(catalog: Catalog, gadgetKind: number): number
	local prices = catalog.pricesByKind[gadgetKind]
	return GadgetRules.STARTING_LEVEL + (if prices then #prices else 0)
end

function GadgetRules.getUpgradeOffer(catalog: Catalog, gadgetKind: number, level: number): Offer
	local prices = catalog.pricesByKind[gadgetKind]
	local nextLevel = level + 1
	if not prices or nextLevel > GadgetRules.levelCap(catalog, gadgetKind) then
		return {
			status = Enums.StoreOffer.MAXED,
			level = nil,
			price = nil,
		}
	end
	return {
		status = Enums.StoreOffer.AVAILABLE,
		level = nextLevel,
		-- the first price buys level 2
		price = prices[nextLevel - GadgetRules.STARTING_LEVEL],
	}
end

function GadgetRules.canAfford(balance: number, price: number): boolean
	return balance >= price
end

-- the row of a stats table for a level, held inside the table's range
function GadgetRules.statsFor<T>(statsByLevel: { T }, level: number): T
	local clamped = math.clamp(math.floor(level), 1, #statsByLevel)
	return statsByLevel[clamped]
end

function GadgetRules.encodeCatalog(catalog: Catalog): string
	local prices: { [string]: { number } } = {}
	for gadgetKind, list in catalog.pricesByKind do
		prices[tostring(gadgetKind)] = list
	end
	return HttpService:JSONEncode({ prices = prices })
end

function GadgetRules.decodeCatalog(encoded: any): Catalog?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.prices) ~= "table" then
		return nil
	end
	local pricesByKind: { [number]: { number } } = {}
	for key, list in decoded.prices do
		local gadgetKind = tonumber(key)
		if gadgetKind and typeof(list) == "table" then
			pricesByKind[gadgetKind] = list
		end
	end
	return { pricesByKind = pricesByKind }
end

return GadgetRules
