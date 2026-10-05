--!strict

-- The Refinery on this client (GDD "Refining Ore"): the balance rows in the
-- gameplay HUD, the Camp Level billboard this client clones onto the
-- Refinery model (GDD "Camp Level"), and the placeholder payout sequence. On NotifyRefineStarted ore icons fly from the backpack button
-- into the Refinery on screen while the grind sound plays; on
-- NotifyRefineCompleted refined icons fly from the Refinery to their HUD row,
-- which bumps and updates as each one lands. Numbers come from the
-- CurrentPlayer and GameMetadata attributes RefineryManager writes.
local Players = game:GetService("Players")

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
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
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
		-- the pool shown while diamonds are in flight, and the last pool
		-- rendered, which is where a payout's icons start counting from
		campHeldPool: number?,
		campFlightsInProgress: number,
		displayedCampPool: number,
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
local NOTIFY_CAMP_LEVEL_UP_SHAPE = {
	level = "positiveInteger",
}
local CAMP_LEVEL_UP_FORMAT = "Camp upgraded to level %d"

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
	[Enums.RawResource.CRYSTAL] = Color3.fromRGB(150, 220, 255),
	[Enums.RawResource.URANIUM_ORE] = Color3.fromRGB(90, 200, 70),
}
local COLOR_BY_REFINED: { [number]: Color3 } = {
	[Enums.RefinedResource.IRON_BAR] = Color3.fromRGB(160, 165, 175),
	[Enums.RefinedResource.GOLD_BAR] = Color3.fromRGB(240, 200, 60),
	[Enums.RefinedResource.DIAMOND] = Color3.fromRGB(120, 200, 255),
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
	Attributes.BACKPACK_CRYSTAL,
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

-- the camp's Diamond pool has no display since 2026-09-29 (the Camp Level
-- billboard above the Refinery was removed and its spot given to the
-- Refinery's HP bar); the pool is still tracked so a payout counts right
function ClientRefineryManager:renderCampLevel()
	local pool = self.campHeldPool or readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_DIAMONDS))
	self.displayedCampPool = pool
end

function ClientRefineryManager:render(resource: number)
	if resource == Enums.RefinedResource.DIAMOND then
		self:renderCampLevel()
	else
		self:renderRow(resource)
	end
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

-- where a refined resource lands: its row, or the camp billboard for Diamonds
-- nil for Diamonds, which have nowhere on screen to land since the Camp
-- Level billboard went (2026-09-29); their payout skips the flight
function ClientRefineryManager:landingTarget(resource: number): GuiObject?
	if resource == Enums.RefinedResource.DIAMOND then
		return nil
	end
	local row = self.rowByResource[resource]
	return if row then row.frame else nil
end

-- freezes a resource's shown value while iconCount icons are in flight
function ClientRefineryManager:holdValue(resource: number, value: number, iconCount: number)
	if resource == Enums.RefinedResource.DIAMOND then
		if self.campHeldPool == nil then
			self.campHeldPool = value
		end
		self.campFlightsInProgress += iconCount
	else
		local row = self.rowByResource[resource]
		if not row then
			return
		end
		if row.heldValue == nil then
			row.heldValue = value
		end
		row.flightsInProgress += iconCount
	end
	self:render(resource)
end

-- one icon landed: the shown value moves by its share; the last landing
-- releases the hold so the attributes show again
function ClientRefineryManager:stepHeldValue(resource: number, delta: number)
	if resource == Enums.RefinedResource.DIAMOND then
		local held = self.campHeldPool
		if held == nil then
			return
		end
		self.campHeldPool = held + delta
		self.campFlightsInProgress = math.max(self.campFlightsInProgress - 1, 0)
		if self.campFlightsInProgress == 0 then
			self.campHeldPool = nil
		end
	else
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
	-- diamonds may have rolled the level over, so count on from what was shown
	return self.displayedCampPool
end

-- the top of the Refinery, where ore is tipped in and bars come out; nil
-- without a Refinery model (a flight then lands at once)
function ClientRefineryManager:refineryHopperPosition(): Vector3?
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		return nil
	end
	local boundsCFrame, boundsSize = refinery:GetBoundingBox()
	return boundsCFrame.Position + Vector3.new(0, boundsSize.Y / 2, 0)
end

-- a crewmate's refine, watched from outside: the same icons fly between
-- that player and the hopper, and nothing else happens here (no sound, no
-- HUD). Either end may be streamed out for a watcher far away, and then
-- there is nothing to show
function ClientRefineryManager:flyForCrewmate(entries: { { resource: number, amount: number } }, imageByResource: { [number]: string }, colorByResource: { [number]: Color3 }, from: Vector3?, to: Vector3?)
	if not from or not to then
		return
	end
	local delaySec = 0
	for _, entry in entries do
		for _ = 1, iconCount(entry.amount) do
			ClientIconFlightManager:flyWorld(imageByResource[entry.resource], colorByResource[entry.resource] or UiStyle.TEXT_MUTED_COLOR, from, to, delaySec, nil)
			delaySec += ICON_STAGGER_SEC
		end
	end
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
	if payload.userId ~= Players.LocalPlayer.UserId then
		self:flyForCrewmate(payload.ore, Icons.RAW_RESOURCE, COLOR_BY_RAW, self:characterPosition(payload.userId), self:refineryHopperPosition())
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_GRIND)
	-- the ore leaves the player's hands and drops into the hopper, in the
	-- world, so the camera can turn away without stranding it
	local from = self:characterPosition()
	local to = self:refineryHopperPosition()
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
	if payload.userId ~= Players.LocalPlayer.UserId then
		self:flyForCrewmate(payload.refined, Icons.REFINED_RESOURCE, COLOR_BY_REFINED, self:refineryHopperPosition(), self:characterPosition(payload.userId))
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_PAYOUT)
	-- the bars come out of the hopper and reach the player in the world;
	-- the HUD row bumps as each one arrives
	local from = self:refineryHopperPosition()
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

-- the level-up beat (GDD "Camp Level", decided 2026-09-16): a notification
-- and a sound, nothing to dismiss; the billboard rolls over on its own
-- from the attributes
function ClientRefineryManager:onCampLevelUp(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_CAMP_LEVEL_UP_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyCampLevelUp")
		return
	end
	ClientPlayerFeedbackManager:announceLocal(string.format(CAMP_LEVEL_UP_FORMAT, payload.level))
	ClientSoundManager:playSfx(SoundNames.Sfx.CAMP_LEVEL_UP)
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
	for _, key in { Attributes.CAMP_LEVEL, Attributes.CAMP_DIAMONDS, Attributes.CAMP_DIAMONDS_REQUIRED } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:onValueChanged(Enums.RefinedResource.DIAMOND)
			end
		)
	end
	for _, resource in Enums.getAllValues(Enums.RefinedResource) do
		self:onValueChanged(resource)
	end

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_CAMP_LEVEL_UP,
		function(payload: any)
			self:onCampLevelUp(payload)
		end
	)
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
	self.campHeldPool = nil
	self.campFlightsInProgress = 0
	self.displayedCampPool = 0
	return self
end

return ClientRefineryManager.new()
