--!strict

-- The Tower Menu on this client (GDD "Upgrading and Selling Towers"),
-- M26. A placed Tower's shadow carries an Upgrade/Sell prompt the server
-- creates; ClientPlacementManager shows it only to the owner, and when it
-- fires here this manager opens the TowerMenu overlay in the tower
-- defense layout: the Tower's picture, name, and level; the Target
-- Priority toggle with its arrows; the current stats; a red Sell button
-- with the sale value; the Upgrade button naming the next level and its
-- Iron price, with four pips filled one per upgrade bought; and the stats
-- the upgrade changes, current to next. Everything is drawn from the
-- catalogue in GameMetadata, the shadow's attributes, and the Iron
-- balance; every button sends a request and the server decides.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)

local ClientTowerMenuManager = {}
ClientTowerMenuManager.__index = ClientTowerMenuManager

type StatRow = {
	stat: number,
	frame: GuiObject,
	valueLabel: TextLabel?,
	nextLabel: TextLabel?,
	arrowLabel: TextLabel?,
}

export type ClientTowerMenuManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		portrait: ImageLabel?,
		nameLabel: TextLabel?,
		levelLabel: TextLabel?,
		priorityValueLabel: TextLabel?,
		statRows: { StatRow },
		upgradeStatRows: { StatRow },
		sellButton: GuiButton?,
		upgradeButton: GuiButton?,
		upgradeNameLabel: TextLabel?,
		upgradePriceLabel: TextLabel?,
		upgradePriceRow: GuiObject?,
		pips: { GuiObject },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		openShadow: BasePart?,
		shadowConnections: { RBXScriptConnection },
	},
	ClientTowerMenuManager
))

local NOTIFY_TOWER_UPGRADED_SHAPE = {
	id = "string",
	level = "positiveInteger",
	price = "nonnegativeInteger",
}

local LEVEL_FORMAT = "Level %d"
local SELL_FORMAT = "Sell %d"
local MAX_TEXT = "Max"
local FIRE_RATE_FORMAT = "%.1f/s"
local RANGE_FORMAT = "%d"
local HP_FORMAT = "%d / %d"
local ARROW_TEXT = ">"
local FEEDBACK_NOT_ENOUGH_IRON = "You don't have enough Iron Bars"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientTowerMenuManager:getCatalog(): PlacementRules.Catalog?
	return PlacementRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.DEFENSE_CATALOG))
end

function ClientTowerMenuManager:getIron(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS), 0)
end

-- one stat's text: shots per second, studs, damage, or hp of max
function ClientTowerMenuManager:statText(stat: number, stats: PlacementRules.TowerLevelStats, hp: number?): string
	if stat == Enums.TowerStat.FIRE_RATE then
		return string.format(FIRE_RATE_FORMAT, if stats.FIRE_INTERVAL_SEC > 0 then 1 / stats.FIRE_INTERVAL_SEC else 0)
	elseif stat == Enums.TowerStat.RANGE then
		return string.format(RANGE_FORMAT, stats.RANGE_STUDS)
	elseif stat == Enums.TowerStat.DAMAGE then
		return tostring(stats.DAMAGE)
	end
	if hp then
		return string.format(HP_FORMAT, math.ceil(hp), stats.MAX_HP)
	end
	return tostring(stats.MAX_HP)
end

function ClientTowerMenuManager:statChanges(stat: number, current: PlacementRules.TowerLevelStats, next: PlacementRules.TowerLevelStats): boolean
	if stat == Enums.TowerStat.FIRE_RATE then
		return current.FIRE_INTERVAL_SEC ~= next.FIRE_INTERVAL_SEC
	elseif stat == Enums.TowerStat.RANGE then
		return current.RANGE_STUDS ~= next.RANGE_STUDS
	elseif stat == Enums.TowerStat.DAMAGE then
		return current.DAMAGE ~= next.DAMAGE
	end
	return current.MAX_HP ~= next.MAX_HP
end

