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
		fill: ImageLabel?,
		-- the fill is the bar's own picture over it (designer, 2026-10-29):
		-- its size never changes, the Mask gradient hides the spent part
		fillMask: UIGradient?,
		-- the share on show, tweened so the mask can follow a tween
		fillShare: NumberValue,
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
-- the mask's edge: a hair of fade so the cut reads clean at any width
local FILL_MASK_EDGE_SHARE = 0.002
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
	self.fill = if fill and fill:IsA("ImageLabel") then fill else nil
	local fillMask = if fill then fill:FindFirstChild(Constants.REFINERY_HP_FILL_MASK) else nil
	self.fillMask = if fillMask and fillMask:IsA("UIGradient") then fillMask else nil
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

-- the mask keeps the left `share` of the fill and hides the rest: a
-- gradient runs on screen whatever the label's Rotation, so 0 is the
-- bar's left end
function ClientRefineryHpManager:setFillShare(share: number)
	local fillMask = self.fillMask
	if not fillMask then
		return
	end
	if share >= 1 - FILL_MASK_EDGE_SHARE then
		fillMask.Transparency = NumberSequence.new(0)
	elseif share <= 0 then
		fillMask.Transparency = NumberSequence.new(1)
	else
		local edge = math.min(share + FILL_MASK_EDGE_SHARE, 1)
		fillMask.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(share, 0),
			NumberSequenceKeypoint.new(edge, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
end

function ClientRefineryHpManager:render(isInstant: boolean)
	local fill = self.fill
	if not fill then
		return
	end
	local share = self:getHpShare()
	local color = UiStyle.HP_EMPTY_COLOR:Lerp(UiStyle.HP_FULL_COLOR, share)
	local fillShare = self.fillShare
	if isInstant then
		fill.ImageColor3 = color
		fillShare.Value = share
		return
	end
	local tweenInfo = TweenInfo.new(FILL_TWEEN_SEC)
	TweenService:Create(fill, tweenInfo, { ImageColor3 = color }):Play()
	-- a NumberSequence cannot be tweened, so the share is, and the mask
	-- follows it through the value's Changed
	TweenService:Create(fillShare, tweenInfo, { Value = share }):Play()
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
		and not self:isRescueLanded()
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

-- once the rescue helicopter is on the pad the Refinery no longer
-- matters (the server lets it fall without losing the run), so the bar
-- and its alarm go (designer, 2026-10-28)
function ClientRefineryHpManager:isRescueLanded(): boolean
	return ClientDataManager:getGameMetadata(Attributes.RESCUE_IS_LANDED) == true
end

-- night brings the bar down once the day clock has gone up; dawn takes
-- it up at once, and the clock follows it down; the landing takes it up
-- at once too, the countdown climbing beside it
function ClientRefineryHpManager:refreshShown(isInstant: boolean)
	local slide = self.slide
	if not slide then
		return
	end
	local isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	local isShown = isNight and not self:isRescueLanded()
	if isInstant then
		slide:snap(isShown)
	else
		slide:setShown(isShown, if isShown then UiStyle.HUD_SLIDE_SEC else 0)
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
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RESCUE_IS_LANDED,
		function()
			self:refreshShown(false)
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
	self.fillMask = nil
	local fillShare = Instance.new("NumberValue")
	fillShare.Value = 1
	fillShare.Changed:Connect(
		function()
			self:setFillShare(fillShare.Value)
		end
	)
	self.fillShare = fillShare
	self.icon = nil
	self.alarmTween = nil
	self.alarmGeneration = 0
	self.refineryShadow = nil
	self.shadowConnections = {}
	return self
end

return ClientRefineryHpManager.new()
