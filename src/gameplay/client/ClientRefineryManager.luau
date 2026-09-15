--!strict

-- The Refinery on this client (GDD "Refining Ore"): the balance rows in the
-- gameplay HUD, the Camp Level billboard this client clones onto the
-- Refinery model (GDD "Camp Level"), and the placeholder payout sequence. On NotifyRefineStarted ore icons fly from the backpack button
-- into the Refinery on screen while the grind sound plays; on
-- NotifyRefineCompleted refined icons fly from the Refinery to their HUD row,
-- which bumps and updates as each one lands. Numbers come from the
-- CurrentPlayer and GameMetadata attributes RefineryManager writes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
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
		rowByResource: { [number]: Row },
		campBillboard: BillboardGui?,
		campLevelFrame: Frame?,
		campTitleLabel: TextLabel?,
		campFill: Frame?,
		campProgressLabel: TextLabel?,
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
local NOTIFY_REFINE_STARTED_SHAPE = {
	ore = { type = "array", elementType = ORE_ENTRY_SHAPE },
	durationSec = "positiveNumber",
}
local NOTIFY_REFINE_COMPLETED_SHAPE = {
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
local ROW_NAME_BY_REFINED: { [number]: string } = {
	[Enums.RefinedResource.IRON_BAR] = Constants.HUD_BALANCE_IRON_ROW,
	[Enums.RefinedResource.GOLD_BAR] = Constants.HUD_BALANCE_GOLD_ROW,
	[Enums.RefinedResource.URANIUM] = Constants.HUD_BALANCE_URANIUM_ROW,
}

-- icons per resource per refine, so a full backpack does not spawn fifty
local MAX_ICONS_PER_RESOURCE = 6
local ICON_STAGGER_SEC = 0.08
local URANIUM_FORMAT = "%d / %d"
local PROGRESS_FORMAT = "%d / %d"
local CAMP_LEVEL_FORMAT = "Camp Level %d"

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

function ClientRefineryManager:renderCampLevel()
	local level = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL))
	local pool = self.campHeldPool or readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_DIAMONDS))
	local required = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_DIAMONDS_REQUIRED))
	self.displayedCampPool = pool
	local title = self.campTitleLabel
	if title then
		title.Text = UiStyle.formatTitle(string.format(CAMP_LEVEL_FORMAT, level))
	end
	local progressLabel = self.campProgressLabel
	if progressLabel then
		progressLabel.Text = if required > 0 then string.format(PROGRESS_FORMAT, pool, required) else "MAX"
	end
	local fill = self.campFill
	if fill then
		local fraction = if required > 0 then math.clamp(pool / required, 0, 1) else 1
		TweenService:Create(fill, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) }):Play()
	end
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
function ClientRefineryManager:landingTarget(resource: number): GuiObject?
	if resource == Enums.RefinedResource.DIAMOND then
		return self.campLevelFrame
	end
	local row = self.rowByResource[resource]
	return if row then row.frame else nil
end

-- the screen point a resource's icons aim at: a HUD row's centre, or the
-- billboard's world position for Diamonds (a BillboardGui's descendants
-- report positions in billboard space, not screen space)
function ClientRefineryManager:landingScreenPoint(resource: number, target: GuiObject): Vector2
	if resource == Enums.RefinedResource.DIAMOND then
		local billboard = self.campBillboard
		local adornee = if billboard then billboard.Adornee else nil
		if adornee and adornee:IsA("BasePart") then
			local point = ClientIconFlightManager:worldToScreen(adornee.Position + (billboard :: BillboardGui).StudsOffsetWorldSpace)
			if point then
				return point
			end
		end
		return self:refineryScreenPoint()
	end
	return ClientIconFlightManager:screenCenterOf(target)
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

-- the Refinery's pivot on screen; off-screen refineries fall back to the
-- screen centre so the sequence still reads
function ClientRefineryManager:refineryScreenPoint(): Vector2
	local layer = ClientIconFlightManager:getLayer()
	local fallback = if layer then ClientIconFlightManager:screenCenterOf(layer) else Vector2.zero
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		return fallback
	end
	return ClientIconFlightManager:worldToScreen(refinery:GetPivot().Position) or fallback
