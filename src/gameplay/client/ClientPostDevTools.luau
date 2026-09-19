--!strict

-- Gameplay dev tool section for posts (M25): pick the post weapon the next
-- claim spawns (standing in for the lobby loadout until that store exists),
-- claim and mount a post by number from anywhere, and hand a claimed post back.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientPostDevTools = {}
ClientPostDevTools.__index = ClientPostDevTools

export type ClientPostDevTools = typeof(setmetatable(
	{} :: {
		kindOptions: { string },
		kindOption: any,
		indexInput: any,
	},
	ClientPostDevTools
))

-- must match PostDevTools.*_COMMAND on the server
local SET_LOADOUT_POST_COMMAND = "setLoadoutPost"
local RELEASE_POST_COMMAND = "releasePost"
local CLAIM_POST_COMMAND = "claimPost"
local MOUNT_POST_COMMAND = "mountPost"

function ClientPostDevTools:renderSection()
	Iris.Separator()
	Iris.Text({ "Posts" })
	Iris.ComboArray({ "Post weapon" }, { index = self.kindOption }, self.kindOptions)
	if Iris.Button({ "Set loadout post" }).clicked() then
		local kind = Enums.getValueByName(Enums.PostWeaponKind, self.kindOption:get())
		if kind then
			ClientNetManager:fireServer(
				NetEventNames.TRY_DEV_TOOL,
				{
					command = SET_LOADOUT_POST_COMMAND,
					args = { kind = kind },
				}
			)
		end
	end
	Iris.InputNum({ "Post number", 1, 1, 6 }, { number = self.indexInput })
	for _, entry in { { label = "Claim post", command = CLAIM_POST_COMMAND }, { label = "Mount post", command = MOUNT_POST_COMMAND } } do
		if Iris.Button({ entry.label }).clicked() then
			ClientNetManager:fireServer(
				NetEventNames.TRY_DEV_TOOL,
				{
					command = entry.command,
					args = { index = self.indexInput:get() },
				}
			)
		end
	end
	if Iris.Button({ "Release my post" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = RELEASE_POST_COMMAND,
				args = {},
			}
		)
	end
end

function ClientPostDevTools:init()
	for _, kind in Enums.getAllValues(Enums.PostWeaponKind) do
		table.insert(self.kindOptions, Enums.getName(Enums.PostWeaponKind, kind) or "?")
	end
	self.kindOption = Iris.State(self.kindOptions[1])
	self.indexInput = Iris.State(1)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientPostDevTools.new(): ClientPostDevTools
	local self = setmetatable({}, ClientPostDevTools) :: ClientPostDevTools
	self.kindOptions = {}
	self.kindOption = nil
	self.indexInput = nil
	return self
end

return ClientPostDevTools.new()
