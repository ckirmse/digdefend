--!strict

-- The Camp Map on this client (GDD "HUD", M33): a square top right that
-- slides in from the right edge at night and out again at dawn, drawing
-- the camp from above so the crew can see which
-- walls are weak and where everyone stands. Every wall, the gate, and the
-- Refinery is a structure shadow (Tags.STRUCTURE) carrying its HP, max HP,
-- destroyed flag, and the box it stood in when whole; a clone of the
-- designer's StructureTemplate is laid out from that box through
-- CampMapRules (the map is fixed north-up, the top toward the gate, where
-- the monsters come from) and coloured by its health band, black with an
-- unturned red X over it once it is rubble; a thin wall is
-- drawn no thinner than a readable stripe. Crewmates are dots in their compass
-- colours (the local player ringed in white) from the compass positions
-- the server publishes, or the live character when it is loaded here;
-- monsters are smaller red dots from the positions the monster manager
-- already draws. Nothing here decides anything.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CampMapRules = require("@game/ReplicatedStorage/Shared/CampMapRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientHudSlide = require(script.Parent.Parent.Client.ClientHudSlide)
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)

local ClientCampMapManager = {}
ClientCampMapManager.__index = ClientCampMapManager

type StructureView = {
	shadow: BasePart,
	frame: GuiObject,
	destroyedMark: GuiObject?,
	connections: { RBXScriptConnection },
}

export type ClientCampMapManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		root: GuiObject?,
		slide: ClientHudSlide.ClientHudSlide?,
		canvas: GuiObject?,
		structureTemplate: GuiObject?,
		destroyedMarkTemplate: GuiObject?,
		-- the authored REFINERY word, placed under the Refinery's box
		refineryLabel: TextLabel?,
		playerDotTemplate: GuiObject?,
		monsterDotTemplate: GuiObject?,
		viewsByShadow: { [BasePart]: StructureView },
		-- the camp's frame and fit, rebuilt when a structure comes or goes
		frame: CampMapRules.Frame?,
		layout: CampMapRules.Layout?,
		isLayoutDirty: boolean,
		playerDotByUserId: { [number]: GuiObject },
		-- a pool of monster dots, the first `monsterDotsShown` visible
		monsterDots: { GuiObject },
		monsterDotsShown: number,
		sinceStepSec: number,
	},
	ClientCampMapManager
))

-- the camp fills the square to within this margin on each side: zoomed in
-- as far as it goes while every wall still fits (designer, 2026-10-06)
local MARGIN_SHARE = 0.04
-- the dots move this often; the structures redraw as their attributes change
local STEP_INTERVAL_SEC = 0.1
-- more monsters than this are not drawn; the nearest hundred-odd dots say enough
local MAX_MONSTER_DOTS = 150
-- a structure is drawn at least this share of the square on each side, so
-- a wall's colour reads as a stripe and not a hairline on a phone
local MIN_STRUCTURE_SIDE_SHARE = 0.045
-- the map waits off the right edge of the screen by day; clear of its own width
local HIDDEN_POSITION_X_SCALE = 1.6

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function isStructureShadow(instance: Instance): boolean
	return instance:IsA("BasePart") and instance:GetAttribute(Attributes.STRUCTURE_KIND) ~= nil
end

function ClientCampMapManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.CAMP_MAP_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientCampMapManager: no CampMap ScreenGui; run scripts/studio/build_camp_map_gui.luau")
		return
	end
	self.gui = gui
	local root = gui:FindFirstChild(Constants.CAMP_MAP_ROOT_FRAME)
	self.root = if root and root:IsA("GuiObject") then root else nil
	if self.root then
		self.slide = ClientHudSlide.new(self.root, UDim2.new(HIDDEN_POSITION_X_SCALE, 0, self.root.Position.Y.Scale, self.root.Position.Y.Offset))
	end
	local canvas = if root then root:FindFirstChild(Constants.CAMP_MAP_CANVAS) else nil
	self.canvas = if canvas and canvas:IsA("GuiObject") then canvas else nil
	local function findTemplate(name: string): GuiObject?
		local template = if canvas then canvas:FindFirstChild(name) else nil
		if not template or not template:IsA("GuiObject") then
			warn(`ClientCampMapManager: the CampMap Canvas has no {name}; rebuild it with scripts/studio/build_camp_map_gui.luau`)
			return nil
		end
		template.Visible = false
		return template
	end
	self.structureTemplate = findTemplate(Constants.CAMP_MAP_STRUCTURE_TEMPLATE)
	self.destroyedMarkTemplate = findTemplate(Constants.CAMP_MAP_DESTROYED_MARK_TEMPLATE)
	local refineryLabel = if canvas then canvas:FindFirstChild(Constants.CAMP_MAP_REFINERY_LABEL) else nil
	self.refineryLabel = if refineryLabel and refineryLabel:IsA("TextLabel") then refineryLabel else nil
	if not self.refineryLabel then
		warn("ClientCampMapManager: the CampMap canvas has no RefineryLabel; rerun scripts/studio/build_camp_map_gui.luau")
	end
	self.playerDotTemplate = findTemplate(Constants.CAMP_MAP_PLAYER_DOT_TEMPLATE)
	self.monsterDotTemplate = findTemplate(Constants.CAMP_MAP_MONSTER_DOT_TEMPLATE)
