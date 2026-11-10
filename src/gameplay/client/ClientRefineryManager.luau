--!strict

-- The Refinery on this client (GDD "Refining Ore"): the balance rows in the
-- gameplay HUD and the payout sequence. On NotifyRefineStarted ore icons fly
-- from the player's hands into the Refinery's side for that ore (the
-- artist's IronGoldOreTarget on the left, UraniumOreTarget on the right,
-- 2026-11-09; the Funnel's Entrance attachment on an older model); as the
-- first gold or iron ore lands the machine enters its refining state (the
-- grinder spikes spin, the grind loop plays 3D, the SmokeParticle emits,
-- the RefiningGlow shows and its light pulses) on every client, whoever
-- refines, until NotifyRefineCompleted, when refined icons fly from the
-- same side to the player and the HUD row bumps and updates as each one
-- lands. The uranium tube's fill grows with the crew's share of the
-- uranium target. Numbers come from the CurrentPlayer and GameMetadata
-- attributes RefineryManager writes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local TweenService = game:GetService("TweenService")

local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)

-- the gap between the balance rows once the crew headings are gone
local SOLO_BALANCES_PADDING = UDim.new(0.04, 0)

local ClientRefineryManager = {}
ClientRefineryManager.__index = ClientRefineryManager

type Row = {
	frame: Frame,
	valueLabel: TextLabel?,
	-- the value shown while icons are in flight; nil shows the attribute
	heldValue: number?,
	flightsInProgress: number,
}

export type ClientRefineryManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		-- the refining ring drawn around the camp's Refinery, local only
		ring: Model?,
		rowByResource: { [number]: Row },
		-- the Balances box, kept so a solo run can drop its crew headings
		balancesFrame: Instance?,
		hasRemovedCrewHeadings: boolean,
		-- the grinder while it runs: the spin's Heartbeat connection, the
		-- 3D grind loop on the Funnel, and the server time it gives up
		-- should the completion never come; all nil while the Refinery is idle
		spinConnection: RBXScriptConnection?,
		grindPlayer: AudioPlayer?,
		grindUntil: number?,
		-- the players whose gold or iron refine is grinding now: the
		-- Refinery takes the whole crew at once (2026-11-09), so the
		-- machine stops only when the last of them is paid out
		grindingUserIds: { [number]: boolean },
		hasWarnedNoSpikes: boolean,
		-- the artist's refining state: whether it is shown, and the
		-- RefiningLight's pulse while it is
		isRefiningShown: boolean,
		refiningLightPulse: Tween?,
		-- the uranium tube fill's growth in flight
		tubeFillTween: Tween?,
		-- the uranium row's green pulse while the quota is met and the
		-- rescue not yet called (designer, 2026-10-27)
		uraniumPulse: Tween?,
	},
	ClientRefineryManager
))

-- one beat of the pulse, there and back
local URANIUM_PULSE_SEC = 0.6

local ORE_ENTRY_SHAPE = {
	resource = { type = "enum", name = "RawResource" },
	amount = "positiveInteger",
}
local REFINED_ENTRY_SHAPE = {
	resource = { type = "enum", name = "RefinedResource" },
	amount = "positiveInteger",
}

