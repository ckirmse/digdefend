--!strict

-- The Badges menu (GDD "Earning Diamonds", M69). Everything it draws is
-- already on the client: every badge (stars, description, picture,
-- reward) is the BadgeCatalogue GameMetadata JSON, and the player's own
-- record is two CurrentPlayer attributes, the badges earned and the ones
-- whose reward has been claimed. Pure BadgeRules turns the two into each
-- badge's state: LOCKED (not earned), CLAIMABLE (earned, the Diamonds
-- waiting), or CLAIMED.
--
-- On the left, one clone of the gui's BadgeTemplate per badge: a locked
-- one half transparent, a claimable one under its CLAIM! banner, a
-- claimed one with the check in its corner. A tap selects a badge and
-- the info panel on the right shows it: name, picture, stars,
-- description, and in one spot either the Claim button (claimable) or
-- the reward line ("REWARD: 10 [diamond]" while locked, COMPLETED once
-- claimed). The button sends TryClaimBadgeReward; the server pays once
-- and NotifyBadgeRewardClaimed brings back the amount for the sound and
-- the feedback line.
--
-- The HUD's Badges button (the left stack) opens the menu and wears its
-- red mark while any reward waits. The toast for a badge just earned is
-- the common ClientBadgeManager's.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BadgeRules = require("@game/ReplicatedStorage/Shared/BadgeRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientBadgeMenuManager = {}
ClientBadgeMenuManager.__index = ClientBadgeMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	list: GuiObject,
	tileTemplate: GuiButton,
	infoTitle: TextLabel,
	infoIcon: ImageLabel,
	infoStars: GuiObject,
	infoDescription: TextLabel,
	claimButton: GuiButton,
	claimAmountLabel: TextLabel,
	rewardText: GuiObject,
	rewardLabel: TextLabel,
	rewardIcon: GuiObject,
}

type Tile = {
	badge: BadgeRules.PublishedBadge,
	button: GuiButton,
	icon: ImageLabel?,
	stars: GuiObject?,
	claimBanner: GuiObject?,
	check: GuiObject?,
	selected: UIStroke?,
}

export type ClientBadgeMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		tiles: { Tile },
		tileConnections: { RBXScriptConnection },
		selectedKind: number?,
		-- the badge whose claim is on its way to the server
		pendingKind: number?,
		hudAlert: GuiObject?,
	},
	ClientBadgeMenuManager
))

-- a badge not yet earned: its picture and stars this see-through
local LOCKED_TRANSPARENCY = 0.5
-- between the reward line's words and its Diamond, as a share of the
-- line's height
local REWARD_ICON_GAP_SHARE = 0.15
local FEEDBACK_SEC = 4

local REWARD_FORMAT = "Reward: %s"
local COMPLETED_TEXT = "Completed"
local FEEDBACK_FORMAT = "Badge reward: +%s"
local TILE_NAME_FORMAT = "Badge%d"

function ClientBadgeMenuManager:getCatalogue(): { BadgeRules.PublishedBadge }
	return BadgeRules.decodeCatalogue(ClientDataManager:getGameMetadata(Attributes.BADGE_CATALOGUE)) or {}
end

function ClientBadgeMenuManager:getBadgeState(badgeKind: number): BadgeRules.BadgeState
	return BadgeRules.getState(ClientDataManager:getBadges()[badgeKind] == true, ClientDataManager:getClaimedBadges()[badgeKind] == true)
end

-- Star1 to Star5 of a Stars row: gold up to the rating, dark after it
function ClientBadgeMenuManager:renderStars(stars: GuiObject?, rating: number, transparency: number)
	if not stars then
		return
	end
	for index = 1, BadgeRules.MAX_STARS do
		local star = stars:FindFirstChild(string.format(Constants.BADGES_STAR_FORMAT, index))
		if star and star:IsA("TextLabel") then
			star.TextColor3 = if index <= rating then UiStyle.CLASS_CARD_STAR_GOLD_COLOR else UiStyle.CLASS_MENU_STAR_DARK_COLOR
			star.TextTransparency = transparency
		end
	end