end

-- the map is a night instrument: it slides in as night falls and out at
-- dawn; by day the clock and the camp itself say enough
function ClientCampMapManager:refreshShown(isInstant: boolean)
	local slide = self.slide
	if not slide then
		return
	end
	local isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	if isInstant then
		slide:snap(isNight)
	else
		slide:setShown(isNight, 0)
	end
end

function ClientCampMapManager:findShadowOfKind(kind: number): BasePart?
	for shadow in self.viewsByShadow do
		if shadow:GetAttribute(Attributes.STRUCTURE_KIND) == kind then
			return shadow
		end
	end
	return nil
end

-- the structure's whole box, as the server measured it; the shadow's own
-- spot stands in for a shadow that has no box yet
function ClientCampMapManager:readBox(shadow: BasePart): (CFrame, Vector3)
	local boundsCFrame = shadow:GetAttribute(Attributes.STRUCTURE_BOUNDS_CFRAME)
	local boundsSize = shadow:GetAttribute(Attributes.STRUCTURE_BOUNDS_SIZE)
	if typeof(boundsCFrame) ~= "CFrame" then
		boundsCFrame = shadow.CFrame
	end
	if typeof(boundsSize) ~= "Vector3" then
		boundsSize = shadow.Size
	end
	return boundsCFrame :: CFrame, boundsSize :: Vector3
end

-- the camp's frame runs from the Refinery to the gate, and every box is
-- fitted into the square; done once per change, not per frame
function ClientCampMapManager:rebuildLayout()
	self.isLayoutDirty = false
	local refinery = self:findShadowOfKind(Enums.StructureKind.REFINERY)
	local gate = self:findShadowOfKind(Enums.StructureKind.GATE)
	if not refinery then
		self.frame = nil
		self.layout = nil
		return
	end
	local refineryCFrame = self:readBox(refinery)
	local gateCFrame = if gate then self:readBox(gate) else refineryCFrame
	local frame = CampMapRules.makeFrame(refineryCFrame.Position, gateCFrame.Position)
	local points: { CampMapRules.MapPoint } = {}
	for shadow in self.viewsByShadow do
		local boundsCFrame, boundsSize = self:readBox(shadow)
		for _, corner in CampMapRules.boxCorners(frame, boundsCFrame, boundsSize) do
			table.insert(points, corner)
		end
	end
	self.frame = frame
	self.layout = CampMapRules.layoutFor(points, MARGIN_SHARE)
	for _, view in self.viewsByShadow do
		self:placeStructure(view)
	end
end

function ClientCampMapManager:placeStructure(view: StructureView)
	local frame = self.frame
	local layout = self.layout
	if not frame or not layout then
		view.frame.Visible = false
		return
	end
	local boundsCFrame, boundsSize = self:readBox(view.shadow)
	local u, v = CampMapRules.toMap(frame, boundsCFrame.Position.X, boundsCFrame.Position.Z)
	local x, y = CampMapRules.toScreen(layout, u, v)
	view.frame.Position = UDim2.fromScale(x, y)
	view.frame.Size = UDim2.fromScale(math.max(boundsSize.X * layout.scale, MIN_STRUCTURE_SIDE_SHARE), math.max(boundsSize.Z * layout.scale, MIN_STRUCTURE_SIDE_SHARE))
	view.frame.Rotation = CampMapRules.rotationDegrees(frame, boundsCFrame.RightVector)
	view.frame.Visible = true
	local destroyedMark = view.destroyedMark
	if destroyedMark then
		destroyedMark.Position = UDim2.fromScale(x, y)
	end
	local refineryLabel = self.refineryLabel
	if refineryLabel and view.shadow:GetAttribute(Attributes.STRUCTURE_KIND) == Enums.StructureKind.REFINERY then
		-- just under the box's bottom edge, whichever way the box is turned
		local halfHeight = math.max(view.frame.Size.X.Scale, view.frame.Size.Y.Scale) / 2
		refineryLabel.Position = UDim2.fromScale(x, y + halfHeight)
		refineryLabel.Visible = true
	end
