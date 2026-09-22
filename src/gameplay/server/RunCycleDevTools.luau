--!strict

-- Gameplay dev tools for the day and night loop (M28): bring dusk or dawn
-- now, clear a night as the last enemy dying will at M29, and lose the
-- run, so the whole loop can be watched without waiting out a day.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local RunCycleData = require("@game/ServerScriptService/GameData/Control/RunCycle")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local RunCycleManager = require(script.Parent.RunCycleManager)

local RunCycleDevTools = {}
RunCycleDevTools.__index = RunCycleDevTools

export type RunCycleDevTools = typeof(setmetatable({} :: {}, RunCycleDevTools))

RunCycleDevTools.FORCE_NIGHT_COMMAND = "forceNight"
RunCycleDevTools.CLEAR_NIGHT_COMMAND = "clearNight"
RunCycleDevTools.LOSE_RUN_COMMAND = "loseRun"

local FORCE_NIGHT_ARGS_SHAPE = {
	isNight = "boolean",
}
local NO_ARGS_SHAPE = {}

function RunCycleDevTools:init()
	DevTools:registerPlaceCommand(
		RunCycleDevTools.FORCE_NIGHT_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, FORCE_NIGHT_ARGS_SHAPE)
			if not isValid then
				warn("RunCycleDevTools: forceNight with invalid args:", err)
				return
			end
			RunCycleManager:forceNight(args.isNight)
		end
	)
	DevTools:registerPlaceCommand(
		RunCycleDevTools.CLEAR_NIGHT_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("RunCycleDevTools: clearNight with invalid args:", err)
				return
			end
			RunCycleManager:clearNight()
		end
	)
	DevTools:registerPlaceCommand(
		RunCycleDevTools.LOSE_RUN_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("RunCycleDevTools: loseRun with invalid args:", err)
				return
			end
			RunCycleManager:endRun(false, RunCycleData.LOST_ALL_DEAD_MESSAGE)
		end
	)
end

function RunCycleDevTools.new(): RunCycleDevTools
	local self = setmetatable({}, RunCycleDevTools) :: RunCycleDevTools
	return self
end

return RunCycleDevTools.new()
