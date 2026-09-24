--!strict

-- Gameplay dev tools for the monsters (M29): spawn any kind at a numbered
-- spawn, kill every monster, run the stress test (a crowd spread over every
-- spawn), start the night's wave now, and show the path grid (red where
-- nothing walks, orange barriers, green arrows along the ground field).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local MonsterWaveManager = require(script.Parent.MonsterWaveManager)

local MonsterDevTools = {}
MonsterDevTools.__index = MonsterDevTools

export type MonsterDevTools = typeof(setmetatable({} :: {}, MonsterDevTools))

MonsterDevTools.SPAWN_MONSTERS_COMMAND = "spawnMonsters"
MonsterDevTools.KILL_ALL_MONSTERS_COMMAND = "killAllMonsters"
MonsterDevTools.STRESS_TEST_MONSTERS_COMMAND = "stressTestMonsters"
MonsterDevTools.SET_MONSTER_PATHS_VISIBLE_COMMAND = "setMonsterPathsVisible"

local SPAWN_MONSTERS_ARGS_SHAPE = {
	kind = { type = "enum", name = "MonsterKind" },
	count = "positiveInteger",
	spawnNumber = "positiveInteger",
}
local STRESS_TEST_ARGS_SHAPE = {
	count = "positiveInteger",
}
local SET_VISIBLE_ARGS_SHAPE = {
	isVisible = "boolean",
}
local NO_ARGS_SHAPE = {}

local function register(name: string, shape: { [string]: any }, handler: (args: { [string]: any }) -> ())
	DevTools:registerPlaceCommand(
		name,
		function(_player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, shape)
			if not isValid then
				warn(`MonsterDevTools: {name} with invalid args:`, errorMessage)
				return
			end
			handler(args)
		end
	)
end

function MonsterDevTools:init()
	register(
		MonsterDevTools.SPAWN_MONSTERS_COMMAND,
		SPAWN_MONSTERS_ARGS_SHAPE,
		function(args)
			MonsterWaveManager:spawnGroupNow(args.kind, math.min(args.count, BehaviorData.STRESS_TEST_MAX), args.spawnNumber)
		end
	)
	register(
		MonsterDevTools.KILL_ALL_MONSTERS_COMMAND,
		NO_ARGS_SHAPE,
		function(_args)
			MonsterManager:killAll()
		end
	)
	-- spread over every spawn so the crowd walks in as a wide front
	register(
		MonsterDevTools.STRESS_TEST_MONSTERS_COMMAND,
		STRESS_TEST_ARGS_SHAPE,
		function(args)
			local spawnNumbers = MonsterPathManager:getSpawnNumbers()
			if #spawnNumbers == 0 then
				warn("MonsterDevTools: the camp has no monster spawns")
				return
			end
			local total = math.min(args.count, BehaviorData.STRESS_TEST_MAX)
			for index, spawnNumber in spawnNumbers do
				local share = total // #spawnNumbers + (if index <= total % #spawnNumbers then 1 else 0)
				if share > 0 then
					MonsterWaveManager:spawnGroupNow(Enums.MonsterKind.ZOMBIE_1, share, spawnNumber)
				end
			end
			print(`[MonsterDevTools] stress test: {total} monsters over {#spawnNumbers} spawns`)
		end
	)
	register(
		MonsterDevTools.SET_MONSTER_PATHS_VISIBLE_COMMAND,
		SET_VISIBLE_ARGS_SHAPE,
		function(args)
			MonsterPathManager:setDebugVisible(args.isVisible)
		end
	)
end

function MonsterDevTools.new(): MonsterDevTools
	local self = setmetatable({}, MonsterDevTools) :: MonsterDevTools
	return self
end

return MonsterDevTools.new()
