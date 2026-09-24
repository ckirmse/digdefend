--!strict

-- Gameplay dev tools for the rescue (M31): fill the uranium count to the
-- target, call the helicopter now, and board it from anywhere, so the
-- ending can be played without mining a whole run.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local RefineryManager = require(script.Parent.RefineryManager)
local RescueManager = require(script.Parent.RescueManager)

local RescueDevTools = {}
RescueDevTools.__index = RescueDevTools

export type RescueDevTools = typeof(setmetatable({} :: {}, RescueDevTools))

RescueDevTools.URANIUM_TO_TARGET_COMMAND = "uraniumToTarget"
RescueDevTools.CALL_HELICOPTER_COMMAND = "callHelicopter"
RescueDevTools.BOARD_HELICOPTER_COMMAND = "boardHelicopter"

local NO_ARGS_SHAPE = {}

function RescueDevTools:init()
	DevTools:registerPlaceCommand(
		RescueDevTools.URANIUM_TO_TARGET_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("RescueDevTools: uraniumToTarget with invalid args:", errorMessage)
				return
			end
			RefineryManager:addUranium(math.max(0, RefineryManager:getUraniumTarget() - RefineryManager:getUraniumTotal()))
		end
	)
	DevTools:registerPlaceCommand(
		RescueDevTools.CALL_HELICOPTER_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("RescueDevTools: callHelicopter with invalid args:", errorMessage)
				return
			end
			RescueManager:call(player)
		end
	)
	DevTools:registerPlaceCommand(
		RescueDevTools.BOARD_HELICOPTER_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("RescueDevTools: boardHelicopter with invalid args:", errorMessage)
				return
			end
			RescueManager:board(player)
		end
	)
end

function RescueDevTools.new(): RescueDevTools
	local self = setmetatable({}, RescueDevTools) :: RescueDevTools
	return self
end

return RescueDevTools.new()
