--!strict

-- Daily Rewards (GDD "Daily Rewards Menu", M39; the format of Lucky
-- Squares): progress is driven by claims, never by the calendar. A day
-- stays claimable until it is claimed, each claim starts a wait before
-- the next day opens, and a missed day costs nothing (there is no streak
-- to break). The rewards are a list of tiles; the last tile repeats for
-- every day past the list's end ("Day 8+" on a list of eight). Pure, so
-- the server's claim and the client's menu judge by the same functions.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local DailyRewardRules = {}

-- the save's record: the last day claimed (0 on a new account) and the
-- server time from which the next one may be claimed
export type State = {
	lastClaimedDay: number,
	nextClaimTime: number,
}

-- one tile as GameData writes it
export type Reward = {
	KIND: number,
	-- Diamonds or Keys paid
	AMOUNT: number?,
	-- a COSMETIC tile's skin, and the Diamonds paid in its place to a
	-- player who already owns it
	COSMETIC_ID: string?,
	DUPLICATE_DIAMONDS: number?,
}

-- one tile as the client draws it; for a cosmetic, amount is the
-- Diamonds paid for a duplicate
export type PublishedReward = {
	kind: number,
	amount: number,
	cosmeticId: string?,
}

export type TileState = "READY" | "CLAIMED" | "LOCKED"

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number" and value > 0 and value == math.floor(value)
end

-- the problems with the reward list, in order; empty means every tile can
-- be paid. isKnownCosmetic answers for the cosmetics catalogue
function DailyRewardRules.validate(rewards: { Reward }, isKnownCosmetic: (cosmeticId: string) -> boolean): { string }
	local problems = {}
	if #rewards == 0 then
		table.insert(problems, "REWARDS is empty")
	end
	for tileIndex, reward in rewards do
		local kind = reward.KIND
		if kind == Enums.DailyRewardKind.DIAMONDS or kind == Enums.DailyRewardKind.KEYS then
			if not isPositiveInteger(reward.AMOUNT) then
				table.insert(problems, `tile {tileIndex} needs a positive whole AMOUNT`)
			end
		elseif kind == Enums.DailyRewardKind.COSMETIC then
			local cosmeticId = reward.COSMETIC_ID
			if typeof(cosmeticId) ~= "string" or not isKnownCosmetic(cosmeticId) then
				table.insert(problems, `tile {tileIndex} names a cosmetic that is not in the catalogue`)
			end
			if not isPositiveInteger(reward.DUPLICATE_DIAMONDS) then
				table.insert(problems, `tile {tileIndex} needs a positive whole DUPLICATE_DIAMONDS`)
			end
		else
			table.insert(problems, `tile {tileIndex} has an unknown KIND`)
		end
	end
	return problems
end

-- the day that may be claimed now; nil while the wait is still running
function DailyRewardRules.getClaimableDay(state: State, now: number): number?
	if now < state.nextClaimTime then
		return nil
	end
	return state.lastClaimedDay + 1
end

-- the record after claiming now; the input is left as it was
function DailyRewardRules.applyClaim(state: State, now: number, intervalSec: number): State
	return {
		lastClaimedDay = state.lastClaimedDay + 1,
		nextClaimTime = math.floor(now) + intervalSec,
	}
end

-- the tile a day is paid from: its own, or the last one for every day
-- past the list's end
function DailyRewardRules.getTileForDay(day: number, tileCount: number): number
	return math.clamp(day, 1, math.max(tileCount, 1))
end

-- seconds until the next claim opens; nil when one is ready
function DailyRewardRules.getRemainingSec(state: State, now: number): number?
	if now >= state.nextClaimTime then
		return nil
	end
	return state.nextClaimTime - now
end

-- how a tile is drawn: the one to claim now, one already had, or one
-- still ahead. Past the list's end the last tile alternates between
-- CLAIMED and READY and every other tile stays CLAIMED
function DailyRewardRules.getTileState(state: State, now: number, tileIndex: number, tileCount: number): TileState
	local claimableDay = DailyRewardRules.getClaimableDay(state, now)
	if claimableDay and DailyRewardRules.getTileForDay(claimableDay, tileCount) == tileIndex then
		return "READY"
	end
	local claimedTile = if state.lastClaimedDay > 0 then DailyRewardRules.getTileForDay(state.lastClaimedDay, tileCount) else 0
	if tileIndex <= claimedTile then
		return "CLAIMED"
	end
	return "LOCKED"
end

function DailyRewardRules.publish(rewards: { Reward }): { PublishedReward }
	local published = {}
	for _, reward in rewards do
		local isCosmetic = reward.KIND == Enums.DailyRewardKind.COSMETIC
		table.insert(
			published,
			{
				kind = reward.KIND,
				amount = (if isCosmetic then reward.DUPLICATE_DIAMONDS else reward.AMOUNT) or 0,
				cosmeticId = if isCosmetic then reward.COSMETIC_ID else nil,
			}
		)
	end
	return published
end

function DailyRewardRules.encodeCatalogue(published: { PublishedReward }): string
	return HttpService:JSONEncode(published)
end

-- nil for anything that is not a well-formed catalogue
function DailyRewardRules.decodeCatalogue(encoded: any): { PublishedReward }?
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
	local published: { PublishedReward } = {}
	for _, entry in decoded do
		if typeof(entry) ~= "table" or typeof(entry.kind) ~= "number" or typeof(entry.amount) ~= "number" then
			return nil
		end
		table.insert(
			published,
			{
				kind = entry.kind,
				amount = entry.amount,
				cosmeticId = if typeof(entry.cosmeticId) == "string" then entry.cosmeticId else nil,
			}
		)
	end
	return published
end

return DailyRewardRules
