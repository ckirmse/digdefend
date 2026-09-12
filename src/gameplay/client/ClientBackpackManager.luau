--!strict

-- The backpack on this client (GDD "Mining Rock", "Collecting Ore"): the HUD
-- button with "taken/total", red and "Backpack full" when there is no room,
-- shown while the pick axe is held; the pop sound when ore is collected;
-- and the contents menu (an overlay) listing only the ores carried. All
-- numbers come from the CurrentPlayer attributes BackpackManager writes.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientBackpackManager = {}
ClientBackpackManager.__index = ClientBackpackManager

export type ClientBackpackManager = typeof(setmetatable(
	{} :: {
		hudGui: ScreenGui?,
		button: GuiButton?,
		countLabel: TextLabel?,
		fullLabel: TextLabel?,
		buttonBasePosition: UDim2?,
		menuGui: ScreenGui?,
		menuDialog: Frame?,
		list: Frame?,
		rowTemplate: Frame?,
		emptyLabel: TextLabel?,
		rows: { Frame },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		isPickAxeHeld: boolean,
	},
	ClientBackpackManager
))

local NOTIFY_ORE_COLLECTED_SHAPE = {
	resource = { type = "enum", name = "RawResource" },
	amount = "positiveInteger",
}

local COUNT_FORMAT = "%d/%d"
-- listed in a fixed order so the menu does not reshuffle as ore arrives
local RESOURCE_ORDER = {
	Enums.RawResource.IRON_ORE,
	Enums.RawResource.GOLD_ORE,
	Enums.RawResource.CRYSTAL,
	Enums.RawResource.URANIUM_ORE,
}

local function readNumber(key: string): number
	local value = ClientDataManager:getCurrentPlayerAttribute(key)
	return if typeof(value) == "number" then value else 0
end

function ClientBackpackManager:readContents(): BackpackRules.Contents
	local contents = {}
	for _, resource in RESOURCE_ORDER do
		local attribute = BackpackRules.attributeForResource(resource) :: string
		local amount = readNumber(attribute)
		if amount > 0 then
			contents[resource] = amount
		end
	end
	return contents
end

function ClientBackpackManager:renderHud()
	local countLabel = self.countLabel
	local fullLabel = self.fullLabel
	if not countLabel then
		return
	end
	local capacity = readNumber(Attributes.BACKPACK_CAPACITY)
	local total = BackpackRules.getTotal(self:readContents())
	local isFull = capacity > 0 and total >= capacity
	countLabel.Text = string.format(COUNT_FORMAT, total, capacity)
	countLabel.TextColor3 = if isFull then UiStyle.NEGATIVE_COLOR else UiStyle.TEXT_COLOR
	if fullLabel then
		fullLabel.Visible = isFull
	end
end

function ClientBackpackManager:renderMenu()
	local list = self.list
	local template = self.rowTemplate
	if not list or not template then
		return
	end
	for _, row in self.rows do
		row:Destroy()
	end
	self.rows = {}
	local contents = self:readContents()
	local order = 0
	for _, resource in RESOURCE_ORDER do
		local amount = contents[resource]
		if not amount then
			continue
		end
		order += 1
		local row = template:Clone()
		row.Name = "Row" .. order
		row.LayoutOrder = order
		row.Visible = true
		local nameLabel = row:FindFirstChild(Constants.BACKPACK_ROW_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			(nameLabel :: TextLabel).Text = Enums.getPublicName(Enums.RawResource, resource) or "?"
		end
		local amountLabel = row:FindFirstChild(Constants.BACKPACK_ROW_AMOUNT_LABEL)
		if amountLabel and amountLabel:IsA("TextLabel") then
			(amountLabel :: TextLabel).Text = tostring(amount)
		end
		row.Parent = list
		table.insert(self.rows, row)
	end
	local emptyLabel = self.emptyLabel
	if emptyLabel then
		emptyLabel.Visible = order == 0
	end
end

function ClientBackpackManager:setHudVisible()
	local button = self.button
	if not button then
		return
	end
	button.Visible = self.isPickAxeHeld and not self.isMenuOpen
end

function ClientBackpackManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	local menuGui = self.menuGui
	if menuGui then
		menuGui.Enabled = false
	end
	self:setHudVisible()
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientBackpackManager:openMenu()
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen then
		return
	end
	self.isMenuOpen = true
	self:renderMenu()
	menuGui.Enabled = true
	self:setHudVisible()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientBackpackManager:onOreCollected(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_ORE_COLLECTED_SHAPE)
	if not isValid then
		warn("ClientBackpackManager: malformed NotifyOreCollected")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
	local button = self.button
	if button and button.Visible then
		-- a quick bump so the number change reads as the ore landing
		local base = self.buttonBasePosition or button.Position
		button.Position = base + UDim2.fromScale(0, -0.01)
		TweenService:Create(button, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad), { Position = base }):Play()
	end
