--!strict

-- Gameplay-only dev tool buttons, added as a section of the common admin
-- panel so common code never has to know the place.
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientRunDevTools = {}
ClientRunDevTools.__index = ClientRunDevTools

export type ClientRunDevTools = typeof(setmetatable({} :: {}, ClientRunDevTools))

-- must match RunDevTools.RETURN_TO_LOBBY_COMMAND on the server
local RETURN_TO_LOBBY_COMMAND = "returnToLobby"

function ClientRunDevTools:renderSection()
	if Iris.Button({ "Return to lobby" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = RETURN_TO_LOBBY_COMMAND,
			}
		)
	end
end

function ClientRunDevTools:init()
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientRunDevTools.new(): ClientRunDevTools
	local self = setmetatable({}, ClientRunDevTools) :: ClientRunDevTools
	return self
end

return ClientRunDevTools.new()
