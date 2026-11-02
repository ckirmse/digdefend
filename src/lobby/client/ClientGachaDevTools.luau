--!strict

-- Lobby dev tool section for the class gacha (M70): the account's Keys,
-- class progress, and policy flag, a free roll, a Keys setter, the next
-- step of one class granted outright, and the restricted path toggled
-- so the direct buy can be tested in Studio.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)

local ClientGachaDevTools = {}
ClientGachaDevTools.__index = ClientGachaDevTools

export type ClientGachaDevTools = typeof(setmetatable(
	{} :: {
		keysInput: any,
		classOption: any,
		classOptions: { string },
		restrictedChecked: any,
		lastSentRestricted: boolean?,
	},
	ClientGachaDevTools
))

-- must match GachaManager.*_COMMAND on the server
local ROLL_FREE_COMMAND = "rollGachaFree"
local SET_KEYS_COMMAND = "setKeys"
local GRANT_CLASS_STEP_COMMAND = "grantClassStep"
local SET_RESTRICTED_COMMAND = "setPaidRandomRestricted"

local function sendDevTool(command: string, args: { [string]: any })
	ClientNetManager:fireServer(
		NetEventNames.TRY_DEV_TOOL,
		{
			command = command,
			args = args,
		}
	)
end

function ClientGachaDevTools:renderSection()
	Iris.Separator()
	local config = GachaRules.decodeConfig(ClientDataManager:getGameMetadata(Attributes.GACHA_CONFIG))
	local progress = ClientDataManager:getClassProgress()
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	Iris.Text({ `Gacha: {ClientDataManager:getKeys()} Keys, paid random items {if isRestricted then "restricted" else "allowed"}` })
	local owned = {}
	for className, slots in progress do
		table.insert(owned, `{className} {slots}/{if config then config.maxSkillSlots else "?"}`)
	end
	table.sort(owned)
	Iris.Text({ "Classes: " .. table.concat(owned, ", ") })

	if Iris.Button({ "Roll for free" }).clicked() then
		sendDevTool(ROLL_FREE_COMMAND, {})
	end

	Iris.InputNum({ "Keys", 1, 0 }, { number = self.keysInput })
	if Iris.Button({ "Set Keys" }).clicked() then
		sendDevTool(SET_KEYS_COMMAND, { keys = math.max(0, math.floor(self.keysInput:get())) })
	end

	-- the pool's classes, from the published config, so the list is the
	-- server's and never a stale copy
	if config and #self.classOptions ~= #config.poolClassKinds then
		self.classOptions = {}
		for _, classKind in config.poolClassKinds do
			table.insert(self.classOptions, Enums.getName(Enums.ClassKind, classKind) or "?")
		end
		self.classOption:set(self.classOptions[1] or "")
	end
	Iris.ComboArray({ "Class to step" }, { index = self.classOption }, self.classOptions)
	if Iris.Button({ "Grant next step of class" }).clicked() then
		local classKind = Enums.getValueByName(Enums.ClassKind, self.classOption:get())
		if classKind then
			sendDevTool(GRANT_CLASS_STEP_COMMAND, { classKind = classKind })
		end
	end

	-- a change made elsewhere (the policy answering) resets the box so it
	-- never sends what the server already holds
	if self.lastSentRestricted == nil or (isRestricted ~= self.lastSentRestricted and self.restrictedChecked:get() == self.lastSentRestricted) then
		self.lastSentRestricted = isRestricted
		self.restrictedChecked:set(isRestricted)
	end
	Iris.Checkbox({ "Paid random items restricted" }, { isChecked = self.restrictedChecked })
	local wanted = self.restrictedChecked:get()
	if wanted ~= self.lastSentRestricted then
		self.lastSentRestricted = wanted
		sendDevTool(SET_RESTRICTED_COMMAND, { isRestricted = wanted })
	end
end

function ClientGachaDevTools:init()
	self.keysInput = Iris.State(0)
	self.classOption = Iris.State("")
	self.restrictedChecked = Iris.State(false)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientGachaDevTools.new(): ClientGachaDevTools
	local self = setmetatable({}, ClientGachaDevTools) :: ClientGachaDevTools
	self.keysInput = nil
	self.classOption = nil
	self.classOptions = {}
	self.restrictedChecked = nil
	self.lastSentRestricted = nil
	return self
end

return ClientGachaDevTools.new()