-- a user id is any whole number (Studio's local test players have negative ones)
local NOTIFY_REFINE_STARTED_SHAPE = {
	userId = "integer",
	ore = { type = "array", elementType = ORE_ENTRY_SHAPE },
	durationSec = "positiveNumber",
}
local NOTIFY_REFINE_COMPLETED_SHAPE = {
	userId = "integer",
	refined = { type = "array", elementType = REFINED_ENTRY_SHAPE },
}

-- fallback disc colours for any resource whose Icons entry is still the placeholder
local COLOR_BY_RAW: { [number]: Color3 } = {
	[Enums.RawResource.IRON_ORE] = Color3.fromRGB(120, 125, 135),
	[Enums.RawResource.GOLD_ORE] = Color3.fromRGB(200, 160, 40),
	[Enums.RawResource.URANIUM_ORE] = Color3.fromRGB(90, 200, 70),
}
local COLOR_BY_REFINED: { [number]: Color3 } = {
	[Enums.RefinedResource.IRON_BAR] = Color3.fromRGB(160, 165, 175),
	[Enums.RefinedResource.GOLD_BAR] = Color3.fromRGB(240, 200, 60),
	[Enums.RefinedResource.URANIUM] = Color3.fromRGB(120, 240, 90),
}
-- the refining ring: flat Neon segments on the ground around the Refinery
local RING_NAME = "RefineRing"
local RING_SEGMENTS = 48
local RING_THICKNESS_STUDS = 0.5
local RING_HEIGHT_STUDS = 0.1
local RING_LIFT_STUDS = 0.15
-- how far above and below a ring point the ground is looked for
local RING_GROUND_PROBE_STUDS = 20
-- the ring shows only while the player carries ore to refine (decided
-- 2026-10-02): it fades in as the first ore lands in the backpack and
-- fades out once the Refinery has pulled the last of it
local RING_FADE_SEC = 0.6
local BACKPACK_ORE_ATTRIBUTES = {
	Attributes.BACKPACK_IRON_ORE,
	Attributes.BACKPACK_GOLD_ORE,
	Attributes.BACKPACK_URANIUM_ORE,
}
local RING_COLOR = Color3.fromRGB(245, 200, 80)
local RING_TRANSPARENCY = 0.3
local WAIT_FOR_CAMP_SEC = 30

local ROW_NAME_BY_REFINED: { [number]: string } = {
	[Enums.RefinedResource.IRON_BAR] = Constants.HUD_BALANCE_IRON_ROW,
	[Enums.RefinedResource.GOLD_BAR] = Constants.HUD_BALANCE_GOLD_ROW,
	[Enums.RefinedResource.URANIUM] = Constants.HUD_BALANCE_URANIUM_ROW,
}

-- icons per resource per refine, so a full backpack does not spawn fifty
local MAX_ICONS_PER_RESOURCE = 6
local ICON_STAGGER_SEC = 0.08
-- world flights start and end this far above the character's root (0: at
-- the waist, a stud lower than first tried, which in first person put the
-- icon right in front of the camera, 2026-09-29)
local HANDS_LIFT_STUDS = 0
-- how fast each grinder roller turns about its own long axis while a
-- refine runs; the two rollers turn against each other so the rock between
-- them reads as crushed, not carried
local SPIKE_SPIN_RADIANS_PER_SEC = math.rad(180)
-- the grind loop plays from the Funnel so the whole camp hears the machine
-- work: full volume this close, silent at 25 studs (decided 2026-10-09)
local GRIND_FULL_VOLUME_STUDS = 6
local GRIND_SILENT_STUDS = 25
-- the grinder stops on NotifyRefineCompleted; this much past the refine's
-- own length is the safety stop should that message never arrive
local GRIND_GRACE_SEC = 2
local URANIUM_FORMAT = "%d / %d"
-- the artist's refining state (2026-11-09): the RefiningLight rises from
-- dark to its working brightness, then pulses down to the lower one and
-- back, one beat a second; the RefiningGlow part shows with it
local REFINING_LIGHT_BRIGHTNESS = 10
local REFINING_LIGHT_PULSE_BRIGHTNESS = 5
local REFINING_LIGHT_PULSE_SEC = 0.5
local REFINING_LIGHT_FADE_SEC = 0.4
-- the uranium tube's fill is this tall on Y when the crew holds the whole
-- uranium target, a hair when it holds none (a part never scales from
-- zero); X and Z keep the artist's size, and the part stays centred on
-- TubeFillPlacement, whose lower half is buried in the base, so the top
-- rises with the share
local TUBE_FILL_FULL_SIZE_Y = 12
local TUBE_FILL_EMPTY_SIZE_Y = 0.001
local TUBE_FILL_TWEEN_SEC = 0.6
local URANIUM_GLOW_BRIGHTNESS = 2
-- which side of the Refinery each resource goes in and comes out
local ORE_TARGET_BY_RAW: { [number]: string } = {
	[Enums.RawResource.IRON_ORE] = Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT,
	[Enums.RawResource.GOLD_ORE] = Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT,
	[Enums.RawResource.URANIUM_ORE] = Constants.REFINERY_URANIUM_ORE_TARGET_ATTACHMENT,
}
local ORE_TARGET_BY_REFINED: { [number]: string } = {
	[Enums.RefinedResource.IRON_BAR] = Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT,
	[Enums.RefinedResource.GOLD_BAR] = Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT,
	[Enums.RefinedResource.URANIUM] = Constants.REFINERY_URANIUM_ORE_TARGET_ATTACHMENT,
}
-- the ores whose refine runs the grinder and the refining state; uranium
-- only drops into its tube (artist, 2026-11-09)
local GRINDER_RAW_RESOURCES: { [number]: boolean } = {
	[Enums.RawResource.IRON_ORE] = true,
	[Enums.RawResource.GOLD_ORE] = true,
}

local function readNumber(value: any): number
	return if typeof(value) == "number" then value else 0
end

local function iconCount(amount: number): number
	return math.clamp(amount, 1, MAX_ICONS_PER_RESOURCE)
end

local function hasGrinderOre(entries: { { resource: number, amount: number } }): boolean
	for _, entry in entries do
		if GRINDER_RAW_RESOURCES[entry.resource] then
			return true
		end
	end
	return false
end

