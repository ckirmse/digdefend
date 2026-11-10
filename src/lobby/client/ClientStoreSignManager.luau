--!strict

-- Which of a lobby stall's two name signs this player sees (designer,
-- 2026-11-10). Each stall folder (DiamondStore, SupplyCrateStore,
-- ClassSelection, GearSelection) has a 3DText model of letter meshes,
-- visible as authored, and a Sign part whose SurfaceGui is authored off
-- and carries the same name in an auto-localised TextLabel. Roblox's
-- translation cannot reach a mesh, so a player whose Roblox language is
-- not English gets the flat sign instead, on every stall. A player
-- restricted from paid random items gets the flat signs too, because the
-- Supply Crate stall is something else for them: it is the rotating
-- store and reads STORE. All of it is local to this client (the letters are
-- hidden with LocalTransparencyModifier, which never replicates and
-- leaves the authored Transparency alone), and it is undone if the
-- restricted flag turns off again (the dev panel's checkbox).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientLoadingScreenManager = require(script.Parent.Parent.Client.ClientLoadingScreenManager)

local ClientStoreSignManager = {}
ClientStoreSignManager.__index = ClientStoreSignManager

type Stall = {
	folderName: string,
	textModel: Instance?,
	surfaceGui: SurfaceGui?,
	label: TextLabel?,
	-- the label's own words, put back when it is no longer overridden
	authoredText: string,
}

-- an always-on information sign whose words change for a restricted
-- player
type InfoSign = {
	label: TextLabel,
	authoredText: string,
	restrictedText: string,
}

export type ClientStoreSignManager = typeof(setmetatable(
	{} :: {
		stalls: { Stall },
		infoSigns: { InfoSign },
		-- nil until the language has been asked for
		isEnglish: boolean?,
		-- stalls still being waited for, and whether the loading
		-- screen has been let go
		pendingStallCount: number,
		hasReleasedHold: boolean,
	},
	ClientStoreSignManager
))

local STALL_FOLDER_NAMES = {
	Constants.LOBBY_DIAMOND_STORE_FOLDER,
	Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER,
	Constants.LOBBY_CLASS_SELECTION_FOLDER,
	Constants.LOBBY_GEAR_SELECTION_FOLDER,
}
-- what a stall is called for a player who may not buy paid random
-- items, by its folder (designer, 2026-11-10: STORE on the Supply Crate
-- stall, which is the rotating store for them; GEAR STORE there and
-- CLASS STORE on the Class Selection stall were tried the same day);
-- auto-localised like the label's own words. A stall not listed keeps
-- its own
local RESTRICTED_TEXT_BY_FOLDER = {
	[Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER] = "STORE",
}
-- the information signs beside a stall that speak of Supply Crates
-- (designer, 2026-11-10): always on, as authored, and reworded for a
-- player who has the rotating store in the crates' place
local RESTRICTED_INFO_SIGNS = {
	{
		folderName = Constants.LOBBY_CLASS_SELECTION_FOLDER,
		partName = "Sign1",
		text = "UNLOCK CLASSES IN THE STORE",
	},
}
-- the arrival loading screen stays up until the signs are final (every
-- stall found, the language known, the policy answered), so the swap is
-- never seen; ClientLoadingScreenManager gives up after 10 s
local LOADING_HOLD_NAME = "StoreSigns"

-- the language the player's Roblox is set to, as its bare tag ("en" for
-- en-us and en-gb alike); the Translator carries the account's setting
local function playerLanguage(): string
	local localeId = LocalizationService.RobloxLocaleId
	local isSuccess, translator = pcall(
		function()
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end
	)
	if isSuccess and translator then
		localeId = translator.LocaleId
	end
	return string.lower(string.split(localeId, "-")[1])
end

function ClientStoreSignManager:setLettersHidden(stall: Stall, isHidden: boolean)
	local textModel = stall.textModel
	if not textModel then
		return
	end
	for _, descendant in textModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if isHidden then 1 else 0
		end
	end
end

function ClientStoreSignManager:renderStall(stall: Stall)
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	local usesFlatSign = self.isEnglish == false or isRestricted
	self:setLettersHidden(stall, usesFlatSign)
	local surfaceGui = stall.surfaceGui
	if surfaceGui then
		surfaceGui.Enabled = usesFlatSign
	end
	local label = stall.label
	local restrictedText = RESTRICTED_TEXT_BY_FOLDER[stall.folderName]
	if label and restrictedText then
		label.Text = if isRestricted then restrictedText else stall.authoredText
	end
end

-- lets the loading screen go once nothing more can change the signs
function ClientStoreSignManager:releaseHoldIfFinal()
	if self.hasReleasedHold or self.pendingStallCount > 0 or self.isEnglish == nil then
		return
	end
	if ClientDataManager:getCurrentPlayerAttribute(Attributes.IS_PAID_RANDOM_ITEMS_POLICY_KNOWN) ~= true then
		return
	end
	self.hasReleasedHold = true
	self:render()
	ClientLoadingScreenManager:releaseHold(LOADING_HOLD_NAME)