end

function ClientCampMapManager:refreshStructure(view: StructureView)
	local shadow = view.shadow
	local hp = readNumber(shadow:GetAttribute(Attributes.STRUCTURE_HP), 0)
	local maxHp = readNumber(shadow:GetAttribute(Attributes.STRUCTURE_MAX_HP), 0)
	local isDestroyed = shadow:GetAttribute(Attributes.STRUCTURE_IS_DESTROYED) == true
	local band = CampMapRules.healthBand(hp, maxHp, isDestroyed)
	local isRubble = band == Enums.StructureHealthBand.DESTROYED
	view.frame.BackgroundColor3 = UiStyle.CAMP_MAP_BAND_COLORS[band] or UiStyle.TEXT_COLOR
	if view.destroyedMark then
		view.destroyedMark.Visible = isRubble
	end
end

function ClientCampMapManager:track(instance: Instance)
	local template = self.structureTemplate
	local canvas = self.canvas
	if not template or not canvas or not isStructureShadow(instance) or self.viewsByShadow[instance :: BasePart] then
		return
	end
	local shadow = instance :: BasePart
	local frame = template:Clone()
	frame.Name = shadow.Name
	frame.Visible = false
	frame.Parent = canvas
	local destroyedMark: GuiObject? = nil
	local markTemplate = self.destroyedMarkTemplate
	if markTemplate then
		local mark = markTemplate:Clone()
		mark.Name = `{shadow.Name}Destroyed`
		mark.Visible = false
		mark.Parent = canvas
		destroyedMark = mark
	end
	local view: StructureView = {
		shadow = shadow,
		frame = frame,
		destroyedMark = destroyedMark,
		connections = {},
	}
	self.viewsByShadow[shadow] = view
	for _, attribute in { Attributes.STRUCTURE_HP, Attributes.STRUCTURE_MAX_HP, Attributes.STRUCTURE_IS_DESTROYED } do
		table.insert(
			view.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:refreshStructure(view)
				end
			)
		)
	end
	-- a rebuilt or upgraded structure can swap its model and so its box
	for _, attribute in { Attributes.STRUCTURE_BOUNDS_CFRAME, Attributes.STRUCTURE_BOUNDS_SIZE } do
		table.insert(
			view.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self.isLayoutDirty = true
				end
			)
		)
	end
	self:refreshStructure(view)
	self.isLayoutDirty = true
end

function ClientCampMapManager:untrack(instance: Instance)
	local view = self.viewsByShadow[instance :: BasePart]
	if not view then
		return
	end
	for _, connection in view.connections do
		connection:Disconnect()
	end
	view.frame:Destroy()
	if view.destroyedMark then
		view.destroyedMark:Destroy()
	end
	self.viewsByShadow[instance :: BasePart] = nil
	self.isLayoutDirty = true
end

-- a dot at a world location, hidden when it falls off the square
function ClientCampMapManager:placeDot(dot: GuiObject, worldX: number, worldZ: number)
	local frame = self.frame
	local layout = self.layout
	if not frame or not layout then
		dot.Visible = false
		return
	end
	local u, v = CampMapRules.toMap(frame, worldX, worldZ)
	local x, y = CampMapRules.toScreen(layout, u, v)
	if not CampMapRules.isOnScreen(x, y) then
		dot.Visible = false
		return
	end
	dot.Position = UDim2.fromScale(x, y)
	dot.Visible = true
end

