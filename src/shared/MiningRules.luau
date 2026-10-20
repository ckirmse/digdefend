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

-- gadgets that are a mode rather than a thing in the hand: no
-- GameAssets/Tools model. The Auto Turret shows its ghost in the world
-- (M66); the Binoculars live on the post. Every other gadget (the Stim
-- Shot, 2026-10-19) is held like any tool, from "GADGET_<KEY>"
local GADGETS_WITHOUT_MODEL: { [number]: boolean } = {
	[Enums.GadgetKind.NONE] = true,
	[Enums.GadgetKind.AUTO_TURRET] = true,
	[Enums.GadgetKind.BINOCULARS] = true,
}

-- whether the tool in hand has a model to hold; the gadget slot depends
-- on which gadget fills it
function MiningRules.hasHeldModel(tool: number, gadgetKind: number?): boolean
	if tool == Enums.ToolKind.GADGET then
		return not GADGETS_WITHOUT_MODEL[gadgetKind or Enums.GadgetKind.NONE]
	end
	return true
end

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

-- the order the tool bar shows its slots in, whatever order they were
-- granted (2026-10-20: dynamite always sits last, after repair); a tool
-- not listed here comes after every listed one
MiningRules.TOOL_BAR_ORDER = {
	Enums.ToolKind.PICK_AXE,
	Enums.ToolKind.WEAPON,
	Enums.ToolKind.TORCH,
	Enums.ToolKind.GADGET,
	Enums.ToolKind.HAMMER,
	Enums.ToolKind.DYNAMITE,
}

function MiningRules.sortToolSlots(slots: { number }): { number }
	local sorted = table.clone(slots)
	local function rankOf(tool: number): number
		return table.find(MiningRules.TOOL_BAR_ORDER, tool) or (#MiningRules.TOOL_BAR_ORDER + tool)
	end
	table.sort(
		sorted,
		function(a: number, b: number): boolean
			return rankOf(a) < rankOf(b)
		end
	)
	return sorted
end

-- consumable counts travel as JSON { [toolKind] = count }; JSON keys are
-- strings, so they are restored to numbers on decode
function MiningRules.encodeToolCounts(countByTool: { [number]: number }): string
	local encodable: { [string]: number } = {}
	for tool, count in countByTool do
		encodable[tostring(tool)] = count
	end
	return HttpService:JSONEncode(encodable)
end

function MiningRules.decodeToolCounts(encoded: any): { [number]: number }
	local counts: { [number]: number } = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return counts
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" then
		return counts
	end
	for key, count in decoded :: { [any]: any } do
		local tool = tonumber(key)
		-- a zero is kept: a slot held at x0 (the Demolitionist's dynamite, 2026-10-20)
		if tool and Enums.isValidValue(Enums.ToolKind, tool) and typeof(count) == "number" and count >= 0 then
			counts[tool] = count
		end
	end
	return counts
end

-- consumables live in the bar only while some are held (GDD "Mining Tools")
function MiningRules.isConsumable(tool: number): boolean
	return tool == Enums.ToolKind.TORCH or tool == Enums.ToolKind.DYNAMITE
end

-- the per-player Iron and Gold yield multiplier for a party size; sizes past
-- the table use its last row
function MiningRules.getOreYieldMultiplier(multiplierByPlayerCount: { number }, playerCount: number): number
	local clamped = math.clamp(math.floor(playerCount), 1, #multiplierByPlayerCount)
	return multiplierByPlayerCount[clamped]
end

-- only Iron and Gold are per player (GDD "Party scaling"); Uranium is
-- shared and never scaled
function MiningRules.isYieldScaledByParty(resource: number): boolean
	return resource == Enums.RawResource.IRON_ORE or resource == Enums.RawResource.GOLD_ORE
end

return MiningRules
