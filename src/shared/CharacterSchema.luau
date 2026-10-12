--!strict

-- The shape of one character (GDD "Characters", M55): the first instanced
-- per-player record. Pure, like PlayerSaveSchema: defaults in, a repaired
-- record out, so every rule is unit tested and PlayerData stays thin. A
-- character is permanent (no reset, no delete), named by its id and never
-- by its position in the list, and holds its Nights Survived, its gear rows
-- (one per Enums.GearSlot: a kind saved by enum key name, and 1 to 5
-- stars), up to three skills keyed by slot, and the cosmetics map M61
-- fills. Kinds are saved as names so a save stays readable and survives an
-- enum being renumbered.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)
local Validate = require(script.Parent.Validate)

local CharacterSchema = {}

export type GearSave = {
	-- key name in the slot's kind enum (see getGearEnum)
	kind: string,
	stars: number,
}

export type SkillSave = {
	skillId: string,
	rarity: number,
}

export type CharacterSave = {
	id: string,
	name: string,
	nightsSurvived: number,
	-- Enums.GearSlot key name -> the row; every slot is always present
	gear: { [string]: GearSave },
	-- slot index as a string ("1" to "3"; DataStore keys are strings) ->
	-- the skill in it; an open slot with no skill yet is simply absent
	skills: { [string]: SkillSave },
	-- Enums.CosmeticSlot key name -> skin id (M61); empty until then
	cosmetics: { [string]: string },
}

-- everything the schema needs from GameData, handed in so the module stays
-- pure (PlayerData builds it once; tests build their own)
export type Defaults = {
	-- Enums.GearSlot value -> the kind a new character starts with
	defaultKindByGearSlot: { [number]: number },
	minStars: number,
	maxStars: number,
	-- Nights Survived needed per skill slot, by slot index; its length is
	-- the slot count
	skillSlotUnlockNights: { number },
	-- skill id -> true for every skill in the catalogue
	validSkillIds: { [string]: boolean },
	maxNameLength: number,
	defaultNamePrefix: string,
}

export type Repair = string

-- the kind enum each gear row draws from; two Tower rows since 2026-10-12
local GEAR_ENUM_BY_SLOT: { [number]: any } = {
	[Enums.GearSlot.WEAPON] = Enums.WeaponKind,
	[Enums.GearSlot.POST] = Enums.PostWeaponKind,
	[Enums.GearSlot.TOWER_1] = Enums.TowerKind,
	[Enums.GearSlot.TOWER_2] = Enums.TowerKind,
}

function CharacterSchema.getGearEnum(gearSlot: number): any?
	return GEAR_ENUM_BY_SLOT[gearSlot]
end

-- the name a character gets before its player renames it ("Character 2")
function CharacterSchema.makeDefaultName(defaults: Defaults, index: number): string
	return defaults.defaultNamePrefix .. tostring(index)
end

local function getDefaultGear(defaults: Defaults): { [string]: GearSave }
	local gear: { [string]: GearSave } = {}
	for _, gearSlot in Enums.getAllValues(Enums.GearSlot) do
		local slotName = Enums.getName(Enums.GearSlot, gearSlot) :: string
		gear[slotName] = {
			kind = Enums.getName(GEAR_ENUM_BY_SLOT[gearSlot], defaults.defaultKindByGearSlot[gearSlot]) :: string,
			stars = defaults.minStars,
		}
	end
	return gear
end

function CharacterSchema.getDefault(defaults: Defaults, id: string, name: string): CharacterSave
	return {
		id = id,
		name = name,
		nightsSurvived = 0,
		gear = getDefaultGear(defaults),
		skills = {},
		cosmetics = {},
	}
end

-- how many skill slots this many nights has opened: slot N opens when the
-- count reaches its threshold, and thresholds only ever climb
function CharacterSchema.openSkillSlots(nightsSurvived: number, skillSlotUnlockNights: { number }): number
	local open = 0
	for _, threshold in skillSlotUnlockNights do
		if nightsSurvived >= threshold then
			open += 1
		else
			break
		end
	end
	return open
end

function CharacterSchema.getMaxSkillSlots(defaults: Defaults): number
	return #defaults.skillSlotUnlockNights
end

-- every gear slot present with a kind its enum knows and stars in range;
-- a bad row goes back to the slot's default, an unknown key is dropped
local function validateGear(record: any, defaults: Defaults, prefix: string, repairs: { Repair })
	if typeof(record.gear) ~= "table" then
		record.gear = getDefaultGear(defaults)
		table.insert(repairs, prefix .. "gear reset")
		return
	end
	local defaultGear = getDefaultGear(defaults)
	for key in record.gear do
		if defaultGear[key] == nil then
			record.gear[key] = nil
			table.insert(repairs, prefix .. "gear dropped slot " .. tostring(key))
		end
	end
	for slotName, defaultRow in defaultGear do
		local gearSlot = Enums.getValueByName(Enums.GearSlot, slotName) :: number
		local row = record.gear[slotName]
		if typeof(row) ~= "table" then
			record.gear[slotName] = defaultRow
			table.insert(repairs, prefix .. "gear." .. slotName .. " reset")
			continue
		end
		if typeof(row.kind) ~= "string" or Enums.getValueByName(GEAR_ENUM_BY_SLOT[gearSlot], row.kind) == nil then
			row.kind = defaultRow.kind
			table.insert(repairs, prefix .. "gear." .. slotName .. ".kind reset")
		end
		if not Validate.isValueType(row.stars, "positiveInteger") or row.stars < defaults.minStars or row.stars > defaults.maxStars then
			row.stars = defaults.minStars
			table.insert(repairs, prefix .. "gear." .. slotName .. ".stars reset")
		end
		for field in row do
			if field ~= "kind" and field ~= "stars" then
				row[field] = nil
				table.insert(repairs, prefix .. "gear." .. slotName .. " dropped field " .. tostring(field))
			end
		end
	end
