--!strict

-- The custom tool bar (GDD "Tool Bar System"): one slot per tool in the
-- order the server lists them, more than three on mobile, one equipped at a
-- time. Tap a slot to equip, tap it again or another to switch; keys 1-9
-- and the gamepad bumpers do the same. The bar only asks (TryEquipTool);
-- what it shows is the server's answer in the CurrentPlayer attributes.
-- Slides away while a menu is open.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)

local ClientToolBarManager = {}
ClientToolBarManager.__index = ClientToolBarManager

type SlotView = {
	tool: number,
	frame: GuiButton,
}

export type ClientToolBarManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		slotsFrame: Frame?,
		slotTemplate: GuiButton?,
		basePosition: UDim2?,
		slots: { number },
		equipped: number,
		slotViews: { SlotView },
	},
	ClientToolBarManager
))

local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

function ClientToolBarManager:requestEquip(tool: number)
	ClientNetManager:fireServer(
		NetEventNames.TRY_EQUIP_TOOL,
		{
			tool = tool,
		}
	)
end

-- tapping the equipped tool unequips it (GDD)
function ClientToolBarManager:toggleTool(tool: number)
	if self.equipped == tool then
		self:requestEquip(MiningRules.NO_TOOL)
	else
		self:requestEquip(tool)
	end
end

function ClientToolBarManager:toggleSlotIndex(index: number)
	local tool = self.slots[index]
	if tool then
		self:toggleTool(tool)
	end
end

-- bumpers step through the bar; past either end unequips
function ClientToolBarManager:cycle(direction: number)
	local count = #self.slots
	if count == 0 then
		return
	end
	local current = table.find(self.slots, self.equipped) or 0
	local next = current + direction
	if next < 1 or next > count then
		self:requestEquip(MiningRules.NO_TOOL)
		return
	end
	self:requestEquip(self.slots[next])
end

function ClientToolBarManager:renderSlots()
	local slotsFrame = self.slotsFrame
	local template = self.slotTemplate
	if not slotsFrame or not template then
		return
	end
	for _, view in self.slotViews do
		view.frame:Destroy()
	end
	self.slotViews = {}
	for index, tool in self.slots do
		local frame = template:Clone()
		frame.Name = "Slot" .. index
		frame.LayoutOrder = index
		frame.Visible = true
		local label = frame:FindFirstChild(Constants.TOOL_SLOT_LABEL)
		if label and label:IsA("TextLabel") then
			(label :: TextLabel).Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ToolKind, tool) or "?")
		end
		local keyLabel = frame:FindFirstChild(Constants.TOOL_SLOT_KEY_LABEL)
		if keyLabel and keyLabel:IsA("TextLabel") then
			(keyLabel :: TextLabel).Text = tostring(index)
			keyLabel.Visible = UserInputService.KeyboardEnabled
		end
		frame.Activated:Connect(
			function()
				self:toggleTool(tool)
			end
		)
		frame.Parent = slotsFrame
		table.insert(self.slotViews, { tool = tool, frame = frame })
	end
	self:renderEquipped()
end

function ClientToolBarManager:renderEquipped()
	for _, view in self.slotViews do
		local isEquipped = view.tool == self.equipped
		local stroke = view.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if isEquipped then UiStyle.ACCENT_COLOR else UiStyle.PANEL_COLOR
		end
		view.frame.BackgroundColor3 = if isEquipped then UiStyle.PANEL_COLOR else UiStyle.EMPTY_SLOT_COLOR
	end
end

function ClientToolBarManager:tweenTo(position: UDim2)
	local slotsFrame = self.slotsFrame
	if not slotsFrame then
		return
	end
	TweenService:Create(slotsFrame, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad), { Position = position }):Play()
end

function ClientToolBarManager:notifyBeginOverlay()
	local base = self.basePosition
	if base then
		self:tweenTo(UDim2.new(base.X.Scale, base.X.Offset, 1.3, 0))
	end
end

function ClientToolBarManager:notifyEndOverlay()
	local base = self.basePosition
	if base then
		self:tweenTo(base)
	end
end

function ClientToolBarManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		if index then
			self:toggleSlotIndex(index)
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonR1 then
		self:cycle(1)
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
		self:cycle(-1)
	end
end

function ClientToolBarManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.TOOL_BAR_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientToolBarManager: no ToolBar ScreenGui; run scripts/studio/build_tool_bar_gui.luau")
		return
	end
	self.gui = gui
	local slotsFrame = gui:FindFirstChild(Constants.TOOL_BAR_SLOTS_FRAME)
	local template = if slotsFrame then slotsFrame:FindFirstChild(Constants.TOOL_BAR_SLOT_TEMPLATE) else nil
	if not slotsFrame or not slotsFrame:IsA("Frame") or not template or not template:IsA("GuiButton") then
		warn("ClientToolBarManager: ToolBar is missing Slots.SlotTemplate")
		return
	end
	self.slotsFrame = slotsFrame
	self.slotTemplate = template
	self.basePosition = slotsFrame.Position
	template.Visible = false

	self.slots = MiningRules.decodeToolSlots(ClientDataManager:getCurrentPlayerAttribute(Attributes.TOOL_SLOTS))
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	self.equipped = if typeof(equipped) == "number" then equipped else MiningRules.NO_TOOL
	self:renderSlots()

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.TOOL_SLOTS,
		function(value: any)
			self.slots = MiningRules.decodeToolSlots(value)
			self:renderSlots()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.EQUIPPED_TOOL,
		function(value: any)
			self.equipped = if typeof(value) == "number" then value else MiningRules.NO_TOOL
			self:renderEquipped()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	ClientOverlayManager:addOverlayNotifier(self)
end

function ClientToolBarManager.new(): ClientToolBarManager
	local self = setmetatable({}, ClientToolBarManager) :: ClientToolBarManager
	self.gui = nil
	self.slotsFrame = nil
	self.slotTemplate = nil
	self.basePosition = nil
	self.slots = {}
	self.equipped = MiningRules.NO_TOOL
	self.slotViews = {}
	return self
end

return ClientToolBarManager.new()
