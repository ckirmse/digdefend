--!strict

-- Pure rules for helicopter pad parties: config validation, map and
-- difficulty unlock checks, and Create selection validation. Shared so the
-- server enforces and the Create Party menu previews the same rules. The
-- config is passed in (GameData/Pads/Party on the server; the replicated copy
-- on the client) so this module stays free of GameData and unit testable.
local CompletionKeys = require(script.Parent.CompletionKeys)
local Enums = require(script.Parent.Enums)
local Validate = require(script.Parent.Validate)

local PartyRules = {}

export type Requirement = {
	map: number?,
	difficulty: number?,
}

export type MapEntry = {
	map: number,
	thumbnail: string,
	requires: Requirement?,
}

export type DifficultyEntry = {
	difficulty: number,
	requires: Requirement?,
}

export type Config = {
	CREATION_TIMEOUT_SEC: number,
	BOARDING_TIMEOUT_SEC: number,
	CAPACITY_TIME_SEC: number,
	MAX_PARTY_SIZE: number,
	DEFAULT_MAX_PLAYERS: number,
	DEFAULT_VISIBILITY: number,
	MAPS: { MapEntry },
	DIFFICULTIES: { DifficultyEntry },
}

export type Selection = {
	map: number,
	difficulty: number,
	maxPlayers: number,
	visibility: number,
}

export type HasCompletion = (completionKey: string) -> boolean

local REQUIREMENT_SHAPE = {
	map = { type = "enum", name = "Map", optional = true },
	difficulty = { type = "enum", name = "Difficulty", optional = true },
}

local MAP_ENTRY_SHAPE = {
	map = { type = "enum", name = "Map" },
	thumbnail = "string",
	requires = { type = "table", shape = REQUIREMENT_SHAPE, optional = true },
}

local DIFFICULTY_ENTRY_SHAPE = {
	difficulty = { type = "enum", name = "Difficulty" },
	requires = { type = "table", shape = REQUIREMENT_SHAPE, optional = true },
}

local CONFIG_SHAPE = {
	CREATION_TIMEOUT_SEC = "positiveNumber",
	BOARDING_TIMEOUT_SEC = "positiveNumber",
	CAPACITY_TIME_SEC = "positiveNumber",
	MAX_PARTY_SIZE = "positiveInteger",
	DEFAULT_MAX_PLAYERS = "positiveInteger",
	DEFAULT_VISIBILITY = { type = "enum", name = "PartyVisibility" },
	MAPS = { type = "array", elementType = { type = "table", shape = MAP_ENTRY_SHAPE }, nonempty = true },
	DIFFICULTIES = { type = "array", elementType = { type = "table", shape = DIFFICULTY_ENTRY_SHAPE }, nonempty = true },
}

PartyRules.SELECTION_SHAPE = {
	map = { type = "enum", name = "Map" },
	difficulty = { type = "enum", name = "Difficulty" },
	maxPlayers = "positiveInteger",
	visibility = { type = "enum", name = "PartyVisibility" },
}

function PartyRules.getMapEntry(config: Config, map: number): MapEntry?
	for _, entry in config.MAPS do
		if entry.map == map then
			return entry
		end
	end
	return nil
end

function PartyRules.getDifficultyEntry(config: Config, difficulty: number): DifficultyEntry?
	for _, entry in config.DIFFICULTIES do
		if entry.difficulty == difficulty then
			return entry
		end
	end
	return nil
end

-- every problem with a config, each naming the offending key; empty when valid
function PartyRules.validateConfig(config: any): { string }
	local problems = {}
	local isValid, err = Validate.isTableShape(config, CONFIG_SHAPE)
	if not isValid then
		table.insert(problems, "shape: " .. tostring(err))
		return problems
	end

	local typedConfig = config :: Config
	if typedConfig.DEFAULT_MAX_PLAYERS > typedConfig.MAX_PARTY_SIZE then
		table.insert(problems, "DEFAULT_MAX_PLAYERS exceeds MAX_PARTY_SIZE")
	end

	local seenMaps: { [number]: boolean } = {}
	for index, entry in typedConfig.MAPS do
		if seenMaps[entry.map] then
			table.insert(problems, `MAPS[{index}] duplicates map {Enums.getName(Enums.Map, entry.map)}`)
		end
		seenMaps[entry.map] = true
	end

	local seenDifficulties: { [number]: boolean } = {}
	for index, entry in typedConfig.DIFFICULTIES do
		if seenDifficulties[entry.difficulty] then
			table.insert(problems, `DIFFICULTIES[{index}] duplicates difficulty {Enums.getName(Enums.Difficulty, entry.difficulty)}`)
		end
		seenDifficulties[entry.difficulty] = true
	end

	for index, entry in typedConfig.MAPS do
		local requires = entry.requires
		if not requires then
			continue
		end
		if requires.map == nil or requires.difficulty == nil then
			table.insert(problems, `MAPS[{index}].requires needs both map and difficulty`)
			continue
		end
		if not seenMaps[requires.map] then
			table.insert(problems, `MAPS[{index}].requires.map is not in MAPS`)
		end
		if not seenDifficulties[requires.difficulty] then
			table.insert(problems, `MAPS[{index}].requires.difficulty is not in DIFFICULTIES`)
		end
		if requires.map == entry.map then
			table.insert(problems, `MAPS[{index}].requires its own map`)
		end
	end

	for index, entry in typedConfig.DIFFICULTIES do
		local requires = entry.requires
		if not requires then
			continue
		end
		if requires.difficulty == nil then
			table.insert(problems, `DIFFICULTIES[{index}].requires needs a difficulty`)
			continue
		end
		if not seenDifficulties[requires.difficulty] then
			table.insert(problems, `DIFFICULTIES[{index}].requires.difficulty is not in DIFFICULTIES`)
		end
		if requires.map ~= nil and not seenMaps[requires.map] then
			table.insert(problems, `DIFFICULTIES[{index}].requires.map is not in MAPS`)
		end
		if requires.map == nil and requires.difficulty == entry.difficulty then
			table.insert(problems, `DIFFICULTIES[{index}].requires itself`)
		end
	end

	return problems
