--!strict

-- The group reward on the client (M78, designer 2026-11-12). Two things
-- are drawn from the same two CurrentPlayer attributes
-- (HasClaimedGroupReward, IsInRewardGroup) and the amount in
-- GameMetadata (GroupRewardDiamonds):
--
-- The banner: the designer's GroupReward picture in the Supply Crate
-- menu, the rotating store, and the Diamond Store. Each menu hands its
-- gui to bindBanner once; this module writes the line and hides the
-- banner for good once the reward is claimed, so no menu repeats that.
--
-- The claim menu: the designer's GroupRewardClaim ScreenGui, raised for a
-- group member who has not claimed (GroupRewardRules.canClaim), never
-- sooner than ARRIVAL_DELAY_SEC after the arrival loading screen has
-- slid away. It is an overlay like every menu (blur, backdrop, frozen
-- character) and has no close button: the Claim button sends
-- TryClaimGroupReward and closes it. The server decides the claim and
-- the amount; this only asks.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local GroupRewardRules = require("@game/ReplicatedStorage/Shared/GroupRewardRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientGroupRewardManager = {}
ClientGroupRewardManager.__index = ClientGroupRewardManager

-- one menu's banner; isHidden is the owning menu's own reason to put it
-- away for a while (the crate menu during an opening)
export type Banner = {
	root: GuiObject,
	message: TextLabel?,
	isHidden: boolean,
}

type ClaimView = {
	gui: ScreenGui,
	root: GuiObject,
	claimButton: GuiButton,
	amountLabel: TextLabel,
}

export type ClientGroupRewardManager = typeof(setmetatable(
	{} :: {
		banners: { Banner },
		claimView: ClaimView?,
		overlay: ClientOverlayManager.Overlay?,
		isClaimOpen: boolean,
		-- the claim has been sent and the save's flag has not come back
		-- yet: the menu must not come up again in that gap
		isClaimSent: boolean,
		-- the loading screen has gone and the pause after it has passed;
		-- the claim menu never opens before
		isArrivalDone: boolean,
	},
	ClientGroupRewardManager
))

-- the banner's line (the designer's words); %d is the Diamonds amount
-- the claim menu waits this long after the arrival loading screen has
-- finished sliding away (designer, 2026-11-12), so the player sees the
-- lobby first
local ARRIVAL_DELAY_SEC = 1
local ARRIVAL_POLL_SEC = 0.1

local BANNER_TEXT_FORMAT = "Like the game and join our group to get %d Diamonds for free!"

function ClientGroupRewardManager:getRewardDiamonds(): number
	local value = ClientDataManager:getGameMetadata(Attributes.GROUP_REWARD_DIAMONDS)
	return if typeof(value) == "number" then value else 0
end

function ClientGroupRewardManager:renderBanner(banner: Banner)
	local isShown = not banner.isHidden and not ClientDataManager:hasClaimedGroupReward()
	banner.root.Visible = isShown
	local message = banner.message
	if isShown and message then
		message.Text = UiStyle.formatTitle(string.format(BANNER_TEXT_FORMAT, self:getRewardDiamonds()))
	end
end

function ClientGroupRewardManager:renderBanners()
	for _, banner in self.banners do
		self:renderBanner(banner)
	end
end

-- a menu's one call: its gui's GroupReward banner is kept right from
-- here on. Nil (with a warning) for a copy of the gui without one
function ClientGroupRewardManager:bindBanner(gui: Instance): Banner?
	local root = gui:FindFirstChild(Constants.GROUP_REWARD_BANNER, true)
	if not root or not root:IsA("GuiObject") then
		warn(`ClientGroupRewardManager: {gui.Name} has no {Constants.GROUP_REWARD_BANNER} banner`)
		return nil
	end
	local message = root:FindFirstChild(Constants.GROUP_REWARD_BANNER_MESSAGE)
	local banner: Banner = {
		root = root,
		message = if message and message:IsA("TextLabel") then message else nil,
		isHidden = false,
	}
	table.insert(self.banners, banner)
	self:renderBanner(banner)
	return banner
end

function ClientGroupRewardManager:setBannerHidden(banner: Banner?, isHidden: boolean)
	if not banner or banner.isHidden == isHidden then
		return
	end
	banner.isHidden = isHidden
	self:renderBanner(banner)
end

-- a store menu opened: a player not yet seen in the group may have
-- joined since the last look, so the server asks Roblox again (it
-- throttles). The answer comes back as IsInRewardGroup
function ClientGroupRewardManager:requestRefreshIfNeeded()
	if ClientDataManager:hasClaimedGroupReward() or ClientDataManager:isInRewardGroup() then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_REFRESH_GROUP_REWARD, {})
end

function ClientGroupRewardManager:canClaim(): boolean
	return not self.isClaimSent and GroupRewardRules.canClaim(ClientDataManager:isInRewardGroup(), ClientDataManager:hasClaimedGroupReward())
end

