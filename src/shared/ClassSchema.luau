--!strict

-- The shape of one class's record on a player's save (GDD "Classes",
-- the Class Equip Menu of 2026-11-04, which replaced the character records
-- of M55): what the player has put on that class, never what the class
-- is. A class brings its kit from GameData/Classes/Roster and its open
-- skill slots from the account's gacha progress; the record holds only
-- the skills (shown as Perks) rolled into those slots (the cosmetics
-- left the record for the account's one loadout, CosmeticLoadoutSchema,
-- the same day). Pure, like PlayerSaveSchema: defaults in, a repaired
-- record out, so every rule is unit tested and PlayerData stays thin.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)
local Validate = require(script.Parent.Validate)

local ClassSchema = {}

export type SkillSave = {
	skillId: string,
	rarity: number,
}

-- a slot's last free roll (the restricted player's reroll, 2026-11-10):
-- when it was rolled, which starts the wait for the next one, and the
-- offer until it is kept
export type FreeRollSave = {
	rollTime: number,
	skillId: string?,
	rarity: number?,
}

export type ClassSave = {
	-- slot index as a string ("1" to "3"; DataStore keys are strings) ->
	-- the skill in it; an open slot with no skill yet is simply absent
	skills: { [string]: SkillSave },
	-- slot index as a string -> that slot's last free roll; absent on a
	-- record that never took one (so an old save needs no repair)
	freeRolls: { [string]: FreeRollSave }?,
}

-- Enums.ClassKind key name -> that class's record; a class with no record
-- yet reads as the default one
export type Records = { [string]: ClassSave }

-- everything the schema needs from GameData, handed in so the module stays
-- pure (PlayerData builds it once; tests build their own)
export type Defaults = {
	-- the skill slots a class can open (the gacha opens them, M70); the
	-- highest slot index a save may name
	maxSkillSlots: number,
	-- skill id -> true for every skill in the catalogue
	validSkillIds: { [string]: boolean },
}

export type Repair = string

function ClassSchema.getDefault(defaults: Defaults): ClassSave
	return {
		skills = {},
	}
end

local function validateSkills(record: any, defaults: Defaults, prefix: string, repairs: { Repair })
	if typeof(record.skills) ~= "table" then
		record.skills = {}
		table.insert(repairs, prefix .. "skills reset")
		return
	end
	for key, skill in record.skills do
		local slot = if typeof(key) == "string" then tonumber(key) else nil
		local isSlotValid = slot ~= nil and Validate.isValueType(slot, "positiveInteger") and slot <= defaults.maxSkillSlots
		local isSkillValid = typeof(skill) == "table"
			and typeof(skill.skillId) == "string"
			and defaults.validSkillIds[skill.skillId] == true
			and Enums.isValidValue(Enums.Rarity, skill.rarity)
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

-- the optional free rolls: a slot key or a roll time that makes no sense
-- drops the entry, an offer naming an unknown skill or rarity drops only
-- the offer (the wait it started still stands)
local function validateFreeRolls(record: any, defaults: Defaults, prefix: string, repairs: { Repair })
	if record.freeRolls == nil then
		return
	end
	if typeof(record.freeRolls) ~= "table" then
		record.freeRolls = nil
		table.insert(repairs, prefix .. "freeRolls reset")
		return
	end
	for key, freeRoll in record.freeRolls do
		local slot = if typeof(key) == "string" then tonumber(key) else nil
		local isSlotValid = slot ~= nil and Validate.isValueType(slot, "positiveInteger") and slot <= defaults.maxSkillSlots
		if not isSlotValid or typeof(freeRoll) ~= "table" or typeof(freeRoll.rollTime) ~= "number" then
			record.freeRolls[key] = nil
			table.insert(repairs, prefix .. "freeRolls dropped slot " .. tostring(key))
			continue
		end
		local hasOffer = freeRoll.skillId ~= nil or freeRoll.rarity ~= nil
		local isOfferValid = typeof(freeRoll.skillId) == "string" and defaults.validSkillIds[freeRoll.skillId] == true and Enums.isValidValue(Enums.Rarity, freeRoll.rarity)
		if hasOffer and not isOfferValid then
			freeRoll.skillId = nil
			freeRoll.rarity = nil
			table.insert(repairs, prefix .. "freeRolls." .. key .. " dropped its offer")
		end
		for field in freeRoll do
			if field ~= "rollTime" and field ~= "skillId" and field ~= "rarity" then
				freeRoll[field] = nil
				table.insert(repairs, prefix .. "freeRolls." .. key .. " dropped field " .. tostring(field))
			end
		end
	end
