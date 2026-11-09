--!strict

-- The shape of one player's persistent save. Pure: defaults in, validated
-- data out, so it is unit-testable and PlayerData (the sole owner of the live
-- record) stays thin. Adding a save field = a type entry, a default, and a
-- validation rule here, plus coverage in the reset-player dev tool contract.
local ClassSchema = require(script.Parent.ClassSchema)
local CompletionKeys = require(script.Parent.CompletionKeys)
local CosmeticLoadoutSchema = require(script.Parent.CosmeticLoadoutSchema)
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
	-- Enums.ClassKind key name -> what the player has put on that class
	-- (its rolled skills; the Class Equip Menu of 2026-11-04, which
	-- replaced the `characters` list of M55: a class is the loadout now).
	-- A class with no record reads as the default one
	classes: ClassSchema.Records,
	-- the account's one cosmetic loadout, worn with every class (designer,
	-- 2026-11-04; a field of each class record for a few hours before, and
	-- of each character before that)
	cosmetics: CosmeticLoadoutSchema.Loadout,
	-- Enums.ClassKind key name of the class the player brings on the next
	-- run; always an owned one
	activeClassKind: string,
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
	-- the controls panel collapsed to its tab (2026-11-09); shown by default
	isControlsPanelHidden: boolean,
}

export type Defaults = {
	startingDiamonds: number,
	class: ClassSchema.Defaults,
	-- Enums.CosmeticSlot key name -> the skin a new account wears; a
	-- loadout missing one of these slots is repaired to it
	defaultCosmetics: CosmeticLoadoutSchema.Loadout,
	-- Enums.ClassKind value every new player starts as, the one class
	-- always owned, and the one a save is repaired to
	defaultClassKind: number,
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

function PlayerSaveSchema.getDefaultClassName(defaults: Defaults): string
	return Enums.getName(Enums.ClassKind, defaults.defaultClassKind) :: string
end

-- the free class, owned from the start with no skill slots
function PlayerSaveSchema.getDefaultClassProgress(defaults: Defaults): { [string]: number }
	return {
		[PlayerSaveSchema.getDefaultClassName(defaults)] = 0,
	}
end

-- every cosmetic a new account wears is owned by every account
function PlayerSaveSchema.getDefaultOwnedCosmetics(defaults: Defaults): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for _, cosmeticId in defaults.defaultCosmetics do
		owned[cosmeticId] = true
	end
	return owned
end

function PlayerSaveSchema.getDefault(defaults: Defaults): SaveData
	return {
		diamonds = defaults.startingDiamonds,
		classes = {},
		cosmetics = CosmeticLoadoutSchema.getDefault(defaults.defaultCosmetics),
		activeClassKind = PlayerSaveSchema.getDefaultClassName(defaults),
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
		isControlsPanelHidden = false,
	}
end

-- a save from before the Class Menu (M55 to 2026-11-04) carried a
-- `characters` list, each with a class, skills, and cosmetics, and the id
-- of the active one. Each character's skills become its class's record
-- (the first character seen for a class wins), the active character's
-- class becomes the active class, its cosmetics the account's loadout,
-- and the old fields go. The profile is reconciled against the defaults
-- before it gets here, so `classes` already exists; what the old list
-- holds is laid over it
local function migrateCharacters(data: any, repairs: { Repair })
	if typeof(data.characters) ~= "table" then
		return
	end
	if typeof(data.classes) ~= "table" then
		data.classes = {}
	end
	local activeClassName: string? = nil
	for _, record in data.characters do
		if typeof(record) ~= "table" or typeof(record.classKind) ~= "string" then
			continue
		end
		if data.classes[record.classKind] == nil then
			data.classes[record.classKind] = {
				skills = if typeof(record.skills) == "table" then record.skills else {},
			}
		end
		if record.id ~= nil and record.id == data.activeCharacterId then
			activeClassName = record.classKind
			if typeof(record.cosmetics) == "table" then
				data.cosmetics = record.cosmetics
			end
		end
	end
	if activeClassName then
		data.activeClassKind = activeClassName
	end
	data.characters = nil
	data.activeCharacterId = nil
	table.insert(repairs, "characters migrated to classes")
end

-- for a few hours on 2026-11-04 each class record carried its own
-- `cosmetics`: the active class's become the account's loadout and every
-- record's copy goes, so the record validation never reports them
local function migrateClassCosmetics(data: any, repairs: { Repair })
	if typeof(data.classes) ~= "table" then
		return
	end
	local isFound = false
	for className, record in data.classes do
		if typeof(record) ~= "table" or record.cosmetics == nil then
			continue
		end
		if className == data.activeClassKind and typeof(record.cosmetics) == "table" then
			data.cosmetics = record.cosmetics
		end
		record.cosmetics = nil
		isFound = true
	end
	if isFound then
		table.insert(repairs, "class cosmetics migrated to the account loadout")
	end
end

local function validateCosmetics(data: any, defaults: Defaults, repairs: { Repair })
	data.cosmetics = CosmeticLoadoutSchema.validate(data.cosmetics, defaults.defaultCosmetics, "cosmetics.", repairs)
end

local function validateClasses(data: any, defaults: Defaults, repairs: { Repair })
	data.classes = ClassSchema.validateRecords(data.classes, defaults.class, repairs)
end

-- the active class must be one the account owns (classProgress validated
-- first), else the free one
local function validateActiveClassKind(data: any, defaults: Defaults, repairs: { Repair })
	local name = data.activeClassKind
	if typeof(name) == "string" and Enums.getValueByName(Enums.ClassKind, name) ~= nil and data.classProgress[name] ~= nil then
		return
	end
	data.activeClassKind = PlayerSaveSchema.getDefaultClassName(defaults)
	table.insert(repairs, "activeClassKind reset")
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
	local maxSkillSlots = defaults.class.maxSkillSlots
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

	-- an older save's characters become class records before anything
	-- reads either field, and a class record's cosmetics the account's
	migrateCharacters(data, repairs)
	migrateClassCosmetics(data, repairs)

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

	validateClasses(data, defaults, repairs)
	validateCosmetics(data, defaults, repairs)
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
	if typeof(data.isControlsPanelHidden) ~= "boolean" then
		data.isControlsPanelHidden = false
		table.insert(repairs, "isControlsPanelHidden reset")
	end
	-- after the progress: the active class must be an owned one
	validateActiveClassKind(data, defaults, repairs)

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
