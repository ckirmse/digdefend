--!strict

-- The post upgrade menu on this client (GDD "Upgrading a Post Weapon"),
-- M25, opened at the Post Upgrade Table in the defense building (decided
-- 2026-10-01). The table's prompt (Tags.POST_UPGRADE_PROMPT) is the
-- server's; when it fires here, this opens the PostUpgrade overlay (for
-- the owned post's weapon, or the loadout weapon before a claim, since
-- upgrades are the player's and carry onto the post, 2026-10-06). The menu is
-- one row per attribute with four pips (one filled per upgrade bought) and
-- a button showing the Gold price, gone when maxed. Everything is drawn
-- from the catalogue in GameMetadata, the upgrade counts on CurrentPlayer,
-- and the Gold balance; a tap sends TryUpgradePost and the server decides.
-- The table also carries a display: the designer's DisplayPost model sets
-- the spot and size, and this client redraws it locally as the current
-- fortification tier's post with its own loadout post weapon standing on
-- it, no sign, no prompts, display only. Each player sees their own.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
}

export type ClientPostUpgradeManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		titleLabel: TextLabel?,
		rows: { Row },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		-- the display on the table: where the designer's post stood, how
		-- much smaller than a real post it was, and what stands there now
		displayParent: Instance?,
		displayPivot: CFrame?,
		displayScale: number,
		displayPost: Model?,
		displayWeapon: Model?,
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
local WAIT_FOR_CAMP_SEC = 30
local DISPLAY_POST_NAME = "DisplayPost"
local DISPLAY_WEAPON_NAME = "DisplayWeapon"

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

function ClientPostUpgradeManager:renderRow(row: Row, catalog: PostRules.Catalog, upgrades: PostRules.Upgrades, gold: number)
	local offer = PostRules.getUpgradeOffer(catalog, upgrades, row.attribute)
	local level = PostRules.upgradeLevel(upgrades, row.attribute)
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
			row.priceLabel.TextColor3 = if not PostRules.canAfford(gold, price) then UiStyle.NEGATIVE_COLOR else UiStyle.ACCENT_STROKE_COLOR
		end
	end
	if row.resourceIcon then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR]
		row.resourceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		row.resourceIcon.Visible = not isMaxed
	end
end

function ClientPostUpgradeManager:renderMenu()
	local catalog = PostRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.POST_CATALOG))
	if not catalog then
		return
	end
	local kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0)
	if kind == 0 then
		kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_LOADOUT_WEAPON_KIND), 0)
	end
	if self.titleLabel then
		self.titleLabel.Text = UiStyle.formatTitle(string.format(TITLE_FORMAT, Enums.getPublicName(Enums.PostWeaponKind, kind) or "Post"))
	end
	local upgrades = self:getOwnUpgrades()
	local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
	-- a row per attribute exists; the weapon kind picks which four show
	-- and in what order (the Machine Gun has Cooldown, the Rocket
	-- Launcher has Range)
	for _, row in self.rows do
		local order = PostRules.attributeOrder(catalog, kind, row.attribute)
		row.frame.Visible = order ~= nil
		row.frame.LayoutOrder = order or 0
		if order ~= nil then
			self:renderRow(row, catalog, upgrades, gold)
		end
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

-- the table's prompt opens the menu for anyone
function ClientPostUpgradeManager:onTablePrompt()
	self:openMenu()
end

-- a buy that cannot go through is refused here with the Fail sound and
-- the reason (decided 2026-09-18); the server checks again regardless
function ClientPostUpgradeManager:requestUpgrade(attribute: number)
	local catalog = PostRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.POST_CATALOG))
	if catalog then
		local offer = PostRules.getUpgradeOffer(catalog, self:getOwnUpgrades(), attribute)
		local gold = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS), 0)
		local refusal: string? = nil
		if offer.status == Enums.StoreOffer.AVAILABLE and not PostRules.canAfford(gold, offer.price or 0) then
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

function ClientPostUpgradeManager:findTemplate(folderName: string, templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(folderName) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	return if template and template:IsA("Model") then template else nil
end

-- the display as of now: the tier's post, shrunk to the designer's size
-- and stood where their post stood, stripped of its sign, with the
-- loadout post weapon on its Spawn the way a claimed post carries one
function ClientPostUpgradeManager:renderDisplay()
	local parent = self.displayParent
	local pivot = self.displayPivot
	if not parent or not pivot then
		return
	end
	if self.displayPost then
		self.displayPost:Destroy()
		self.displayPost = nil
	end
	if self.displayWeapon then
		self.displayWeapon:Destroy()
		self.displayWeapon = nil
	end
	local tier = math.max(1, readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_TIER), 1))
	local postTemplate = self:findTemplate(Constants.STRUCTURE_TEMPLATES_FOLDER, `{Constants.POST_TEMPLATE_PREFIX}_{tier}`)
	if not postTemplate then
		return
	end
	local post = postTemplate:Clone()
	post.Name = DISPLAY_POST_NAME
	local sign = post:FindFirstChild(Constants.POST_SIGN_MODEL)
	if sign then
		sign:Destroy()
	end
	-- ScaleTo is absolute, and a template may already carry a scale of its own
	post:ScaleTo(post:GetScale() * self.displayScale)
	post:PivotTo(pivot)
	post.Parent = parent
	self.displayPost = post

	local kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_LOADOUT_WEAPON_KIND), 0)
	local weaponTemplate = self:findTemplate(Constants.POST_WEAPON_TEMPLATES_FOLDER, Enums.getName(Enums.PostWeaponKind, kind) or "")
	local spawn = post:FindFirstChild(Constants.POST_SPAWN_PART)
	if not weaponTemplate or not spawn or not spawn:IsA("BasePart") then
		return
	end
	local weapon = weaponTemplate:Clone()
	weapon.Name = DISPLAY_WEAPON_NAME
	-- the template carries the authored Use prompt (on its Prompt part since
	-- 2026-10-09); a display model is only to look at
	for _, descendant in weapon:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end
	weapon:ScaleTo(weapon:GetScale() * self.displayScale)
	weapon:PivotTo(spawn.CFrame)
	spawn.Transparency = 1
	weapon.Parent = parent
	self.displayWeapon = weapon
