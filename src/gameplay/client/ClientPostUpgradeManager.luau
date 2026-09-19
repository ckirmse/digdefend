--!strict

-- The post upgrade menu on this client (GDD "Upgrading a Post Weapon"),
-- M25. The owner's bench (Tags.POST_WORKBENCH) carries an Upgrade prompt
-- the server configures; this client enables it only for the post it owns
-- and, when it fires here, opens the PostUpgrade overlay: one row per
-- attribute with four pips (one filled per upgrade bought) and a button
-- showing the Gold price, greyed with a "Camp Level N required" line while
-- locked, gone when maxed. Everything is drawn from the catalogue in
-- GameMetadata, the upgrade counts on CurrentPlayer, the Gold balance, and
-- the Camp Level; a tap sends TryUpgradePost and the server decides.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientPostUpgradeManager = {}
ClientPostUpgradeManager.__index = ClientPostUpgradeManager

type Row = {
	attribute: number,
	frame: GuiObject,
	pips: { GuiObject },
	button: GuiButton?,
	priceLabel: TextLabel?,
	resourceIcon: ImageLabel?,
	lockLabel: TextLabel?,
}

export type ClientPostUpgradeManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		titleLabel: TextLabel?,
		rows: { Row },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		benchPromptsByModel: { [Model]: ProximityPrompt },
	},
	ClientPostUpgradeManager
))

local NOTIFY_POST_UPGRADED_SHAPE = {
	attribute = { type = "enum", name = "PostAttribute" },
	level = "positiveInteger",
	price = "nonnegativeInteger",
}

local TITLE_FORMAT = "Upgrade %s"
local MAXED_TEXT = "MAX"
local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientPostUpgradeManager:getOwnPostIndex(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_INDEX), PostRules.NO_POST)
end

function ClientPostUpgradeManager:getOwnUpgrades(): PostRules.Upgrades
	local upgrades: PostRules.Upgrades = {}
	for attribute, attributeName in PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE do
		upgrades[attribute] = readNumber(ClientDataManager:getCurrentPlayerAttribute(attributeName), 0)
	end
	return upgrades
end

function ClientPostUpgradeManager:renderRow(row: Row, catalog: PostRules.Catalog, upgrades: PostRules.Upgrades, gold: number, campLevel: number)
	local offer = PostRules.getUpgradeOffer(catalog, upgrades, row.attribute, campLevel)
	local level = PostRules.upgradeLevel(upgrades, row.attribute)
	for index, pip in row.pips do
		pip.BackgroundColor3 = if index <= level then UiStyle.ACCENT_COLOR else UiStyle.EMPTY_SLOT_COLOR
	end
	local isMaxed = offer.status == Enums.StoreOffer.MAXED
	local isLocked = offer.status == Enums.StoreOffer.LOCKED
	local price = offer.price or 0
	local button = row.button
	if button then
		-- a locked button still takes the tap, to say why it is locked
		button.Active = not isMaxed
		button.AutoButtonColor = button.Active
		button.BackgroundColor3 = if not isMaxed and not isLocked then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	end
	if row.priceLabel then
		if isMaxed then
			row.priceLabel.Text = MAXED_TEXT
			row.priceLabel.TextColor3 = UiStyle.TEXT_COLOR
		else
			row.priceLabel.Text = tostring(price)
			row.priceLabel.TextColor3 = if not isLocked and not PostRules.canAfford(gold, price) then UiStyle.NEGATIVE_COLOR else UiStyle.ACCENT_STROKE_COLOR
		end
	end
	if row.resourceIcon then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR]
		row.resourceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		row.resourceIcon.Visible = not isMaxed
	end
	if row.lockLabel then
		row.lockLabel.Visible = isLocked
		row.lockLabel.Text = UiStyle.formatTitle(string.format(PostRules.LOCKED_FORMAT, offer.requiredCampLevel or 0))
	end
end