-- everything a close leaves behind, whoever closed it
function ClientGroupRewardManager:cleanUpClaim(view: ClaimView)
	self.isClaimOpen = false
	view.gui.Enabled = false
end

function ClientGroupRewardManager:closeClaim()
	local view = self.claimView
	if not view or not self.isClaimOpen then
		return
	end
	self:cleanUpClaim(view)
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

-- raises the claim menu when the reward is there to claim and no other
-- menu is up; with one up it waits, and the overlay notifier below asks
-- again when that menu closes
function ClientGroupRewardManager:openClaimIfNeeded()
	local view = self.claimView
	local overlay = self.overlay
	if not view or not overlay or not self.isArrivalDone or self.isClaimOpen or not self:canClaim() then
		return
	end
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isClaimOpen = true
	view.amountLabel.Text = utils.abbreviateNumber(self:getRewardDiamonds())
	view.gui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientGroupRewardManager:onClaimActivated()
	if not self.isClaimOpen then
		return
	end
	self.isClaimSent = true
	ClientNetManager:fireServer(NetEventNames.TRY_CLAIM_GROUP_REWARD, {})
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	self:closeClaim()
end

-- either attribute changed: the banners follow, an open claim menu that
-- no longer applies goes, and one that now applies comes up
function ClientGroupRewardManager:onStateChanged()
	if not ClientDataManager:hasClaimedGroupReward() then
		-- unclaimed again (the dev tool's reset): the menu may return
		self.isClaimSent = false
	end
	self:renderBanners()
	if self.isClaimOpen and not self:canClaim() then
		self:closeClaim()
		return
	end
	self:openClaimIfNeeded()
end

function ClientGroupRewardManager:findClaimView(playerGui: PlayerGui): ClaimView?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.GROUP_REWARD_CLAIM_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientGroupRewardManager: no {Constants.GROUP_REWARD_CLAIM_GUI_NAME} ScreenGui`)
		return nil
	end
	local root = gui:FindFirstChildWhichIsA("GuiObject")
	local claimButton = gui:FindFirstChild(Constants.GROUP_REWARD_CLAIM_BUTTON, true)
	local amountLabel = claimButton and claimButton:FindFirstChild(Constants.GROUP_REWARD_CLAIM_AMOUNT_LABEL, true)
	if not root or not claimButton or not claimButton:IsA("GuiButton") or not amountLabel or not amountLabel:IsA("TextLabel") then
		warn(`ClientGroupRewardManager: {Constants.GROUP_REWARD_CLAIM_GUI_NAME} is missing parts`)
		return nil
	end
	return {
		gui = gui,
		root = root,
		claimButton = claimButton,
		amountLabel = amountLabel,
	}
end

-- before the menus that bind a banner, so their first drawing is right
function ClientGroupRewardManager:init()
	for _, attribute in { Attributes.HAS_CLAIMED_GROUP_REWARD, Attributes.IS_IN_REWARD_GROUP } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:onStateChanged()
			end
		)
	end
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.GROUP_REWARD_DIAMONDS,
		function()
			self:renderBanners()
		end
	)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findClaimView(playerGui)
	if not view then
		return
	end
	self.claimView = view
	view.gui.Enabled = false
	-- a menu draws over the HUD and the backdrop whatever the gui was
	-- authored at
	view.gui.DisplayOrder = math.max(view.gui.DisplayOrder, ClientOverlayManager.MENU_DISPLAY_ORDER)
	view.claimButton.Activated:Connect(
		function()
			self:onClaimActivated()
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.root
		end,
		-- another menu took the screen: this one steps aside and comes
		-- back when that menu closes
		notifyForceEnd = function(_overlay)
			self:cleanUpClaim(view)
		end,
		-- no way out but the Claim button (designer, 2026-11-12)
		notifyClickOutside = function(_overlay) end,
		notifyBack = function(_overlay) end,
	}
	self.overlay = overlay

	ClientOverlayManager:addOverlayNotifier(
		{
			notifyBeginOverlay = function(_notifier, _overlay) end,
			-- deferred: the closing menu is still mid-close here
			notifyEndOverlay = function(_notifier, endedOverlay)
				if endedOverlay ~= overlay then
					task.defer(
						function()
							self:openClaimIfNeeded()
						end
					)
				end
			end,
		}
	)

	-- the overlay manager holds menus back for exactly as long as the
	-- loading screen is up, so its flag is the screen's "gone" signal
	task.spawn(
		function()
			while ClientOverlayManager:getIsDeferringOverlays() do
				task.wait(ARRIVAL_POLL_SEC)
			end
			task.wait(ARRIVAL_DELAY_SEC)
			self.isArrivalDone = true
			self:openClaimIfNeeded()
		end
	)
end

function ClientGroupRewardManager.new(): ClientGroupRewardManager
	local self = setmetatable({}, ClientGroupRewardManager) :: ClientGroupRewardManager
	self.banners = {}
	self.isClaimOpen = false
	self.isClaimSent = false
	self.isArrivalDone = false
	return self
end

return ClientGroupRewardManager.new()
