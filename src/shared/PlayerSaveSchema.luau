--!strict

-- The shape of one player's persistent save. Pure: defaults in, validated
-- data out, so it is unit-testable and PlayerData (the sole owner of the live
-- record) stays thin. Adding a save field = a type entry, a default, and a
-- validation rule here, plus coverage in the reset-player dev tool contract.
local CompletionKeys = require(script.Parent.CompletionKeys)
local Enums = require(script.Parent.Enums)
local Validate = require(script.Parent.Validate)

local PlayerSaveSchema = {}

export type SessionMetaSave = {
	creationTime: number,
	sessions: number,
	totalPlaySec: number,
	saveTime: number,
}

export type DailyRewardSave = {
	lastClaimedDay: number,
	nextClaimTime: number,
}

export type SaveData = {
	cash: number,
	-- set of owned unlock names (weapons, posts, defenses)
	ownedUnlocks: { [string]: boolean },
	-- LoadoutSlot key name -> equipped unlock name; absent when the slot is empty
	loadout: { [string]: string },
	-- set of CompletionKeys ("MAP/DIFFICULTY")
	completions: { [string]: boolean },
	dailyReward: DailyRewardSave,
	sessionMeta: SessionMetaSave,
	-- the Robux receipts already granted, oldest first (PurchaseManager): a
	-- receipt Roblox sends again is answered without granting twice
	processedPurchaseIds: { string },
	-- Enums.ReviveKind key name -> revives paid for but not yet used (a
	-- purchase that could not apply is kept as a credit, never refused)
	reviveCredits: { [string]: number },
}

export type Defaults = {
	startingCash: number,
}

-- only the newest receipts are kept: Roblox retries a receipt for days at
-- most, so an old id can never come back, and the save stays small
PlayerSaveSchema.MAX_PROCESSED_PURCHASE_IDS = 100

-- a unit-test-visible record of what validate() had to repair
export type Repair = string

function PlayerSaveSchema.getDefaultReviveCredits(): { [string]: number }
	local credits = {}
	for _, kind in Enums.getAllValues(Enums.ReviveKind) do
		credits[Enums.getName(Enums.ReviveKind, kind) :: string] = 0
	end
	return credits
end

function PlayerSaveSchema.getDefault(defaults: Defaults): SaveData
	return {
		cash = defaults.startingCash,
		ownedUnlocks = {},
		loadout = {},
		completions = {},
		dailyReward = {
			lastClaimedDay = 0,
			nextClaimTime = 0,
		},
		sessionMeta = {
			creationTime = 0,
			sessions = 0,
			totalPlaySec = 0,
			saveTime = 0,
		},
		processedPurchaseIds = {},
		reviveCredits = PlayerSaveSchema.getDefaultReviveCredits(),
	}
end

local function validateStringSet(data: any, field: string, repairs: { Repair })
	if typeof(data[field]) ~= "table" then
		data[field] = {}
		table.insert(repairs, field .. " reset")
		return
	end
	for key, value in data[field] do
		if typeof(key) ~= "string" or key == "" or value ~= true then
			data[field][key] = nil
			table.insert(repairs, field .. " dropped entry " .. tostring(key))
		end
	end
end

local function validateLoadout(data: any, repairs: { Repair })
	if typeof(data.loadout) ~= "table" then
		data.loadout = {}
		table.insert(repairs, "loadout reset")
		return
	end
	for slotName, unlockName in data.loadout do
		if Enums.getValueByName(Enums.LoadoutSlot, slotName) == nil
			or typeof(unlockName) ~= "string"
			or unlockName == ""
			or data.ownedUnlocks[unlockName] ~= true
		then
			data.loadout[slotName] = nil
			table.insert(repairs, "loadout dropped slot " .. tostring(slotName))
		end
	end
end

local function validateCompletions(data: any, repairs: { Repair })
	if typeof(data.completions) ~= "table" then
		data.completions = {}
		table.insert(repairs, "completions reset")
		return
	end
	for key, value in data.completions do
		if not CompletionKeys.isValid(key) or value ~= true then
			data.completions[key] = nil
			table.insert(repairs, "completions dropped entry " .. tostring(key))
		end
	end
end

