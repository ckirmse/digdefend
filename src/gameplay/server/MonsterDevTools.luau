--!strict

-- Gameplay dev tools for the monsters (M29): spawn any kind at a numbered
-- spawn, kill every monster, run the stress test (a crowd spread over every
-- spawn), start the night's wave now, and show the path grid (red where
-- nothing walks, orange barriers, green arrows along the ground field).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
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
MonsterDevTools.PREVIEW_WAVE_COMMAND = "previewWave"
MonsterDevTools.PREVIEW_CURVE_COMMAND = "previewWaveCurve"

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
local PREVIEW_WAVE_ARGS_SHAPE = {
	night = "positiveInteger",
}
local NO_ARGS_SHAPE = {}
local PREVIEW_CURVE_NIGHTS = 20

local function register(name: string, shape: { [string]: any }, handler: (player: Player, args: { [string]: any }) -> ())
	DevTools:registerPlaceCommand(
		name,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, shape)
			if not isValid then
				warn(`MonsterDevTools: {name} with invalid args:`, errorMessage)
				return
			end
			handler(player, args)
		end
	)
end

function MonsterDevTools:init()
	register(
		MonsterDevTools.SPAWN_MONSTERS_COMMAND,
		SPAWN_MONSTERS_ARGS_SHAPE,
		function(_player: Player, args: { [string]: any })
			MonsterWaveManager:spawnGroupNow(args.kind, math.min(args.count, BehaviorData.STRESS_TEST_MAX), args.spawnNumber)
		end
	)
	register(
		MonsterDevTools.KILL_ALL_MONSTERS_COMMAND,
		NO_ARGS_SHAPE,
		function(_player: Player, _args: { [string]: any })
			MonsterManager:killAll()
		end
	)
	-- spread over every spawn so the crowd walks in as a wide front
	register(
		MonsterDevTools.STRESS_TEST_MONSTERS_COMMAND,
		STRESS_TEST_ARGS_SHAPE,
		function(_player: Player, args: { [string]: any })
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
		function(_player: Player, args: { [string]: any })
			MonsterPathManager:setDebugVisible(args.isVisible)
		end
	)
	-- what a night would spawn for this run and crew, a roll of the dice like
	-- the real night; the whole wave goes to the Output, the headline to the player
	register(
		MonsterDevTools.PREVIEW_WAVE_COMMAND,
		PREVIEW_WAVE_ARGS_SHAPE,
		function(player: Player, args: { [string]: any })
			local result, reason = MonsterWaveManager:buildWave(args.night)
			if not result then
				PlayerFeedbackManager:give(player, `No wave: {reason}`)
				return
			end
			local lines = MonsterWaveManager:describeWave(result)
			print("[MonsterDevTools] preview\n" .. table.concat(lines, "\n"))
			PlayerFeedbackManager:give(player, lines[1] .. " (the rest is in the Output)")
		end
	)
	-- the difficulty curve as numbers, night by night, for tuning
	register(
		MonsterDevTools.PREVIEW_CURVE_COMMAND,
		NO_ARGS_SHAPE,
		function(player: Player, _args: { [string]: any })
			local lines = MonsterWaveManager:describeCurve(PREVIEW_CURVE_NIGHTS)
			print("[MonsterDevTools] curve\n" .. table.concat(lines, "\n"))
			PlayerFeedbackManager:give(player, "The wave curve is in the Output")
		end
	)
end

function MonsterDevTools.new(): MonsterDevTools
	local self = setmetatable({}, MonsterDevTools) :: MonsterDevTools
	return self
end

return MonsterDevTools.new()