function ClientRefineryManager:renderRow(resource: number)
	local row = self.rowByResource[resource]
	local label = if row then row.valueLabel else nil
	if not label then
		return
	end
	local held = (row :: Row).heldValue
	if resource == Enums.RefinedResource.IRON_BAR then
		label.Text = tostring(held or readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS)))
	elseif resource == Enums.RefinedResource.GOLD_BAR then
		label.Text = tostring(held or readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS)))
	elseif resource == Enums.RefinedResource.URANIUM then
		local total = held or readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL))
		local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET))
		label.Text = string.format(URANIUM_FORMAT, total, target)
		local isMet = target > 0 and total >= target
		local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE))
		local isCalled = runState == Enums.RunState.RESCUE_WAIT or runState == Enums.RunState.RESCUE or runState == Enums.RunState.WON
		self:setUraniumPulsing(label, isMet and not isCalled)
		if not self.uraniumPulse then
			label.TextColor3 = if isMet then UiStyle.POSITIVE_COLOR else UiStyle.TEXT_COLOR
		end
	end
end

-- the quota met pulses the row between white and green until the radio
-- is used, so nobody misses it (designer, 2026-10-27); steady green after
function ClientRefineryManager:setUraniumPulsing(label: TextLabel, isPulsing: boolean)
	local pulse = self.uraniumPulse
	if isPulsing == (pulse ~= nil) then
		return
	end
	if pulse then
		pulse:Cancel()
		self.uraniumPulse = nil
		return
	end
	label.TextColor3 = UiStyle.TEXT_COLOR
	local tween = TweenService:Create(
		label,
		TweenInfo.new(URANIUM_PULSE_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextColor3 = UiStyle.POSITIVE_COLOR }
	)
	self.uraniumPulse = tween
	tween:Play()
end

function ClientRefineryManager:render(resource: number)
	self:renderRow(resource)
end

-- attribute changes render one step later, so a NotifyRefineCompleted in
-- the same step can hold the old value before the render runs
function ClientRefineryManager:onValueChanged(resource: number)
	task.defer(
		function()
			self:render(resource)
		end
	)
end

-- where a refined resource lands: its HUD row
function ClientRefineryManager:landingTarget(resource: number): GuiObject?
	local row = self.rowByResource[resource]
	return if row then row.frame else nil
end

-- freezes a resource's shown value while iconCount icons are in flight
function ClientRefineryManager:holdValue(resource: number, value: number, iconCount: number)
	local row = self.rowByResource[resource]
	if not row then
		return
	end
	if row.heldValue == nil then
		row.heldValue = value
	end
	row.flightsInProgress += iconCount
	self:render(resource)
end

-- one icon landed: the shown value moves by its share; the last landing
-- releases the hold so the attributes show again
function ClientRefineryManager:stepHeldValue(resource: number, delta: number)
	local row = self.rowByResource[resource]
	local held = if row then row.heldValue else nil
	if not row or held == nil then
		return
	end
	row.heldValue = held + delta
	row.flightsInProgress = math.max(row.flightsInProgress - 1, 0)
	if row.flightsInProgress == 0 then
		row.heldValue = nil
	end
	self:render(resource)
end

-- true while a payout's icons are still flying to this resource's row, so
-- the shown count has not caught up with the balance yet (the tutorial
-- holds its Gold Bars lines on it, 2026-11-10)
function ClientRefineryManager:isPayoutInFlight(resource: number): boolean
	local row = self.rowByResource[resource]
	return row ~= nil and row.flightsInProgress > 0
end

-- what a row shows before a payout: the attribute already includes it
function ClientRefineryManager:valueBeforePayout(resource: number, amount: number): number
	if resource == Enums.RefinedResource.IRON_BAR then
		return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS)) - amount
	elseif resource == Enums.RefinedResource.GOLD_BAR then
		return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS)) - amount
	elseif resource == Enums.RefinedResource.URANIUM then
		return readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL)) - amount
	end
	return 0
end

-- the camp's Refinery model; nil before the camp loads or when it is
-- streamed out
function ClientRefineryManager:refineryModel(): Model?
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		return nil
	end
	return refinery
end

-- the top of the Refinery, the stand-in for a Funnel attachment the model
-- does not have; nil without a Refinery model (a flight then lands at once)
function ClientRefineryManager:refineryHopperPosition(): Vector3?
	local refinery = self:refineryModel()
	if not refinery then
		return nil
	end
	local boundsCFrame, boundsSize = refinery:GetBoundingBox()
	return boundsCFrame.Position + Vector3.new(0, boundsSize.Y / 2, 0)
end

-- one of the Funnel's attachments in the world, by name; the hopper top
-- when the model has no such attachment
function ClientRefineryManager:funnelAttachmentPosition(attachmentName: string): Vector3?
	local refinery = self:refineryModel()
	local funnel = if refinery then refinery:FindFirstChild(Constants.REFINERY_FUNNEL_PART) else nil
	local attachment = if funnel then funnel:FindFirstChild(attachmentName) else nil
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldPosition
	end
	return self:refineryHopperPosition()
