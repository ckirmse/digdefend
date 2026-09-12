--!strict

-- Gameplay-only dev tool buttons, added as a section of the common admin
-- panel so common code never has to know the place.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientRunDevTools = {}
ClientRunDevTools.__index = ClientRunDevTools

export type ClientRunDevTools = typeof(setmetatable(
	{} :: {
		mapOptions: { string },
		difficultyOptions: { string },
		mapOption: any,
		difficultyOption: any,
	},
	ClientRunDevTools
))

-- must match RunDevTools.*_COMMAND on the server
local RETURN_TO_LOBBY_COMMAND = "returnToLobby"
local START_RUN_AS_COMMAND = "startRunAs"

local function enumKeyOptions(enumTable: Enums.EnumTable): { string }
	local options = {}
	for _, value in Enums.getAllValues(enumTable) do
		table.insert(options, Enums.getName(enumTable, value) :: string)
	end
	return options
end

function ClientRunDevTools:renderSection()
	if Iris.Button({ "Return to lobby" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = RETURN_TO_LOBBY_COMMAND,
			}
		)
	end

	Iris.Separator()
	Iris.ComboArray({ "Map" }, { index = self.mapOption }, self.mapOptions)
	Iris.ComboArray({ "Difficulty" }, { index = self.difficultyOption }, self.difficultyOptions)
	if Iris.Button({ "Start run as" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = START_RUN_AS_COMMAND,
				args = {
					map = Enums.getValueByName(Enums.Map, self.mapOption:get()),
					difficulty = Enums.getValueByName(Enums.Difficulty, self.difficultyOption:get()),
				},
			}
		)
	end
end

function ClientRunDevTools:init()
	self.mapOptions = enumKeyOptions(Enums.Map)
	self.difficultyOptions = enumKeyOptions(Enums.Difficulty)
	self.mapOption = Iris.State(self.mapOptions[1])
	self.difficultyOption = Iris.State(self.difficultyOptions[1])
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientRunDevTools.new(): ClientRunDevTools
	local self = setmetatable({}, ClientRunDevTools) :: ClientRunDevTools
	self.mapOptions = {}
	self.difficultyOptions = {}
	self.mapOption = nil
	self.difficultyOption = nil
	return self
end

return ClientRunDevTools.new()
