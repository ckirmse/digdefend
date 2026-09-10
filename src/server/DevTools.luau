--!strict

-- Server half of the admin-only dev tools. Every command arrives as
-- TryDevTool { command, args }; the sender must be an admin and the command
-- must be on the explicit allowlist below. Each command validates its own args.
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevToolCommands = require(script.Parent.DevToolCommands)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local DevTools = {}
DevTools.__index = DevTools

export type DevTools = typeof(setmetatable({} :: {}, DevTools))

local gameController: any -- prevent circular reference by not initializing here

local TRY_DEV_TOOL_SHAPE = {
	command = "string",
	args = { type = "table", optional = true },
}

local SEND_TEST_FEEDBACK_ARGS_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

-- a method is client-callable only if named in DevToolCommands.NAMES; init()
-- verifies every listed name has a method below
function DevTools:getNetHandlers()
	return {
		[NetEventNames.TRY_DEV_TOOL] = {
			shape = TRY_DEV_TOOL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryDevTool(player, payload)
			end,
		},
	}
end

function DevTools:handleTryDevTool(player: Player, payload: { [string]: any })
	if not gameController:isPlayerAdmin(player) then
		warn("DevTools: command from non-admin", player.Name, payload.command)
		return
	end

	local command = payload.command
	if not DevToolCommands.isCommand(command) then
		warn("DevTools: unknown command", command, "from", player.Name)
		return
	end

	print("DevTools: executing", command, "for", player.Name)
	local method = (DevTools :: any)[command]
	method(self, player, payload.args or {})
end

-- full reset to a brand-new player; see DEV TOOL CONTRACT in GameController
function DevTools:resetPlayerState(player: Player, args: { [string]: any })
	gameController:resetPlayerState(player)
end

function DevTools:sendTestFeedback(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SEND_TEST_FEEDBACK_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: sendTestFeedback with invalid args:", err)
		return
	end
	PlayerFeedbackManager:give(player, args.message, args.displaySec)
end

function DevTools:init(gameControllerIn: any)
	gameController = gameControllerIn
	for _, name in DevToolCommands.NAMES do
		if typeof((DevTools :: any)[name]) ~= "function" then
			error("DevTools: allowlisted command has no method: " .. name)
		end
	end
end

function DevTools.new(): DevTools
	local self = setmetatable({}, DevTools) :: DevTools
	return self
end

return DevTools.new()