end

-- a named part anywhere in the Refinery model; nil without either
function ClientRefineryManager:findRefineryPart(name: string): BasePart?
	local refinery = self:refineryModel()
	local part = if refinery then refinery:FindFirstChild(name, true) else nil
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

-- a named attachment anywhere in the Refinery model (the artist's sit on
-- the body mesh); nil without either
function ClientRefineryManager:findRefineryAttachment(name: string): Attachment?
	local refinery = self:refineryModel()
	local attachment = if refinery then refinery:FindFirstChild(name, true) else nil
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	return nil
end

-- one of the artist's ore targets in the world; an older model's Funnel
-- attachment, then the hopper top, stand in
function ClientRefineryManager:oreTargetPosition(targetName: string, funnelAttachmentName: string): Vector3?
	local attachment = self:findRefineryAttachment(targetName)
	if attachment then
		return attachment.WorldPosition
	end
	return self:funnelAttachmentPosition(funnelAttachmentName)
end

-- where this ore is tipped in: gold and iron on the left side, uranium on
-- the right
function ClientRefineryManager:refineryEntrancePosition(resource: number): Vector3?
	local targetName = ORE_TARGET_BY_RAW[resource] or Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT
	return self:oreTargetPosition(targetName, Constants.REFINERY_ENTRANCE_ATTACHMENT)
end

-- where this bar comes out: the side its ore went in
function ClientRefineryManager:refineryExitPosition(resource: number): Vector3?
	local targetName = ORE_TARGET_BY_REFINED[resource] or Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT
	return self:oreTargetPosition(targetName, Constants.REFINERY_EXIT_ATTACHMENT)
end

