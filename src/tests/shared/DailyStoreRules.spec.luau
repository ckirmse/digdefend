-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DailyStoreRules = require(game:GetService("ReplicatedStorage").Shared.DailyStoreRules)

local CONFIG = {
	classCount = 2,
	cosmeticCount = 1,
	intervalSec = 86400,
}
-- a day number of the size the real clock gives
local START_DAY = 20767

local function makeIds(prefix: string, count: number): { string }
	local ids = {}
	for index = 1, count do
		table.insert(ids, string.format("%s_%02d", prefix, index))
	end
	return ids
end

local function countShared(first: { string }, second: { string }): number
	local shared = 0
	for _, id in first do
		if table.find(second, id) then
			shared += 1
		end
	end
	return shared
end

local function hasRepeat(picked: { string }): boolean
	for index, id in picked do
		if table.find(picked, id) ~= index then
			return true
		end
	end
	return false
end

describe(
	"DailyStoreRules.pickItems",
	function()
		it(
			"shows every item when there are no more than fit",
			function()
				expect(DailyStoreRules.pickItems({ "B", "A" }, START_DAY, 3)).toEqual({ "A", "B" })
				expect(DailyStoreRules.pickItems({}, START_DAY, 3)).toEqual({})
				expect(DailyStoreRules.pickItems({ "A", "B" }, START_DAY, 0)).toEqual({})
			end
		)

		it(
			"picks the same distinct items for a day whatever order the ids come in",
			function()
				local ids = makeIds("ITEM", 12)
				local picked = DailyStoreRules.pickItems(ids, START_DAY, 3)
				local reversed = {}
				for index = #ids, 1, -1 do
					table.insert(reversed, ids[index])
				end
				expect(#picked).toBe(3)
				expect(hasRepeat(picked)).toBe(false)
				expect(DailyStoreRules.pickItems(reversed, START_DAY, 3)).toEqual(picked)
			end
		)

		it(
			"never sells an item two days running with two days' worth or more",
			function()
				local cases = {
					{ count = 2, hand = 1 },
					{ count = 3, hand = 1 },
					{ count = 8, hand = 2 },
					{ count = 6, hand = 3 },
					{ count = 10, hand = 3 },
					{ count = 11, hand = 3 },
					{ count = 36, hand = 3 },
				}
				for _, case in cases do
					local ids = makeIds("ITEM", case.count)
					local previous = DailyStoreRules.pickItems(ids, START_DAY, case.hand)
					for day = START_DAY + 1, START_DAY + 400 do
						local picked = DailyStoreRules.pickItems(ids, day, case.hand)
						expect(#picked).toBe(case.hand)
						expect(hasRepeat(picked)).toBe(false)
						expect(countShared(previous, picked)).toBe(0)
						previous = picked
					end
				end
			end
		)

		it(
			"gets round to every item",
			function()
				local ids = makeIds("ITEM", 25)
				local seen: { [string]: boolean } = {}
				for day = START_DAY, START_DAY + 80 do
					for _, id in DailyStoreRules.pickItems(ids, day, 3) do
						seen[id] = true
					end
				end
				local distinct = 0
				for _ in seen do
					distinct += 1
				end
				expect(distinct).toBe(25)
			end
		)

		it(
			"still picks distinct items from a shelf with less than two days' worth",
			function()
				local ids = makeIds("ITEM", 5)
				for day = START_DAY, START_DAY + 50 do
					local picked = DailyStoreRules.pickItems(ids, day, 3)
					expect(#picked).toBe(3)
					expect(hasRepeat(picked)).toBe(false)
				end
			end
		)
	end
)

describe(
	"DailyStoreRules.build",
	function()
		it(
			"names the day, the next change, and both shelves",
			function()
				local classIds = makeIds("CLASS", 8)
				local cosmeticIds = makeIds("SKIN", 12)
				local store = DailyStoreRules.build(classIds, cosmeticIds, START_DAY * 86400 + 3600, CONFIG)
				expect(store.day).toBe(START_DAY)
				expect(store.refreshTime).toBe((START_DAY + 1) * 86400)
				expect(store.classIds).toEqual(DailyStoreRules.pickItems(classIds, START_DAY, 2))
				expect(store.cosmeticIds).toEqual(DailyStoreRules.pickItems(cosmeticIds, START_DAY, 1))
				expect(DailyStoreRules.isClassOnSale(store, store.classIds[1])).toBe(true)
				expect(DailyStoreRules.isClassOnSale(store, store.cosmeticIds[1])).toBe(false)
				expect(DailyStoreRules.isCosmeticOnSale(store, store.cosmeticIds[1])).toBe(true)
				expect(DailyStoreRules.isCosmeticOnSale(store, "NOT_AN_ITEM")).toBe(false)
			end
		)

		it(
			"always has a class and a cosmetic while both exist",
			function()
				local classIds = makeIds("CLASS", 8)
				local cosmeticIds = makeIds("SKIN", 2)
				for day = START_DAY, START_DAY + 60 do
					local store = DailyStoreRules.build(classIds, cosmeticIds, day * 86400, CONFIG)
					expect(#store.classIds).toBe(2)
					expect(#store.cosmeticIds).toBe(1)
				end
			end
		)

		it(
			"gives a short shelf's room to the other",
			function()
				local noCosmetics = DailyStoreRules.build(makeIds("CLASS", 8), {}, START_DAY * 86400, CONFIG)
				expect(#noCosmetics.classIds).toBe(3)
				expect(#noCosmetics.cosmeticIds).toBe(0)
				local oneClass = DailyStoreRules.build(makeIds("CLASS", 1), makeIds("SKIN", 9), START_DAY * 86400, CONFIG)
				expect(#oneClass.classIds).toBe(1)
				expect(#oneClass.cosmeticIds).toBe(2)
			end
		)

		it(
			"round-trips through its codec",
			function()
				local store = DailyStoreRules.build(makeIds("CLASS", 8), makeIds("SKIN", 12), START_DAY * 86400, CONFIG)
				expect(DailyStoreRules.decode(DailyStoreRules.encode(store))).toEqual(store)
				expect(DailyStoreRules.decode(nil)).toBeNil()
				expect(DailyStoreRules.decode("{not json")).toBeNil()
			end
		)
	end
)

describe(
	"DailyStoreRules.formatRefresh",
	function()
		it(
			"writes hours, minutes, and seconds",
			function()
				expect(DailyStoreRules.formatRefresh(5 * 3600 + 3 * 60 + 9)).toBe("5h 3m 9s")
				expect(DailyStoreRules.formatRefresh(59.2)).toBe("0h 1m 0s")
				expect(DailyStoreRules.formatRefresh(-4)).toBe("0h 0m 0s")
			end
		)
	end
)

describe(
	"DailyStoreRules purchases",
	function()
		it(
			"counts a class as bought only on the day it was bought",
			function()
				local purchases = DailyStoreRules.getDefaultPurchases()
				expect(DailyStoreRules.hasBoughtClass(purchases, 12, "GUNNER")).toBe(false)
				DailyStoreRules.recordClassPurchase(purchases, 12, "GUNNER")
				expect(DailyStoreRules.hasBoughtClass(purchases, 12, "GUNNER")).toBe(true)
				expect(DailyStoreRules.hasBoughtClass(purchases, 12, "RANGER")).toBe(false)
				expect(DailyStoreRules.hasBoughtClass(purchases, 13, "GUNNER")).toBe(false)
			end
		)
		it(
			"empties an older day's record on the next purchase",
			function()
				local purchases = DailyStoreRules.getDefaultPurchases()
				DailyStoreRules.recordClassPurchase(purchases, 12, "GUNNER")
				DailyStoreRules.recordClassPurchase(purchases, 12, "GUNNER")
				DailyStoreRules.recordClassPurchase(purchases, 13, "RANGER")
				expect(purchases).toEqual({ day = 13, classIds = { "RANGER" } })
			end
		)
		it(
			"survives its codec and reads rubbish as nothing bought",
			function()
				local purchases = { day = 12, classIds = { "GUNNER", "RANGER" } }
				expect(DailyStoreRules.decodePurchases(DailyStoreRules.encodePurchases(purchases))).toEqual(purchases)
				expect(DailyStoreRules.decodePurchases(nil)).toEqual({ day = 0, classIds = {} })
				expect(DailyStoreRules.decodePurchases("not json")).toEqual({ day = 0, classIds = {} })
			end
		)
	end
)
