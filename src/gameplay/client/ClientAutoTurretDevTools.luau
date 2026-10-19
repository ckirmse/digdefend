--!strict

-- Gameplay dev tool section for the Auto Turret (M66): the standing
-- turret's HP, a button that hurts it (the loss path without waiting on
-- a wave), and one that brings a lost turret back before dawn.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientAutoTurretDevTools = {}
ClientAutoTurretDevTools.__index = ClientAutoTurretDevTools

export type ClientAutoTurretDevTools = typeof(setmetatable(
	{} :: {
		damageInput: any,
	},
	ClientAutoTurretDevTools
))

-- must match AutoTurretDevTools.*_COMMAND on the server
local DAMAGE_AUTO_TURRET_COMMAND = "damageAutoTurret"
local RESTORE_AUTO_TURRET_COMMAND = "restoreAutoTurret"

function ClientAutoTurretDevTools:renderSection()
	Iris.Separator()
	local isLost = ClientDataManager:getCurrentPlayerAttribute(Attributes.AUTO_TURRET_IS_LOST) == true
	Iris.Text({ `Auto Turret: {if isLost then "lost until dawn" else "available"}` })
	local turretCount = 0
	for _, shadow in CollectionService:GetTagged(Tags.AUTO_TURRET) do
		turretCount += 1
		Iris.Text({ `{shadow.Name}: owner {tostring(shadow:GetAttribute(Attributes.AUTO_TURRET_OWNER_USER_ID))}, HP {tostring(shadow:GetAttribute(Attributes.AUTO_TURRET_HP))} / {tostring(shadow:GetAttribute(Attributes.AUTO_TURRET_MAX_HP))}` })
	end
	if turretCount == 0 then
		Iris.Text({ "No turret standing" })
	end
	Iris.InputNum({ "Turret damage", 10, 1 }, { number = self.damageInput })
	if Iris.Button({ "Damage my turret" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = DAMAGE_AUTO_TURRET_COMMAND,
				args = { amount = math.max(1, math.floor(self.damageInput:get())) },
			}
		)
	end
	if Iris.Button({ "Restore lost turret" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = RESTORE_AUTO_TURRET_COMMAND,
				args = {},
			}
		)
	end
end

function ClientAutoTurretDevTools:init()
	self.damageInput = Iris.State(50)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientAutoTurretDevTools.new(): ClientAutoTurretDevTools
	local self = setmetatable({}, ClientAutoTurretDevTools) :: ClientAutoTurretDevTools
	self.damageInput = nil
	return self
end

return ClientAutoTurretDevTools.new()
