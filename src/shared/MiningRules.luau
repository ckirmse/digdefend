--!strict

-- Pure rules for tools and mining (GDD "Tools", "Mining Rock", "Party
-- scaling"): pick axe damage by level, reach and cooldown checks the server
-- applies to every hit, the crack stage a block shows, the tool slot codec,
-- and the party ore yield lookup. Tuning is passed in from GameData so this
-- stays unit testable.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local MiningRules = {}

-- crack overlay thresholds from the GDD: a block shows stage 1 at or below
-- 60% hp and stage 2 at or below 30%
MiningRules.CRACK_THRESHOLDS = { 0.6, 0.3 }
MiningRules.NO_TOOL = 0

function MiningRules.damageForLevel(damageByLevel: { number }, level: number): number
	local clamped = math.clamp(math.floor(level), 1, #damageByLevel)
	return damageByLevel[clamped]
end

-- the server accepts a hit when the player's root is within reach of the
-- block centre, with a tolerance for latency and the block's own half size
function MiningRules.isWithinReach(playerPosition: Vector3, blockCenter: Vector3, reachStuds: number, toleranceStuds: number): boolean
	return (blockCenter - playerPosition).Magnitude <= reachStuds + toleranceStuds
end

function MiningRules.canHit(lastHitTime: number?, now: number, cooldownSec: number): boolean
	return lastHitTime == nil or now - lastHitTime >= cooldownSec
end

-- 0 untouched, 1 cracked, 2 crumbling
function MiningRules.crackStage(remainingHp: number, maxHp: number): number
	if maxHp <= 0 then
		return 0
	end
	local fraction = remainingHp / maxHp
	local stage = 0
	for index, threshold in MiningRules.CRACK_THRESHOLDS do
		if fraction <= threshold then
			stage = index
		end
	end
	return stage
end

function MiningRules.encodeToolSlots(slots: { number }): string
	return HttpService:JSONEncode(slots)
end

-- tolerant of garbage so a bad attribute leaves the bar empty rather than erroring
function MiningRules.decodeToolSlots(encoded: any): { number }
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" then
		return {}
	end
	local slots = {}
	for _, value in decoded do
		if Enums.isValidValue(Enums.ToolKind, value) then
			table.insert(slots, value)
		end
	end
	return slots
end

-- the per-player Iron and Gold yield multiplier for a party size; sizes past
-- the table use its last row
function MiningRules.getOreYieldMultiplier(multiplierByPlayerCount: { number }, playerCount: number): number
	local clamped = math.clamp(math.floor(playerCount), 1, #multiplierByPlayerCount)
	return multiplierByPlayerCount[clamped]
end

-- only Iron and Gold are per player (GDD "Party scaling"); Diamonds and
-- Uranium are shared and never scaled
function MiningRules.isYieldScaledByParty(resource: number): boolean
	return resource == Enums.RawResource.IRON_ORE or resource == Enums.RawResource.GOLD_ORE
end

return MiningRules
