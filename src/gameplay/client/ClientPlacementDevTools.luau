--!strict

-- Gameplay dev tool section for placements (M26): build the Tower loadout
-- the build bar shows (standing in for the lobby loadout until that menu
-- exists), grant Traps without a store trip, damage a placement by id to
-- test HP and destruction, and clear the grid.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientPlacementDevTools = {}
ClientPlacementDevTools.__index = ClientPlacementDevTools

export type ClientPlacementDevTools = typeof(setmetatable(
	{} :: {
		towerOptions: { string },
		towerOption: any,
		trapOptions: { string },
		trapOption: any,
		trapAmountInput: any,
		placementIdInput: any,
		damageInput: any,
	},
	ClientPlacementDevTools
))

-- must match PlacementDevTools.*_COMMAND on the server
local ADD_LOADOUT_TOWER_COMMAND = "addLoadoutTower"
local CLEAR_LOADOUT_TOWERS_COMMAND = "clearLoadoutTowers"
local GRANT_TRAP_COMMAND = "grantTrap"
local DAMAGE_PLACEMENT_COMMAND = "damagePlacement"
local CLEAR_PLACEMENTS_COMMAND = "clearPlacements"

function ClientPlacementDevTools:send(command: string, args: { [string]: any })
	ClientNetManager:fireServer(
		NetEventNames.TRY_DEV_TOOL,
		{
			command = command,
			args = args,
		}
	)
end

function ClientPlacementDevTools:renderSection()
	Iris.Separator()
	Iris.Text({ "Placements" })
	Iris.ComboArray({ "Tower" }, { index = self.towerOption }, self.towerOptions)
	if Iris.Button({ "Add tower to loadout" }).clicked() then
		local kind = Enums.getValueByName(Enums.TowerKind, self.towerOption:get())
		if kind then
			self:send(ADD_LOADOUT_TOWER_COMMAND, { kind = kind })
		end
	end
	if Iris.Button({ "Clear tower loadout" }).clicked() then
		self:send(CLEAR_LOADOUT_TOWERS_COMMAND, {})
	end
	Iris.ComboArray({ "Trap" }, { index = self.trapOption }, self.trapOptions)
	Iris.InputNum({ "Trap amount", 1, 1, 20 }, { number = self.trapAmountInput })
	if Iris.Button({ "Grant traps" }).clicked() then
		local kind = Enums.getValueByName(Enums.TrapKind, self.trapOption:get())
		if kind then
			self:send(GRANT_TRAP_COMMAND, { kind = kind, amount = self.trapAmountInput:get() })
		end
	end
	Iris.InputText({ "Placement id" }, { text = self.placementIdInput })
	Iris.InputNum({ "Damage", 10, 1, 10000 }, { number = self.damageInput })
	if Iris.Button({ "Damage placement" }).clicked() then
		self:send(DAMAGE_PLACEMENT_COMMAND, { id = self.placementIdInput:get(), amount = self.damageInput:get() })
	end
	if Iris.Button({ "Clear every placement" }).clicked() then
		self:send(CLEAR_PLACEMENTS_COMMAND, {})
	end
end

function ClientPlacementDevTools:init()
	for _, kind in Enums.getAllValues(Enums.TowerKind) do
		table.insert(self.towerOptions, Enums.getName(Enums.TowerKind, kind) or "?")
	end
	for _, kind in Enums.getAllValues(Enums.TrapKind) do
		table.insert(self.trapOptions, Enums.getName(Enums.TrapKind, kind) or "?")
	end
	self.towerOption = Iris.State(self.towerOptions[1])
	self.trapOption = Iris.State(self.trapOptions[1])
	self.trapAmountInput = Iris.State(3)
	self.placementIdInput = Iris.State("Placement1")
	self.damageInput = Iris.State(50)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientPlacementDevTools.new(): ClientPlacementDevTools
	local self = setmetatable({}, ClientPlacementDevTools) :: ClientPlacementDevTools
	self.towerOptions = {}
	self.towerOption = nil
	self.trapOptions = {}
	self.trapOption = nil
	self.trapAmountInput = nil
	self.placementIdInput = nil
	self.damageInput = nil
	return self
end

return ClientPlacementDevTools.new()
