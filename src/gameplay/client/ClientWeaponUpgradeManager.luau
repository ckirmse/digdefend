--!strict

-- The weapon upgrade menu on this client (GDD "Weapon Upgrades"), opened
-- at the Weapons Table in the defense building (decided 2026-10-01). The
-- table's prompt (Tags.WEAPON_UPGRADE_PROMPT) is the server's; when it
-- fires here, this opens the WeaponUpgrade overlay: one row per attribute
-- (Damage, Ammo, Range) with four pips, one filled per upgrade bought, and
-- a button showing the Gold price, gone when maxed. Weapon upgrades are
-- never locked by Camp Level. Everything is drawn from the catalogue in
-- GameMetadata, the upgrade counts on CurrentPlayer, and the Gold
-- balance; a tap sends TryUpgradeWeapon and the server decides. The menu
-- is the same build as the post one, so the two read alike.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientWeaponUpgradeManager = {}
ClientWeaponUpgradeManager.__index = ClientWeaponUpgradeManager

type Row = {
	attribute: number,
	frame: GuiObject,
	pips: { GuiObject },
	button: GuiButton?,
	priceLabel: TextLabel?,
	resourceIcon: ImageLabel?,
	lockLabel: TextLabel?,
}

export type ClientWeaponUpgradeManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		titleLabel: TextLabel?,
		rows: { Row },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
	},
	ClientWeaponUpgradeManager
))

local NOTIFY_WEAPON_UPGRADED_SHAPE = {
	attribute = { type = "enum", name = "WeaponAttribute" },
	level = "positiveInteger",
	price = "nonnegativeInteger",
}

local TITLE_FORMAT = "Upgrade %s"
local MAXED_TEXT = "MAX"
local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientWeaponUpgradeManager:getOwnUpgrades(): WeaponRules.Upgrades
	local upgrades: WeaponRules.Upgrades = {}
	for attribute, attributeName in WeaponRules.UPGRADE_ATTRIBUTE_BY_WEAPON_ATTRIBUTE do
		upgrades[attribute] = readNumber(ClientDataManager:getCurrentPlayerAttribute(attributeName), 0)
	end
	return upgrades
end

function ClientWeaponUpgradeManager:renderRow(row: Row, catalog: WeaponRules.Catalog, upgrades: WeaponRules.Upgrades, gold: number)
	local offer = WeaponRules.getUpgradeOffer(catalog, upgrades, row.attribute)
	local level = WeaponRules.upgradeLevel(upgrades, row.attribute)
	for index, pip in row.pips do
		pip.BackgroundColor3 = if index <= level then UiStyle.ACCENT_COLOR else UiStyle.EMPTY_SLOT_COLOR
	end
	local isMaxed = offer.status == Enums.StoreOffer.MAXED
	local price = offer.price or 0
	local button = row.button
	if button then
		button.Active = not isMaxed
		button.AutoButtonColor = button.Active
		button.BackgroundColor3 = if not isMaxed then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	end
	if row.priceLabel then
		if isMaxed then
			row.priceLabel.Text = MAXED_TEXT
			row.priceLabel.TextColor3 = UiStyle.TEXT_COLOR
		else
			row.priceLabel.Text = tostring(price)
			row.priceLabel.TextColor3 = if not WeaponRules.canAfford(gold, price) then UiStyle.NEGATIVE_COLOR else UiStyle.ACCENT_STROKE_COLOR
		end
	end
	if row.resourceIcon then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR]
		row.resourceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		row.resourceIcon.Visible = not isMaxed
	end
	-- the shared menu build has a lock line; weapons never lock
	if row.lockLabel then
		row.lockLabel.Visible = false
	end
end

function ClientWeaponUpgradeManager:renderMenu()
	local catalog = WeaponRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.WEAPON_CATALOG))
	if not catalog then
		return
	end
	local kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND), 0)
	if self.titleLabel then
		self.titleLabel.Text = UiStyle.formatTitle(string.format(TITLE_FORMAT, Enums.getPublicName(Enums.WeaponKind, kind) or "Weapon"))
	end
	local upgrades = self:getOwnUpgrades()
	local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
	for _, row in self.rows do
		self:renderRow(row, catalog, upgrades, gold)
	end
end

function ClientWeaponUpgradeManager:closeMenu()
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

