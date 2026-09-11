--!strict

-- Gameplay-only dev tool commands, registered with the common DevTools so
-- the admin panel can drive them without common code knowing the place.
local TeleportService = game:GetService("TeleportService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)

local RunDevTools = {}
RunDevTools.__index = RunDevTools

export type RunDevTools = typeof(setmetatable({} :: {}, RunDevTools))

RunDevTools.RETURN_TO_LOBBY_COMMAND = "returnToLobby"

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

function RunDevTools:init()
	DevTools:registerPlaceCommand(
		RunDevTools.RETURN_TO_LOBBY_COMMAND,
		function(player: Player, _args: { [string]: any })
			self:returnToLobby(player)
		end
	)
end

function RunDevTools.new(): RunDevTools
	local self = setmetatable({}, RunDevTools) :: RunDevTools
	return self
end

return RunDevTools.new()
