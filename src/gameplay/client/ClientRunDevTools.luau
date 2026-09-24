--!strict

-- Gameplay-only dev tool buttons, added as a section of the common admin
-- panel so common code never has to know the place.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
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
		dayInput: any,
	},
	ClientRunDevTools
))

-- must match RunDevTools.*_COMMAND on the server
local RETURN_TO_LOBBY_COMMAND = "returnToLobby"
local START_RUN_AS_COMMAND = "startRunAs"
-- must match RunCycleDevTools.*_COMMAND on the server
local FORCE_NIGHT_COMMAND = "forceNight"
local CLEAR_NIGHT_COMMAND = "clearNight"
local LOSE_RUN_COMMAND = "loseRun"
local SET_DAY_COMMAND = "setDay"
-- must match RescueDevTools.*_COMMAND on the server
local URANIUM_TO_TARGET_COMMAND = "uraniumToTarget"
local CALL_HELICOPTER_COMMAND = "callHelicopter"
local BOARD_HELICOPTER_COMMAND = "boardHelicopter"

local function enumKeyOptions(enumTable: Enums.EnumTable): { string }
	local options = {}
	for _, value in Enums.getAllValues(enumTable) do
		table.insert(options, Enums.getName(enumTable, value) :: string)
	end
	return options
end

function ClientRunDevTools:send(command: string, args: { [string]: any })
	ClientNetManager:fireServer(
		NetEventNames.TRY_DEV_TOOL,
		{
			command = command,
			args = args,
		}
	)
end

function ClientRunDevTools:renderSection()
	local runState = ClientDataManager:getGameMetadata(Attributes.RUN_STATE)
	Iris.Text({ `Run: {Enums.getPublicName(Enums.RunState, if typeof(runState) == "number" then runState else 0) or "?"}, day {tostring(ClientDataManager:getGameMetadata(Attributes.RUN_DAY))}, crew {tostring(ClientDataManager:getGameMetadata(Attributes.RUN_SCALING_COUNT))}` })
	if Iris.Button({ "Dusk now" }).clicked() then
		self:send(FORCE_NIGHT_COMMAND, { isNight = true })
	end
	if Iris.Button({ "Clear the night (dawn)" }).clicked() then
		self:send(CLEAR_NIGHT_COMMAND, {} :: { [string]: any })
	end
	if Iris.Button({ "Lose the run" }).clicked() then
		self:send(LOSE_RUN_COMMAND, {} :: { [string]: any })
	end
	if Iris.Button({ "Uranium to target" }).clicked() then
		self:send(URANIUM_TO_TARGET_COMMAND, {} :: { [string]: any })
	end
	if Iris.Button({ "Call the helicopter" }).clicked() then
		self:send(CALL_HELICOPTER_COMMAND, {} :: { [string]: any })
	end
	if Iris.Button({ "Board the helicopter" }).clicked() then
		self:send(BOARD_HELICOPTER_COMMAND, {} :: { [string]: any })
	end
	Iris.InputNum({ "Day", 1, 1, 99 }, { number = self.dayInput })
	if Iris.Button({ "Set day (by day only)" }).clicked() then
		self:send(SET_DAY_COMMAND, {
			day = math.max(1, math.floor(self.dayInput:get())),
		})
	end
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
	self.dayInput = Iris.State(1)
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
	self.dayInput = nil
	return self
end

return ClientRunDevTools.new()