end

-- reads the designer's DisplayPost on the table (its pivot, and its height
-- against a real post's) then takes it over: from here the display is
-- redrawn locally whenever the tier or this player's loadout changes
function ClientPostUpgradeManager:attachDisplay()
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, WAIT_FOR_CAMP_SEC)
	local store = if camp then camp:WaitForChild(Constants.CAMP_DEFENSE_STORE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	local tables = if store then store:WaitForChild(Constants.DEFENSE_TABLES_FOLDER, WAIT_FOR_CAMP_SEC) else nil
	local tableModel = if tables then tables:WaitForChild(Constants.POST_UPGRADE_TABLE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	local authored = if tableModel then tableModel:WaitForChild(Constants.POST_UPGRADE_TABLE_DISPLAY_POST, WAIT_FOR_CAMP_SEC) else nil
	if not tableModel or not authored or not authored:IsA("Model") then
		warn(`ClientPostUpgradeManager: no {Constants.POST_UPGRADE_TABLE_MODEL}.{Constants.POST_UPGRADE_TABLE_DISPLAY_POST} model in the camp's {Constants.CAMP_DEFENSE_STORE_MODEL}; no display`)
		return
	end
	local fullSize = self:findTemplate(Constants.STRUCTURE_TEMPLATES_FOLDER, `{Constants.POST_TEMPLATE_PREFIX}_1`)
	if not fullSize then
		warn("ClientPostUpgradeManager: no POST_1 template to size the display post against")
		return
	end
	local _authoredCFrame, authoredSize = authored:GetBoundingBox()
	local _fullCFrame, fullSizeBounds = fullSize:GetBoundingBox()
	self.displayParent = tableModel
	self.displayPivot = authored:GetPivot()
	self.displayScale = if fullSizeBounds.Y > 0 then authoredSize.Y / fullSizeBounds.Y else 1
	-- the authored copy was the reference; the live display replaces it here only
	authored:Destroy()
	self:renderDisplay()
	-- a new run brings a new camp and a new table; follow it
	tableModel.AncestryChanged:Connect(
		function()
			if not tableModel:IsDescendantOf(workspace) then
				self.displayParent = nil
				self.displayPivot = nil
				self.displayPost = nil
				self.displayWeapon = nil
				task.spawn(
					function()
						self:attachDisplay()
					end
				)
			end
		end
	)
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
	local dialog = menuGui:FindFirstChild(Constants.UPGRADE_MENU_DIALOG)
	self.menuDialog = if dialog and dialog:IsA("GuiObject") then dialog else nil
	local title = if dialog then dialog:FindFirstChild(Constants.UPGRADE_MENU_TITLE_LABEL) else nil
	self.titleLabel = if title and title:IsA("TextLabel") then title else nil
	local list = if dialog then dialog:FindFirstChild(Constants.UPGRADE_MENU_LIST) else nil
	local template = if list then list:FindFirstChild(Constants.UPGRADE_MENU_ROW_TEMPLATE) else nil
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
		local nameLabel = frame:FindFirstChild(Constants.UPGRADE_MENU_ROW_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.PostAttribute, attribute) or "?")
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
		local row: Row = {
			attribute = attribute,
			frame = frame,
			pips = pips,
			button = if button and button:IsA("GuiButton") then button else nil,
			priceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil,
			resourceIcon = if resourceIcon and resourceIcon:IsA("ImageLabel") then resourceIcon else nil,
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

function ClientPostUpgradeManager:init()
	self:findMenu()
	-- the camp can take a while to stream in; nothing else waits on the display
	task.spawn(
		function()
			self:attachDisplay()
		end
	)
	-- the prompt fires here as well as on the server; only the table's is ours
	ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, player: Player)
			if player == Players.LocalPlayer and CollectionService:HasTag(prompt, Tags.POST_UPGRADE_PROMPT) then
				self:onTablePrompt()
			end
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
		Attributes.FORTIFICATION_TIER,
		function()
			self:renderDisplay()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.POST_LOADOUT_WEAPON_KIND,
		function()
			self:renderDisplay()
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
	self.displayParent = nil
	self.displayPivot = nil
	self.displayScale = 1
	self.displayPost = nil
	self.displayWeapon = nil
	return self
end

return ClientPostUpgradeManager.new()
