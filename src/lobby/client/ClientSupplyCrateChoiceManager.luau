--!strict

-- The Supply Crate stall's first screen (designer, 2026-11-05): a small
-- dialog with OPEN SUPPLY CRATES and KEY STORE. Walking into the stall
-- (ClientStoreZoneManager) and the HUD's Store button open this instead
-- of the crate menu; a plate closes this menu and opens the one it names
-- (one overlay at a time, so the close must come first). Nothing here
-- talks to the server: both menus it hands off to are client overlays.
local Players = game:GetService("Players")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)
local ClientKeyStoreManager = require(script.Parent.ClientKeyStoreManager)

local ClientSupplyCrateChoiceManager = {}
ClientSupplyCrateChoiceManager.__index = ClientSupplyCrateChoiceManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	cratesButton: GuiButton,
	keyStoreButton: GuiButton,
}

export type ClientSupplyCrateChoiceManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
	},
	ClientSupplyCrateChoiceManager
))

function ClientSupplyCrateChoiceManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	-- one menu at a time: a stall zone entered with another menu up waits
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientSupplyCrateChoiceManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	view.gui.Enabled = false
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientSupplyCrateChoiceManager:openCrates()
	self:closeMenu()
	ClientGachaMenuManager:openMenu()
end

function ClientSupplyCrateChoiceManager:openKeyStore()
	self:closeMenu()
	ClientKeyStoreManager:openMenu()
end

function ClientSupplyCrateChoiceManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.SUPPLY_CRATE_CHOICE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientSupplyCrateChoiceManager: no {Constants.SUPPLY_CRATE_CHOICE_GUI_NAME} ScreenGui; run build_supply_crate_choice_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.SUPPLY_CRATE_CHOICE_BACK_BUTTON)
	local cratesButton = dialog and dialog:FindFirstChild(Constants.SUPPLY_CRATE_CHOICE_CRATES_BUTTON)
	local keyStoreButton = dialog and dialog:FindFirstChild(Constants.SUPPLY_CRATE_CHOICE_KEY_STORE_BUTTON)
	if not dialog or not backButton or not cratesButton or not keyStoreButton then
		warn(`ClientSupplyCrateChoiceManager: {Constants.SUPPLY_CRATE_CHOICE_GUI_NAME} is missing parts; rerun build_supply_crate_choice_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		cratesButton = cratesButton :: GuiButton,
		keyStoreButton = keyStoreButton :: GuiButton,
	}
end

function ClientSupplyCrateChoiceManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.cratesButton.Activated:Connect(
		function()
			self:openCrates()
		end
	)
	view.keyStoreButton.Activated:Connect(
		function()
			self:openKeyStore()
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self.isOpen = false
			view.gui.Enabled = false
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay
end

function ClientSupplyCrateChoiceManager.new(): ClientSupplyCrateChoiceManager
	local self = setmetatable({}, ClientSupplyCrateChoiceManager) :: ClientSupplyCrateChoiceManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	return self
end

return ClientSupplyCrateChoiceManager.new()
