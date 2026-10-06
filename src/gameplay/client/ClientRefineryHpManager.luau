--!strict

-- The Refinery HP bar on this client (GDD "Wave Cycle", M33): the night's
-- counterpart to the day clock, in the same spot top centre. It reads the
-- Refinery's HP from its structure shadow (the server writes StructureHp
-- and StructureMaxHp there) and draws it as a bar coloured like every HP
-- bar, under the compass home icon and the caption "REFINERY HP", so the
-- crew always knows how the thing that loses the run is holding up
-- wherever they are; the square behind the icon flashes red while the
-- server says the Refinery is under attack, the siren sounding once with
-- every flash so the two line up. When night falls the day
-- clock slides up off the screen and this bar follows it down from above;
-- at dawn the two swap back. Nothing here decides anything.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientHudSlide = require(script.Parent.Parent.Client.ClientHudSlide)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientRefineryHpManager = {}
ClientRefineryHpManager.__index = ClientRefineryHpManager

export type ClientRefineryHpManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		slide: ClientHudSlide.ClientHudSlide?,
		fill: Frame?,
		icon: GuiObject?,
		-- the red flash while under attack: the tween of the half-beat under
		-- way, and a count that outdates a loop once the attack ends
		alarmTween: Tween?,
		alarmGeneration: number,
		refineryShadow: BasePart?,
		shadowConnections: { RBXScriptConnection },
	},
	ClientRefineryHpManager
))

local LABEL_TEXT = "Refinery HP"
local FILL_TWEEN_SEC = 0.25
-- one under-attack flash, black to red and back, with the siren once at
-- its start (designer, 2026-10-06)
local ALARM_FLASH_SEC = 1
-- the bar waits off the top of the screen; well clear of its own height
local HIDDEN_POSITION_Y_SCALE = -0.3

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientRefineryHpManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.REFINERY_HP_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientRefineryHpManager: no RefineryHp ScreenGui; run scripts/studio/build_refinery_hp_gui.luau")
		return
	end
	self.gui = gui
	local root = gui:FindFirstChild(Constants.REFINERY_HP_ROOT_FRAME)
	if root and root:IsA("GuiObject") then
		self.slide = ClientHudSlide.new(root, UDim2.new(root.Position.X.Scale, root.Position.X.Offset, HIDDEN_POSITION_Y_SCALE, 0))
	else
		warn("ClientRefineryHpManager: the RefineryHp gui has no Root")
	end
	local bar = if root then root:FindFirstChild(Constants.REFINERY_HP_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.REFINERY_HP_FILL) else nil
	self.fill = if fill and fill:IsA("Frame") then fill else nil
	local icon = if root then root:FindFirstChild(Constants.REFINERY_HP_ICON) else nil
	self.icon = if icon and icon:IsA("GuiObject") then icon else nil
	local label = if root then root:FindFirstChild(Constants.REFINERY_HP_LABEL) else nil
	if label and label:IsA("TextLabel") then
		label.Text = UiStyle.formatTitle(LABEL_TEXT)
	end
end

-- the Refinery's health as a share; full until its shadow has arrived,
-- so the bar never alarms over missing data
function ClientRefineryHpManager:getHpShare(): number
	local shadow = self.refineryShadow
	if not shadow then
		return 1
	end
	local hp = readNumber(shadow:GetAttribute(Attributes.STRUCTURE_HP), 0)
	local maxHp = readNumber(shadow:GetAttribute(Attributes.STRUCTURE_MAX_HP), 0)
	if maxHp <= 0 then
		return 1
	end
	return math.clamp(hp / maxHp, 0, 1)
end

function ClientRefineryHpManager:render(isInstant: boolean)
	local fill = self.fill
	if not fill then
		return
	end
	local share = self:getHpShare()
	local goal = {
		Size = UDim2.fromScale(share, 1),
		BackgroundColor3 = UiStyle.HP_EMPTY_COLOR:Lerp(UiStyle.HP_FULL_COLOR, share),
	}
	if isInstant then
		fill.Size = goal.Size
		fill.BackgroundColor3 = goal.BackgroundColor3
		return
	end
	TweenService:Create(fill, TweenInfo.new(FILL_TWEEN_SEC), goal):Play()
end

function ClientRefineryHpManager:watchShadow(instance: Instance)
	if not instance:IsA("BasePart") or instance:GetAttribute(Attributes.STRUCTURE_KIND) ~= Enums.StructureKind.REFINERY then
		return
	end
	self:unwatchShadow()
	self.refineryShadow = instance
	for _, attribute in { Attributes.STRUCTURE_HP, Attributes.STRUCTURE_MAX_HP } do
		table.insert(
			self.shadowConnections,
			instance:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:render(false)
				end
			)
		)
	end
	self:render(true)
end

function ClientRefineryHpManager:unwatchShadow()
	for _, connection in self.shadowConnections do
		connection:Disconnect()
	end
	self.shadowConnections = {}
	self.refineryShadow = nil
end

-- the square behind the icon flashes red while a monster is at the
-- Refinery (the server's RefineryUnderAttack flag), and rests black otherwise
function ClientRefineryHpManager:refreshAlarm()
	local icon = self.icon
	if not icon then
		return
	end
	local isUnderAttack = ClientDataManager:getGameMetadata(Attributes.REFINERY_UNDER_ATTACK) == true
	self.alarmGeneration += 1
	local generation = self.alarmGeneration
	if self.alarmTween then
		self.alarmTween:Cancel()
		self.alarmTween = nil
	end
	if not isUnderAttack then
		icon.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
		return
	end
	-- one flash per loop, the siren at its start, so sound and colour keep
	-- step however long the attack lasts
	task.spawn(
		function()
			while self.alarmGeneration == generation do
				ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_UNDER_ATTACK)
				icon.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
				local tween = TweenService:Create(icon, TweenInfo.new(ALARM_FLASH_SEC / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), { BackgroundColor3 = UiStyle.ALERT_COLOR })
				self.alarmTween = tween
				tween:Play()
				tween.Completed:Wait()
			end
		end
	)
end

-- night brings the bar down once the day clock has gone up; dawn takes
-- it up at once, and the clock follows it down
function ClientRefineryHpManager:refreshShown(isInstant: boolean)
	local slide = self.slide
	if not slide then
		return
	end
	local isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	if isInstant then
		slide:snap(isNight)
	else
		slide:setShown(isNight, if isNight then UiStyle.HUD_SLIDE_SEC else 0)
	end
end

function ClientRefineryHpManager:init()
	self:findGui()
	local gui = self.gui
	if not gui then
		return
	end
	for _, shadow in CollectionService:GetTagged(Tags.STRUCTURE) do
		self:watchShadow(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			self:watchShadow(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			if shadow == self.refineryShadow then
				self:unwatchShadow()
				self:render(true)
			end
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.IS_NIGHT,
		function()
			self:refreshShown(false)
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.REFINERY_UNDER_ATTACK,
		function()
			self:refreshAlarm()
		end
	)
	self:refreshShown(true)
	self:render(true)
	self:refreshAlarm()
	gui.Enabled = true
end

function ClientRefineryHpManager.new(): ClientRefineryHpManager
	local self = setmetatable({}, ClientRefineryHpManager) :: ClientRefineryHpManager
	self.gui = nil
	self.slide = nil
	self.fill = nil
	self.icon = nil
	self.alarmTween = nil
	self.alarmGeneration = 0
	self.refineryShadow = nil
	self.shadowConnections = {}
	return self
end

return ClientRefineryHpManager.new()