local function validateNonnegativeIntegerFields(container: any, fields: { string }, prefix: string, repairs: { Repair })
	for _, field in fields do
		if not Validate.isValueType(container[field], "nonnegativeInteger") then
			container[field] = 0
			table.insert(repairs, prefix .. field .. " reset")
		end
	end
end

-- an ordered list of non-empty strings, trimmed to the newest entries
local function validatePurchaseIds(data: any, repairs: { Repair })
	if typeof(data.processedPurchaseIds) ~= "table" then
		data.processedPurchaseIds = {}
		table.insert(repairs, "processedPurchaseIds reset")
		return
	end
	local kept = {}
	local isRepaired = false
	for key, value in data.processedPurchaseIds do
		if typeof(key) == "number" and typeof(value) == "string" and value ~= "" then
			table.insert(kept, value)
		else
			isRepaired = true
		end
	end
	local overflow = #kept - PlayerSaveSchema.MAX_PROCESSED_PURCHASE_IDS
	if overflow > 0 then
		kept = table.move(kept, overflow + 1, #kept, 1, {})
		isRepaired = true
	end
	if isRepaired then
		data.processedPurchaseIds = kept
		table.insert(repairs, "processedPurchaseIds repaired")
	end
end

-- one count per Enums.ReviveKind key; a missing or bad count is 0
local function validateReviveCredits(data: any, repairs: { Repair })
	if typeof(data.reviveCredits) ~= "table" then
		data.reviveCredits = PlayerSaveSchema.getDefaultReviveCredits()
		table.insert(repairs, "reviveCredits reset")
		return
	end
	for key in data.reviveCredits do
		if Enums.getValueByName(Enums.ReviveKind, key) == nil then
			data.reviveCredits[key] = nil
			table.insert(repairs, "reviveCredits dropped entry " .. tostring(key))
		end
	end
	for key in PlayerSaveSchema.getDefaultReviveCredits() do
		if not Validate.isValueType(data.reviveCredits[key], "nonnegativeInteger") then
			-- a save from before the field existed simply has no counts yet
			if data.reviveCredits[key] ~= nil then
				table.insert(repairs, "reviveCredits." .. key .. " reset")
			end
			data.reviveCredits[key] = 0
		end
	end
end

-- repairs data in place and returns it, plus the list of repairs made; a
-- non-table save is replaced wholesale
function PlayerSaveSchema.validate(data: any, defaults: Defaults): (SaveData, { Repair })
	local repairs: { Repair } = {}
	if typeof(data) ~= "table" then
		table.insert(repairs, "top-level save reset")
		return PlayerSaveSchema.getDefault(defaults), repairs
	end

	local defaultData = PlayerSaveSchema.getDefault(defaults)

	if not Validate.isValueType(data.cash, "nonnegativeInteger") then
		data.cash = defaultData.cash
		table.insert(repairs, "cash reset")
	end

	-- ownedUnlocks before loadout: an equipped item must be owned
	validateStringSet(data, "ownedUnlocks", repairs)
	validateLoadout(data, repairs)
	validateCompletions(data, repairs)

	if typeof(data.dailyReward) ~= "table" then
		data.dailyReward = defaultData.dailyReward
		table.insert(repairs, "dailyReward reset")
	else
		validateNonnegativeIntegerFields(data.dailyReward, { "lastClaimedDay", "nextClaimTime" }, "dailyReward.", repairs)
	end

	if typeof(data.sessionMeta) ~= "table" then
		data.sessionMeta = defaultData.sessionMeta
		table.insert(repairs, "sessionMeta reset")
	else
		validateNonnegativeIntegerFields(
			data.sessionMeta,
			{ "creationTime", "sessions", "totalPlaySec", "saveTime" },
			"sessionMeta.",
			repairs
		)
	end

	validatePurchaseIds(data, repairs)
	validateReviveCredits(data, repairs)

	-- unknown top-level keys are dropped so a renamed field cannot linger forever
	local knownFields = defaultData :: any
	for key in data do
		if knownFields[key] == nil then
			data[key] = nil
			table.insert(repairs, "dropped unknown field " .. tostring(key))
		end
	end

	return data, repairs
end

return PlayerSaveSchema
