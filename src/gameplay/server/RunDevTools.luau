--!strict

-- Gameplay-only dev tool commands, registered with the common DevTools so
-- the admin panel can drive them without common code knowing the place.
local TeleportService = game:GetService("TeleportService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local RunManager = require(script.Parent.RunManager)

local RunDevTools = {}
RunDevTools.__index = RunDevTools

export type RunDevTools = typeof(setmetatable({} :: {}, RunDevTools))

RunDevTools.RETURN_TO_LOBBY_COMMAND = "returnToLobby"
RunDevTools.START_RUN_AS_COMMAND = "startRunAs"

local START_RUN_AS_ARGS_SHAPE = {
	map = { type = "enum", name = "Map" },
	difficulty = { type = "enum", name = "Difficulty" },
}

-- no game-driven way back exists until the win and loss rules, so testers
-- need this to complete a round trip
function RunDevTools:returnToLobby(player: Player)
	local isSuccess, err = pcall(
		function()
			TeleportService:TeleportAsync(Constants.LOBBY_PLACE_ID, { player })
		end
	)
	if not isSuccess then
		warn(`RunDevTools: return to lobby failed for {player.Name}:`, err)
		PlayerFeedbackManager:give(player, PartyRules.FEEDBACK_TELEPORT_FAILED)
	end
end

-- Studio has no teleport data, so this is how a designer plays another map
-- or difficulty without leaving Play
function RunDevTools:startRunAs(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, START_RUN_AS_ARGS_SHAPE)
	if not isValid then
		warn("RunDevTools: startRunAs with invalid args:", err)
		return
	end
	RunManager:restartAs(args.map, args.difficulty)
	PlayerFeedbackManager:give(player, `Run restarted as {Enums.getPublicName(Enums.Map, args.map)} / {Enums.getPublicName(Enums.Difficulty, args.difficulty)}`)
end

function RunDevTools:init()
	DevTools:registerPlaceCommand(
		RunDevTools.RETURN_TO_LOBBY_COMMAND,
		function(player: Player, _args: { [string]: any })
			self:returnToLobby(player)
		end
	)
	DevTools:registerPlaceCommand(
		RunDevTools.START_RUN_AS_COMMAND,
		function(player: Player, args: { [string]: any })
			self:startRunAs(player, args)
		end
	)
end

function RunDevTools.new(): RunDevTools
	local self = setmetatable({}, RunDevTools) :: RunDevTools
	return self
end

return RunDevTools.new()