end

local function validateSkills(record: any, defaults: Defaults, prefix: string, repairs: { Repair })
	if typeof(record.skills) ~= "table" then
		record.skills = {}
		table.insert(repairs, prefix .. "skills reset")
		return
	end
	local maxSlots = CharacterSchema.getMaxSkillSlots(defaults)
	for key, skill in record.skills do
		local slot = if typeof(key) == "string" then tonumber(key) else nil
		local isSlotValid = slot ~= nil and Validate.isValueType(slot, "positiveInteger") and slot <= maxSlots
		local isSkillValid = typeof(skill) == "table"
			and typeof(skill.skillId) == "string"
			and defaults.validSkillIds[skill.skillId] == true
			and Enums.isValidValue(Enums.SkillRarity, skill.rarity)
		if isSlotValid and isSkillValid then
			-- extra fields on a skill are dropped so a renamed field cannot linger
			for field in skill do
				if field ~= "skillId" and field ~= "rarity" then
					skill[field] = nil
					table.insert(repairs, prefix .. "skills." .. key .. " dropped field " .. tostring(field))
				end
			end
			continue
		end
		record.skills[key] = nil
		table.insert(repairs, prefix .. "skills dropped slot " .. tostring(key))
	end
end

local function validateCosmetics(record: any, prefix: string, repairs: { Repair })
	if typeof(record.cosmetics) ~= "table" then
		record.cosmetics = {}
		table.insert(repairs, prefix .. "cosmetics reset")
		return
	end
	for key, value in record.cosmetics do
		if typeof(key) == "string" and Enums.getValueByName(Enums.CosmeticSlot, key) ~= nil and typeof(value) == "string" and value ~= "" then
			continue
		end
		record.cosmetics[key] = nil
		table.insert(repairs, prefix .. "cosmetics dropped slot " .. tostring(key))
	end
end

-- repairs one record in place and returns it; nil when it is not a table
-- or has no usable id, which the list validation drops. `prefix` names the
-- record in repair messages ("characters[2].")
function CharacterSchema.validate(record: any, defaults: Defaults, fallbackName: string, prefix: string, repairs: { Repair }): CharacterSave?
	if typeof(record) ~= "table" then
		table.insert(repairs, prefix .. "dropped: not a table")
		return nil
	end
	if typeof(record.id) ~= "string" or record.id == "" then
		table.insert(repairs, prefix .. "dropped: no id")
		return nil
	end

	if typeof(record.name) ~= "string" or record.name == "" or #record.name > defaults.maxNameLength then
		record.name = fallbackName
		table.insert(repairs, prefix .. "name reset")
	end
	if not Validate.isValueType(record.nightsSurvived, "nonnegativeInteger") then
		record.nightsSurvived = 0
		table.insert(repairs, prefix .. "nightsSurvived reset")
	end

	validateGear(record, defaults, prefix, repairs)
	validateSkills(record, defaults, prefix, repairs)
	validateCosmetics(record, prefix, repairs)

	local knownFields = CharacterSchema.getDefault(defaults, record.id, record.name) :: any
	for key in record do
		if knownFields[key] == nil then
			record[key] = nil
			table.insert(repairs, prefix .. "dropped unknown field " .. tostring(key))
		end
	end

	return record
end

-- the gear row a GearSlot names, as (kind enum value, stars); the kind is
-- resolved from the saved name, so a record that passed validate always
-- resolves
function CharacterSchema.getGear(record: CharacterSave, gearSlot: number): (number?, number)
	local slotName = Enums.getName(Enums.GearSlot, gearSlot)
	local gearEnum = GEAR_ENUM_BY_SLOT[gearSlot]
	local row = if slotName then record.gear[slotName] else nil
	if not row or not gearEnum then
		return nil, 0
	end
	return Enums.getValueByName(gearEnum, row.kind), row.stars
end

-- the skills travel to the client as one JSON attribute: an array in slot
-- order, an empty slot an empty table, so the sheet can draw every row
function CharacterSchema.encodeSkills(skills: { [string]: SkillSave }, slotCount: number): string
	local rows = {}
	for slot = 1, slotCount do
		local skill = skills[tostring(slot)]
		rows[slot] = if skill then { skillId = skill.skillId, rarity = skill.rarity } else {}
	end
	return HttpService:JSONEncode(rows)
end

function CharacterSchema.decodeSkills(encoded: any): { [string]: SkillSave }
	local skills: { [string]: SkillSave } = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return skills
	end
	local isSuccess, rows = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(rows) ~= "table" then
		return skills
	end
	for slot, row in rows do
		if typeof(row) == "table" and typeof(row.skillId) == "string" and typeof(row.rarity) == "number" then
			skills[tostring(slot)] = { skillId = row.skillId, rarity = row.rarity }
		end
	end
	return skills
end

function CharacterSchema.encodeCosmetics(cosmetics: { [string]: string }): string
	return HttpService:JSONEncode(cosmetics)
end

function CharacterSchema.decodeCosmetics(encoded: any): { [string]: string }
	local cosmetics: { [string]: string } = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return cosmetics
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return cosmetics
	end
	for key, value in decoded do
		if typeof(key) == "string" and typeof(value) == "string" then
			cosmetics[key] = value
		end
	end
	return cosmetics
end

return CharacterSchema
