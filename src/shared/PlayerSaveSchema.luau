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
}

export type Defaults = {
	startingCash: number,
}

-- a unit-test-visible record of what validate() had to repair
export type Repair = string

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