end

function ClientRefineryManager:onRefineStarted(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_REFINE_STARTED_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyRefineStarted")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_GRIND)
	local layer = ClientIconFlightManager:getLayer()
	local from = ClientBackpackManager:getButtonScreenCenter()
	if not from then
		-- the button is hidden without the pick axe; start from its corner
		from = if layer then layer.AbsolutePosition + layer.AbsoluteSize * Vector2.new(0.95, 0.95) else Vector2.zero
	end
	local to = self:refineryScreenPoint()
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
					ClientBackpackManager:stepHeldTotal(-shares[index])
				end
			)
			ClientIconFlightManager:fly(
				imageId,
				color,
				from :: Vector2,
				to,
				delaySec,
				function()
					-- each ore pops as it is sucked into the machine
					ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
				end
			)
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
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_PAYOUT)
	local from = self:refineryScreenPoint()
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
			ClientIconFlightManager:fly(
				imageId,
				color,
				from,
				self:landingScreenPoint(resource, target),
				delaySec,
				function()
					-- every bar pops, bumps its target, and adds its share
					ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
					local landedOn = self:landingTarget(resource)
					if landedOn then
						ClientIconFlightManager:bump(landedOn)
					end
					self:stepHeldValue(resource, shares[index])
				end
			)
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

-- clones the Camp Level billboard template above the Refinery. Local only:
-- the billboard lives in this player's PlayerGui and adorns a Refinery part,
-- so the server never holds a GUI. The camp is cloned at run start, before
-- any client starts, but a slow join still waits for it
function ClientRefineryManager:attachCampBillboard()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.CAMP_LEVEL_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn("ClientRefineryManager: no CampLevel BillboardGui under GameAssets.Gui; run scripts/studio/build_camp_level_billboard.luau")
		return
	end
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, 30)
	local refinery = if camp then camp:WaitForChild(Constants.CAMP_REFINERY_MODEL, 30) else nil
	if not refinery or not refinery:IsA("Model") then
		warn("ClientRefineryManager: no Camp.Refinery model to hang the Camp Level billboard on")
		return
	end
	local adornee = refinery.PrimaryPart or refinery:FindFirstChildWhichIsA("BasePart")
	if not adornee then
		warn("ClientRefineryManager: the Refinery model has no parts")
		return
	end
	local boundsCFrame, boundsSize = refinery:GetBoundingBox()
	local billboard = template:Clone()
	billboard.Adornee = adornee
	-- float above the model's top, whichever part is adorned
	billboard.StudsOffsetWorldSpace = boundsCFrame.Position + Vector3.new(0, boundsSize.Y / 2 + Constants.CAMP_LEVEL_BILLBOARD_LIFT_STUDS, 0) - adornee.Position
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.campBillboard = billboard
	local root = billboard:FindFirstChild(Constants.CAMP_LEVEL_ROOT_FRAME)
	if root and root:IsA("Frame") then
		self.campLevelFrame = root
		local title = root:FindFirstChild(Constants.CAMP_LEVEL_TITLE_LABEL)
		self.campTitleLabel = if title and title:IsA("TextLabel") then title else nil
		local bar = root:FindFirstChild(Constants.CAMP_LEVEL_BAR)
		local fill = if bar then bar:FindFirstChild(Constants.CAMP_LEVEL_FILL) else nil
		self.campFill = if fill and fill:IsA("Frame") then fill else nil
		local progress = if bar then bar:FindFirstChild(Constants.CAMP_LEVEL_PROGRESS_LABEL) else nil
		self.campProgressLabel = if progress and progress:IsA("TextLabel") then progress else nil
	else
		warn("ClientRefineryManager: the CampLevel billboard has no Root frame")
	end
	self:renderCampLevel()
end

function ClientRefineryManager:init()
	self:findHud()
	self:attachCampBillboard()

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
	self.rowByResource = {}
	self.campBillboard = nil
	self.campLevelFrame = nil
	self.campTitleLabel = nil
	self.campFill = nil
	self.campProgressLabel = nil
	self.campHeldPool = nil
	self.campFlightsInProgress = 0
	self.displayedCampPool = 0
	return self
end

return ClientRefineryManager.new()