end

-- completion key the host needs before this map can be selected; nil when free
function PartyRules.getMapRequirementKey(config: Config, map: number): string?
	local entry = PartyRules.getMapEntry(config, map)
	if not entry or not entry.requires then
		return nil
	end
	local requires = entry.requires
	if requires.map == nil or requires.difficulty == nil then
		return nil
	end
	return CompletionKeys.make(requires.map, requires.difficulty)
end

-- completion key the host needs before this difficulty can be selected on
-- this map; nil when free
function PartyRules.getDifficultyRequirementKey(config: Config, map: number, difficulty: number): string?
	local entry = PartyRules.getDifficultyEntry(config, difficulty)
	if not entry or not entry.requires then
		return nil
	end
	local requires = entry.requires
	if requires.difficulty == nil then
		return nil
	end
	return CompletionKeys.make(requires.map or map, requires.difficulty)
end

function PartyRules.isMapUnlocked(config: Config, map: number, hasCompletion: HasCompletion): boolean
	if not PartyRules.getMapEntry(config, map) then
		return false
	end
	local key = PartyRules.getMapRequirementKey(config, map)
	return key == nil or hasCompletion(key)
end

function PartyRules.isDifficultyUnlocked(config: Config, map: number, difficulty: number, hasCompletion: HasCompletion): boolean
	if not PartyRules.getDifficultyEntry(config, difficulty) then
		return false
	end
	local key = PartyRules.getDifficultyRequirementKey(config, map, difficulty)
	return key == nil or hasCompletion(key)
end

-- carousel order; nil only when the config is broken
function PartyRules.getFirstUnlockedDifficulty(config: Config, map: number, hasCompletion: HasCompletion): number?
	for _, entry in config.DIFFICULTIES do
		if PartyRules.isDifficultyUnlocked(config, map, entry.difficulty, hasCompletion) then
			return entry.difficulty
		end
	end
	return nil
end

-- player-facing text for a locked option, e.g. "Complete Deadman's Canyon on Normal"
function PartyRules.getRequirementText(completionKey: string): string
	local map, difficulty = CompletionKeys.parse(completionKey)
	if map == nil or difficulty == nil then
		return "Locked"
	end
	local mapName = Enums.getPublicName(Enums.Map, map) or "?"
	local difficultyName = Enums.getPublicName(Enums.Difficulty, difficulty) or "?"
	return `Complete {mapName} on {difficultyName}`
end

-- the server's Create validation; the returned reason is player-facing
function PartyRules.validateSelection(config: Config, selection: any, hasCompletion: HasCompletion): (boolean, string?)
	local isValidShape = Validate.isTableShape(selection, PartyRules.SELECTION_SHAPE)
	if not isValidShape then
		return false, "Invalid party settings"
	end
	local typedSelection = selection :: Selection
	if not PartyRules.getMapEntry(config, typedSelection.map) then
		return false, "Unknown map"
	end
	if not PartyRules.getDifficultyEntry(config, typedSelection.difficulty) then
		return false, "Unknown difficulty"
	end
	if not PartyRules.isMapUnlocked(config, typedSelection.map, hasCompletion) then
		return false, "Map is locked"
	end
	if not PartyRules.isDifficultyUnlocked(config, typedSelection.map, typedSelection.difficulty, hasCompletion) then
		return false, "Difficulty is locked"
	end
	if typedSelection.maxPlayers > config.MAX_PARTY_SIZE then
		return false, "Party size too large"
	end
	return true, nil
end

return PartyRules
