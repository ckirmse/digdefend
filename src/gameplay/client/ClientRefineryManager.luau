--!strict

-- The Refinery on this client (GDD "Refining Ore"): the balance rows and
-- the Camp Level bar in the gameplay HUD, and the placeholder payout
-- sequence. On NotifyRefineStarted ore icons fly from the backpack button
-- into the Refinery on screen while the grind sound plays; on
-- NotifyRefineCompleted refined icons fly from the Refinery to their HUD row,
-- which bumps and updates as each one lands. Numbers come from the
-- CurrentPlayer and GameMetadata attributes RefineryManager writes.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)

local ClientRefineryManager = {}
ClientRefineryManager.__index = ClientRefineryManager

type Row = {
	frame: Frame,
	valueLabel: TextLabel?,
	basePosition: UDim2,
}

export type ClientRefineryManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		flyLayer: Frame?,
		rowByResource: { [number]: Row },
		campLevelFrame: Frame?,
		campTitleLabel: TextLabel?,
		campFill: Frame?,
		campProgressLabel: TextLabel?,
		campBasePosition: UDim2?,
		-- refined resources whose HUD value waits for an icon to land
		pendingByResource: { [number]: boolean },
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

-- placeholder icon colours until ore and bar art exists
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
local ICON_FLIGHT_SEC = 0.55
local ICON_SIZE_SCALE = 0.03
local ICON_MIN_PX = 18
local ICON_MAX_PX = 44
-- how far a landing icon nudges its row, as a fraction of the screen
local BUMP_SCALE = 0.008
-- if the payout message never comes, the held value shows anyway
local PENDING_TIMEOUT_SEC = 5
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
	if resource == Enums.RefinedResource.IRON_BAR then
		label.Text = tostring(readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS)))
	elseif resource == Enums.RefinedResource.GOLD_BAR then
		label.Text = tostring(readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_GOLD_BARS)))
	elseif resource == Enums.RefinedResource.URANIUM then
		local total = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL))
		local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET))
		label.Text = string.format(URANIUM_FORMAT, total, target)
		label.TextColor3 = if target > 0 and total >= target then UiStyle.POSITIVE_COLOR else UiStyle.TEXT_COLOR
	end
end

function ClientRefineryManager:renderCampLevel()
	local level = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL))
	local pool = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_DIAMONDS))
	local required = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_DIAMONDS_REQUIRED))
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

-- attribute changes render at once unless a payout is in flight for that
-- resource, in which case the landing icon triggers the render
function ClientRefineryManager:onValueChanged(resource: number)
	if self.pendingByResource[resource] then
		return
	end
	if resource == Enums.RefinedResource.DIAMOND then
		self:renderCampLevel()
	else
		self:renderRow(resource)
	end
end

function ClientRefineryManager:bump(frame: GuiObject, basePosition: UDim2)
	frame.Position = basePosition + UDim2.fromScale(0, -BUMP_SCALE)
	TweenService:Create(frame, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad), { Position = basePosition }):Play()
end

-- where a refined resource lands: its row, or the camp bar for Diamonds
function ClientRefineryManager:landingTarget(resource: number): (GuiObject?, UDim2?)
	if resource == Enums.RefinedResource.DIAMOND then
		return self.campLevelFrame, self.campBasePosition
	end
	local row = self.rowByResource[resource]
	return if row then row.frame else nil, if row then row.basePosition else nil
end

function ClientRefineryManager:onIconLanded(resource: number)
	self.pendingByResource[resource] = nil
	local target, basePosition = self:landingTarget(resource)
	if target and basePosition then
		self:bump(target, basePosition)
	end
	self:onValueChanged(resource)
end

function ClientRefineryManager:screenCenterOf(guiObject: GuiObject): Vector2
	return guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
end

-- the Refinery's pivot on screen; off-screen refineries fall back to the
-- screen centre so the sequence still reads
function ClientRefineryManager:refineryScreenPoint(): Vector2
	local layer = self.flyLayer
	local fallback = if layer then self:screenCenterOf(layer) else Vector2.zero
	local camera = workspace.CurrentCamera
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not camera or not refinery or not refinery:IsA("Model") then
		return fallback
	end
	local point, isOnScreen = camera:WorldToViewportPoint(refinery:GetPivot().Position)
	if not isOnScreen then
		return fallback
	end
	return Vector2.new(point.X, point.Y)
end

-- a layer-relative scale position from an absolute screen point, so icons
-- follow the GUI standard of scale everywhere
function ClientRefineryManager:toLayerScale(point: Vector2): UDim2
	local layer = self.flyLayer
	if not layer or layer.AbsoluteSize.X <= 0 or layer.AbsoluteSize.Y <= 0 then
		return UDim2.fromScale(0.5, 0.5)
	end
	local relative = point - layer.AbsolutePosition
	return UDim2.fromScale(relative.X / layer.AbsoluteSize.X, relative.Y / layer.AbsoluteSize.Y)
