--!strict

-- The shape of one player's persistent save. Pure: defaults in, validated
-- data out, so it is unit-testable and PlayerData (the sole owner of the live
-- record) stays thin. Adding a save field = a type entry, a default, and a
-- validation rule here, plus coverage in the reset-player dev tool contract.
local CharacterSchema = require(script.Parent.CharacterSchema)
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
	diamonds: number,
	-- the player's characters in slot order (M55); every player has at
	-- least one, and a character is named by its id, never its position.
	-- The bought-unlock `ownedUnlocks` and `loadout` fields went with the
	-- Character redesign on 2026-10-12: the character brings its gear
	characters: { CharacterSchema.CharacterSave },
	-- the id of the character the player brings on the next run
	activeCharacterId: string,
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
	-- Enums.ClassKind key name -> skill slots unlocked on that class (M70):
	-- a class with an entry is owned, one without is locked. The free class
	-- is always present, so a player can never own nothing
	classProgress: { [string]: number },
	-- the third currency (M70): paid by the gacha for a complete class or
	-- a duplicate cosmetic, spent on cosmetics by name (M61)
	keys: number,
	-- cosmetic id -> true for every cosmetic the account owns; the defaults
	-- every character starts in are always present
	ownedCosmetics: { [string]: boolean },
}

export type Defaults = {
	startingDiamonds: number,
	character: CharacterSchema.Defaults,
	maxCharacters: number,
	-- makes a fresh character id; handed in so the schema stays pure
	generateId: () -> string,
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

-- the empty character a new slot holds, named for its position
function PlayerSaveSchema.makeDefaultCharacter(defaults: Defaults, index: number): CharacterSchema.CharacterSave
	return CharacterSchema.getDefault(defaults.character, defaults.generateId(), CharacterSchema.makeDefaultName(defaults.character, index))
end

-- the free class, owned from the start with no skill slots
function PlayerSaveSchema.getDefaultClassProgress(defaults: Defaults): { [string]: number }
	return {
		[Enums.getName(Enums.ClassKind, defaults.character.defaultClassKind) :: string] = 0,
	}
end

-- every cosmetic a new character wears is owned by every account
function PlayerSaveSchema.getDefaultOwnedCosmetics(defaults: Defaults): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for _, cosmeticId in defaults.character.defaultCosmetics do
		owned[cosmeticId] = true
	end
	return owned
end

function PlayerSaveSchema.getDefault(defaults: Defaults): SaveData
	local firstCharacter = PlayerSaveSchema.makeDefaultCharacter(defaults, 1)
	return {
		diamonds = defaults.startingDiamonds,
		characters = { firstCharacter },
		activeCharacterId = firstCharacter.id,
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
		classProgress = PlayerSaveSchema.getDefaultClassProgress(defaults),
		keys = 0,
		ownedCosmetics = PlayerSaveSchema.getDefaultOwnedCosmetics(defaults),
	}
end

-- every record repaired by CharacterSchema in list order; a record that
-- cannot be repaired, a duplicate id, or one past the cap is dropped, and a
-- player is never left without a character
local function validateCharacters(data: any, defaults: Defaults, repairs: { Repair })
	if typeof(data.characters) ~= "table" then
		data.characters = { PlayerSaveSchema.makeDefaultCharacter(defaults, 1) }
		table.insert(repairs, "characters reset")
		return
	end
	local kept: { CharacterSchema.CharacterSave } = {}
	local seenIds: { [string]: boolean } = {}
	local isRepaired = false
	for key, record in data.characters do
		if typeof(key) ~= "number" then
			table.insert(repairs, "characters dropped entry " .. tostring(key))
			isRepaired = true
			continue
		end
		local position = #kept + 1
		local prefix = "characters[" .. tostring(key) .. "]."
		local validated = CharacterSchema.validate(record, defaults.character, CharacterSchema.makeDefaultName(defaults.character, position), prefix, repairs)
		if not validated then
			isRepaired = true
			continue
		end
		if seenIds[validated.id] then
			table.insert(repairs, prefix .. "dropped: duplicate id")
			isRepaired = true
			continue
		end
		if position > defaults.maxCharacters then
			table.insert(repairs, prefix .. "dropped: over the character cap")
			isRepaired = true
			continue
		end
		seenIds[validated.id] = true
		table.insert(kept, validated)
	end
	if #kept == 0 then
		table.insert(kept, PlayerSaveSchema.makeDefaultCharacter(defaults, 1))
		table.insert(repairs, "characters refilled with a new character")
		isRepaired = true
	end
	if isRepaired then
		data.characters = kept
	end
end

local function validateActiveCharacterId(data: any, repairs: { Repair })
	for _, record in data.characters do
		if record.id == data.activeCharacterId then
			return
		end
	end
	data.activeCharacterId = data.characters[1].id
	table.insert(repairs, "activeCharacterId reset")
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

-- one slot count per owned class, keyed by a class the enum knows and
-- clamped to the slot cap; the free class is always owned (M70)
local function validateClassProgress(data: any, defaults: Defaults, repairs: { Repair })
	if typeof(data.classProgress) ~= "table" then
		data.classProgress = PlayerSaveSchema.getDefaultClassProgress(defaults)
		table.insert(repairs, "classProgress reset")
		return
	end
	local maxSkillSlots = CharacterSchema.getMaxSkillSlots(defaults.character)
	for className, slots in data.classProgress do
		if typeof(className) ~= "string" or Enums.getValueByName(Enums.ClassKind, className) == nil then
			data.classProgress[className] = nil
			table.insert(repairs, "classProgress dropped entry " .. tostring(className))
			continue
		end
		if not Validate.isValueType(slots, "nonnegativeInteger") then
			data.classProgress[className] = 0
			table.insert(repairs, "classProgress." .. className .. " reset")
		elseif slots > maxSkillSlots then
			data.classProgress[className] = maxSkillSlots
			table.insert(repairs, "classProgress." .. className .. " clamped")
		end
	end
	for className, slots in PlayerSaveSchema.getDefaultClassProgress(defaults) do
		if data.classProgress[className] == nil then
			data.classProgress[className] = slots
			table.insert(repairs, "classProgress." .. className .. " restored")
		end
	end
end

-- a set of non-empty ids; the default cosmetics are always owned
local function validateOwnedCosmetics(data: any, defaults: Defaults, repairs: { Repair })
	if typeof(data.ownedCosmetics) ~= "table" then
		data.ownedCosmetics = PlayerSaveSchema.getDefaultOwnedCosmetics(defaults)
		table.insert(repairs, "ownedCosmetics reset")
		return
	end
	for cosmeticId, value in data.ownedCosmetics do
		if typeof(cosmeticId) ~= "string" or cosmeticId == "" or value ~= true then
			data.ownedCosmetics[cosmeticId] = nil
			table.insert(repairs, "ownedCosmetics dropped entry " .. tostring(cosmeticId))
		end
	end
	for cosmeticId in PlayerSaveSchema.getDefaultOwnedCosmetics(defaults) do
		if data.ownedCosmetics[cosmeticId] == nil then
			data.ownedCosmetics[cosmeticId] = true
			table.insert(repairs, "ownedCosmetics." .. cosmeticId .. " restored")
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

	-- the balance was saved as "cash" until M33 (2026-10-06): an older save
	-- carries it across under its new name, once. The profile is reconciled
	-- against the defaults before it gets here, so `diamonds` already holds
	-- the starting balance; the old cash is added onto it, never compared
	if Validate.isValueType(data.cash, "nonnegativeInteger") then
		local diamonds = if Validate.isValueType(data.diamonds, "nonnegativeInteger") then data.diamonds else 0
		data.diamonds = diamonds + data.cash
		data.cash = nil
		table.insert(repairs, "cash migrated to diamonds")
	end

	if not Validate.isValueType(data.diamonds, "nonnegativeInteger") then
		data.diamonds = defaultData.diamonds
		table.insert(repairs, "diamonds reset")
	end

	-- characters before the active id: the id must name a kept character
	validateCharacters(data, defaults, repairs)
	validateActiveCharacterId(data, repairs)
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

	-- a save from before M70 arrives with the defaults reconciled in, so
	-- these only ever repair a broken value
	validateClassProgress(data, defaults, repairs)
	if not Validate.isValueType(data.keys, "nonnegativeInteger") then
		data.keys = 0
		table.insert(repairs, "keys reset")
	end
	validateOwnedCosmetics(data, defaults, repairs)

	-- unknown top-level keys are dropped so a renamed field cannot linger
	-- forever (the pre-M55 ownedUnlocks and loadout go this way: only the
	-- starting Rifle and Machine Gun ever existed, so nothing is lost)
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