-- the artist's refining state on the model: the SmokeParticle emitters
-- run, the RefiningGlow shows, and its RefiningLight rises from dark then
-- pulses; off, everything goes dark and still. An instant change is the
-- idle state put on a freshly streamed model, whose authored values are
-- the working ones
function ClientRefineryManager:setRefiningShown(isShown: boolean, isInstant: boolean?)
	self.isRefiningShown = isShown
	local pulse = self.refiningLightPulse
	if pulse then
		pulse:Cancel()
		self.refiningLightPulse = nil
	end
	local smoke = self:findRefineryAttachment(Constants.REFINERY_SMOKE_ATTACHMENT)
	if smoke then
		for _, child in smoke:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = isShown
			elseif child:IsA("Sound") and isShown and not isInstant then
				-- the designer's one-shot beside the emitter plays from the
				-- top each time the smoke starts (2026-11-09)
				child.TimePosition = 0
				child:Play()
			end
		end
	end
	local glow = self:findRefineryPart(Constants.REFINERY_REFINING_GLOW_PART)
	if not glow then
		return
	end
	local transparency = if isShown then 0 else 1
	local brightness = if isShown then REFINING_LIGHT_BRIGHTNESS else 0
	local light = glow:FindFirstChild(Constants.REFINERY_REFINING_LIGHT)
	if isInstant then
		glow.Transparency = transparency
		if light and light:IsA("Light") then
			light.Brightness = brightness
		end
		return
	end
	local fadeInfo = TweenInfo.new(REFINING_LIGHT_FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(glow, fadeInfo, { Transparency = transparency }):Play()
	if not light or not light:IsA("Light") then
		return
	end
	local rise = TweenService:Create(light, fadeInfo, { Brightness = brightness })
	if isShown then
		rise.Completed:Connect(
			function(playbackState)
				if playbackState ~= Enum.PlaybackState.Completed or not self.isRefiningShown then
					return
				end
				local pulseInfo = TweenInfo.new(REFINING_LIGHT_PULSE_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				local nextPulse = TweenService:Create(light, pulseInfo, { Brightness = REFINING_LIGHT_PULSE_BRIGHTNESS })
				self.refiningLightPulse = nextPulse
				nextPulse:Play()
			end
		)
	end
	rise:Play()
end

-- the uranium tube's fill from the crew's share of the uranium target:
-- invisible and a hair tall at none, grown on Y to TUBE_FILL_FULL_SIZE_Y
-- at the whole target, its UraniumGlow lit once there is any (artist,
-- 2026-11-09). Instant for a freshly streamed model, eased as a refine
-- adds to the total
function ClientRefineryManager:renderTubeFill(isInstant: boolean)
	local fill = self:findRefineryPart(Constants.REFINERY_TUBE_FILL_PART)
	if not fill then
		return
	end
	local total = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL))
	local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET))
	local share = if target > 0 then math.clamp(total / target, 0, 1) else 0
	local sizeY = if share > 0 then math.max(TUBE_FILL_EMPTY_SIZE_Y, TUBE_FILL_FULL_SIZE_Y * share) else TUBE_FILL_EMPTY_SIZE_Y
	local size = Vector3.new(fill.Size.X, sizeY, fill.Size.Z)
	local transparency = if share > 0 then 0 else 1
	local brightness = if share > 0 then URANIUM_GLOW_BRIGHTNESS else 0
	local placement = self:findRefineryAttachment(Constants.REFINERY_TUBE_FILL_PLACEMENT_ATTACHMENT)
	if placement then
		fill.CFrame = placement.WorldCFrame
	end
	local light = fill:FindFirstChild(Constants.REFINERY_URANIUM_GLOW_LIGHT)
	local growth = self.tubeFillTween
	if growth then
		growth:Cancel()
		self.tubeFillTween = nil
	end
	if isInstant then
		fill.Size = size
		fill.Transparency = transparency
		if light and light:IsA("Light") then
			light.Brightness = brightness
		end
		return
	end
	-- visible from the first stud, so the growth is seen
	fill.Transparency = transparency
	local info = TweenInfo.new(TUBE_FILL_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(fill, info, { Size = size })
	self.tubeFillTween = tween
	tween:Play()
	if light and light:IsA("Light") then
		TweenService:Create(light, info, { Brightness = brightness }):Play()
	end
end

-- the grinder rollers the model has, in the order Constants lists them
-- (the artist's model keeps one, 2026-11-09); nil (with one warning) when
-- it has none
function ClientRefineryManager:findSpikes(): { BasePart }?
	local refinery = self:refineryModel()
	if not refinery then
		return nil
	end
	local spikes: { BasePart } = {}
	for _, name in Constants.REFINERY_SPIKE_PARTS do
		local part = refinery:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(spikes, part)
		end
	end
	if #spikes == 0 then
		if not self.hasWarnedNoSpikes then
			self.hasWarnedNoSpikes = true
			warn("ClientRefineryManager: the Refinery model has no Spikes part; the grinder will not spin")
		end
		return nil
	end
	return spikes
end

-- every frame of a grind, turn each roller about its own long (Z) axis,
-- alternating direction so neighbours counter-rotate. The parts are
-- anchored and the server never moves them, so a local CFrame holds, and
-- the gears welded to each roller turn with it
function ClientRefineryManager:stepSpin(deltaSec: number)
	local grindUntil = self.grindUntil
	if not grindUntil or workspace:GetServerTimeNow() >= grindUntil then
		self:stopGrinding()
		return
	end
	local spikes = self:findSpikes()
	if not spikes then
		self:stopGrinding()
		return
	end
	for index, spike in spikes do
		local direction = if index % 2 == 1 then 1 else -1
		spike.CFrame = spike.CFrame * CFrame.Angles(0, 0, direction * SPIKE_SPIN_RADIANS_PER_SEC * deltaSec)
	end
end

-- the rollers stop and the grind loop goes quiet together, so the sound
-- never outlives the motion
function ClientRefineryManager:stopGrinding()
	self.grindingUserIds = {}
	if self.isRefiningShown then
		self:setRefiningShown(false)
	end
	if self.spinConnection then
		self.spinConnection:Disconnect()
		self.spinConnection = nil
	end
	local grindPlayer = self.grindPlayer
	if grindPlayer then
		grindPlayer:Stop()
		local emitter = grindPlayer.Parent and grindPlayer.Parent:FindFirstChildOfClass("AudioEmitter")
		if emitter then
			emitter:Destroy()
		end
		grindPlayer:Destroy()
		self.grindPlayer = nil
	end
	self.grindUntil = nil
end

-- the machine starts working the moment the first ore drops into the
-- Funnel: the rollers turn and the grind loop plays from the Funnel itself,
-- 3D, so every player within earshot hears the same machine. A grind
-- already running is only given the later safety stop
function ClientRefineryManager:startGrinding(durationSec: number)
	local stopAt = workspace:GetServerTimeNow() + durationSec + GRIND_GRACE_SEC
	self.grindUntil = math.max(self.grindUntil or 0, stopAt)
	if self.spinConnection then
		return
	end
	self.spinConnection = RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:stepSpin(deltaSec)
		end
	)
	self:setRefiningShown(true)
	-- the loop plays from the grinder: the artist's glow under it, or an
	-- older model's Funnel
	local source = self:findRefineryPart(Constants.REFINERY_REFINING_GLOW_PART) or self:findRefineryPart(Constants.REFINERY_FUNNEL_PART)
	if source then
		self.grindPlayer = ClientSoundManager:attachLoop(source, SoundNames.Sfx.REFINERY_GRIND, GRIND_FULL_VOLUME_STUDS, GRIND_SILENT_STUDS)
	end
end

-- the machine starts as the first ore icon lands, once per refine; a
-- refine of uranium alone never runs the grinder. The caller calls it at
-- once when nothing flew
function ClientRefineryManager:startGrindingOnFirstLanding(payload: { [string]: any }): () -> ()
	local hasStarted = false
	local isGrinding = hasGrinderOre(payload.ore)
	if isGrinding then
		self.grindingUserIds[payload.userId] = true
	end
	return function()
		if hasStarted then
			return
		end
		hasStarted = true
		if isGrinding then
			self:startGrinding(payload.durationSec)
		end
	end
end

-- a refine is paid out: the machine stops once no other player's is
-- still grinding (the safety stop in stepSpin covers a completion that
-- never arrives)
function ClientRefineryManager:stopGrindingIfIdle(userId: number)
	self.grindingUserIds[userId] = nil
	if next(self.grindingUserIds) == nil then
		self:stopGrinding()
	end
end

-- a crewmate's refine, watched from outside: the same icons fly between
-- that player and the Funnel, and nothing else happens here (no HUD).
-- Either end may be streamed out for a watcher far away, and then there is
-- nothing to show. Returns whether anything flew, so the caller knows
-- whether a landing is coming
function ClientRefineryManager:flyForCrewmate(entries: { { resource: number, amount: number } }, imageByResource: { [number]: string }, colorByResource: { [number]: Color3 }, fromFor: (resource: number) -> Vector3?, toFor: (resource: number) -> Vector3?, onLanded: (() -> ())?): boolean
	local hasFlown = false
	local delaySec = 0
	for _, entry in entries do
		local from = fromFor(entry.resource)
		local to = toFor(entry.resource)
		if not from or not to then
			continue
		end
		hasFlown = true
		for _ = 1, iconCount(entry.amount) do
			ClientIconFlightManager:flyWorld(imageByResource[entry.resource], colorByResource[entry.resource] or UiStyle.TEXT_MUTED_COLOR, from, to, delaySec, onLanded)
			delaySec += ICON_STAGGER_SEC
		end
	end
	return hasFlown
end

-- where a player is (this one when no user id is given), a little above
-- the feet, for ore to leave from and bars to arrive at; nil without a
-- character
function ClientRefineryManager:characterPosition(userId: number?): Vector3?
	local player = if userId then Players:GetPlayerByUserId(userId) else Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position + Vector3.new(0, HANDS_LIFT_STUDS, 0)
end

function ClientRefineryManager:onRefineStarted(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_REFINE_STARTED_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyRefineStarted")
		return
	end
	-- the machine starts for everyone, whoever is refining, once the first
	-- ore reaches it
	local onFirstLanded = self:startGrindingOnFirstLanding(payload)
	if payload.userId ~= Players.LocalPlayer.UserId then
		local from = self:characterPosition(payload.userId)
		local hasFlown = self:flyForCrewmate(
			payload.ore,
			Icons.RAW_RESOURCE,
			COLOR_BY_RAW,
			function()
				return from
			end,
			function(resource: number)
				return self:refineryEntrancePosition(resource)
			end,
			onFirstLanded
		)
		if not hasFlown then
			onFirstLanded()
		end
		return
	end
	-- the ore leaves the player's hands and drops into the Refinery's side
	-- for it, in the world, so the camera can turn away without stranding it
	local from = self:characterPosition()
	local hasFlown = false
	-- the backpack attributes are already empty; keep showing what was in it
	-- and count down as each icon leaves
	local totalOre = 0
	local totalIcons = 0
	for _, entry in payload.ore do
		totalOre += entry.amount
		totalIcons += iconCount(entry.amount)
	end
	ClientBackpackManager:holdTotal(totalOre, totalIcons)
	local delaySec = 0
	for _, entry in payload.ore do
		local to = self:refineryEntrancePosition(entry.resource)
		local color = COLOR_BY_RAW[entry.resource] or UiStyle.TEXT_MUTED_COLOR
		local imageId = Icons.RAW_RESOURCE[entry.resource]
		local count = iconCount(entry.amount)
		local shares = ClientIconFlightManager.splitAmount(entry.amount, count)
		for index = 1, count do
			task.delay(
				delaySec,
				function()
					-- the backpack bounces as each ore leaves it, the way a
					-- balance row does as a bar arrives
					ClientBackpackManager:bumpButton()
					ClientBackpackManager:stepHeldTotal(-shares[index])
				end
			)
			if from and to then
				hasFlown = true
				ClientIconFlightManager:flyWorld(
					imageId,
					color,
					from,
					to,
					delaySec,
					function()
						-- each ore pops as it is sucked into the machine
						ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
						onFirstLanded()
					end
				)
			end
			delaySec += ICON_STAGGER_SEC
		end
	end
	if not hasFlown then
		onFirstLanded()
	end
end

function ClientRefineryManager:onRefineCompleted(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_REFINE_COMPLETED_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyRefineCompleted")
		return
	end
	-- the bars are out: the machine falls quiet and still once nobody
	-- else's ore is in it
	self:stopGrindingIfIdle(payload.userId)
	if payload.userId ~= Players.LocalPlayer.UserId then
		local to = self:characterPosition(payload.userId)
		self:flyForCrewmate(
			payload.refined,
			Icons.REFINED_RESOURCE,
			COLOR_BY_REFINED,
			function(resource: number)
				return self:refineryExitPosition(resource)
			end,
			function()
				return to
			end
		)
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_PAYOUT)
	-- the bars come out of the side their ore went in and reach the player
	-- in the world; the HUD row bumps as each one arrives
	local to = self:characterPosition()
	local delaySec = 0
	for _, entry in payload.refined do
		local resource = entry.resource
		local target = self:landingTarget(resource)
		if not target then
			continue
		end
		local from = self:refineryExitPosition(resource)
		local color = COLOR_BY_REFINED[resource] or UiStyle.TEXT_COLOR
		local imageId = Icons.REFINED_RESOURCE[resource]
		local count = iconCount(entry.amount)
		local shares = ClientIconFlightManager.splitAmount(entry.amount, count)
		self:holdValue(resource, self:valueBeforePayout(resource, entry.amount), count)
		for index = 1, count do
			local function onLanded()
				-- every bar pops, bumps its target, and adds its share
				ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
				local landedOn = self:landingTarget(resource)
				if landedOn then
					ClientIconFlightManager:bump(landedOn)
				end
				self:stepHeldValue(resource, shares[index])
			end
			if from and to then
				ClientIconFlightManager:flyWorld(imageId, color, from, to, delaySec, onLanded)
			else
				task.delay(delaySec, onLanded)
			end
			delaySec += ICON_STAGGER_SEC
		end
	end
end

function ClientRefineryManager:findHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientRefineryManager: no GameplayHud ScreenGui; run scripts/studio/build_gameplay_hud_gui.luau")
		return
	end
	self.gui = gui
	local balances = gui:FindFirstChild(Constants.HUD_BALANCES_FRAME)
	self.balancesFrame = balances
	if balances then
		for resource, rowName in ROW_NAME_BY_REFINED do
			local frame = balances:FindFirstChild(rowName)
			if not frame or not frame:IsA("Frame") then
				warn(`ClientRefineryManager: GameplayHud.Balances is missing {rowName}`)
				continue
			end
			local valueLabel = frame:FindFirstChild(Constants.HUD_BALANCE_VALUE_LABEL)
			self.rowByResource[resource] = {
				frame = frame,
				valueLabel = if valueLabel and valueLabel:IsA("TextLabel") then valueLabel else nil,
				heldValue = nil,
				flightsInProgress = 0,
			}
		end
	else
		warn("ClientRefineryManager: GameplayHud is missing Balances")
	end
end

-- the ground height under a point of the ring, found by looking straight
-- down past the Refinery and the characters; nil over a hole. The model's
-- bounding box was the ground before 2026-11-09, but the artist's model
-- stands sunk into the path and its tube fill is authored half buried, so
-- the box reaches well under the ground
function ClientRefineryManager:groundYAt(refinery: Model, location: Vector3): number?
	local excluded: { Instance } = { refinery }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	local origin = location + Vector3.new(0, RING_GROUND_PROBE_STUDS, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -2 * RING_GROUND_PROBE_STUDS, 0), params)
	return if result then result.Position.Y else nil
end

-- the refining ring on the ground around the Refinery (2026-10-01): a
-- circle of flat segments at the radius the server published, drawn once
-- the camp's Refinery streams in, redrawn for a new camp
function ClientRefineryManager:drawRing()
	if self.ring then
		self.ring:Destroy()
		self.ring = nil
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		return
	end
	local radius = readNumber(ClientDataManager:getGameMetadata(Attributes.REFINE_RADIUS_STUDS))
	if radius <= 0 then
		return
	end
	local boundsCFrame, boundsSize = refinery:GetBoundingBox()
	local fallbackGroundY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local centre = CFrame.new(boundsCFrame.Position.X, 0, boundsCFrame.Position.Z)
	local ring = Instance.new("Model")
	ring.Name = RING_NAME
	local segmentLength = 2 * math.pi * radius / RING_SEGMENTS + RING_THICKNESS_STUDS
	for index = 1, RING_SEGMENTS do
		local angle = (index - 0.5) / RING_SEGMENTS * 2 * math.pi
		local segment = Instance.new("Part")
		segment.Name = "Segment"
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = RING_COLOR
		segment.Transparency = 1
		segment.Size = Vector3.new(segmentLength, RING_HEIGHT_STUDS, RING_THICKNESS_STUDS)
		-- each segment sits on the circle, turned to run along it, at the
		-- ground found under it
		local flat = centre * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius)
		local groundY = self:groundYAt(refinery, flat.Position) or fallbackGroundY
		segment.CFrame = flat + Vector3.new(0, groundY + RING_LIFT_STUDS, 0)
		segment.Parent = ring
	end
	ring.Parent = refinery
	self.ring = ring
	self:refreshRingVisible(true)