function ClientWeaponUpgradeManager:openMenu()
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
function ClientWeaponUpgradeManager:requestUpgrade(attribute: number)
	local catalog = WeaponRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.WEAPON_CATALOG))
	if catalog then
		local offer = WeaponRules.getUpgradeOffer(catalog, self:getOwnUpgrades(), attribute)
		local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
		if offer.status == Enums.StoreOffer.AVAILABLE and not WeaponRules.canAfford(gold, offer.price or 0) then
			ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
			ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOT_ENOUGH_GOLD)
			return
		end
	end
	ClientNetManager:fireServer(NetEventNames.TRY_UPGRADE_WEAPON, { attribute = attribute })
end

function ClientWeaponUpgradeManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild(Constants.WEAPON_UPGRADE_GUI_NAME, 10)
	if not menuGui or not menuGui:IsA("ScreenGui") then
		warn("ClientWeaponUpgradeManager: no WeaponUpgrade ScreenGui; run scripts/studio/build_weapon_upgrade_menu_gui.luau")
		return
	end
	menuGui.Enabled = false
	self.menuGui = menuGui
	local dialog = menuGui:FindFirstChild(Constants.UPGRADE_MENU_DIALOG)
	self.menuDialog = if dialog and dialog:IsA("GuiObject") then dialog else nil
	local title = if dialog then dialog:FindFirstChild(Constants.UPGRADE_MENU_TITLE_LABEL) else nil
	self.titleLabel = if title and title:IsA("TextLabel") then title else nil
	local list = if dialog then dialog:FindFirstChild(Constants.UPGRADE_MENU_LIST) else nil
	local template = if list then list:FindFirstChild(Constants.UPGRADE_MENU_ROW_TEMPLATE) else nil
	if not template or not template:IsA("GuiObject") then
		warn("ClientWeaponUpgradeManager: the WeaponUpgrade menu has no List.RowTemplate")
		return
	end
	for order, attribute in Enums.getAllValues(Enums.WeaponAttribute) do
		local frame = template:Clone()
		frame.Name = Enums.getName(Enums.WeaponAttribute, attribute) or tostring(attribute)
		frame.LayoutOrder = order
		frame.Visible = true
		frame.Parent = list
		local nameLabel = frame:FindFirstChild(Constants.UPGRADE_MENU_ROW_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.WeaponAttribute, attribute) or "?")
		end
		local pipsFrame = frame:FindFirstChild(Constants.UPGRADE_MENU_ROW_PIPS)
		local pips: { GuiObject } = {}
		local pipIndex = 1
		while pipsFrame do
			local pip = pipsFrame:FindFirstChild(Constants.UPGRADE_MENU_ROW_PIP_PREFIX .. pipIndex)
			if not pip or not pip:IsA("GuiObject") then
				break
			end
			table.insert(pips, pip)
			pipIndex += 1
		end
		local button = frame:FindFirstChild(Constants.UPGRADE_MENU_ROW_BUTTON)
		local priceLabel = if button then button:FindFirstChild(Constants.UPGRADE_MENU_ROW_PRICE_LABEL) else nil
		local resourceIcon = if button then button:FindFirstChild(Constants.UPGRADE_MENU_ROW_RESOURCE_ICON) else nil
		local lockLabel = frame:FindFirstChild(Constants.UPGRADE_MENU_ROW_LOCK_LABEL)
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
	local closeButton = if dialog then dialog:FindFirstChild(Constants.UPGRADE_MENU_CLOSE_BUTTON) else nil
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

function ClientWeaponUpgradeManager:init()
	self:findMenu()
	-- the prompt fires here as well as on the server; only the table's is ours
	ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, player: Player)
			if player == Players.LocalPlayer and CollectionService:HasTag(prompt, Tags.WEAPON_UPGRADE_PROMPT) then
				self:openMenu()
			end
		end
	)
	local watched = { Attributes.BALANCE_GOLD_BARS, Attributes.WEAPON_KIND }
	for _, attributeName in WeaponRules.UPGRADE_ATTRIBUTE_BY_WEAPON_ATTRIBUTE do
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
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_WEAPON_UPGRADED,
		function(payload: any)
			if not Validate.isTableShape(payload, NOTIFY_WEAPON_UPGRADED_SHAPE) then
				warn("ClientWeaponUpgradeManager: malformed NotifyWeaponUpgraded")
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
		end
	)
end

function ClientWeaponUpgradeManager.new(): ClientWeaponUpgradeManager
	local self = setmetatable({}, ClientWeaponUpgradeManager) :: ClientWeaponUpgradeManager
	self.menuGui = nil
	self.menuDialog = nil
	self.titleLabel = nil
	self.rows = {}
	self.overlay = nil
	self.isMenuOpen = false
	return self
end

return ClientWeaponUpgradeManager.new()