end

function ClientBackpackManager:findHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientBackpackManager: no GameplayHud ScreenGui; run scripts/studio/build_gameplay_hud_gui.luau")
		return
	end
	self.hudGui = gui
	local button = gui:FindFirstChild(Constants.HUD_BACKPACK_BUTTON)
	if not button or not button:IsA("GuiButton") then
		warn("ClientBackpackManager: GameplayHud is missing BackpackButton")
		return
	end
	self.button = button
	self.buttonBasePosition = button.Position
	local countLabel = button:FindFirstChild(Constants.HUD_BACKPACK_COUNT_LABEL)
	self.countLabel = if countLabel and countLabel:IsA("TextLabel") then countLabel else nil
	local fullLabel = button:FindFirstChild(Constants.HUD_BACKPACK_FULL_LABEL)
	self.fullLabel = if fullLabel and fullLabel:IsA("TextLabel") then fullLabel else nil
	button.Activated:Connect(
		function()
			self:openMenu()
		end
	)
end

function ClientBackpackManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.BACKPACK_MENU_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientBackpackManager: no Backpack ScreenGui; run scripts/studio/build_backpack_menu_gui.luau")
		return
	end
	gui.Enabled = false
	self.menuGui = gui
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	self.menuDialog = if dialog and dialog:IsA("Frame") then dialog else nil
	local list = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_LIST) else nil
	self.list = if list and list:IsA("Frame") then list else nil
	local template = if list then list:FindFirstChild(Constants.BACKPACK_MENU_ROW_TEMPLATE) else nil
	self.rowTemplate = if template and template:IsA("Frame") then template else nil
	if self.rowTemplate then
		self.rowTemplate.Visible = false
	end
	local emptyLabel = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_EMPTY_LABEL) else nil
	self.emptyLabel = if emptyLabel and emptyLabel:IsA("TextLabel") then emptyLabel else nil
	local closeButton = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_CLOSE_BUTTON) else nil
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

function ClientBackpackManager:init()
	self:findHud()
	self:findMenu()

	local function applyEquipped(value: any)
		self.isPickAxeHeld = value == Enums.ToolKind.PICK_AXE
		self:setHudVisible()
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)

	local watched = { Attributes.BACKPACK_CAPACITY }
	for _, resource in RESOURCE_ORDER do
		table.insert(watched, BackpackRules.attributeForResource(resource) :: string)
	end
	for _, key in watched do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:renderHud()
				if self.isMenuOpen then
					self:renderMenu()
				end
			end
		)
	end
	self:renderHud()

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_ORE_COLLECTED,
		function(payload: any)
			self:onOreCollected(payload)
		end
	)
end

function ClientBackpackManager.new(): ClientBackpackManager
	local self = setmetatable({}, ClientBackpackManager) :: ClientBackpackManager
	self.hudGui = nil
	self.button = nil
	self.countLabel = nil
	self.fullLabel = nil
	self.buttonBasePosition = nil
	self.menuGui = nil
	self.menuDialog = nil
	self.list = nil
	self.rowTemplate = nil
	self.emptyLabel = nil
	self.rows = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.isPickAxeHeld = false
	return self
end

return ClientBackpackManager.new()
