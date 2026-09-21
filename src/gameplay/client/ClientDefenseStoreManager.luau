--!strict

-- The Defense Store on this client (GDD "Buying Traps"), M26: every
-- stand in the camp's DefenseStore is drawn here from the defense
-- catalogue in GameMetadata, exactly as the Mining Store's are: the Trap's
-- name, its Iron price (red while the player cannot pay), a red "Camp
-- Level N required" line only while unmet, the prompt's text, and the
-- Trap's model spinning over the ItemSpawn part. Buying is the server's
-- job: the prompt trigger never leaves this client as a message.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientDefenseStoreManager = {}
ClientDefenseStoreManager.__index = ClientDefenseStoreManager

type StandView = {
	kind: number,
	base: BasePart,
	itemSpawn: BasePart?,
	nameLabel: TextLabel?,
	priceBox: GuiObject?,
	priceLabel: TextLabel?,
	resourceIcon: ImageLabel?,
	campLevelLabel: TextLabel?,
	prompt: ProximityPrompt?,
	display: Model?,
	spin: number,
}

export type ClientDefenseStoreManager = typeof(setmetatable(
	{} :: {
		catalog: PlacementRules.Catalog?,
		stands: { StandView },
		heartbeat: RBXScriptConnection?,
		warnedTemplates: { [string]: boolean },
	},
	ClientDefenseStoreManager
))

local NOTIFY_TRAP_PURCHASED_SHAPE = {
	kind = { type = "enum", name = "TrapKind" },
	price = "nonnegativeInteger",
}

local DISPLAY_TURN_DEGREES_PER_SEC = 45
local DISPLAY_LIFT_STUDS = 0.5
local PROMPT_ACTION_BUY = "Buy"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientDefenseStoreManager:getCampLevel(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL), 1)
end

function ClientDefenseStoreManager:getIron(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS), 0)
end

function ClientDefenseStoreManager:findTemplate(kind: number): Model?
	local templateName = PlacementRules.templateNameFor(Enums.PlacementKind.TRAP, kind)
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.TRAP_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`ClientDefenseStoreManager: no display Model GameAssets.{Constants.TRAP_TEMPLATES_FOLDER}.{templateName}`)
	end
	return nil
end

function ClientDefenseStoreManager:setDisplay(view: StandView)
	local itemSpawn = view.itemSpawn
	if view.display or not itemSpawn then
		return
	end
	local template = self:findTemplate(view.kind)
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

function ClientDefenseStoreManager:renderStand(view: StandView)
	local catalog = self.catalog
	local trap = if catalog then catalog.traps[view.kind] else nil
	if not trap then
		return
	end
	local isLocked = self:getCampLevel() < trap.REQUIRED_CAMP_LEVEL
	if view.nameLabel then
		view.nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.TrapKind, view.kind) or "?")
	end
	if view.priceBox then
		view.priceBox.Visible = true
	end
	if view.priceLabel then
		view.priceLabel.Text = tostring(trap.PRICE_IRON)
		local color = UiStyle.TEXT_COLOR
		if isLocked then
			color = UiStyle.DISABLED_COLOR
		elseif not PlacementRules.canAfford(self:getIron(), trap.PRICE_IRON) then
			color = UiStyle.NEGATIVE_COLOR
		end
		view.priceLabel.TextColor3 = color
	end
	local campLevelLabel = view.campLevelLabel
	if campLevelLabel then
		-- only a requirement the crew has not met is worth a line (decided 2026-09-15)
		campLevelLabel.Visible = isLocked
		campLevelLabel.Text = string.format(StoreRules.LOCKED_FORMAT, trap.REQUIRED_CAMP_LEVEL)
		campLevelLabel.TextColor3 = UiStyle.NEGATIVE_COLOR
	end
	if view.resourceIcon then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
		view.resourceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		view.resourceIcon.ImageColor3 = if isLocked then UiStyle.DISABLED_COLOR else Color3.new(1, 1, 1)
	end
	-- these prompt edits are local: the server still decides every buy
	local prompt = view.prompt
	if prompt then
		prompt.Enabled = not isLocked
		prompt.ActionText = PROMPT_ACTION_BUY
	end
	self:setDisplay(view)
end

function ClientDefenseStoreManager:renderAll()
	for _, view in self.stands do
		self:renderStand(view)
	end
end

function ClientDefenseStoreManager:step(deltaSec: number)
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

function ClientDefenseStoreManager:bindStand(store: Instance, kind: number)
	local stand = store:FindFirstChild(StoreRules.standNameFromKey(Enums.getName(Enums.TrapKind, kind) or "?"))
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
		kind = kind,
		base = base,
		itemSpawn = if itemSpawn and itemSpawn:IsA("BasePart") then itemSpawn else nil,
		nameLabel = if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil,
		priceBox = if priceBox and priceBox:IsA("GuiObject") then priceBox else nil,
		priceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil,
		resourceIcon = if resourceIcon and resourceIcon:IsA("ImageLabel") then resourceIcon else nil,
		campLevelLabel = if campLevelLabel and campLevelLabel:IsA("TextLabel") then campLevelLabel else nil,
		prompt = prompt,
		display = nil,
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

function ClientDefenseStoreManager:bindCamp(camp: Instance)
	for _, view in self.stands do
		if view.display then
			view.display:Destroy()
		end
	end
	self.stands = {}
	local store = camp:FindFirstChild(Constants.CAMP_DEFENSE_STORE_MODEL)
	if not store then
		warn("ClientDefenseStoreManager: the camp has no DefenseStore")
		return
	end
	for _, kind in Enums.getAllValues(Enums.TrapKind) do
		self:bindStand(store, kind)
	end
	if not self.heartbeat then
		self.heartbeat = RunService.Heartbeat:Connect(
			function(deltaSec: number)
				self:step(deltaSec)
			end
		)
	end
end

function ClientDefenseStoreManager:onPurchase(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_TRAP_PURCHASED_SHAPE) then
		warn("ClientDefenseStoreManager: malformed NotifyTrapPurchased")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
end

function ClientDefenseStoreManager:readCatalog()
	self.catalog = PlacementRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.DEFENSE_CATALOG))
	self:renderAll()
end

function ClientDefenseStoreManager:init()
	self:readCatalog()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.DEFENSE_CATALOG,
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
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.BALANCE_IRON_BARS,
		function()
			self:renderAll()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_TRAP_PURCHASED,
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

function ClientDefenseStoreManager.new(): ClientDefenseStoreManager
	local self = setmetatable({}, ClientDefenseStoreManager) :: ClientDefenseStoreManager
	self.catalog = nil
	self.stands = {}
	self.heartbeat = nil
	self.warnedTemplates = {}
	return self
end

return ClientDefenseStoreManager.new()