end

function ClientBadgeMenuManager:renderTile(tile: Tile)
	local state = self:getBadgeState(tile.badge.kind)
	local transparency = if state == "LOCKED" then LOCKED_TRANSPARENCY else 0
	local icon = tile.icon
	if icon then
		icon.Image = tile.badge.icon
		icon.ImageTransparency = transparency
	end
	self:renderStars(tile.stars, tile.badge.stars, transparency)
	if tile.claimBanner then
		tile.claimBanner.Visible = state == "CLAIMABLE"
	end
	if tile.check then
		tile.check.Visible = state == "CLAIMED"
	end
	if tile.selected then
		tile.selected.Enabled = tile.badge.kind == self.selectedKind
	end
end

-- the reward line's Diamond sits right after its words, wherever the
-- scaled text ends
function ClientBadgeMenuManager:seatRewardIcon(view: View)
	local gapPx = view.rewardLabel.AbsoluteSize.Y * REWARD_ICON_GAP_SHARE
	view.rewardIcon.Position = UDim2.new(0.5, view.rewardLabel.TextBounds.X / 2 + gapPx, 0.5, 0)
end

function ClientBadgeMenuManager:renderInfo(view: View)
	local selected: BadgeRules.PublishedBadge? = nil
	for _, tile in self.tiles do
		if tile.badge.kind == self.selectedKind then
			selected = tile.badge
		end
	end
	if not selected then
		return
	end
	local state = self:getBadgeState(selected.kind)
	view.infoTitle.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.BadgeKind, selected.kind) or "")
	view.infoIcon.Image = selected.icon
	self:renderStars(view.infoStars, selected.stars, 0)
	view.infoDescription.Text = selected.description
	local amountText = utils.abbreviateNumber(selected.diamonds)
	view.claimButton.Visible = state == "CLAIMABLE"
	view.claimButton.Active = self.pendingKind ~= selected.kind
	view.claimAmountLabel.Text = amountText
	view.rewardText.Visible = state ~= "CLAIMABLE"
	view.rewardIcon.Visible = state == "LOCKED"
	view.rewardLabel.Text = UiStyle.formatTitle(if state == "CLAIMED" then COMPLETED_TEXT else string.format(REWARD_FORMAT, amountText))
	self:seatRewardIcon(view)
end

function ClientBadgeMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	for _, tile in self.tiles do
		self:renderTile(tile)
	end
	self:renderInfo(view)
end

function ClientBadgeMenuManager:select(badgeKind: number)
	self.selectedKind = badgeKind
	self:render()
end

function ClientBadgeMenuManager:dropTiles()
	for _, connection in self.tileConnections do
		connection:Disconnect()
	end
	self.tileConnections = {}
	for _, tile in self.tiles do
		tile.button:Destroy()
	end
	self.tiles = {}
end

-- one clone of the template per badge, the earned first and each group
-- by its stars (BadgeRules.sortForMenu). The order is taken once as the
-- menu opens, so a badge earned with it open never reshuffles the grid
function ClientBadgeMenuManager:buildTiles(view: View)
	self:dropTiles()
	for index, badge in BadgeRules.sortForMenu(self:getCatalogue(), ClientDataManager:getBadges()) do
		local button = view.tileTemplate:Clone()
		button.Name = string.format(TILE_NAME_FORMAT, index)
		button.LayoutOrder = index
		button.Visible = true
		local icon = button:FindFirstChild(Constants.BADGES_TILE_ICON)
		local stars = button:FindFirstChild(Constants.BADGES_STARS)
		local claimBanner = button:FindFirstChild(Constants.BADGES_TILE_CLAIM_BANNER)
		local check = button:FindFirstChild(Constants.BADGES_TILE_CHECK)
		local selected = button:FindFirstChild(Constants.BADGES_TILE_SELECTED)
		local tile: Tile = {
			badge = badge,
			button = button,
			icon = if icon and icon:IsA("ImageLabel") then icon else nil,
			stars = if stars and stars:IsA("GuiObject") then stars else nil,
			claimBanner = if claimBanner and claimBanner:IsA("GuiObject") then claimBanner else nil,
			check = if check and check:IsA("GuiObject") then check else nil,
			selected = if selected and selected:IsA("UIStroke") then selected else nil,
		}
		table.insert(
			self.tileConnections,
			button.Activated:Connect(
				function()
					self:select(badge.kind)
				end
			)
		)
		button.Parent = view.list
		table.insert(self.tiles, tile)
	end