function ClientPostUpgradeManager:renderMenu()
	local catalog = PostRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.POST_CATALOG))
	if not catalog then
		return
	end
	local kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0)
	if self.titleLabel then
		self.titleLabel.Text = UiStyle.formatTitle(string.format(TITLE_FORMAT, Enums.getPublicName(Enums.PostWeaponKind, kind) or "Post"))
	end
	local upgrades = self:getOwnUpgrades()
	local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
	local campLevel = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL), 1)
	for _, row in self.rows do
		self:renderRow(row, catalog, upgrades, gold, campLevel)
	end
end

function ClientPostUpgradeManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	if self.menuGui then
		self.menuGui.Enabled = false
	end
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientPostUpgradeManager:openMenu()
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen then
		return
	end
	self.isMenuOpen = true
	self:renderMenu()
	menuGui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

-- a buy that cannot go through is refused here with the Fail sound and
-- the reason (decided 2026-09-18); the server checks again regardless
function ClientPostUpgradeManager:requestUpgrade(attribute: number)
	local catalog = PostRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.POST_CATALOG))
	if catalog then
		local campLevel = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL), 1)
		local offer = PostRules.getUpgradeOffer(catalog, self:getOwnUpgrades(), attribute, campLevel)
		local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
		local refusal: string? = nil
		if offer.status == Enums.StoreOffer.LOCKED then
			refusal = string.format(PostRules.LOCKED_FORMAT, offer.requiredCampLevel or 0)
		elseif offer.status == Enums.StoreOffer.AVAILABLE and not PostRules.canAfford(gold, offer.price or 0) then
			refusal = FEEDBACK_NOT_ENOUGH_GOLD
		end
		if refusal then
			ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
			ClientPlayerFeedbackManager:giveLocal(refusal)
			return
		end
	end
	ClientNetManager:fireServer(NetEventNames.TRY_UPGRADE_POST, { attribute = attribute })
end

-- the bench's prompt is only for the post's owner; the server would refuse
-- anyone else's upgrade anyway, but the prompt should not even show
function ClientPostUpgradeManager:renderBenchPrompt(model: Model, prompt: ProximityPrompt)
	prompt.Enabled = readNumber(model:GetAttribute(Attributes.POST_MODEL_INDEX), 0) == self:getOwnPostIndex()
end

function ClientPostUpgradeManager:renderBenchPrompts()
	for model, prompt in self.benchPromptsByModel do
		self:renderBenchPrompt(model, prompt)
	end
end

