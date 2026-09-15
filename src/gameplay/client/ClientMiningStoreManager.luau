--!strict

-- The Mining Supplies Store on this client (GDD "Mining Supplies Store"):
-- every stand in the camp's MiningStore is drawn here, because what a stand
-- offers depends on the viewer (their level on that track) as well as the
-- crew (the Camp Level). The server publishes the catalogue once as
-- GameMetadata JSON; this manager fills each stand's SurfaceGui (next level
-- name, Gold price, "Maxed out", greyed when locked), sets the prompt's text
-- locally, and spins the next level's display model over the ItemSpawn part.
-- Buying is the server's job: the prompt trigger never leaves this client as
-- a message.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientMiningStoreManager = {}
ClientMiningStoreManager.__index = ClientMiningStoreManager

type StandView = {
	item: number,
	base: BasePart,
	itemSpawn: BasePart?,
	nameLabel: TextLabel?,
	priceBox: GuiObject?,
	priceLabel: TextLabel?,
	resourceIcon: ImageLabel?,
	campLevelLabel: TextLabel?,
	prompt: ProximityPrompt?,
	display: Model?,
	displayName: string?,
	spin: number,
}

export type ClientMiningStoreManager = typeof(setmetatable(
	{} :: {
		catalog: StoreRules.Catalog?,
		stands: { StandView },
		heartbeat: RBXScriptConnection?,
		warnedTemplates: { [string]: boolean },
	},
	ClientMiningStoreManager
))

local NOTIFY_STORE_PURCHASE_SHAPE = {
	item = { type = "enum", name = "StoreItem" },
	price = "nonnegativeInteger",
}

-- degrees per second the display model turns
local DISPLAY_TURN_DEGREES_PER_SEC = 45
local DISPLAY_LIFT_STUDS = 0.5
local PROMPT_ACTION_BUY = "Buy"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientMiningStoreManager:getCampLevel(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL), 1)
end

function ClientMiningStoreManager:getGold(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
end

function ClientMiningStoreManager:getOwnedLevel(item: number): number
	local attribute = StoreRules.LEVEL_ATTRIBUTE_BY_ITEM[item]
	if not attribute then
		return 1
	end
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(attribute), 1)
end

-- upgrade tracks show the level a buy would reach (the top level once
-- maxed); consumables show the one model. Pick axes are the held-tool
-- templates so the stand and the hand agree; the rest are store displays.
function ClientMiningStoreManager:displayTemplateName(item: number, offer: StoreRules.Offer): string?
	local key = Enums.getName(Enums.StoreItem, item)
	if not key then
		return nil
	end
	local track = if self.catalog then self.catalog.upgrades[item] else nil
	if track then
		local level = offer.level or #track.priceByLevel
		return `{key}_{level}`
	end
	return key
end

function ClientMiningStoreManager:findTemplate(item: number, templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	if not gameAssets then
		return nil
	end
	local folderName = if item == Enums.StoreItem.PICK_AXE or item == Enums.StoreItem.TORCH or item == Enums.StoreItem.DYNAMITE
		then Constants.TOOL_TEMPLATES_FOLDER
		else Constants.STORE_DISPLAY_TEMPLATES_FOLDER
	local folder = gameAssets:FindFirstChild(folderName)
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`ClientMiningStoreManager: no display Model GameAssets.{folderName}.{templateName}`)
	end
	return nil
end

function ClientMiningStoreManager:setDisplay(view: StandView, templateName: string?)
	if view.displayName == templateName then
		return
	end
	if view.display then
		view.display:Destroy()
		view.display = nil
	end
	view.displayName = templateName
	local itemSpawn = view.itemSpawn
	if not templateName or not itemSpawn then
		return
	end
	local template = self:findTemplate(view.item, templateName)
	if not template then
		return
	end
	local model = template:Clone()
	model.Name = "Display"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	model.Parent = itemSpawn
	view.display = model
end

function ClientMiningStoreManager:renderStand(view: StandView)
	local catalog = self.catalog
	if not catalog then
		return
	end
	local offer = StoreRules.getOffer(catalog, view.item, self:getOwnedLevel(view.item), self:getCampLevel())
	if not offer then
		return
	end
	local isMaxed = offer.status == Enums.StoreOffer.MAXED
	local isLocked = offer.status == Enums.StoreOffer.LOCKED
	local price = offer.price or 0
	if view.nameLabel then
		view.nameLabel.Text = UiStyle.formatTitle(StoreRules.nameText(view.item, offer))
	end
	if view.priceBox then
		view.priceBox.Visible = not isMaxed
	end
	if view.priceLabel then
		view.priceLabel.Text = tostring(price)
		local color = UiStyle.TEXT_COLOR
		if isLocked then
			color = UiStyle.DISABLED_COLOR
		elseif not StoreRules.canAfford(self:getGold(), price) then
			color = UiStyle.NEGATIVE_COLOR
		end
		view.priceLabel.TextColor3 = color
	end
	local campLevelLabel = view.campLevelLabel
	if campLevelLabel then
		-- only a requirement the crew has not met is worth a line (decided 2026-09-15)
		local required = StoreRules.requiredCampLevelForOffer(offer)
		if required and isLocked then
			campLevelLabel.Text = string.format(StoreRules.LOCKED_FORMAT, required)
			campLevelLabel.TextColor3 = UiStyle.NEGATIVE_COLOR
			campLevelLabel.Visible = true
		else
			campLevelLabel.Visible = false
		end
	end
	if view.resourceIcon then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR]
		view.resourceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		view.resourceIcon.ImageColor3 = if isLocked then UiStyle.DISABLED_COLOR else Color3.new(1, 1, 1)
	end
	-- these prompt edits are local: the server still decides every buy
	local prompt = view.prompt
	if prompt then
		if isMaxed then
			prompt.Enabled = false
		elseif isLocked then
			prompt.Enabled = false
		else
			prompt.Enabled = true
			prompt.ActionText = PROMPT_ACTION_BUY
		end
	end
	self:setDisplay(view, self:displayTemplateName(view.item, offer))
