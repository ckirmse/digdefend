--!strict

-- Gameplay dev tool section for weapons and defenses (M24, M27): spawn a
-- target dummy in front of you, a walking or flying dummy that comes at
-- you from far out, and clear them all, since nothing else can be shot,
-- slowed, or trapped until enemies exist.
local CollectionService = game:GetService("CollectionService")

local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientWeaponDevTools = {}
ClientWeaponDevTools.__index = ClientWeaponDevTools

export type ClientWeaponDevTools = typeof(setmetatable({} :: {}, ClientWeaponDevTools))

-- must match WeaponDevTools.*_COMMAND on the server
local SPAWN_TARGET_DUMMY_COMMAND = "spawnTargetDummy"
local SPAWN_WALKING_DUMMY_COMMAND = "spawnWalkingDummy"
local CLEAR_TARGET_DUMMIES_COMMAND = "clearTargetDummies"

function ClientWeaponDevTools:renderSection()
	Iris.Separator()
	Iris.Text({ `Weapons: {#CollectionService:GetTagged(Tags.DAMAGEABLE)} target(s)` })
	if Iris.Button({ "Spawn target dummy" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SPAWN_TARGET_DUMMY_COMMAND,
				args = {},
			}
		)
	end
	if Iris.Button({ "Spawn walking dummy" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SPAWN_WALKING_DUMMY_COMMAND,
				args = { isAirborne = false },
			}
		)
	end
	if Iris.Button({ "Spawn flying dummy" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SPAWN_WALKING_DUMMY_COMMAND,
				args = { isAirborne = true },
			}
		)
	end
	if Iris.Button({ "Clear target dummies" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = CLEAR_TARGET_DUMMIES_COMMAND,
				args = {},
			}
		)
	end
end

function ClientWeaponDevTools:init()
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientWeaponDevTools.new(): ClientWeaponDevTools
	local self = setmetatable({}, ClientWeaponDevTools) :: ClientWeaponDevTools
	return self
end

return ClientWeaponDevTools.new()