function ClientPostUpgradeManager:bindBench(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local promptPart = model:WaitForChild(Constants.WORKBENCH_PROMPT_PART, 10)
	if not promptPart then
		return
	end
	local function bindPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			self.benchPromptsByModel[model] = prompt
			self:renderBenchPrompt(model, prompt)
		end
	end
	local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		bindPrompt(prompt)
	else
		promptPart.ChildAdded:Connect(bindPrompt)
	end
end

function ClientPostUpgradeManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild(Constants.POST_UPGRADE_GUI_NAME, 10)
	if not menuGui or not menuGui:IsA("ScreenGui") then
		warn("ClientPostUpgradeManager: no PostUpgrade ScreenGui; run scripts/studio/build_post_upgrade_menu_gui.luau")
		return
	end
	menuGui.Enabled = false
	self.menuGui = menuGui
	local dialog = menuGui:FindFirstChild(Constants.POST_UPGRADE_DIALOG)
	self.menuDialog = if dialog and dialog:IsA("GuiObject") then dialog else nil
	local title = if dialog then dialog:FindFirstChild(Constants.POST_UPGRADE_TITLE_LABEL) else nil
	self.titleLabel = if title and title:IsA("TextLabel") then title else nil
	local list = if dialog then dialog:FindFirstChild(Constants.POST_UPGRADE_LIST) else nil
	local template = if list then list:FindFirstChild(Constants.POST_UPGRADE_ROW_TEMPLATE) else nil
	if not template or not template:IsA("GuiObject") then
		warn("ClientPostUpgradeManager: the PostUpgrade menu has no List.RowTemplate")
		return
	end
	for order, attribute in Enums.getAllValues(Enums.PostAttribute) do
		local frame = template:Clone()
		frame.Name = Enums.getName(Enums.PostAttribute, attribute) or tostring(attribute)
		frame.LayoutOrder = order
		frame.Visible = true
		frame.Parent = list
		local nameLabel = frame:FindFirstChild(Constants.POST_UPGRADE_ROW_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.PostAttribute, attribute) or "?")
		end
		local pipsFrame = frame:FindFirstChild(Constants.POST_UPGRADE_ROW_PIPS)
		local pips: { GuiObject } = {}
		local pipIndex = 1
		while pipsFrame do
			local pip = pipsFrame:FindFirstChild(Constants.POST_UPGRADE_ROW_PIP_PREFIX .. pipIndex)
			if not pip or not pip:IsA("GuiObject") then
				break
			end
			table.insert(pips, pip)
			pipIndex += 1
		end
		local button = frame:FindFirstChild(Constants.POST_UPGRADE_ROW_BUTTON)
		local priceLabel = if button then button:FindFirstChild(Constants.POST_UPGRADE_ROW_PRICE_LABEL) else nil
		local resourceIcon = if button then button:FindFirstChild(Constants.POST_UPGRADE_ROW_RESOURCE_ICON) else nil
		local lockLabel = frame:FindFirstChild(Constants.POST_UPGRADE_ROW_LOCK_LABEL)
		local row: Row = {
			attribute = attribute,
			frame = frame,
			pips = pips,
			button = if button and button:IsA("GuiButton") then button else nil,
			priceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil,
			resourceIcon = if resourceIcon and resourceIcon:IsA("ImageLabel") then resourceIcon else nil,
			lockLabel = if lockLabel and lockLabel:IsA("TextLabel") then lockLabel else nil,
		}
		if row.button then
			row.button.Activated:Connect(
				function()
					if row.button and row.button.Active then
						self:requestUpgrade(attribute)
					end
				end
			)
		end
		table.insert(self.rows, row)
	end
	local closeButton = if dialog then dialog:FindFirstChild(Constants.POST_UPGRADE_CLOSE_BUTTON) else nil
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.Activated:Connect(
			function()
				self:closeMenu()
			end
		)
	end
	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return self.menuDialog
		end,
		notifyForceEnd = function(_overlay)
			self:closeMenu()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay
end

function ClientPostUpgradeManager:init()
	self:findMenu()
	for _, model in CollectionService:GetTagged(Tags.POST_WORKBENCH) do
		task.spawn(
			function()
				self:bindBench(model)
			end
		)
	end
	CollectionService:GetInstanceAddedSignal(Tags.POST_WORKBENCH):Connect(
		function(model: Instance)
			self:bindBench(model)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.POST_WORKBENCH):Connect(
		function(model: Instance)
			self.benchPromptsByModel[model :: Model] = nil
		end
	)
	-- the prompt fires here as well as on the server; only the bench's is ours
	ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, player: Player)
			if player ~= Players.LocalPlayer then
				return
			end
			for _, benchPrompt in self.benchPromptsByModel do
				if benchPrompt == prompt then
					self:openMenu()
					return
				end
			end
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.POST_INDEX,
		function()
			self:renderBenchPrompts()
		end
	)
	local watched = { Attributes.BALANCE_GOLD_BARS, Attributes.POST_WEAPON_KIND }
	for _, attributeName in PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE do
		table.insert(watched, attributeName)
	end
	for _, attributeName in watched do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attributeName,
			function()
				if self.isMenuOpen then
					self:renderMenu()
				end
			end
		)
	end
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.CAMP_LEVEL,
		function()
			if self.isMenuOpen then
				self:renderMenu()
			end
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_UPGRADED,
		function(payload: any)
			if not Validate.isTableShape(payload, NOTIFY_POST_UPGRADED_SHAPE) then
				warn("ClientPostUpgradeManager: malformed NotifyPostUpgraded")
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
		end
	)
end

function ClientPostUpgradeManager.new(): ClientPostUpgradeManager
	local self = setmetatable({}, ClientPostUpgradeManager) :: ClientPostUpgradeManager
	self.menuGui = nil
	self.menuDialog = nil
	self.titleLabel = nil
	self.rows = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.benchPromptsByModel = {}
	return self
end

return ClientPostUpgradeManager.new()
