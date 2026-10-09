--!strict

-- The Refinery on this client (GDD "Refining Ore"): the balance rows in the
-- gameplay HUD and the payout sequence. On NotifyRefineStarted ore icons fly
-- from the player's hands into the Funnel's Entrance attachment; as the
-- first one lands the grinder spikes spin and the grind loop plays 3D from
-- the Funnel (on every client, whoever refines) until NotifyRefineCompleted,
-- when refined icons fly from the Funnel's Exit attachment to the player
-- and the HUD row bumps and updates as each one lands. Numbers come from
-- the CurrentPlayer and GameMetadata attributes RefineryManager writes.
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
		-- the grinder while it runs: the spin's Heartbeat connection, the
		-- 3D grind loop on the Funnel, and the server time it gives up
		-- should the completion never come; all nil while the Refinery is idle
		spinConnection: RBXScriptConnection?,
		grindPlayer: AudioPlayer?,
		grindUntil: number?,
		hasWarnedNoSpikes: boolean,
	},
	ClientRefineryManager
))

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

local function readNumber(value: any): number
	return if typeof(value) == "number" then value else 0
end

local function iconCount(amount: number): number
	return math.clamp(amount, 1, MAX_ICONS_PER_RESOURCE)
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
		label.TextColor3 = if target > 0 and total >= target then UiStyle.POSITIVE_COLOR else UiStyle.TEXT_COLOR
	end
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

-- where ore is tipped in
function ClientRefineryManager:refineryEntrancePosition(): Vector3?
	return self:funnelAttachmentPosition(Constants.REFINERY_ENTRANCE_ATTACHMENT)
end

-- where bars come out
function ClientRefineryManager:refineryExitPosition(): Vector3?
	return self:funnelAttachmentPosition(Constants.REFINERY_EXIT_ATTACHMENT)
end

-- the grinder rollers, in the order Constants lists them; nil (with one
-- warning) when the model lacks any of them
function ClientRefineryManager:findSpikes(): { BasePart }?
	local refinery = self:refineryModel()
	if not refinery then
		return nil
	end
	local spikes: { BasePart } = {}
	for _, name in Constants.REFINERY_SPIKE_PARTS do
		local part = refinery:FindFirstChild(name)
		if not part or not part:IsA("BasePart") then
			if not self.hasWarnedNoSpikes then
				self.hasWarnedNoSpikes = true
				warn(string.format("ClientRefineryManager: the Refinery model has no %s part; the grinder will not spin", name))
			end
			return nil
		end
		table.insert(spikes, part)
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
	local refinery = self:refineryModel()
	local funnel = if refinery then refinery:FindFirstChild(Constants.REFINERY_FUNNEL_PART) else nil
	if funnel and funnel:IsA("BasePart") then
		self.grindPlayer = ClientSoundManager:attachLoop(funnel, SoundNames.Sfx.REFINERY_GRIND, GRIND_FULL_VOLUME_STUDS, GRIND_SILENT_STUDS)
	end
end

-- the grinder starts as the first ore icon lands in the Funnel; with no
-- flight to wait on (either end missing) it starts at once
function ClientRefineryManager:startGrindingOnFirstLanding(durationSec: number, isFlying: boolean): (() -> ())?
	if not isFlying then
		self:startGrinding(durationSec)
		return nil
	end
	local hasStarted = false
	return function()
		if hasStarted then
			return
		end
		hasStarted = true
		self:startGrinding(durationSec)
	end
end

-- a crewmate's refine, watched from outside: the same icons fly between
-- that player and the Funnel, and nothing else happens here (no HUD).
-- Either end may be streamed out for a watcher far away, and then there is
-- nothing to show. Returns whether anything flew, so the caller knows
-- whether a landing is coming
function ClientRefineryManager:flyForCrewmate(entries: { { resource: number, amount: number } }, imageByResource: { [number]: string }, colorByResource: { [number]: Color3 }, from: Vector3?, to: Vector3?, onLanded: (() -> ())?): boolean
	if not from or not to then
		return false
	end
	local delaySec = 0
	for _, entry in entries do
		for _ = 1, iconCount(entry.amount) do
			ClientIconFlightManager:flyWorld(imageByResource[entry.resource], colorByResource[entry.resource] or UiStyle.TEXT_MUTED_COLOR, from, to, delaySec, onLanded)
			delaySec += ICON_STAGGER_SEC
		end
	end
	return true
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
	-- the grinder turns for everyone, whoever is refining, once the first
	-- ore reaches the Funnel
	if payload.userId ~= Players.LocalPlayer.UserId then
		local from = self:characterPosition(payload.userId)
		local to = self:refineryEntrancePosition()
		local onLanded = self:startGrindingOnFirstLanding(payload.durationSec, from ~= nil and to ~= nil)
		self:flyForCrewmate(payload.ore, Icons.RAW_RESOURCE, COLOR_BY_RAW, from, to, onLanded)
		return
	end
	-- the ore leaves the player's hands and drops into the Funnel's mouth,
	-- in the world, so the camera can turn away without stranding it
	local from = self:characterPosition()
	local to = self:refineryEntrancePosition()
	local onFirstLanded = self:startGrindingOnFirstLanding(payload.durationSec, from ~= nil and to ~= nil)
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
				ClientIconFlightManager:flyWorld(
					imageId,
					color,
					from,
					to,
					delaySec,
					function()
						-- each ore pops as it is sucked into the machine
						ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
						if onFirstLanded then
							onFirstLanded()
						end
					end
				)
			end
			delaySec += ICON_STAGGER_SEC
		end
	end
end

function ClientRefineryManager:onRefineCompleted(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_REFINE_COMPLETED_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyRefineCompleted")
		return
	end
	-- the bars are out: the machine falls quiet and still
	self:stopGrinding()
	if payload.userId ~= Players.LocalPlayer.UserId then
		self:flyForCrewmate(payload.refined, Icons.REFINED_RESOURCE, COLOR_BY_REFINED, self:refineryExitPosition(), self:characterPosition(payload.userId))
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_PAYOUT)
	-- the bars come out of the Funnel's exit and reach the player in the
	-- world; the HUD row bumps as each one arrives
	local from = self:refineryExitPosition()
	local to = self:characterPosition()
	local delaySec = 0
	for _, entry in payload.refined do
		local resource = entry.resource
		local target = self:landingTarget(resource)
		if not target then
			continue
		end
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
	local groundY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local centre = CFrame.new(boundsCFrame.Position.X, groundY + RING_LIFT_STUDS, boundsCFrame.Position.Z)
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
		-- each segment sits on the circle, turned to run along it
		segment.CFrame = centre * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius)
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

function ClientRefineryManager:init()
	self:findHud()
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
	for _, key in { Attributes.URANIUM_TOTAL, Attributes.URANIUM_TARGET } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:onValueChanged(Enums.RefinedResource.URANIUM)
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
	self.spinConnection = nil
	self.grindPlayer = nil
	self.grindUntil = nil
	self.hasWarnedNoSpikes = false
	return self
end

return ClientRefineryManager.new()
