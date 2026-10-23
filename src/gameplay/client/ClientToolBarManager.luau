--!strict

-- The custom tool bar (GDD "Tool Bar System"): one slot per tool in the
-- order the server lists them, more than three on mobile, one equipped at a
-- time. Tap a slot to equip, tap it again or another to switch; keys 1-9
-- and the gamepad bumpers do the same. Consumables show how many are held
-- in a corner badge and leave the bar at zero. The bar only asks (TryEquipTool);
-- what it shows is the server's answer in the CurrentPlayer attributes.
-- Slides away while a menu is open. The gadget slot (M66) is named for the
-- class's gadget and, while a destroyed Auto Turret waits for dawn, wears
-- a grey sheet and refuses the tap with a line.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

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
		countByTool: { [number]: number },
		equipped: number,
		slotViews: { SlotView },
		-- Build Mode (ClientDefenseTableManager) stands in for the bar:
		-- the row hides and the number keys are its to read
		isHidden: boolean,
		-- the gadget slot (M66): what fills it, and whether the Auto Turret
		-- is lost until dawn
		gadgetKind: number,
		isAutoTurretLost: boolean,
		-- the Stim Shot is used until dawn (2026-10-19): its slot stays, the
		-- icon dimmed, the effect counted down on the badge, then the grey sheet
		isStimShotUsed: boolean,
		stimShotEffectEndTime: number,
		-- the gadget's cooldown (2026-10-20; the Remote Charge after a
		-- detonation, the Flare after a throw): the server time it is in
		-- hand again and each cooldown's length, the slot's grey sheet
		-- draining down over it
		gadgetReadyTime: number,
		cooldownSecByGadget: { [number]: number },
		-- the gadget's held variant ("" for the gadget itself), which renames the slot
		gadgetVariant: string,
		-- the Demolitionist's next stick (2026-10-20): when it is in hand and
		-- the wait's length, the slot's sheet draining over it
		dynamiteReadyTime: number,
		dynamiteRespawnSec: number,
		stimCountdownConnection: RBXScriptConnection?,
	},
	ClientToolBarManager
))

local FEEDBACK_NOT_AVAILABLE_BY_GADGET: { [number]: string } = {
	[Enums.GadgetKind.AUTO_TURRET] = "Auto Turret not available yet.",
	[Enums.GadgetKind.STIM_SHOT] = "You'll receive another STIM in the morning",
	[Enums.GadgetKind.REMOTE_CHARGE] = "Next charge is on its way",
	[Enums.GadgetKind.FLARE] = "Next flare is on its way",
	[Enums.GadgetKind.ORE_SCANNER] = "The scanner is recharging",
}
-- the gadgets whose slot runs a cooldown (GadgetReadyTime) shown by the
-- sheet draining, and the GameMetadata key holding each one's length
local COOLDOWN_SEC_ATTRIBUTE_BY_GADGET: { [number]: string } = {
	[Enums.GadgetKind.REMOTE_CHARGE] = Attributes.REMOTE_CHARGE_COOLDOWN_SEC,
	[Enums.GadgetKind.FLARE] = Attributes.FLARE_COOLDOWN_SEC,
	[Enums.GadgetKind.ORE_SCANNER] = Attributes.ORE_SCANNER_COOLDOWN_SEC,
}
-- the Demolitionist's empty dynamite slot while the next stick comes (2026-10-20)
local FEEDBACK_DYNAMITE_COMING = "Next stick in %d s"
local FEEDBACK_DYNAMITE_EMPTY = "No dynamite yet"
-- a used Stim Shot's icon while the slot waits for dawn
local USED_STIM_ICON_TRANSPARENCY = 0.7
local FEEDBACK_DISPLAY_SEC = 2

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

-- the gadget slot while its gadget is spent until dawn (a lost turret, a
-- used Stim Shot): every path to it (tap, key, bumper) is told once
-- instead of equipping
function ClientToolBarManager:isConsumableEmpty(tool: number): boolean
	return MiningRules.isConsumable(tool) and self.countByTool[tool] ~= nil and self.countByTool[tool] <= 0
end

function ClientToolBarManager:isGadgetLost(tool: number): boolean
	if self:isConsumableEmpty(tool) then
		return true
	end
	if tool ~= Enums.ToolKind.GADGET then
		return false
	end
	if self.gadgetKind == Enums.GadgetKind.AUTO_TURRET then
		return self.isAutoTurretLost
	end
	if self.gadgetKind == Enums.GadgetKind.STIM_SHOT then
		-- the sheet waits until the effect has run out; the countdown shows first
		return self.isStimShotUsed and self:getStimSecondsLeft() <= 0
	end
	if COOLDOWN_SEC_ATTRIBUTE_BY_GADGET[self.gadgetKind] then
		return self:getGadgetSecondsLeft() > 0
	end
	return false