end

function ClientStoreSignManager:render()
	for _, stall in self.stalls do
		self:renderStall(stall)
	end
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	for _, infoSign in self.infoSigns do
		infoSign.label.Text = if isRestricted then infoSign.restrictedText else infoSign.authoredText
	end
end

-- waited for like a stall's parts; a sign that never comes is left alone
function ClientStoreSignManager:bindInfoSign(folderName: string, partName: string, restrictedText: string)
	local folder = workspace:WaitForChild(folderName, Constants.GUI_WAIT_SEC)
	local part = if folder then folder:WaitForChild(partName, Constants.GUI_WAIT_SEC) else nil
	local surfaceGui = if part then part:WaitForChild("SurfaceGui", Constants.GUI_WAIT_SEC) else nil
	local label = if surfaceGui then surfaceGui:WaitForChild("TextLabel", Constants.GUI_WAIT_SEC) else nil
	if not label or not label:IsA("TextLabel") then
		warn(`ClientStoreSignManager: no {folderName}.{partName}.SurfaceGui.TextLabel; that sign is left as authored`)
		return
	end
	table.insert(self.infoSigns, {
		label = label,
		authoredText = label.Text,
		restrictedText = restrictedText,
	})
	self:render()
end

-- a stall's parts can arrive after this client starts, so each is waited
-- for off the main thread; letters that arrive later still are hidden as
-- they come
function ClientStoreSignManager:bindStall(folderName: string)
	local folder = workspace:WaitForChild(folderName, Constants.GUI_WAIT_SEC)
	if not folder then
		warn(`ClientStoreSignManager: no {folderName} folder in Workspace; its sign is left as authored`)
		return
	end
	local textModel = folder:WaitForChild(Constants.LOBBY_STALL_3D_TEXT_MODEL, Constants.GUI_WAIT_SEC)
	local sign = folder:WaitForChild(Constants.LOBBY_STALL_SIGN_PART, Constants.GUI_WAIT_SEC)
	local surfaceGui = if sign then sign:WaitForChild("SurfaceGui", Constants.GUI_WAIT_SEC) else nil
	local label = if surfaceGui then surfaceGui:WaitForChild("TextLabel", Constants.GUI_WAIT_SEC) else nil
	if not textModel or not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		warn(`ClientStoreSignManager: {folderName} has no {Constants.LOBBY_STALL_3D_TEXT_MODEL} model or no {Constants.LOBBY_STALL_SIGN_PART}.SurfaceGui; its sign is left as authored`)
		return
	end
	local stall: Stall = {
		folderName = folderName,
		textModel = textModel,
		surfaceGui = surfaceGui,
		label = if label and label:IsA("TextLabel") then label else nil,
		authoredText = if label and label:IsA("TextLabel") then label.Text else "",
	}
	table.insert(self.stalls, stall)
	textModel.DescendantAdded:Connect(
		function()
			self:renderStall(stall)
		end
	)
	self:renderStall(stall)
end

function ClientStoreSignManager:init()
	self.pendingStallCount = #STALL_FOLDER_NAMES + #RESTRICTED_INFO_SIGNS
	for _, infoSign in RESTRICTED_INFO_SIGNS do
		task.spawn(
			function()
				self:bindInfoSign(infoSign.folderName, infoSign.partName, infoSign.text)
				self.pendingStallCount -= 1
				self:releaseHoldIfFinal()
			end
		)
	end
	for _, folderName in STALL_FOLDER_NAMES do
		task.spawn(
			function()
				self:bindStall(folderName)
				self.pendingStallCount -= 1
				self:releaseHoldIfFinal()
			end
		)
	end
	-- the language is a web call: until it answers the letters stay, and
	-- the signs are drawn again once it has
	task.spawn(
		function()
			self.isEnglish = playerLanguage() == Constants.TITLE_ART_LANGUAGE
			self:render()
			self:releaseHoldIfFinal()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.IS_PAID_RANDOM_ITEMS_POLICY_KNOWN,
		function()
			self:releaseHoldIfFinal()
		end
	)
	self:releaseHoldIfFinal()
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED,
		function()
			self:render()
		end
	)
end

function ClientStoreSignManager.new(): ClientStoreSignManager
	local self = setmetatable({}, ClientStoreSignManager) :: ClientStoreSignManager
	self.stalls = {}
	self.infoSigns = {}
	self.isEnglish = nil
	self.pendingStallCount = 0
	self.hasReleasedHold = false
	-- at require time, which is before startup can reach hide()
	ClientLoadingScreenManager:addHold(LOADING_HOLD_NAME)
	return self
end

return ClientStoreSignManager.new()
