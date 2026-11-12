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
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)

local ClientGachaDevTools = {}
ClientGachaDevTools.__index = ClientGachaDevTools

export type ClientGachaDevTools = typeof(setmetatable(
	{} :: {
		keysInput: any,
		classOption: any,
		classOptions: { string },
		-- the dropdown of every prize in the pool, label to prize key
		prizeOption: any,
		prizeOptions: { string },
		prizeKeyByOption: { [string]: string },
		restrictedChecked: any,
		lastSentRestricted: boolean?,
	},
	ClientGachaDevTools
))

-- must match GachaManager.*_COMMAND on the server
local ROLL_FREE_COMMAND = "rollGachaFree"
local ROLL_FORCED_COMMAND = "rollGachaForced"
local SET_KEYS_COMMAND = "setKeys"
local GRANT_CLASS_STEP_COMMAND = "grantClassStep"
local SET_RESTRICTED_COMMAND = "setPaidRandomRestricted"
local CLEAR_CLASS_PROGRESS_COMMAND = "clearClassProgress"
local CLEAR_COSMETICS_COMMAND = "clearCosmetics"
local RESET_CRATE_TUTORIAL_COMMAND = "resetCrateTutorial"
local RESET_FREE_REROLLS_COMMAND = "resetFreeRerolls"
local RESET_STORE_PURCHASES_COMMAND = "resetStorePurchases"
local RESET_GROUP_REWARD_COMMAND = "resetGroupReward"
local ADVANCE_DAILY_REWARD_COMMAND = "advanceDailyReward"
local GRANT_STARTER_PACK_COMMAND = "grantStarterPack"
local RESET_STARTER_PACK_COMMAND = "resetStarterPack"
local RESET_DAILY_REWARD_COMMAND = "resetDailyReward"

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

	-- every prize in the pool, from the published config, so the list is
	-- the server's; the label is the prize's name and its key is what is sent
	if config and #self.prizeOptions ~= #config.prizes then
		self.prizeOptions = {}
		self.prizeKeyByOption = {}
		for _, prize in config.prizes do
			local label
			if prize.kind == Enums.GachaResultKind.CLASS then
				label = "Class: " .. (Enums.getName(Enums.ClassKind, prize.classKind or 0) or "?")
			elseif prize.kind == Enums.GachaResultKind.COSMETIC then
				label = "Cosmetic: " .. tostring(prize.cosmeticId)
			else
				label = "Keys"
			end
			table.insert(self.prizeOptions, label)
			self.prizeKeyByOption[label] = prize.key
		end
		table.sort(self.prizeOptions)
		self.prizeOption:set(self.prizeOptions[1] or "")
	end
	Iris.ComboArray({ "Prize to force" }, { index = self.prizeOption }, self.prizeOptions)
	if Iris.Button({ "Roll the chosen prize (free)" }).clicked() then
		local prizeKey = self.prizeKeyByOption[self.prizeOption:get()]
		if prizeKey then
			local send = function()
				sendDevTool(ROLL_FORCED_COMMAND, { prizeKey = prizeKey })
			end
			-- with the menu open the crate plays it out; closed, it just lands
			if not ClientGachaMenuManager:requestForcedRoll(send) then
				send()
			end
		end
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
	if Iris.Button({ "Clear class progress" }).clicked() then
		sendDevTool(CLEAR_CLASS_PROGRESS_COMMAND, {})
	end
	if Iris.Button({ "Clear cosmetics" }).clicked() then
		sendDevTool(CLEAR_COSMETICS_COMMAND, {})
	end
	if Iris.Button({ "Daily rewards: make the next day ready" }).clicked() then
		sendDevTool(ADVANCE_DAILY_REWARD_COMMAND, {})
	end
	if Iris.Button({ "Daily rewards: reset to day 1" }).clicked() then
		sendDevTool(RESET_DAILY_REWARD_COMMAND, {})
	end
	if Iris.Button({ "Starter Pack: pay the contents (no purchase)" }).clicked() then
		sendDevTool(GRANT_STARTER_PACK_COMMAND, {})
	end
	if Iris.Button({ "Starter Pack: reset" }).clicked() then
		sendDevTool(RESET_STARTER_PACK_COMMAND, {})
	end
	if Iris.Button({ "Reset the group reward" }).clicked() then
		sendDevTool(RESET_GROUP_REWARD_COMMAND, {})
	end
	if Iris.Button({ "Reset the Supply Crate tutorial" }).clicked() then
		sendDevTool(RESET_CRATE_TUTORIAL_COMMAND, {})
	end
	if Iris.Button({ "Reset free rerolls (restricted)" }).clicked() then
		sendDevTool(RESET_FREE_REROLLS_COMMAND, {})
	end
	if Iris.Button({ "Reset rotating store purchases (restricted)" }).clicked() then
		sendDevTool(RESET_STORE_PURCHASES_COMMAND, {})
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
	self.prizeOption = Iris.State("")
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
	self.prizeOption = nil
	self.prizeOptions = {}
	self.prizeKeyByOption = {}
	self.restrictedChecked = nil
	self.lastSentRestricted = nil
	return self
end

return ClientGachaDevTools.new()