end

function ClientRefineryManager:flyIcon(color: Color3, from: Vector2, to: Vector2, delaySec: number, onLanded: (() -> ())?)
	local layer = self.flyLayer
	if not layer then
		if onLanded then
			onLanded()
		end
		return
	end
	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = self:toLayerScale(from)
	icon.Size = UDim2.fromScale(ICON_SIZE_SCALE, ICON_SIZE_SCALE)
	icon.BackgroundColor3 = color
	icon.BorderSizePixel = 0
	icon.ZIndex = layer.ZIndex + 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = icon
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(ICON_MIN_PX, ICON_MIN_PX)
	size.MaxSize = Vector2.new(ICON_MAX_PX, ICON_MAX_PX)
	size.Parent = icon
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = icon
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiStyle.BACKGROUND_COLOR
	stroke.Thickness = 1
	stroke.Parent = icon
	icon.Parent = layer
	task.delay(
		delaySec,
		function()
			if not icon.Parent then
				return
			end
			local tween = TweenService:Create(icon, TweenInfo.new(ICON_FLIGHT_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = self:toLayerScale(to) })
			tween.Completed:Connect(
				function()
					icon:Destroy()
					if onLanded then
						onLanded()
					end
				end
			)
			tween:Play()
		end
	)
end

function ClientRefineryManager:onRefineStarted(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_REFINE_STARTED_SHAPE)
	if not isValid then
		warn("ClientRefineryManager: malformed NotifyRefineStarted")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_GRIND)
	local layer = self.flyLayer
	local from = ClientBackpackManager:getButtonScreenCenter()
	if not from then
		-- the button is hidden without the pick axe; start from its corner
		from = if layer then layer.AbsolutePosition + layer.AbsoluteSize * Vector2.new(0.95, 0.95) else Vector2.zero
	end
	local to = self:refineryScreenPoint()
	local delaySec = 0
	for _, entry in payload.ore do
		local color = COLOR_BY_RAW[entry.resource] or UiStyle.TEXT_MUTED_COLOR
		for _ = 1, iconCount(entry.amount) do
			self:flyIcon(color, from :: Vector2, to, delaySec, nil)
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
		local count = iconCount(entry.amount)
		self.pendingByResource[resource] = true
		task.delay(
			PENDING_TIMEOUT_SEC,
			function()
				if self.pendingByResource[resource] then
					self:onIconLanded(resource)
				end
			end
		)
		for index = 1, count do
			local isLast = index == count
			self:flyIcon(
				color,
				from,
				self:screenCenterOf(target),
				delaySec,
				function()
					if isLast then
						self:onIconLanded(resource)
					else
						local landed, basePosition = self:landingTarget(resource)
						if landed and basePosition then
							self:bump(landed, basePosition)
						end
					end
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
	local flyLayer = gui:FindFirstChild(Constants.HUD_FLY_LAYER)
	self.flyLayer = if flyLayer and flyLayer:IsA("Frame") then flyLayer else nil
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
				basePosition = frame.Position,
			}
		end
	else
		warn("ClientRefineryManager: GameplayHud is missing Balances")
	end
	local campLevel = gui:FindFirstChild(Constants.HUD_CAMP_LEVEL_FRAME)
	if campLevel and campLevel:IsA("Frame") then
		self.campLevelFrame = campLevel
		self.campBasePosition = campLevel.Position
		local title = campLevel:FindFirstChild(Constants.HUD_CAMP_LEVEL_TITLE_LABEL)
		self.campTitleLabel = if title and title:IsA("TextLabel") then title else nil
		local bar = campLevel:FindFirstChild(Constants.HUD_CAMP_LEVEL_BAR)
		local fill = if bar then bar:FindFirstChild(Constants.HUD_CAMP_LEVEL_FILL) else nil
		self.campFill = if fill and fill:IsA("Frame") then fill else nil
		local progress = if bar then bar:FindFirstChild(Constants.HUD_CAMP_LEVEL_PROGRESS_LABEL) else nil
		self.campProgressLabel = if progress and progress:IsA("TextLabel") then progress else nil
	else
		warn("ClientRefineryManager: GameplayHud is missing CampLevel")
	end
end

function ClientRefineryManager:init()
	self:findHud()

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
	self.flyLayer = nil
	self.rowByResource = {}
	self.campLevelFrame = nil
	self.campTitleLabel = nil
	self.campFill = nil
	self.campProgressLabel = nil
	self.campBasePosition = nil
	self.pendingByResource = {}
	return self
end

return ClientRefineryManager.new()