function ClientCampMapManager:getPlayerDot(userId: number, colorIndex: number): GuiObject?
	local dot = self.playerDotByUserId[userId]
	if dot then
		return dot
	end
	local template = self.playerDotTemplate
	local canvas = self.canvas
	if not template or not canvas then
		return nil
	end
	dot = template:Clone()
	dot.Name = tostring(userId)
	local colors = UiStyle.COMPASS_PLAYER_COLORS
	dot.BackgroundColor3 = colors[(colorIndex - 1) % #colors + 1]
	-- the ring marks the player looking at the map
	local ring = dot:FindFirstChildOfClass("UIStroke")
	local isLocal = userId == Players.LocalPlayer.UserId
	if ring then
		ring.Enabled = isLocal
		ring.Color = UiStyle.CAMP_MAP_LOCAL_PLAYER_RING_COLOR
	end
	-- the local player draws over crewmates, and every dot over the
	-- structures and the destroyed marks, so a dot crossing a wall stays seen
	dot.ZIndex = if isLocal then 8 else 7
	dot.Visible = false
	dot.Parent = canvas
	self.playerDotByUserId[userId] = dot
	return dot
end

-- a loaded character is smoother than the published spot; far crewmates
-- are only ever the published spot, since streaming hides their characters
local function livePosition(userId: number, data: ClientDataManager.PublicData): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return data.compassPosition
end

function ClientCampMapManager:stepPlayers()
	local seen: { [number]: boolean } = {}
	for _, userId in ClientDataManager:getAllPlayerIds() do
		local data = ClientDataManager:getPlayerPublicData(userId)
		if not data then
			continue
		end
		seen[userId] = true
		local dot = self:getPlayerDot(userId, data.compassColorIndex)
		if not dot then
			continue
		end
		local position = if data.isDead then nil else livePosition(userId, data)
		if position then
			self:placeDot(dot, position.X, position.Z)
		else
			dot.Visible = false
		end
	end
	for userId, dot in self.playerDotByUserId do
		if not seen[userId] then
			dot:Destroy()
			self.playerDotByUserId[userId] = nil
		end
	end
end

function ClientCampMapManager:stepMonsters()
	local template = self.monsterDotTemplate
	local canvas = self.canvas
	if not template or not canvas then
		return
	end
	local shown = 0
	ClientMonsterManager:forEachRenderedLocation(
		function(x: number, z: number)
			if shown >= MAX_MONSTER_DOTS then
				return
			end
			shown += 1
			local dot = self.monsterDots[shown]
			if not dot then
				dot = template:Clone()
				dot.Name = `Monster{shown}`
				dot.ZIndex = 6
				dot.Parent = canvas
				self.monsterDots[shown] = dot
			end
			self:placeDot(dot, x, z)
		end
	)
	-- the dots past the live count stay in the pool, hidden
	for index = shown + 1, self.monsterDotsShown do
		local dot = self.monsterDots[index]
		if dot then
			dot.Visible = false
		end
	end
	self.monsterDotsShown = shown
end

function ClientCampMapManager:step(deltaSec: number)
	if self.isLayoutDirty then
		self:rebuildLayout()
	end
	local root = self.root
	if not root or not root.Visible then
		return
	end
	self.sinceStepSec += deltaSec
	if self.sinceStepSec < STEP_INTERVAL_SEC then
		return
	end
	self.sinceStepSec = 0
	self:stepPlayers()
	self:stepMonsters()
end

function ClientCampMapManager:init()
	self:findGui()
	local gui = self.gui
	if not gui then
		return
	end
	for _, shadow in CollectionService:GetTagged(Tags.STRUCTURE) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.IS_NIGHT,
		function()
			self:refreshShown(false)
		end
	)
	self:refreshShown(true)
	gui.Enabled = true
	RunService.RenderStepped:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientCampMapManager.new(): ClientCampMapManager
	local self = setmetatable({}, ClientCampMapManager) :: ClientCampMapManager
	self.gui = nil
	self.root = nil
	self.slide = nil
	self.canvas = nil
	self.structureTemplate = nil
	self.destroyedMarkTemplate = nil
	self.refineryLabel = nil
	self.playerDotTemplate = nil
	self.monsterDotTemplate = nil
	self.viewsByShadow = {}
	self.frame = nil
	self.layout = nil
	self.isLayoutDirty = false
	self.playerDotByUserId = {}
	self.monsterDots = {}
	self.monsterDotsShown = 0
	self.sinceStepSec = 0
	return self
end

return ClientCampMapManager.new()