end

-- the badge the menu opens on: the first with a reward waiting, else the
-- first of the list
function ClientBadgeMenuManager:pickOpeningKind(): number?
	local firstKind: number? = nil
	for _, tile in self.tiles do
		firstKind = firstKind or tile.badge.kind
		if self:getBadgeState(tile.badge.kind) == "CLAIMABLE" then
			return tile.badge.kind
		end
	end
	return firstKind
end

function ClientBadgeMenuManager:requestClaim()
	local badgeKind = self.selectedKind
	if not badgeKind or self.pendingKind or self:getBadgeState(badgeKind) ~= "CLAIMABLE" then
		return
	end
	self.pendingKind = badgeKind
	ClientNetManager:fireServer(NetEventNames.TRY_CLAIM_BADGE_REWARD, { badgeKind = badgeKind })
	self:render()
end

-- what was paid, as the server says: the sound and one feedback line,
-- the Diamond after the number
function ClientBadgeMenuManager:onRewardClaimed(payload: { [string]: any })
	self.pendingKind = nil
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	local amountText = utils.abbreviateNumber(if typeof(payload.diamonds) == "number" then payload.diamonds else 0)
	ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_FORMAT, amountText), FEEDBACK_SEC, Icons.UI.DIAMONDS)
	self:render()
end

-- the HUD button's red mark, while any earned badge holds its reward
function ClientBadgeMenuManager:renderHudButton()
	local alert = self.hudAlert
	if alert then
		alert.Visible = BadgeRules.countClaimable(ClientDataManager:getBadges(), ClientDataManager:getClaimedBadges()) > 0
	end
end

function ClientBadgeMenuManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	-- one menu at a time
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	self:buildTiles(view)
	self.selectedKind = self:pickOpeningKind()
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

-- everything a close leaves behind, whoever closed it
function ClientBadgeMenuManager:cleanUp(view: View)
	self.isOpen = false
	view.gui.Enabled = false
	self:dropTiles()
end

function ClientBadgeMenuManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:cleanUp(view)
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientBadgeMenuManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.BADGES_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientBadgeMenuManager: no {Constants.BADGES_GUI_NAME} ScreenGui; run build_badges_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.BADGES_BACK_BUTTON)
	local list = dialog and dialog:FindFirstChild(Constants.BADGES_LIST)
	local tileTemplate = list and list:FindFirstChild(Constants.BADGES_TILE_TEMPLATE)
	local panel = dialog and dialog:FindFirstChild(Constants.BADGES_INFO_PANEL)
	local infoTitle = panel and panel:FindFirstChild(Constants.BADGES_INFO_TITLE)
	local infoIcon = panel and panel:FindFirstChild(Constants.BADGES_INFO_ICON)
	local infoStars = panel and panel:FindFirstChild(Constants.BADGES_STARS)
	local infoDescription = panel and panel:FindFirstChild(Constants.BADGES_INFO_DESCRIPTION)
	local claimButton = panel and panel:FindFirstChild(Constants.BADGES_INFO_CLAIM_BUTTON)
	local claimAmountLabel = claimButton and claimButton:FindFirstChild(Constants.BADGES_INFO_CLAIM_AMOUNT_LABEL, true)
	local rewardText = panel and panel:FindFirstChild(Constants.BADGES_INFO_REWARD_TEXT)
	local rewardLabel = rewardText and rewardText:FindFirstChild(Constants.BADGES_INFO_REWARD_LABEL)
	local rewardIcon = rewardText and rewardText:FindFirstChild(Constants.BADGES_INFO_REWARD_ICON)
	if
		not dialog
		or not dialog:IsA("GuiObject")
		or not backButton
		or not backButton:IsA("GuiButton")
		or not list
		or not list:IsA("GuiObject")
		or not tileTemplate
		or not tileTemplate:IsA("GuiButton")
		or not infoTitle
		or not infoTitle:IsA("TextLabel")
		or not infoIcon
		or not infoIcon:IsA("ImageLabel")
		or not infoStars
		or not infoStars:IsA("GuiObject")
		or not infoDescription
		or not infoDescription:IsA("TextLabel")
		or not claimButton
		or not claimButton:IsA("GuiButton")
		or not claimAmountLabel
		or not claimAmountLabel:IsA("TextLabel")
		or not rewardText
		or not rewardText:IsA("GuiObject")
		or not rewardLabel
		or not rewardLabel:IsA("TextLabel")
		or not rewardIcon
		or not rewardIcon:IsA("GuiObject")
	then
		warn(`ClientBadgeMenuManager: {Constants.BADGES_GUI_NAME} is missing parts; see build_badges_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog,
		backButton = backButton,
		list = list,
		tileTemplate = tileTemplate,
		infoTitle = infoTitle,
		infoIcon = infoIcon,
		infoStars = infoStars,
		infoDescription = infoDescription,
		claimButton = claimButton,
		claimAmountLabel = claimAmountLabel,
		rewardText = rewardText,
		rewardLabel = rewardLabel,
		rewardIcon = rewardIcon,
	}
end

-- the HUD's Badges button: only its mark is found here. The HUD manager
-- wires the press, since it owns the HUD's buttons
function ClientBadgeMenuManager:findHudAlert(playerGui: PlayerGui)
	local hud = playerGui:WaitForChild(Constants.HUD_GUI_NAME, Constants.GUI_WAIT_SEC)
	local leftButtons = hud and hud:FindFirstChild(Constants.HUD_LEFT_BUTTONS)
	local button = leftButtons and leftButtons:FindFirstChild(Constants.HUD_BADGES_BUTTON)
	local alert = button and button:FindFirstChild(Constants.HUD_BUTTON_ALERT)
	if not alert or not alert:IsA("GuiObject") then
		warn(`ClientBadgeMenuManager: the HUD has no {Constants.HUD_BADGES_BUTTON} with an {Constants.HUD_BUTTON_ALERT}; run build_badges_gui`)
		return
	end
	self.hudAlert = alert
end

-- before the HUD, whose Badges button opens this menu
function ClientBadgeMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.tileTemplate.Visible = false
	view.gui.Enabled = false
	self:findHudAlert(playerGui)

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.claimButton.Activated:Connect(
		function()
			self:requestClaim()
		end
	)
	view.rewardLabel:GetPropertyChangedSignal("TextBounds"):Connect(
		function()
			self:seatRewardIcon(view)
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self:cleanUp(view)
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
		-- the HUD's Diamonds wallet is this menu's balance: a claim is seen
		-- landing in it
		doesKeepHud = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	for _, attribute in { Attributes.BADGES, Attributes.BADGES_CLAIMED } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:renderHudButton()
				self:render()
			end
		)
	end
	-- a Roblox badge's own picture can arrive after the first publish
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.BADGE_CATALOGUE,
		function()
			if self.isOpen then
				self:buildTiles(view)
				self:render()
			end
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_BADGE_REWARD_CLAIMED,
		function(payload: { [string]: any })
			self:onRewardClaimed(payload)
		end
	)
	self:renderHudButton()
end

function ClientBadgeMenuManager.new(): ClientBadgeMenuManager
	local self = setmetatable({}, ClientBadgeMenuManager) :: ClientBadgeMenuManager
	self.isOpen = false
	self.tiles = {}
	self.tileConnections = {}
	return self
end

return ClientBadgeMenuManager.new()