end

function ClientRefineryManager:isCarryingOre(): boolean
	for _, attribute in BACKPACK_ORE_ATTRIBUTES do
		if readNumber(ClientDataManager:getCurrentPlayerAttribute(attribute)) > 0 then
			return true
		end
	end
	return false
end

-- the ring fades to its colour while ore is carried and away when none
-- is; a fresh ring takes its state at once
function ClientRefineryManager:refreshRingVisible(isInstant: boolean)
	local ring = self.ring
	if not ring then
		return
	end
	local transparency = if self:isCarryingOre() then RING_TRANSPARENCY else 1
	for _, segment in ring:GetChildren() do
		if not segment:IsA("BasePart") then
			continue
		end
		if isInstant then
			segment.Transparency = transparency
		else
			TweenService:Create(segment, TweenInfo.new(RING_FADE_SEC), { Transparency = transparency }):Play()
		end
	end
end

-- draws the ring for the camp in Workspace now and for every camp after it
function ClientRefineryManager:watchRefinery()
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, WAIT_FOR_CAMP_SEC)
	local refinery = if camp then camp:WaitForChild(Constants.CAMP_REFINERY_MODEL, WAIT_FOR_CAMP_SEC) else nil
	if not refinery then
		warn("ClientRefineryManager: no Camp.Refinery model to draw the refining ring around")
		return
	end
	self:drawRing()
	-- the artist authored the model in its working state; a fresh one
	-- starts idle, with the tube at the crew's share
	self:setRefiningShown(false, true)
	self:renderTubeFill(true)
	refinery.AncestryChanged:Connect(
		function()
			if not refinery:IsDescendantOf(workspace) then
				self.ring = nil
				task.spawn(
					function()
						self:watchRefinery()
					end
				)
			end
		end
	)