function ClientTowerMenuManager:renderMenu()
	local shadow = self.openShadow
	local catalog = self:getCatalog()
	if not shadow or not catalog then
		return
	end
	local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
	local level = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_LEVEL), 1)
	local hp = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_HP), 0)
	local priority = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TARGET_PRIORITY), Enums.TargetPriority.CLOSEST)
	local tower = catalog.towers[typeKind]
	if not tower then
		return
	end
	local stats = PlacementRules.towerStats(tower, level)
	local offer = PlacementRules.towerUpgradeOffer(tower, level)
	local iron = self:getIron()

	if self.portrait then
		local template = ClientPlacementManager:findTemplate(Enums.PlacementKind.TOWER, typeKind)
		local imageId = if template then template:GetAttribute(Attributes.ICON_IMAGE_ID) else nil
		self.portrait.Image = if typeof(imageId) == "string" then imageId else ""
	end
	if self.nameLabel then
		self.nameLabel.Text = UiStyle.formatTitle(PlacementRules.publicName(Enums.PlacementKind.TOWER, typeKind))
	end
	if self.levelLabel then
		self.levelLabel.Text = string.format(LEVEL_FORMAT, level)
	end
	if self.priorityValueLabel then
		self.priorityValueLabel.Text = Enums.getPublicName(Enums.TargetPriority, priority) or "?"
	end
	for _, row in self.statRows do
		if row.valueLabel then
			row.valueLabel.Text = self:statText(row.stat, stats, hp)
		end
	end
	local sellButton = self.sellButton
	if sellButton and sellButton:IsA("TextButton") then
		sellButton.Text = UiStyle.formatTitle(string.format(SELL_FORMAT, PlacementRules.sellValueFor(catalog, Enums.PlacementKind.TOWER, typeKind, level)))
	end
	for index, pip in self.pips do
		pip.BackgroundColor3 = if index <= level - 1 then UiStyle.ACCENT_COLOR else UiStyle.EMPTY_SLOT_COLOR
	end
	local upgradeButton = self.upgradeButton
	if upgradeButton then
		upgradeButton.Active = offer ~= nil
		upgradeButton.AutoButtonColor = offer ~= nil
		upgradeButton.BackgroundColor3 = if offer then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	end
	if self.upgradeNameLabel then
		self.upgradeNameLabel.Text = UiStyle.formatTitle(if offer then string.format(LEVEL_FORMAT, offer.level) else MAX_TEXT)
	end
	if self.upgradePriceRow then
		self.upgradePriceRow.Visible = offer ~= nil
	end
	if self.upgradePriceLabel and offer then
		self.upgradePriceLabel.Text = tostring(offer.price)
		self.upgradePriceLabel.TextColor3 = if PlacementRules.canAfford(iron, offer.price) then UiStyle.ACCENT_STROKE_COLOR else UiStyle.NEGATIVE_COLOR
	end
	local nextStats = if offer then PlacementRules.towerStats(tower, offer.level) else nil
	for _, row in self.upgradeStatRows do
		local isChanged = nextStats ~= nil and self:statChanges(row.stat, stats, nextStats)
		row.frame.Visible = isChanged
		if not isChanged or not nextStats then
			continue
		end
		if row.valueLabel then
			row.valueLabel.Text = self:statText(row.stat, stats, nil)
		end
		if row.nextLabel then
			row.nextLabel.Text = self:statText(row.stat, nextStats, nil)
		end
		if row.arrowLabel then
			row.arrowLabel.Text = ARROW_TEXT
		end
	end
end

function ClientTowerMenuManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	for _, connection in self.shadowConnections do
		connection:Disconnect()
	end
	self.shadowConnections = {}
	self.openShadow = nil
	if self.menuGui then
		self.menuGui.Enabled = false
	end
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientTowerMenuManager:openMenu(shadow: BasePart)
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen then
		return
	end
	self.isMenuOpen = true
	self.openShadow = shadow
	for _, attribute in { Attributes.PLACEMENT_LEVEL, Attributes.PLACEMENT_HP, Attributes.PLACEMENT_MAX_HP, Attributes.PLACEMENT_TARGET_PRIORITY } do
		table.insert(
			self.shadowConnections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:renderMenu()
				end
			)
		)
	end
	-- a Tower destroyed or sold while its menu is open takes the menu with it
	table.insert(
		self.shadowConnections,
		shadow.AncestryChanged:Connect(
			function(_child: Instance, parent: Instance?)
				if parent == nil then
					self:closeMenu()
				end
			end
		)
	)
	self:renderMenu()
	menuGui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientTowerMenuManager:getOpenId(): string?
	local shadow = self.openShadow
	local id = if shadow then shadow:GetAttribute(Attributes.PLACEMENT_ID) else nil
	return if typeof(id) == "string" then id else nil
end

function ClientTowerMenuManager:requestSell()
	local id = self:getOpenId()
	if not id then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SELL_PLACEMENT, { id = id })
	self:closeMenu()
