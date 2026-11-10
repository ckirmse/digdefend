--!strict

-- The rotating store's rules (designer, 2026-11-10): a few class cards
-- and a few cosmetics on sale at a time, the same for every player on
-- every server, changed every interval (a day). Pure: a shelf is a
-- function of the day's number and the ids alone, so two servers that
-- agree on the clock agree on the store with nothing stored or sent
-- between them. The two shelves (classes, cosmetics) are dealt apart, so
-- every day has at least one of each while both exist.
--
-- "Never the same item two days in a row" cannot be done by looking at
-- yesterday's pick, since yesterday's would need the day before's, and
-- so on back for ever. Instead a shelf is dealt in cycles: a cycle
-- shuffles every id once (seeded by the cycle's number) and hands them
-- out a day at a time, so days inside a cycle never share an item. The
-- one join left is a cycle's first day against the cycle before's last
-- day, and that is settled without a chain: the first two days' worth of
-- a cycle's shuffle are reordered so the ones the previous cycle ended
-- on come second, and a cycle's last day is never touched by that (it
-- sits past the first two days, which is why this needs at least three
-- days in a cycle). A shelf with exactly two days' worth alternates
-- between two fixed hands, which never repeats either. Only a shelf with
-- less than two days' worth can repeat (there is no way round it), and
-- one with no more ids than its hand shows them all every day.
local HttpService = game:GetService("HttpService")

local DailyStoreRules = {}

export type Config = {
	-- how many class cards and how many cosmetics are on sale at once
	classCount: number,
	cosmeticCount: number,
	-- how long a set stays, in seconds
	intervalSec: number,
}

-- what the server publishes: the day's number, when the next set comes,
-- and what is on sale, in the order the cards are laid out (class ids
-- are Enums.ClassKind key names)
export type Store = {
	day: number,
	refreshTime: number,
	classIds: { string },
	cosmeticIds: { string },
}

-- what one player has bought from a day's set (2026-11-10): a class card
-- sells once per class per day, so the save keeps the day's number and
-- the class ids bought on it. A record from another day counts as empty,
-- which is how the limit lifts when the store changes
export type Purchases = {
	day: number,
	classIds: { string },
}

-- kept apart from any other use of small integers as seeds
local SEED_SALT = 7919
-- the one shuffle a two-day shelf alternates through
local ALTERNATING_SEED = 0

local function shuffled(ids: { string }, seed: number): { string }
	local copy = table.clone(ids)
	Random.new(seed * SEED_SALT + 1):Shuffle(copy)
	return copy
end

-- the whole days gone by at `now`
function DailyStoreRules.dayIndex(now: number, intervalSec: number): number
	return math.floor(now / intervalSec)
end