end

-- the Balances box's three text labels (YOUR RESOURCES, CREW RESOURCES,
-- and the spacer) are for a crew: a solo run destroys them and closes the
-- rows up to SOLO_BALANCES_PADDING once the run's group flag says there is
-- nobody else (designer, 2026-10-29). Only an explicit false counts, since
-- the flag is unset until the server has counted
function ClientRefineryManager:removeCrewHeadingsIfSolo(isGroup: any)
	local balances = self.balancesFrame
	if isGroup ~= false or self.hasRemovedCrewHeadings or not balances then
		return
	end
	self.hasRemovedCrewHeadings = true
	for _, child in balances:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		elseif child:IsA("UIListLayout") then
			child.Padding = SOLO_BALANCES_PADDING
		end
	end
end

function ClientRefineryManager:init()
	self:findHud()
	self:removeCrewHeadingsIfSolo(ClientDataManager:getGameMetadata(Attributes.RUN_IS_GROUP))
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_IS_GROUP,
		function(value: any)
			self:removeCrewHeadingsIfSolo(value)
		end
	)
	task.spawn(
		function()
			self:watchRefinery()
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.REFINE_RADIUS_STUDS,
		function()
			self:drawRing()
		end
	)
	for _, attribute in BACKPACK_ORE_ATTRIBUTES do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:refreshRingVisible(false)
			end
		)
	end

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.BALANCE_IRON_BARS,
		function()
			self:onValueChanged(Enums.RefinedResource.IRON_BAR)
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.BALANCE_GOLD_BARS,
		function()
			self:onValueChanged(Enums.RefinedResource.GOLD_BAR)
		end
	)
	for _, key in { Attributes.URANIUM_TOTAL, Attributes.URANIUM_TARGET, Attributes.RUN_STATE } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:onValueChanged(Enums.RefinedResource.URANIUM)
			end
		)
	end
	for _, key in { Attributes.URANIUM_TOTAL, Attributes.URANIUM_TARGET } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:renderTubeFill(false)
			end
		)
	end
	for _, resource in Enums.getAllValues(Enums.RefinedResource) do
		self:onValueChanged(resource)
	end

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_REFINE_STARTED,
		function(payload: any)
			self:onRefineStarted(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_REFINE_COMPLETED,
		function(payload: any)
			self:onRefineCompleted(payload)
		end
	)
end

function ClientRefineryManager.new(): ClientRefineryManager
	local self = setmetatable({}, ClientRefineryManager) :: ClientRefineryManager
	self.gui = nil
	self.ring = nil
	self.rowByResource = {}
	self.balancesFrame = nil
	self.hasRemovedCrewHeadings = false
	self.spinConnection = nil
	self.grindPlayer = nil
	self.grindUntil = nil
	self.grindingUserIds = {}
	self.hasWarnedNoSpikes = false
	self.isRefiningShown = false
	self.refiningLightPulse = nil
	self.tubeFillTween = nil
	self.uraniumPulse = nil
	return self
end

return ClientRefineryManager.new()