end

-- a buy that cannot go through is refused here with the Fail sound and
-- the reason; the server checks again regardless
function ClientTowerMenuManager:requestUpgrade()
	local id = self:getOpenId()
	local shadow = self.openShadow
	local catalog = self:getCatalog()
	if not id or not shadow or not catalog then
		return
	end
	local tower = catalog.towers[readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)]
	local offer = if tower then PlacementRules.towerUpgradeOffer(tower, readNumber(shadow:GetAttribute(Attributes.PLACEMENT_LEVEL), 1)) else nil
	if not offer then
		return
	end
	if not PlacementRules.canAfford(self:getIron(), offer.price) then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_UPGRADE_TOWER, { id = id })
end

function ClientTowerMenuManager:requestPriority(direction: number)
	local id = self:getOpenId()
	local shadow = self.openShadow
	if not id or not shadow then
		return
	end
	local current = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TARGET_PRIORITY), Enums.TargetPriority.CLOSEST)
	ClientNetManager:fireServer(NetEventNames.TRY_SET_TOWER_TARGET_PRIORITY, {
		id = id,
		priority = PlacementRules.cycleTargetPriority(current, direction),
	})
end

function ClientTowerMenuManager:bindStatRows(frame: Instance?): { StatRow }
	local rows: { StatRow } = {}
	local template = if frame then frame:FindFirstChild(Constants.TOWER_MENU_STAT_ROW_TEMPLATE) else nil
	if not frame or not template or not template:IsA("GuiObject") then
		return rows
	end
	template.Visible = false
	for order, stat in Enums.getAllValues(Enums.TowerStat) do
		local row = template:Clone()
		row.Name = Enums.getName(Enums.TowerStat, stat) or tostring(stat)
		row.LayoutOrder = order
		row.Visible = true
		row.Parent = frame
		local nameLabel = row:FindFirstChild(Constants.TOWER_MENU_STAT_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = Enums.getPublicName(Enums.TowerStat, stat) or "?"
		end
		local valueLabel = row:FindFirstChild(Constants.TOWER_MENU_STAT_VALUE_LABEL)
		local nextLabel = row:FindFirstChild(Constants.TOWER_MENU_STAT_NEXT_LABEL)
		local arrowLabel = row:FindFirstChild(Constants.TOWER_MENU_STAT_ARROW_LABEL)
		table.insert(rows, {
			stat = stat,
			frame = row,
			valueLabel = if valueLabel and valueLabel:IsA("TextLabel") then valueLabel else nil,
			nextLabel = if nextLabel and nextLabel:IsA("TextLabel") then nextLabel else nil,
			arrowLabel = if arrowLabel and arrowLabel:IsA("TextLabel") then arrowLabel else nil,
		})
	end
	return rows
end

function ClientTowerMenuManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild(Constants.TOWER_MENU_GUI_NAME, 10)
	if not menuGui or not menuGui:IsA("ScreenGui") then
		warn("ClientTowerMenuManager: no TowerMenu ScreenGui; run scripts/studio/build_tower_menu_gui.luau")
		return
	end
	menuGui.Enabled = false
	self.menuGui = menuGui
	local dialog = menuGui:FindFirstChild(Constants.TOWER_MENU_DIALOG)
	if not dialog or not dialog:IsA("GuiObject") then
		warn("ClientTowerMenuManager: the TowerMenu has no Dialog")
		return
	end
	self.menuDialog = dialog
	local portrait = dialog:FindFirstChild(Constants.TOWER_MENU_PORTRAIT)
	self.portrait = if portrait and portrait:IsA("ImageLabel") then portrait else nil
	local nameLabel = dialog:FindFirstChild(Constants.TOWER_MENU_NAME_LABEL)
	self.nameLabel = if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil
	local levelLabel = dialog:FindFirstChild(Constants.TOWER_MENU_LEVEL_LABEL)
	self.levelLabel = if levelLabel and levelLabel:IsA("TextLabel") then levelLabel else nil
	local priority = dialog:FindFirstChild(Constants.TOWER_MENU_PRIORITY_FRAME)
	local priorityValue = if priority then priority:FindFirstChild(Constants.TOWER_MENU_PRIORITY_VALUE_LABEL) else nil
	self.priorityValueLabel = if priorityValue and priorityValue:IsA("TextLabel") then priorityValue else nil
	local previousButton = if priority then priority:FindFirstChild(Constants.CAROUSEL_PREVIOUS_BUTTON) else nil
	if previousButton and previousButton:IsA("GuiButton") then
		previousButton.Activated:Connect(
			function()
				self:requestPriority(-1)
			end
		)
	end
	local nextButton = if priority then priority:FindFirstChild(Constants.CAROUSEL_NEXT_BUTTON) else nil
	if nextButton and nextButton:IsA("GuiButton") then
		nextButton.Activated:Connect(
			function()
				self:requestPriority(1)
			end
		)
	end
	self.statRows = self:bindStatRows(dialog:FindFirstChild(Constants.TOWER_MENU_STATS_FRAME))
	self.upgradeStatRows = self:bindStatRows(dialog:FindFirstChild(Constants.TOWER_MENU_UPGRADE_STATS_FRAME))
	local sellButton = dialog:FindFirstChild(Constants.TOWER_MENU_SELL_BUTTON)
	if sellButton and sellButton:IsA("GuiButton") then
		self.sellButton = sellButton
		sellButton.Activated:Connect(
			function()
				self:requestSell()
			end
		)
	end
	local upgradeButton = dialog:FindFirstChild(Constants.TOWER_MENU_UPGRADE_BUTTON)
	if upgradeButton and upgradeButton:IsA("GuiButton") then
		self.upgradeButton = upgradeButton
		local upgradeName = upgradeButton:FindFirstChild(Constants.TOWER_MENU_UPGRADE_NAME_LABEL)
		self.upgradeNameLabel = if upgradeName and upgradeName:IsA("TextLabel") then upgradeName else nil
		local priceRow = upgradeButton:FindFirstChild(Constants.TOWER_MENU_UPGRADE_PRICE_ROW)
		self.upgradePriceRow = if priceRow and priceRow:IsA("GuiObject") then priceRow else nil
		local priceLabel = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_LABEL) else nil
		self.upgradePriceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil
		local priceIcon = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ICON) else nil
		if priceIcon and priceIcon:IsA("ImageLabel") then
			local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
			priceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		end
		upgradeButton.Activated:Connect(
			function()
				if upgradeButton.Active then
					self:requestUpgrade()
				end
			end
		)
	end
	local pipsFrame = dialog:FindFirstChild(Constants.TOWER_MENU_PIPS)
	local pipIndex = 1
	while pipsFrame do
		local pip = pipsFrame:FindFirstChild(Constants.TOWER_MENU_PIP_PREFIX .. pipIndex)
		if not pip or not pip:IsA("GuiObject") then
			break
		end
		table.insert(self.pips, pip)
		pipIndex += 1
	end
	local closeButton = dialog:FindFirstChild(Constants.TOWER_MENU_CLOSE_BUTTON)
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

