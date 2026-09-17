--!strict

-- Gameplay dev tool section for camp structures (M23): damage or destroy a
-- structure by id, grant Iron, set the shared fortification tier, and flip
-- day and night for the gate, since nothing deals damage and no clock runs
-- until later milestones.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientStructureDevTools = {}
ClientStructureDevTools.__index = ClientStructureDevTools

export type ClientStructureDevTools = typeof(setmetatable(
	{} :: {
		damageInput: any,
		ironInput: any,
		tierInput: any,
	},
	ClientStructureDevTools
))

-- must match StructureDevTools.*_COMMAND on the server
local DAMAGE_STRUCTURE_COMMAND = "damageStructure"
local ADD_IRON_COMMAND = "addIron"
local SET_FORTIFICATION_TIER_COMMAND = "setFortificationTier"
local SET_NIGHT_COMMAND = "setNight"

local DESTROY_AMOUNT = 1000000

function ClientStructureDevTools:getStructureIds(): { string }
	local ids = {}
	for _, shadow in CollectionService:GetTagged(Tags.STRUCTURE) do
		local id = shadow:GetAttribute(Attributes.STRUCTURE_ID)
		if typeof(id) == "string" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

function ClientStructureDevTools:damage(id: string, amount: number)
	ClientNetManager:fireServer(
		NetEventNames.TRY_DEV_TOOL,
		{
			command = DAMAGE_STRUCTURE_COMMAND,
			args = {
				id = id,
				amount = amount,
			},
		}
	)
end

function ClientStructureDevTools:renderSection()
	Iris.Separator()
	local isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	Iris.Text({ `Structures: tier {ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_TIER)}, {if isNight then "night" else "day"}` })
	if Iris.Button({ if isNight then "Make it day" else "Make it night" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SET_NIGHT_COMMAND,
				args = { isNight = not isNight },
			}
		)
	end
	Iris.InputNum({ "Iron", 10, 0 }, { number = self.ironInput })
	if Iris.Button({ "Add iron" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = ADD_IRON_COMMAND,
				args = { amount = math.floor(self.ironInput:get()) },
			}
		)
	end
	Iris.InputNum({ "Fortification tier", 1, 1 }, { number = self.tierInput })
	if Iris.Button({ "Set fortification tier" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SET_FORTIFICATION_TIER_COMMAND,
				args = { tier = math.max(1, math.floor(self.tierInput:get())) },
			}
		)
	end
	Iris.InputNum({ "Damage", 10, 1 }, { number = self.damageInput })
	for _, id in self:getStructureIds() do
		Iris.SameLine()
		Iris.Text({ id })
		if Iris.Button({ "Damage" }).clicked() then
			self:damage(id, math.max(1, math.floor(self.damageInput:get())))
		end
		if Iris.Button({ "Destroy" }).clicked() then
			self:damage(id, DESTROY_AMOUNT)
		end
		Iris.End()
	end
end

function ClientStructureDevTools:init()
	self.damageInput = Iris.State(50)
	self.ironInput = Iris.State(200)
	self.tierInput = Iris.State(2)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientStructureDevTools.new(): ClientStructureDevTools
	local self = setmetatable({}, ClientStructureDevTools) :: ClientStructureDevTools
	self.damageInput = nil
	self.ironInput = nil
	self.tierInput = nil
	return self
end

return ClientStructureDevTools.new()