end

function ClientMiningStoreManager:renderAll()
	for _, view in self.stands do
		self:renderStand(view)
	end
end

function ClientMiningStoreManager:step(deltaSec: number)
	for _, view in self.stands do
		local display = view.display
		local itemSpawn = view.itemSpawn
		if not display or not itemSpawn then
			continue
		end
		view.spin = (view.spin + math.rad(DISPLAY_TURN_DEGREES_PER_SEC) * deltaSec) % (math.pi * 2)
		display:PivotTo(CFrame.new(itemSpawn.Position + Vector3.new(0, DISPLAY_LIFT_STUDS, 0)) * CFrame.Angles(0, view.spin, 0))
	end
end

function ClientMiningStoreManager:bindStand(store: Instance, item: number)
	local stand = store:FindFirstChild(StoreRules.standNameForItem(item) :: string)
	local base = if stand then stand:FindFirstChild(Constants.STAND_BASE_PART) else nil
	if not base or not base:IsA("BasePart") then
		return
	end
	local gui = base:FindFirstChild(Constants.STAND_GUI)
	local priceBox = if gui then gui:FindFirstChild(Constants.STAND_PRICE_BOX) else nil
	local nameLabel = if gui then gui:FindFirstChild(Constants.STAND_NAME_LABEL) else nil
	local priceLabel = if priceBox then priceBox:FindFirstChild(Constants.STAND_PRICE_LABEL) else nil
	local resourceIcon = if priceBox then priceBox:FindFirstChild(Constants.STAND_RESOURCE_ICON) else nil
	local campLevelLabel = if gui then gui:FindFirstChild(Constants.STAND_CAMP_LEVEL_LABEL) else nil
	local itemSpawn = if stand then stand:FindFirstChild(Constants.STAND_ITEM_SPAWN_PART) else nil
	-- the server creates the prompt on run start; it may land after the camp
	local prompt = base:FindFirstChildWhichIsA("ProximityPrompt")
	local view: StandView = {
		item = item,
		base = base,
		itemSpawn = if itemSpawn and itemSpawn:IsA("BasePart") then itemSpawn else nil,
		nameLabel = if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil,
		priceBox = if priceBox and priceBox:IsA("GuiObject") then priceBox else nil,
		priceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil,
		resourceIcon = if resourceIcon and resourceIcon:IsA("ImageLabel") then resourceIcon else nil,
		campLevelLabel = if campLevelLabel and campLevelLabel:IsA("TextLabel") then campLevelLabel else nil,
		prompt = prompt,
		display = nil,
		displayName = nil,
		spin = 0,
	}
	if not prompt then
		base.ChildAdded:Connect(
			function(child: Instance)
				if child:IsA("ProximityPrompt") and not view.prompt then
					view.prompt = child
					self:renderStand(view)
				end
			end
		)
	end
	table.insert(self.stands, view)
	self:renderStand(view)
end

function ClientMiningStoreManager:bindCamp(camp: Instance)
	for _, view in self.stands do
		if view.display then
			view.display:Destroy()
		end
	end
	self.stands = {}
	local store = camp:FindFirstChild(Constants.CAMP_MINING_STORE_MODEL)
	if not store then
		warn("ClientMiningStoreManager: the camp has no MiningStore")
		return
	end
	for _, item in Enums.getAllValues(Enums.StoreItem) do
		self:bindStand(store, item)
	end
	if not self.heartbeat then
		self.heartbeat = RunService.Heartbeat:Connect(
			function(deltaSec: number)
				self:step(deltaSec)
			end
		)
	end
end

function ClientMiningStoreManager:onPurchase(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_STORE_PURCHASE_SHAPE)
	if not isValid then
		warn("ClientMiningStoreManager: malformed NotifyStorePurchase")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
end

function ClientMiningStoreManager:readCatalog()
	self.catalog = StoreRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.STORE_CATALOG))
	self:renderAll()
end

function ClientMiningStoreManager:init()
	self:readCatalog()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.STORE_CATALOG,
		function()
			self:readCatalog()
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.CAMP_LEVEL,
		function()
			self:renderAll()
		end
	)
	local watched = { Attributes.BALANCE_GOLD_BARS }
	for _, attribute in StoreRules.LEVEL_ATTRIBUTE_BY_ITEM do
		table.insert(watched, attribute)
	end
	for _, key in watched do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:renderAll()
			end
		)
	end
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_STORE_PURCHASE,
		function(payload: any)
			self:onPurchase(payload)
		end
	)

	-- the camp is cloned into Workspace at run start, possibly after this client loaded
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if camp then
		self:bindCamp(camp)
	end
	workspace.ChildAdded:Connect(
		function(child: Instance)
			if child.Name == Constants.CAMP_FOLDER then
				-- its descendants replicate after the folder itself
				task.defer(
					function()
						self:bindCamp(child)
					end
				)
			end
		end
	)
	local _ = Players.LocalPlayer
end

function ClientMiningStoreManager.new(): ClientMiningStoreManager
	local self = setmetatable({}, ClientMiningStoreManager) :: ClientMiningStoreManager
	self.catalog = nil
	self.stands = {}
	self.heartbeat = nil
	self.warnedTemplates = {}
	return self
end

return ClientMiningStoreManager.new()