function ClientTowerMenuManager:init()
	self:findMenu()
	-- the prompt fires here as well as on the server; only a Tower of ours opens the menu
	ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, player: Player)
			if player ~= Players.LocalPlayer then
				return
			end
			local shadow = prompt.Parent
			if not shadow or not shadow:IsA("BasePart") or shadow:GetAttribute(Attributes.PLACEMENT_KIND) ~= Enums.PlacementKind.TOWER then
				return
			end
			if readNumber(shadow:GetAttribute(Attributes.PLACEMENT_OWNER_USER_ID), PlacementRules.NOBODY) ~= Players.LocalPlayer.UserId then
				return
			end
			self:openMenu(shadow)
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.BALANCE_IRON_BARS,
		function()
			if self.isMenuOpen then
				self:renderMenu()
			end
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_TOWER_UPGRADED,
		function(payload: any)
			if not Validate.isTableShape(payload, NOTIFY_TOWER_UPGRADED_SHAPE) then
				warn("ClientTowerMenuManager: malformed NotifyTowerUpgraded")
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
		end
	)
end

function ClientTowerMenuManager.new(): ClientTowerMenuManager
	local self = setmetatable({}, ClientTowerMenuManager) :: ClientTowerMenuManager
	self.menuGui = nil
	self.menuDialog = nil
	self.portrait = nil
	self.nameLabel = nil
	self.levelLabel = nil
	self.priorityValueLabel = nil
	self.statRows = {}
	self.upgradeStatRows = {}
	self.sellButton = nil
	self.upgradeButton = nil
	self.upgradeNameLabel = nil
	self.upgradePriceLabel = nil
	self.upgradePriceRow = nil
	self.pips = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.openShadow = nil
	self.shadowConnections = {}
	return self
end

return ClientTowerMenuManager.new()