-- a cycle's ids in dealing order, its first day cleared of whatever the
-- cycle before ended on
local function arrangeCycle(sorted: { string }, cycle: number, itemCount: number, daysPerCycle: number): { string }
	local order = shuffled(sorted, cycle)
	local previous = shuffled(sorted, cycle - 1)
	local endedOn: { [string]: boolean } = {}
	for index = (daysPerCycle - 1) * itemCount + 1, daysPerCycle * itemCount do
		endedOn[previous[index]] = true
	end
	local clear: { string } = {}
	local clashing: { string } = {}
	for index = 1, itemCount * 2 do
		local id = order[index]
		table.insert(if endedOn[id] then clashing else clear, id)
	end
	for index, id in clear do
		order[index] = id
	end
	for index, id in clashing do
		order[#clear + index] = id
	end
	return order
end

-- one shelf's ids for a day, `itemCount` of them (fewer when the shelf
-- holds fewer)
function DailyStoreRules.pickItems(ids: { string }, day: number, itemCount: number): { string }
	local sorted = table.clone(ids)
	table.sort(sorted)
	if itemCount <= 0 then
		return {}
	end
	if #sorted <= itemCount then
		return sorted
	end
	local daysPerCycle = #sorted // itemCount
	local order: { string }
	local firstIndex: number
	if daysPerCycle >= 3 then
		order = arrangeCycle(sorted, day // daysPerCycle, itemCount, daysPerCycle)
		firstIndex = (day % daysPerCycle) * itemCount
	elseif daysPerCycle == 2 then
		order = shuffled(sorted, ALTERNATING_SEED)
		firstIndex = (day % 2) * itemCount
	else
		order = shuffled(sorted, day)
		firstIndex = 0
	end
	local picked: { string } = {}
	for index = 1, itemCount do
		picked[index] = order[firstIndex + index]
	end
	return picked
end

-- the day's two shelves. A shelf too short to fill its share gives the
-- room to the other, so the store shows as many cards as it can
function DailyStoreRules.build(classIds: { string }, cosmeticIds: { string }, now: number, config: Config): Store
	local day = DailyStoreRules.dayIndex(now, config.intervalSec)
	local total = config.classCount + config.cosmeticCount
	local cosmeticCount = math.min(config.cosmeticCount, #cosmeticIds)
	local classCount = math.min(total - cosmeticCount, #classIds)
	cosmeticCount = math.min(total - classCount, #cosmeticIds)
	return {
		day = day,
		refreshTime = (day + 1) * config.intervalSec,
		classIds = DailyStoreRules.pickItems(classIds, day, classCount),
		cosmeticIds = DailyStoreRules.pickItems(cosmeticIds, day, cosmeticCount),
	}
end

function DailyStoreRules.isClassOnSale(store: Store, classId: string): boolean
	return table.find(store.classIds, classId) ~= nil
end

function DailyStoreRules.isCosmeticOnSale(store: Store, cosmeticId: string): boolean
	return table.find(store.cosmeticIds, cosmeticId) ~= nil
end

function DailyStoreRules.getDefaultPurchases(): Purchases
	return {
		day = 0,
		classIds = {},
	}
end

-- true when this class's card was already bought from `day`'s set
function DailyStoreRules.hasBoughtClass(purchases: Purchases, day: number, classId: string): boolean
	return purchases.day == day and table.find(purchases.classIds, classId) ~= nil
end

-- writes the purchase into the record in place; an older day's record
-- is emptied first
function DailyStoreRules.recordClassPurchase(purchases: Purchases, day: number, classId: string)
	if purchases.day ~= day then
		purchases.day = day
		table.clear(purchases.classIds)
	end
	if not table.find(purchases.classIds, classId) then
		table.insert(purchases.classIds, classId)
	end
end

-- the wait for the next set as "5h 3m 9s", never negative
function DailyStoreRules.formatRefresh(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%dh %dm %ds", whole // 3600, (whole % 3600) // 60, whole % 60)
end

function DailyStoreRules.encode(store: Store): string
	return HttpService:JSONEncode(store)
end

local function decodeStrings(value: any): { string }
	local strings: { string } = {}
	if typeof(value) == "table" then
		for _, entry in value do
			if typeof(entry) == "string" then
				table.insert(strings, entry)
			end
		end
	end
	return strings
end

function DailyStoreRules.encodePurchases(purchases: Purchases): string
	return HttpService:JSONEncode(purchases)
end

-- anything unreadable is a player who has bought nothing
function DailyStoreRules.decodePurchases(encoded: any): Purchases
	if typeof(encoded) ~= "string" or encoded == "" then
		return DailyStoreRules.getDefaultPurchases()
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.day) ~= "number" then
		return DailyStoreRules.getDefaultPurchases()
	end
	return {
		day = decoded.day,
		classIds = decodeStrings(decoded.classIds),
	}
end

function DailyStoreRules.decode(encoded: any): Store?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.day) ~= "number" or typeof(decoded.refreshTime) ~= "number" then
		return nil
	end
	return {
		day = decoded.day,
		refreshTime = decoded.refreshTime,
		classIds = decodeStrings(decoded.classIds),
		cosmeticIds = decodeStrings(decoded.cosmeticIds),
	}
end

return DailyStoreRules
