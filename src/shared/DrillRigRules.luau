--!strict

-- The Drill Rig's stock (2026-10-22), pure: what it holds, how it grows,
-- how it is taken, and how it travels. A stock is raw ore by
-- Enums.RawResource, kept fractional so a slow yield still adds up; the
-- whole units are what a collector gets and what the billboard shows.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local DrillRigRules = {}

export type Stock = { [number]: number }

export type ResourceShare = {
	RESOURCE: number,
	SHARE: number,
}

function DrillRigRules.total(stock: Stock): number
	local total = 0
	for _, amount in stock do
		total += amount
	end
	return total
end

-- the stock after elapsedSec of drilling at yieldPerMinute, the yield
-- split by the shares and the whole never growing past the cap; a full
-- rig adds nothing until it is collected
function DrillRigRules.accumulate(stock: Stock, yieldPerMinute: number, shares: { ResourceShare }, elapsedSec: number, cap: number): Stock
	local result = table.clone(stock)
	local room = cap - DrillRigRules.total(result)
	if room <= 0 or elapsedSec <= 0 or yieldPerMinute <= 0 then
		return result
	end
	local mined = math.min(yieldPerMinute * elapsedSec / 60, room)
	local shareTotal = 0
	for _, share in shares do
		shareTotal += share.SHARE
	end
	if shareTotal <= 0 then
		return result
	end
	for _, share in shares do
		result[share.RESOURCE] = (result[share.RESOURCE] or 0) + mined * share.SHARE / shareTotal
	end
	return result
end

-- the whole units held of each resource, what a collector can take
function DrillRigRules.wholeUnits(stock: Stock): Stock
	local whole = {}
	for resource, amount in stock do
		local units = math.floor(amount)
		if units > 0 then
			whole[resource] = units
		end
	end
	return whole
end

-- the stock less what was taken of one resource, never below zero
function DrillRigRules.take(stock: Stock, resource: number, amount: number): Stock
	local result = table.clone(stock)
	result[resource] = math.max((result[resource] or 0) - amount, 0)
	return result
end

-- the whole units as the shadow attribute carries them: a JSON list of
-- { resource, amount } rows (a map keyed by number would turn its keys
-- into strings in JSON), ordered by resource so the text is stable
function DrillRigRules.encodeStock(stock: Stock): string
	local rows = {}
	for resource, amount in DrillRigRules.wholeUnits(stock) do
		table.insert(rows, { resource = resource, amount = amount })
	end
	table.sort(
		rows,
		function(a, b)
			return a.resource < b.resource
		end
	)
	return HttpService:JSONEncode(rows)
end

function DrillRigRules.decodeStock(json: any): Stock
	local stock: Stock = {}
	if typeof(json) ~= "string" or json == "" then
		return stock
	end
	local isSuccess, rows = pcall(HttpService.JSONDecode, HttpService, json)
	if not isSuccess or typeof(rows) ~= "table" then
		return stock
	end
	for _, row in rows do
		if typeof(row) == "table" and Enums.isValidValue(Enums.RawResource, row.resource) and typeof(row.amount) == "number" then
			stock[row.resource] = row.amount
		end
	end
	return stock
end

return DrillRigRules