end

-- repairs one record in place and returns it; nil when it is not a table,
-- which the caller replaces with the default. `prefix` names the record
-- in repair messages ("classes.GUNNER.")
function ClassSchema.validate(record: any, defaults: Defaults, prefix: string, repairs: { Repair }): ClassSave?
	if typeof(record) ~= "table" then
		table.insert(repairs, prefix .. "reset: not a table")
		return nil
	end
	validateSkills(record, defaults, prefix, repairs)
	validateFreeRolls(record, defaults, prefix, repairs)
	local knownFields = ClassSchema.getDefault(defaults) :: any
	for key in record do
		if knownFields[key] == nil and key ~= "freeRolls" then
			record[key] = nil
			table.insert(repairs, prefix .. "dropped unknown field " .. tostring(key))
		end
	end
	return record
end

-- every record repaired in place: an entry whose key is not a class name
-- is dropped, a broken record becomes the default. A class with no
-- record is left absent; the manager makes one when the player first
-- touches that class
function ClassSchema.validateRecords(records: any, defaults: Defaults, repairs: { Repair }): Records
	if typeof(records) ~= "table" then
		table.insert(repairs, "classes reset")
		return {}
	end
	for key, record in records do
		if typeof(key) ~= "string" or Enums.getValueByName(Enums.ClassKind, key) == nil then
			records[key] = nil
			table.insert(repairs, "classes dropped entry " .. tostring(key))
			continue
		end
		local validated = ClassSchema.validate(record, defaults, "classes." .. key .. ".", repairs)
		records[key] = validated or ClassSchema.getDefault(defaults)
	end
	return records
end

-- the skills travel to the client as one JSON attribute: an array in slot
-- order, an empty slot an empty table, so a menu can draw every row
function ClassSchema.encodeSkills(skills: { [string]: SkillSave }, slotCount: number): string
	return HttpService:JSONEncode(ClassSchema.skillRows(skills, slotCount))
end

function ClassSchema.skillRows(skills: { [string]: SkillSave }, slotCount: number): { any }
	local rows = {}
	for slot = 1, slotCount do
		local skill = skills[tostring(slot)]
		rows[slot] = if skill then { skillId = skill.skillId, rarity = skill.rarity } else {}
	end
	return rows
end

local function skillsFromRows(rows: any): { [string]: SkillSave }
	local skills: { [string]: SkillSave } = {}
	if typeof(rows) ~= "table" then
		return skills
	end
	for slot, row in rows do
		if typeof(row) == "table" and typeof(row.skillId) == "string" and typeof(row.rarity) == "number" then
			skills[tostring(slot)] = { skillId = row.skillId, rarity = row.rarity }
		end
	end
	return skills
end

-- the free rolls travel beside the skills, keyed by slot as in the save
local function freeRollsFromRows(rows: any): { [string]: FreeRollSave }?
	if typeof(rows) ~= "table" then
		return nil
	end
	local freeRolls: { [string]: FreeRollSave } = {}
	for key, row in rows do
		if typeof(key) == "string" and typeof(row) == "table" and typeof(row.rollTime) == "number" then
			freeRolls[key] = {
				rollTime = row.rollTime,
				skillId = if typeof(row.skillId) == "string" then row.skillId else nil,
				rarity = if typeof(row.rarity) == "number" then row.rarity else nil,
			}
		end
	end
	return freeRolls
end

local function decodeJson(encoded: any): any
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess then
		return nil
	end
	return decoded
end

function ClassSchema.decodeSkills(encoded: any): { [string]: SkillSave }
	return skillsFromRows(decodeJson(encoded))
end

-- every class record as one JSON attribute (the Class Menu draws every
-- class's perks from it): class name -> { skills rows }
function ClassSchema.encodeRecords(records: Records, slotCount: number): string
	local encoded: { [string]: any } = {}
	for className, record in records do
		encoded[className] = {
			skills = ClassSchema.skillRows(record.skills, slotCount),
			-- nil for most records, and then left out of the JSON
			freeRolls = if record.freeRolls and next(record.freeRolls) ~= nil then record.freeRolls else nil,
		}
	end
	return HttpService:JSONEncode(encoded)
end

function ClassSchema.decodeRecords(encoded: any): Records
	local records: Records = {}
	local decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" then
		return records
	end
	for className, record in decoded do
		if typeof(className) ~= "string" or typeof(record) ~= "table" then
			continue
		end
		records[className] = {
			skills = skillsFromRows(record.skills),
			freeRolls = freeRollsFromRows(record.freeRolls),
		}
	end
	return records
end

return ClassSchema