end

-- whether the Stim Shot's slot refuses a tap: used, running or not
function ClientToolBarManager:isGadgetSpent(tool: number): boolean
	if tool == Enums.ToolKind.GADGET and self.gadgetKind == Enums.GadgetKind.STIM_SHOT then
		return self.isStimShotUsed
	end
	return self:isGadgetLost(tool)
end

function ClientToolBarManager:getStimSecondsLeft(): number
	return math.max(0, self.stimShotEffectEndTime - workspace:GetServerTimeNow())
end

function ClientToolBarManager:getGadgetSecondsLeft(): number
	return math.max(0, self.gadgetReadyTime - workspace:GetServerTimeNow())
end

function ClientToolBarManager:getDynamiteSecondsLeft(): number
	return math.max(0, self.dynamiteReadyTime - workspace:GetServerTimeNow())
end

-- the gadget slot's countdown: the Stim Shot while used (a dimmed icon,
-- the seconds of the effect left in a number the icon's size over it,
-- then the grey sheet once they are gone) and the Remote Charge while
-- cooling down (the sheet draining down over the cooldown, no number;
-- decided 2026-10-20)
function ClientToolBarManager:renderStim()
	local secondsLeft = 0
	for _, view in self.slotViews do
		-- the dynamite slot drains its sheet while the next stick comes, no number
		if view.tool == Enums.ToolKind.DYNAMITE then
			secondsLeft = math.max(secondsLeft, self:getDynamiteSecondsLeft())
			continue
		end
		if view.tool ~= Enums.ToolKind.GADGET then
			continue
		end
		local icon = view.frame:FindFirstChild(Constants.TOOL_SLOT_ICON)
		local timerLabel = view.frame:FindFirstChild(Constants.TOOL_SLOT_TIMER_LABEL)
		if self.gadgetKind == Enums.GadgetKind.STIM_SHOT then
			secondsLeft = self:getStimSecondsLeft()
			if icon and icon:IsA("ImageLabel") then
				icon.ImageTransparency = if self.isStimShotUsed then USED_STIM_ICON_TRANSPARENCY else 0
			end
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Text = tostring(math.ceil(secondsLeft))
				timerLabel.Visible = self.isStimShotUsed and secondsLeft > 0
			end
		elseif COOLDOWN_SEC_ATTRIBUTE_BY_GADGET[self.gadgetKind] then
			secondsLeft = self:getGadgetSecondsLeft()
			if icon and icon:IsA("ImageLabel") then
				icon.ImageTransparency = 0
			end
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Visible = false
			end
		end
	end
	self:renderLost()
	-- stepped only while there are seconds to count
	if secondsLeft > 0 and not self.stimCountdownConnection then
		self.stimCountdownConnection = RunService.Heartbeat:Connect(
			function()
				self:renderStim()
			end
		)
	elseif secondsLeft <= 0 and self.stimCountdownConnection then
		self.stimCountdownConnection:Disconnect()
		self.stimCountdownConnection = nil
	end
end

-- tapping the equipped tool unequips it (GDD)
function ClientToolBarManager:toggleTool(tool: number)
	if self:isGadgetSpent(tool) then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		local message = FEEDBACK_NOT_AVAILABLE_BY_GADGET[self.gadgetKind]
		if tool == Enums.ToolKind.DYNAMITE then
			local secondsLeft = self:getDynamiteSecondsLeft()
			message = if secondsLeft > 0 then string.format(FEEDBACK_DYNAMITE_COMING, math.ceil(secondsLeft)) else FEEDBACK_DYNAMITE_EMPTY
		end
		ClientPlayerFeedbackManager:giveLocal(message or "Not available yet.", FEEDBACK_DISPLAY_SEC)
		return
	end
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

