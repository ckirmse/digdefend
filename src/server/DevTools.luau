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

export type PlaceCommandHandler = (player: Player, args: { [string]: any }) -> ()

export type DevTools = typeof(setmetatable(
	{} :: {
		-- commands a place manager registered (registerPlaceCommand); the
		-- common allowlist stays in DevToolCommands
		placeCommands: { [string]: PlaceCommandHandler },
	},
	DevTools
))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any

local TRY_DEV_TOOL_SHAPE = {
	command = "string",
	args = { type = "table", optional = true },
}

local SEND_TEST_FEEDBACK_ARGS_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local SET_CASH_ARGS_SHAPE = {
	cash = "nonnegativeInteger",
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
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not playerData:getIsAdmin() then
		warn("DevTools: command from non-admin", player.Name, payload.command)
		return
	end

	local command = payload.command
	local placeHandler: PlaceCommandHandler? = self.placeCommands[command]
	if placeHandler then
		print("DevTools: executing", command, "for", player.Name)
		placeHandler(player, payload.args or {})
		return
	end
	if not DevToolCommands.isCommand(command) then
		warn("DevTools: unknown command", command, "from", player.Name)
		return
	end

	print("DevTools: executing", command, "for", player.Name)
	local method = (DevTools :: any)[command]
	method(self, player, payload.args or {})
end

-- lobby- and gameplay-only commands plug in here so common code never
-- names a place; the same admin check applies
function DevTools:registerPlaceCommand(name: string, handler: PlaceCommandHandler)
	if self.placeCommands[name] or DevToolCommands.isCommand(name) then
		error("DevTools: duplicate command " .. name)
	end
	self.placeCommands[name] = handler
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

function DevTools:setCash(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_CASH_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setCash with invalid args:", err)
		return
	end
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end
	playerData:setCash(args.cash)
	splendidReplicationManager:replicateCash(player)
	PlayerFeedbackManager:give(player, "Cash set to " .. tostring(playerData:getCash()))
end

function DevTools:init(gameControllerIn: any, splendidReplicationManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	for _, name in DevToolCommands.NAMES do
		if typeof((DevTools :: any)[name]) ~= "function" then
			error("DevTools: allowlisted command has no method: " .. name)
		end
	end
end

function DevTools.new(): DevTools
	local self = setmetatable({}, DevTools) :: DevTools
	self.placeCommands = {}
	return self
end

return DevTools.new()
