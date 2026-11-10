-- Builds the "RestrictedStoreGui" ScreenGui under StarterGui in the lobby
-- place (designer, 2026-11-10): the rotating store a player restricted
-- from paid random items gets in place of the Supply Crate menu. One
-- page: a countdown to the next change over the few cards on sale today
-- (class cards and cosmetics), each with its own Buy plate and price
-- tab. (The same day it was first a Gear Store with a details panel,
-- then one menu with Store and Locker tabs; makeRotatingStore is what
-- turns the first layout into this one, and the tabs are gone.)
-- It is made by CLONING THE LIVE STORE GUI, so whatever the designer has
-- tuned on it comes across as it stands. The dialog itself (header, X,
-- shadow) is the DirectStore's. It has no wallet: the HUD's Diamonds
-- wallet stays on screen under it.
--
-- The DirectStore gui it was built from is parked under
-- ServerStorage.GuiBackups, not deleted. On a place that has neither a
-- DirectStore nor a backup of one, the store page is made from the live
-- KeyStore gui the way the first build was.
--
-- It also turns the Class Menu's two designer-duplicated plates into
-- price buttons: PurchaseButton (a copy of SupplyCrateButton) and
-- UpgradeButton (a copy of OddsButton) each get a word on the left and
-- the Key Store's price tab on the right with the Diamond icon.
--
-- THE DESIGNER TUNES ALL OF THIS IN THE EXPLORER. The script never
-- overwrites an existing RestrictedStoreGui (set REBUILD to true only
-- after porting the live gui's differences here), and it only adds what
-- a Class Menu plate is missing. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the lobby place. Names must match
-- Constants.RESTRICTED_STORE_* and Constants.CLASS_INFO_*.
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local REBUILD = false
local GUI_NAME = "RestrictedStoreGui"
local DIAMOND_ICON = "rbxassetid://101719152234191"
-- the page fills the dialog
local PAGE_POSITION = UDim2.fromScale(0, 0)
local PAGE_SIZE = UDim2.fromScale(1, 1)
-- the store page when it has to be made from the KeyStore gui (the
-- designer's DirectStore numbers of 2026-11-10)
local STORE_TITLE_TEXT = "GEAR STORE"
local BACK_ANCHOR = Vector2.new(1, 0)
local BACK_POSITION = UDim2.fromScale(0.98, 0.015)
local BACK_SIZE = UDim2.fromScale(0.055, 0.08)
local BACK_TEXT = "X"
local ITEM_LIST_POSITION = UDim2.fromScale(0.02, 0.95)
local ITEM_LIST_SIZE = UDim2.fromScale(0.66, 0.78)
local INFO_PANEL_SIZE = UDim2.fromScale(0.27, 0.78)
local ACTIONS_POSITION = UDim2.fromScale(0.5, 0.94)
local ACTIONS_SIZE = UDim2.fromScale(0.86, 0.32)
local ACTION_BUTTON_SIZE = UDim2.fromScale(1, 0.47)
local ACTION_GAP_SCALE = 0.06

local out = {}
ChangeHistoryService:SetWaypoint("Before RestrictedStoreGui")

local keyStore = StarterGui:FindFirstChild("KeyStore")
if not keyStore then
	error("build_restricted_store_gui: needs StarterGui.KeyStore to copy")
end

-- a fresh store gui from the KeyStore, as the first build made it
local function makeStoreFromKeyStore()
	local gui = keyStore:Clone()
	local dialog = gui.Dialog
	dialog.Header.Title.Text = STORE_TITLE_TEXT
	local staleWallet = dialog:FindFirstChild("KeysWallet")
	if staleWallet then
		staleWallet:Destroy()
	end
	dialog.BackButton.AnchorPoint = BACK_ANCHOR
	dialog.BackButton.Position = BACK_POSITION
	dialog.BackButton.Size = BACK_SIZE
	dialog.BackButton.TextLabel.Text = BACK_TEXT
	dialog.ItemList.Position = ITEM_LIST_POSITION
	dialog.ItemList.Size = ITEM_LIST_SIZE
	local infoPanel = dialog.InfoPanel
	infoPanel.Size = INFO_PANEL_SIZE
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.AnchorPoint = Vector2.new(0.5, 1)
	actions.Position = ACTIONS_POSITION
	actions.Size = ACTIONS_SIZE
	actions.BackgroundTransparency = 1
	actions.BorderSizePixel = 0
	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Vertical
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.Padding = UDim.new(ACTION_GAP_SCALE, 0)
	actionsLayout.Parent = actions
	for order, name in { "EquipButton", "BuyButton" } do
		local button = infoPanel[name]
		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.fromScale(0, 0)
		button.Size = ACTION_BUTTON_SIZE
		button.LayoutOrder = order
		button.Parent = actions
	end
	actions.Parent = infoPanel
	actions.BuyButton.PriceTab.Icon.Image = DIAMOND_ICON
	return gui
end

-- the store page as a rotating store: the details panel goes, its hint
-- line becomes the countdown at the top, and its Equip over Buy move
-- onto the card template, which grows taller to hold them; the grid
-- becomes one centred row with nothing to scroll
local TIMER_POSITION = UDim2.fromScale(0.5, 0.15)
local TIMER_SIZE = UDim2.fromScale(0.9, 0.07)
local TIMER_TEXT = "Store Refreshes In: 0h 0m 0s"
local CARD_ACTIONS_POSITION = UDim2.fromScale(0.5, 0.97)
local CARD_ACTIONS_SIZE = UDim2.fromScale(0.86, 0.17)
local CARD_SIZE = UDim2.fromScale(0.25, 0)
local CARD_ASPECT_RATIO = 0.68
local CARD_ICON_POSITION = UDim2.fromScale(0.5, 0.05)
local CARD_ICON_SIZE = UDim2.fromScale(0.7, 0.45)
local CARD_NAME_POSITION = UDim2.fromScale(0.5, 0.76)
local CARD_NAME_SIZE = UDim2.fromScale(0.9, 0.14)
local CARD_ROW_POSITION = UDim2.fromScale(0.5, 0.95)
local CARD_ROW_SIZE = UDim2.fromScale(0.96, 0.7)
local CARD_GAP_SCALE = 0.03

local function makeRotatingStore(storePage)
	local infoPanel = storePage:FindFirstChild("InfoPanel")
	if not infoPanel then
		return
	end
	local itemList = storePage.ItemList
	local template = itemList.ItemTemplate
	local timer = infoPanel.Hint:Clone()
	timer.Name = "RefreshTimer"
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = TIMER_POSITION
	timer.Size = TIMER_SIZE
	timer.Text = TIMER_TEXT
	timer.Visible = true
	timer.Parent = storePage
	local actions = infoPanel.Actions
	actions.AnchorPoint = Vector2.new(0.5, 1)
	actions.Position = CARD_ACTIONS_POSITION
	actions.Size = CARD_ACTIONS_SIZE
	for _, name in { "EquipButton", "BuyButton" } do
		actions[name].Size = UDim2.fromScale(1, 1)
	end
	actions.Parent = template
	template.Size = CARD_SIZE
	template.UIAspectRatioConstraint.AspectRatio = CARD_ASPECT_RATIO
	template.Icon.Position = CARD_ICON_POSITION
	template.Icon.Size = CARD_ICON_SIZE
	local nameLabel = template:FindFirstChild("Name")
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = CARD_NAME_POSITION
	nameLabel.Size = CARD_NAME_SIZE
	itemList.AnchorPoint = Vector2.new(0.5, 1)
	itemList.Position = CARD_ROW_POSITION
	itemList.Size = CARD_ROW_SIZE
	itemList.CanvasSize = UDim2.new(0, 0, 0, 0)
	itemList.AutomaticCanvasSize = Enum.AutomaticSize.None
	itemList.ScrollingEnabled = false
	itemList.ScrollBarThickness = 0
	local layout = itemList.UIListLayout
	layout.Wraps = false
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(CARD_GAP_SCALE, 0)
	infoPanel:Destroy()
end

local function makePage(name, dialog)
	local page = Instance.new("Frame")
	page.Name = name
	page.Position = PAGE_POSITION
	page.Size = PAGE_SIZE
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Parent = dialog
	return page
end

local existing = StarterGui:FindFirstChild(GUI_NAME)
if existing and REBUILD then
	existing:Destroy()
	existing = nil
end
if existing then
	table.insert(out, GUI_NAME .. " exists; left alone")
else
	local backups = ServerStorage:FindFirstChild("GuiBackups")
	local liveStore = StarterGui:FindFirstChild("DirectStore")
	local source = liveStore or (backups and backups:FindFirstChild("DirectStore"))
	local gui = if source then source:Clone() else makeStoreFromKeyStore()
	gui.Name = GUI_NAME
	gui.Enabled = false
	local dialog = gui.Dialog
	-- the first build's empty tab frame, if the copy still has it
	local staleTabs = dialog:FindFirstChild("Tabs")
	if staleTabs then
		staleTabs:Destroy()
	end

	local storePage = makePage("StorePage", dialog)
	dialog.ItemList.Parent = storePage
	dialog.InfoPanel.Parent = storePage

	makeRotatingStore(storePage)

	gui.Parent = StarterGui
	table.insert(out, "built StarterGui." .. GUI_NAME)
	if liveStore then
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "GuiBackups"
			backups.Parent = ServerStorage
		end
		liveStore.Parent = backups
		table.insert(out, "parked DirectStore under ServerStorage.GuiBackups")
	end
end

-- the Class Menu's two plates
local classMenu = StarterGui:FindFirstChild("ClassMenu")
local infoPanel = classMenu and classMenu:FindFirstChild("InfoPanel", true)
local priceTabSource = keyStore.Dialog.InfoPanel.BuyButton.PriceTab
if infoPanel then
	-- the duplicate was named with a slip of the key
	local misnamed = infoPanel:FindFirstChild("UpradeButton")
	if misnamed and not infoPanel:FindFirstChild("UpgradeButton") then
		misnamed.Name = "UpgradeButton"
		table.insert(out, "renamed UpradeButton to UpgradeButton")
	end
	local plates = {
		{ name = "PurchaseButton", word = "BUY", wordSize = UDim2.fromScale(0.5, 0.7), tabSize = UDim2.fromScale(0.3, 0.7) },
		{ name = "UpgradeButton", word = "UPGRADE", wordSize = UDim2.fromScale(0.5, 0.7), tabSize = UDim2.fromScale(0.4, 0.7) },
	}
	for _, spec in plates do
		local plate = infoPanel:FindFirstChild(spec.name)
		if not plate then
			table.insert(out, "ClassMenu has no " .. spec.name)
			continue
		end
		if plate:FindFirstChild("PriceTab") then
			continue
		end
		local label = plate:FindFirstChild("TextLabel")
		if label then
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromScale(0.05, 0.5)
			label.Size = spec.wordSize
			label.Text = spec.word
		end
		local priceTab = priceTabSource:Clone()
		priceTab.AnchorPoint = Vector2.new(1, 0.5)
		priceTab.Position = UDim2.fromScale(0.96, 0.5)
		priceTab.Size = spec.tabSize
		priceTab.Icon.Image = DIAMOND_ICON
		priceTab.Parent = plate
		plate.Visible = false
		table.insert(out, "made " .. spec.name .. " a price button")
	end
else
	table.insert(out, "no ClassMenu InfoPanel found")
end

ChangeHistoryService:SetWaypoint("After RestrictedStoreGui")
print("build_restricted_store_gui: " .. table.concat(out, "; "))
return table.concat(out, "; ")