-- the action word under each slot (2026-09-25): what the tool does, not
-- what it is, since the picture already says that
local CAPTION_BY_TOOL: { [number]: string } = {
	[Enums.ToolKind.PICK_AXE] = "Mine",
	[Enums.ToolKind.WEAPON] = "Shoot",
	[Enums.ToolKind.TORCH] = "Light",
	[Enums.ToolKind.DYNAMITE] = "Blast",
	[Enums.ToolKind.HAMMER] = "Repair",
}

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
		-- the weapon slot is named and pictured for what is carried ("RIFLE")
		local publicName = Enums.getPublicName(Enums.ToolKind, tool)
		local imageId = Icons.TOOL[tool]
		local weaponKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND)
		if tool == Enums.ToolKind.WEAPON and typeof(weaponKind) == "number" and Enums.isValidValue(Enums.WeaponKind, weaponKind) then
			publicName = Enums.getPublicName(Enums.WeaponKind, weaponKind)
			imageId = Icons.WEAPON[weaponKind]
		end
		-- the gadget slot is pictured and captioned for the class's gadget
		-- ("AUTO TURRET" under the square, decided 2026-10-19)
		if tool == Enums.ToolKind.GADGET and Enums.isValidValue(Enums.GadgetKind, self.gadgetKind) then
			publicName = Enums.getPublicName(Enums.GadgetKind, self.gadgetKind)
			imageId = Icons.GADGET[self.gadgetKind]
			-- the Remote Charge's slot is the detonator once its mine is planted (2026-10-20)
			if self.gadgetVariant == Constants.REMOTE_CHARGE_DETONATOR_VARIANT then
				publicName = Constants.REMOTE_CHARGE_DETONATOR_NAME
				imageId = Icons.GADGET_DETONATOR
			end
		end
		local hasImage = not Icons.isPlaceholder(imageId)
		local icon = frame:FindFirstChild(Constants.TOOL_SLOT_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = if hasImage then imageId :: string else ""
		end
		local label = frame:FindFirstChild(Constants.TOOL_SLOT_LABEL)
		if label and label:IsA("TextLabel") then
			(label :: TextLabel).Text = UiStyle.formatTitle(publicName or "?")
			-- the name only stands in while there is no picture
			label.Visible = not hasImage
		end
		local keyLabel = frame:FindFirstChild(Constants.TOOL_SLOT_KEY_LABEL)
		if keyLabel and keyLabel:IsA("TextLabel") then
			(keyLabel :: TextLabel).Text = tostring(index)
			keyLabel.Visible = UserInputService.KeyboardEnabled
		end
		local captionLabel = frame:FindFirstChild(Constants.TOOL_SLOT_CAPTION_LABEL)
		if captionLabel and captionLabel:IsA("TextLabel") then
			(captionLabel :: TextLabel).Text = UiStyle.formatTitle(CAPTION_BY_TOOL[tool] or publicName or "?")
		end
		frame.Activated:Connect(
			function()
				self:toggleTool(tool)
			end
		)
		frame.Parent = slotsFrame
		table.insert(self.slotViews, { tool = tool, frame = frame })
	end
	self:renderCounts()
	self:renderEquipped()
	self:renderStim()
end

-- the share of the gadget slot's sheet still showing: the whole of it
-- for a lost turret or a spent Stim Shot, the Remote Charge's cooldown
-- left as a share of its length (the sheet is anchored to the slot's
-- bottom, so it drains from the top down)
function ClientToolBarManager:getLostShare(tool: number): number
	if tool == Enums.ToolKind.GADGET and COOLDOWN_SEC_ATTRIBUTE_BY_GADGET[self.gadgetKind] then
		return math.clamp(self:getGadgetSecondsLeft() / math.max(self.cooldownSecByGadget[self.gadgetKind] or 1, 1e-3), 0, 1)
	end
	if tool == Enums.ToolKind.DYNAMITE and self.dynamiteReadyTime > 0 then
		return math.clamp(self:getDynamiteSecondsLeft() / math.max(self.dynamiteRespawnSec, 1e-3), 0, 1)
	end
	return 1
end

-- the grey sheet covers the gadget slot while its gadget is lost or cooling
function ClientToolBarManager:renderLost()
	for _, view in self.slotViews do
		local overlay = view.frame:FindFirstChild(Constants.TOOL_SLOT_COOLDOWN_OVERLAY)
		if not overlay or not overlay:IsA("Frame") then
			continue
		end
		overlay.Visible = self:isGadgetLost(view.tool)
		overlay.Size = UDim2.fromScale(1, self:getLostShare(view.tool))
	end
end

function ClientToolBarManager:renderCounts()
	for _, view in self.slotViews do
		local countLabel = view.frame:FindFirstChild(Constants.TOOL_SLOT_COUNT_LABEL)
		if not countLabel or not countLabel:IsA("TextLabel") then
			continue
		end
		local count = self.countByTool[view.tool]
		if MiningRules.isConsumable(view.tool) and count then
			countLabel.Text = `x{count}`
			countLabel.Visible = true
		else
			countLabel.Visible = false
		end
	end
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

function ClientToolBarManager:setHidden(isHidden: boolean)
	self.isHidden = isHidden
	local slotsFrame = self.slotsFrame
	if slotsFrame then
		slotsFrame.Visible = not isHidden
	end
end

function ClientToolBarManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or self.isHidden or ClientOverlayManager:isOverlayActive() then
		return
	end
	-- at a post the hands are on the post gun; the server refuses the
	-- equip as well, this keeps the bar honest
	local mannedIndex = ClientDataManager:getCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX)
	if typeof(mannedIndex) == "number" and mannedIndex ~= PostRules.NO_POST then
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

	self.slots = MiningRules.sortToolSlots(MiningRules.decodeToolSlots(ClientDataManager:getCurrentPlayerAttribute(Attributes.TOOL_SLOTS)))
	self.countByTool = MiningRules.decodeToolCounts(ClientDataManager:getCurrentPlayerAttribute(Attributes.TOOL_COUNTS))
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	self.equipped = if typeof(equipped) == "number" then equipped else MiningRules.NO_TOOL
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	self.gadgetKind = if typeof(gadgetKind) == "number" then gadgetKind else Enums.GadgetKind.NONE
	self.isAutoTurretLost = ClientDataManager:getCurrentPlayerAttribute(Attributes.AUTO_TURRET_IS_LOST) == true
	self.isStimShotUsed = ClientDataManager:getCurrentPlayerAttribute(Attributes.STIM_SHOT_IS_USED) == true
	local readyTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_READY_TIME)
	self.gadgetReadyTime = if typeof(readyTime) == "number" then readyTime else 0
	for gadgetKind, attribute in COOLDOWN_SEC_ATTRIBUTE_BY_GADGET do
		local cooldownSec = ClientDataManager:getGameMetadata(attribute)
		if typeof(cooldownSec) == "number" then
			self.cooldownSecByGadget[gadgetKind] = cooldownSec
		end
	end
	local gadgetVariant = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_VARIANT)
	self.gadgetVariant = if typeof(gadgetVariant) == "string" then gadgetVariant else ""
	local dynamiteReadyTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.DYNAMITE_READY_TIME)
	self.dynamiteReadyTime = if typeof(dynamiteReadyTime) == "number" then dynamiteReadyTime else 0
	local dynamiteRespawnSec = ClientDataManager:getGameMetadata(Attributes.DYNAMITE_RESPAWN_SEC)
	self.dynamiteRespawnSec = if typeof(dynamiteRespawnSec) == "number" then dynamiteRespawnSec else self.dynamiteRespawnSec
	local effectEndTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.STIM_SHOT_EFFECT_END_TIME)
	self.stimShotEffectEndTime = if typeof(effectEndTime) == "number" then effectEndTime else 0
	self:renderSlots()

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.TOOL_SLOTS,
		function(value: any)
			self.slots = MiningRules.sortToolSlots(MiningRules.decodeToolSlots(value))
			self:renderSlots()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.TOOL_COUNTS,
		function(value: any)
			self.countByTool = MiningRules.decodeToolCounts(value)
			self:renderCounts()
			self:renderLost()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.EQUIPPED_TOOL,
		function(value: any)
			self.equipped = if typeof(value) == "number" then value else MiningRules.NO_TOOL
			self:renderEquipped()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.GADGET_KIND,
		function(value: any)
			self.gadgetKind = if typeof(value) == "number" then value else Enums.GadgetKind.NONE
			self:renderSlots()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.AUTO_TURRET_IS_LOST,
		function(value: any)
			self.isAutoTurretLost = value == true
			self:renderLost()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.GADGET_READY_TIME,
		function(value: any)
			self.gadgetReadyTime = if typeof(value) == "number" then value else 0
			self:renderStim()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DYNAMITE_READY_TIME,
		function(value: any)
			self.dynamiteReadyTime = if typeof(value) == "number" then value else 0
			self:renderStim()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.GADGET_VARIANT,
		function(value: any)
			self.gadgetVariant = if typeof(value) == "string" then value else ""
			self:renderSlots()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.STIM_SHOT_IS_USED,
		function(value: any)
			self.isStimShotUsed = value == true
			self:renderStim()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.STIM_SHOT_EFFECT_END_TIME,
		function(value: any)
			self.stimShotEffectEndTime = if typeof(value) == "number" then value else 0
			self:renderStim()
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
	self.countByTool = {}
	self.equipped = MiningRules.NO_TOOL
	self.slotViews = {}
	self.isHidden = false
	self.gadgetKind = Enums.GadgetKind.NONE
	self.isAutoTurretLost = false
	self.isStimShotUsed = false
	self.stimShotEffectEndTime = 0
	self.gadgetReadyTime = 0
	self.cooldownSecByGadget = {}
	self.gadgetVariant = ""
	self.dynamiteReadyTime = 0
	self.dynamiteRespawnSec = 90
	self.stimCountdownConnection = nil
	return self
end

return ClientToolBarManager.new()
