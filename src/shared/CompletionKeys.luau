--!strict

-- A map/difficulty completion is saved as one string key ("DEADMANS_CANYON/NORMAL")
-- so the completions set stays flat and readable in the Explorer and in saves.
local Enums = require(script.Parent.Enums)

local CompletionKeys = {}

local SEPARATOR = "/"

function CompletionKeys.make(map: number, difficulty: number): string?
	local mapName = Enums.getName(Enums.Map, map)
	local difficultyName = Enums.getName(Enums.Difficulty, difficulty)
	if not mapName or not difficultyName then
		return nil
	end
	return mapName .. SEPARATOR .. difficultyName
end

function CompletionKeys.parse(key: any): (number?, number?)
	if typeof(key) ~= "string" then
		return nil, nil
	end
	local mapName, difficultyName = string.match(key, "^([A-Z_]+)" .. SEPARATOR .. "([A-Z_]+)$")
	if not mapName or not difficultyName then
		return nil, nil
	end
	local map = Enums.getValueByName(Enums.Map, mapName)
	local difficulty = Enums.getValueByName(Enums.Difficulty, difficultyName)
	if not map or not difficulty then
		return nil, nil
	end
	return map, difficulty
end

function CompletionKeys.isValid(key: any): boolean
	local map = CompletionKeys.parse(key)
	return map ~= nil
end

return CompletionKeys
