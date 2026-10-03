--!strict

-- Build Mode on this client (GDD "Defense Table"), decided 2026-09-30 in
-- place of the Defenses tool. The server puts the player in Build Mode
-- when they trigger the Defense Table's prompt and publishes it privately
-- (IsInBuildMode); while it is on, this manager lifts the camera into an
-- overhead view of the Defensive Zone and freezes the character where it
-- stands. The view is a classic tower defense screen:
--   the BuildBar along the bottom lists every Tower the loadout brought
--     and every Trap, each with its Iron price, greyed while it cannot
--     be paid for; a tap (or its number key) brings out that item's ghost
--     on the grid, and a second tap puts it away
--   a tap or a drag on the grid moves the ghost, snapped to the cells,
--     red where it cannot stand; the PlacePanel floats beside it with
--     Place (green when it can go down, red when not, with the price),
--     Rotate (a quarter turn each tap, or R), and Cancel
--   every standing Tower shows its range ring while the mode is on, so
--     the gaps in the coverage are plain (2026-10-02)
--   after a build the ghost steps to the nearest free spot beside the one
--     it just filled, so the next can go down at once
--   with no ghost out, a tap on one of the player's own Towers opens the
--     Tower Menu, and on one of their Traps floats the SellPanel under it;
--     both offer Move, which picks the placement up as a ghost to set down
--     on other cells
--   dragging anywhere else pans the view (as do WASD and the arrow keys),
--     the wheel or a pinch zooms it, and Exit asks the server to end the mode
-- Every tap and drag on the world lands on BuildSurface, one invisible
-- full-screen Modal button under the HUD (Modal frees the mouse that first
-- person locks). Place, Sell, and Exit are requests; the server decides.
-- The grid, the snapping, and the red tint run the same PlacementRules
-- maths the server checks with, and the camera is BuildCameraRules. The
-- camera rises from the player's view to the overhead one over
-- CAMERA_TRANSITION_SEC and comes back down the same way on exit
-- (2026-10-02), the character staying put until it lands.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BuildCameraRules = require("@game/ReplicatedStorage/Shared/BuildCameraRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local TowerRules = require("@game/ReplicatedStorage/Shared/TowerRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)
local ClientToolBarManager = require(script.Parent.ClientToolBarManager)
local ClientTowerMenuManager = require(script.Parent.ClientTowerMenuManager)

local ClientDefenseTableManager = {}
ClientDefenseTableManager.__index = ClientDefenseTableManager

type Entry = {
	placementKind: number,
	typeKind: number,
	frame: GuiButton,
}

type ZoneView = {
	part: BasePart,
	index: number,
	grid: PlacementRules.Grid,
	-- the cells the server keeps clear along the walls and posts
	reserved: { PlacementRules.Cell },
	lines: Folder?,
}

type Selection = {
	placementKind: number,
	typeKind: number,
	-- the catalogue's footprint, and the same turned by `rotation`: the
	-- cells the ghost covers on the grid
	baseFootprint: { number },
	footprint: { number },
	rotation: number,
	preview: Model,
	-- every part's own colour, put back when the ghost is placeable; the
	-- parts themselves go red when it is not (a Highlight did not read
	-- through the translucent ghost, 2026-09-21)
	colorByPart: { [BasePart]: Color3 },
	isTintedRed: boolean,
}

-- one finger or the mouse button held on the BuildSurface
type Pointer = {
	input: InputObject,
	isMouse: boolean,
	startPosition: Vector2,
	lastPosition: Vector2,
	-- past the threshold it is a drag and never a tap
	isDragging: boolean,
	-- a drag that began on the ghost moves the ghost; any other pans the view
	isOnGhost: boolean,
}

export type ClientDefenseTableManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		surfaceGui: ScreenGui?,
		entriesFrame: GuiObject?,
		entryTemplate: GuiButton?,
		placePanel: GuiObject?,
		placeButton: GuiButton?,
		placePriceLabel: TextLabel?,
		rotateButton: GuiButton?,
		sellPanel: GuiObject?,
		sellPriceLabel: TextLabel?,
		hintLabel: TextLabel?,
		towerCountLabel: TextLabel?,
		isBuildMode: boolean,
		catalog: PlacementRules.Catalog?,
		entries: { Entry },
		zonesByPart: { [BasePart]: ZoneView },
		gridFolder: Folder?,
		-- the range rings of every standing Tower, drawn while the mode is on
		rangeFolder: Folder?,
		selection: Selection?,
		-- where the ghost stands right now
		targetZone: ZoneView?,
		targetCell: PlacementRules.Cell?,
		canPlaceHere: boolean,
		-- the placement the ghost stands in for while its owner moves it
		moveShadow: BasePart?,
		-- a build was just asked for: once it lands on the ghost's cells the
		-- ghost steps aside to the nearest free spot
		isAdvancePending: boolean,
		-- the player's own Trap the SellPanel is open on
		sellShadow: BasePart?,
		sellConnection: RBXScriptConnection?,
		-- the overhead camera: the zone it looks at, the point on it, how far
		-- back it sits, and which way is up the screen
		cameraZone: ZoneView?,
		focus: Vector3,
		distanceStuds: number,
		forwardX: number,
		forwardZ: number,
		savedCameraType: Enum.CameraType?,
		-- where the player was looking at the table, so leaving hands their view back
		savedCameraCFrame: CFrame?,
		-- the rise into the overhead view: where the camera started and when,
		-- nil once it has arrived
		transitionFromCFrame: CFrame?,
		transitionStartTime: number?,
		-- the fall back to the player's view on exit, while it runs
		exitTween: Tween?,
		anchoredRootPart: BasePart?,
		stepConnection: RBXScriptConnection?,
		pointer: Pointer?,
		pinchStartDistanceStuds: number?,
	},
	ClientDefenseTableManager
))

local FEEDBACK_NOT_ENOUGH_IRON = "You don't have enough Iron Bars"
local FEEDBACK_NO_SPACE = "Not enough space"
local FEEDBACK_OUTSIDE_ZONE = "Defenses can only go in the Defensive Zone"
local FEEDBACK_NOT_YOURS = "That belongs to another player"
local HINT_IDLE = "Select a defense to place, or tap one of yours"
local HINT_PLACING = "Tap the grid to move it"
local HINT_MOVING = "Tap the grid to choose its new spot"
local PLACE_TEXT = "Place"
local MOVE_TEXT = "Move"
local HINT_CANNOT_PLACE = "Cannot place here"
local HINT_LOADING = "Loading the Defensive Zone"
local TOWER_COUNT_FORMAT = "%d / %d"
local PREVIEW_TRANSPARENCY = 0.45
local CANNOT_PLACE_COLOR = Color3.fromRGB(230, 70, 60)
local GRID_LINE_COLOR = Color3.fromRGB(245, 200, 80)
-- thicker than a line seen from the ground: these are read from far above
local GRID_LINE_THICKNESS_STUDS = 0.25
local GRID_LINE_LIFT_STUDS = 0.06
local GRID_LINE_TRANSPARENCY = 0.35
-- the range ring around a Tower ghost (decided 2026-09-22): a circle of
-- the Tower's reach drawn as flat segments on the ground
local RANGE_RING_NAME = "RangeRing"
local RANGE_RING_SEGMENTS = 64
local RANGE_RING_THICKNESS_STUDS = 0.6
local RANGE_RING_HEIGHT_STUDS = 0.1
local RANGE_RING_LIFT_STUDS = 0.15
local RANGE_RING_COLOR = Color3.fromRGB(120, 200, 255)
local RANGE_RING_TRANSPARENCY = 0.25
-- a standing Tower's ring is fainter than the ghost's, so the ghost's reads first
local STANDING_RING_TRANSPARENCY = 0.6
local RANGE_FOLDER_NAME = "TowerRanges"
local ROTATE_KEY = Enum.KeyCode.R
local GREYED_TRANSPARENCY = 0.55
-- a press that moves less than this is a tap
local DRAG_THRESHOLD_PX = 8
-- each wheel click closes or opens the view by this share
local ZOOM_STEP_SHARE = 0.1
-- the floating panels sit this far beside what they act on (to its right,
-- or its left when the right would run off the screen), as a share of the
-- screen's width, level with its middle, and never closer than this to
-- the screen's edges or lower than this
local PANEL_GAP_SHARE = 0.015
local PANEL_EDGE_SHARE = 0.12
local PANEL_BOTTOM_SHARE = 0.66
-- the server publishes the real numbers (GameData/Defenses/Table)
local DEFAULT_CAMERA_DISTANCE_STUDS = 150
local DEFAULT_CAMERA_MIN_DISTANCE_STUDS = 50
local DEFAULT_CAMERA_MAX_DISTANCE_STUDS = 300
local DEFAULT_CAMERA_PITCH_DEGREES = 65
local DEFAULT_CAMERA_PAN_SCREENS_PER_SEC = 0.9
local DEFAULT_CAMERA_TRANSITION_SEC = 1
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
-- keyboard panning: right and forward (up the screen) per key
local PAN_KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.W] = Vector2.new(0, 1),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.S] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientDefenseTableManager:getIsBuildMode(): boolean
	return self.isBuildMode
end

function ClientDefenseTableManager:getIron(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS), 0)
end

function ClientDefenseTableManager:getCampLevel(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL), 1)
end

function ClientDefenseTableManager:getLoadout(): { number }
	return PlacementRules.decodeTowerLoadout(ClientDataManager:getCurrentPlayerAttribute(Attributes.TOWER_LOADOUT))
end

function ClientDefenseTableManager:getPitchDegrees(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_PITCH_DEGREES), DEFAULT_CAMERA_PITCH_DEGREES)
end

function ClientDefenseTableManager:getTransitionSec(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_TRANSITION_SEC), DEFAULT_CAMERA_TRANSITION_SEC)
end

-- a Trap the Camp Level has not opened yet; Towers are gated by the loadout
function ClientDefenseTableManager:isEntryLocked(placementKind: number, typeKind: number): boolean
	local catalog = self.catalog
	return catalog ~= nil and self:getCampLevel() < PlacementRules.requiredCampLevel(catalog, placementKind, typeKind)
end

function ClientDefenseTableManager:canAffordEntry(placementKind: number, typeKind: number): boolean
	local catalog = self.catalog
	if not catalog or self:isEntryLocked(placementKind, typeKind) then
		return false
	end
	return PlacementRules.canAfford(self:getIron(), PlacementRules.buildPrice(catalog, placementKind, typeKind))
end

function ClientDefenseTableManager:renderEntry(entry: Entry, index: number)
	local catalog = self.catalog
	if not catalog then
		return
	end
	local frame = entry.frame
	local isAffordable = self:canAffordEntry(entry.placementKind, entry.typeKind)
	local selection = self.selection
	local isSelected = selection ~= nil and selection.placementKind == entry.placementKind and selection.typeKind == entry.typeKind
	local isTower = entry.placementKind == Enums.PlacementKind.TOWER
	local slot = frame:FindFirstChild(Constants.BUILD_BAR_ENTRY_SLOT)
	if slot and slot:IsA("GuiObject") then
		-- the tool bar's equipped look: panel fill and accent stroke
		slot.BackgroundColor3 = if isSelected then UiStyle.PANEL_COLOR else UiStyle.EMPTY_SLOT_COLOR
		slot.BackgroundTransparency = if isAffordable then UiStyle.PANEL_TRANSPARENCY else GREYED_TRANSPARENCY
		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if isSelected then UiStyle.ACCENT_COLOR else UiStyle.PANEL_COLOR
		end
	end
	local icon = if slot then slot:FindFirstChild(Constants.BUILD_BAR_ENTRY_ICON) else nil
	if icon and icon:IsA("ImageLabel") then
		local template = ClientPlacementManager:findTemplate(entry.placementKind, entry.typeKind)
		local imageId = if template then template:GetAttribute(Attributes.ICON_IMAGE_ID) else nil
		icon.Image = if typeof(imageId) == "string" then imageId else ""
		icon.ImageTransparency = if isAffordable then 0 else GREYED_TRANSPARENCY
	end
	local typeIcon = if slot then slot:FindFirstChild(Constants.BUILD_BAR_ENTRY_TYPE_ICON) else nil
	if typeIcon and typeIcon:IsA("ImageLabel") then
		local imageId = if isTower then Icons.UI.TOWER else Icons.UI.TRAP
		typeIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		typeIcon.ImageTransparency = if isAffordable then 0 else GREYED_TRANSPARENCY
	end
	local keyLabel = if slot then slot:FindFirstChild(Constants.BUILD_BAR_ENTRY_KEY_LABEL) else nil
	if keyLabel and keyLabel:IsA("TextLabel") then
		keyLabel.Text = tostring(index)
		keyLabel.Visible = UserInputService.KeyboardEnabled and index <= #NUMBER_KEYS
	end
	local nameLabel = frame:FindFirstChild(Constants.BUILD_BAR_ENTRY_NAME_LABEL)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(PlacementRules.publicName(entry.placementKind, entry.typeKind))
		nameLabel.TextColor3 = if isAffordable then UiStyle.TEXT_COLOR else UiStyle.DISABLED_COLOR
	end
	local priceRow = frame:FindFirstChild(Constants.BUILD_BAR_ENTRY_PRICE_ROW)
	local priceIcon = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_ENTRY_PRICE_ICON) else nil
	local priceLabel = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_ENTRY_PRICE_LABEL) else nil
	if priceIcon and priceIcon:IsA("ImageLabel") then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
		priceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
	end
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = tostring(PlacementRules.buildPrice(catalog, entry.placementKind, entry.typeKind))
		priceLabel.TextColor3 = if isAffordable then UiStyle.TEXT_COLOR else UiStyle.NEGATIVE_COLOR
	end
end

-- every Tower the loadout brought, then every Trap in the catalogue
function ClientDefenseTableManager:renderEntries()
	local entriesFrame = self.entriesFrame
	local template = self.entryTemplate
	local catalog = self.catalog
	if not entriesFrame or not template or not catalog then
		return
	end
	for _, entry in self.entries do
		entry.frame:Destroy()
	end
	self.entries = {}
	local wanted: { { placementKind: number, typeKind: number } } = {}
	for _, kind in self:getLoadout() do
		table.insert(wanted, { placementKind = Enums.PlacementKind.TOWER, typeKind = kind })
	end
	local trapKinds = {}
	for kind in catalog.traps do
		table.insert(trapKinds, kind)
	end
	table.sort(trapKinds)
	for _, kind in trapKinds do
		table.insert(wanted, { placementKind = Enums.PlacementKind.TRAP, typeKind = kind })
	end
	for order, item in wanted do
		local frame = template:Clone()
		frame.Name = `{Enums.getName(Enums.PlacementKind, item.placementKind)}_{PlacementRules.templateNameFor(item.placementKind, item.typeKind)}`
		frame.LayoutOrder = order
		frame.Visible = true
		local entry: Entry = {
			placementKind = item.placementKind,
			typeKind = item.typeKind,
			frame = frame,
		}
		frame.Activated:Connect(
			function()
				self:toggleEntry(entry.placementKind, entry.typeKind)
			end
		)
		frame.Parent = entriesFrame
		table.insert(self.entries, entry)
		self:renderEntry(entry, order)
	end
	-- a Tower that left the loadout mid-ghost takes the ghost with it
	local selection = self.selection
	if selection and not self:findEntry(selection.placementKind, selection.typeKind) then
		self:cancel()
	end
end

function ClientDefenseTableManager:findEntry(placementKind: number, typeKind: number): Entry?
	for _, entry in self.entries do
		if entry.placementKind == placementKind and entry.typeKind == typeKind then
			return entry
		end
	end
	return nil
end

-- Towers standing against the limit; red once it is reached
function ClientDefenseTableManager:renderTowerCount()
	local label = self.towerCountLabel
	local catalog = self.catalog
	if not label or not catalog then
		return
	end
	local count = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.ACTIVE_TOWER_COUNT), 0)
	-- the camp's Towers shared among the crew sampled at dawn
	local crewCount = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_SCALING_COUNT), 1)
	local allowance = PlacementRules.towerAllowance(catalog.maxActiveTowersCamp, crewCount)
	label.Text = string.format(TOWER_COUNT_FORMAT, count, allowance)
	label.TextColor3 = if count >= allowance then UiStyle.NEGATIVE_COLOR else UiStyle.TEXT_COLOR
end

-- the Place button's price (red when the player is short) and the hint
function ClientDefenseTableManager:renderPanel()
	local selection = self.selection
	local catalog = self.catalog
	local hintLabel = self.hintLabel
	if hintLabel then
		local hint = HINT_IDLE
		if not self.cameraZone then
			hint = HINT_LOADING
		elseif selection and not self.canPlaceHere then
			hint = HINT_CANNOT_PLACE
		elseif selection then
			hint = if self.moveShadow then HINT_MOVING else HINT_PLACING
		end
		hintLabel.Text = UiStyle.formatTitle(hint)
	end
	local placePanel = self.placePanel
	if placePanel then
		placePanel.Visible = selection ~= nil
	end
	if not selection or not catalog then
		return
	end
	-- a move costs nothing, so its button carries the word alone. The button
	-- is green while the ghost can go down and be paid for, red otherwise
	local isMoving = self.moveShadow ~= nil
	local isAffordable = isMoving or self:canAffordEntry(selection.placementKind, selection.typeKind)
	local placeButton = self.placeButton
	if placeButton then
		placeButton.BackgroundColor3 = if self.canPlaceHere and isAffordable then UiStyle.POSITIVE_COLOR else UiStyle.NEGATIVE_COLOR
	end
	local placeText = if placeButton then placeButton:FindFirstChild(Constants.BUILD_BAR_BUILD_TEXT_LABEL) else nil
	if placeText and placeText:IsA("TextLabel") then
		placeText.Text = UiStyle.formatTitle(if isMoving then MOVE_TEXT else PLACE_TEXT)
	end
	local placePriceRow = if placeButton then placeButton:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ROW) else nil
	if placePriceRow and placePriceRow:IsA("GuiObject") then
		placePriceRow.Visible = not isMoving
	end
	local priceLabel = self.placePriceLabel
	if priceLabel then
		priceLabel.Text = tostring(PlacementRules.buildPrice(catalog, selection.placementKind, selection.typeKind))
	end
end

function ClientDefenseTableManager:renderAffordability()
	for index, entry in self.entries do
		self:renderEntry(entry, index)
	end
	self:renderPanel()
end

-- the grid over one zone: thin bars along the column and row edges of
-- every cell that can be built on, so the grid stops at the walls and
-- posts instead of shading the reserved cells (decided 2026-10-01); local,
-- and only in Build Mode. Each line is one part per unbroken run of edges
function ClientDefenseTableManager:drawZone(view: ZoneView)
	local gridFolder = self.gridFolder
	if view.lines or not gridFolder then
		return
	end
	local grid = view.grid
	local folder = Instance.new("Folder")
	folder.Name = view.part.Name
	local reservedKeys: { [string]: boolean } = {}
	for _, cell in view.reserved do
		reservedKeys[PlacementRules.occupancyKey(cell)] = true
	end
	local function isBuildable(column: number, row: number): boolean
		local cell = { column = column, row = row }
		return PlacementRules.isCellInside(grid, cell) and not reservedKeys[PlacementRules.occupancyKey(cell)]
	end
	local function addLine(name: string, size: Vector3, offset: Vector3)
		local line = Instance.new("Part")
		line.Name = name
		line.Size = size
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.CanTouch = false
		line.CastShadow = false
		line.Material = Enum.Material.Neon
		line.Color = GRID_LINE_COLOR
		line.Transparency = GRID_LINE_TRANSPARENCY
		line.CFrame = grid.cframe * CFrame.new(offset + Vector3.new(0, GRID_LINE_LIFT_STUDS, 0))
		line.Parent = folder
	end
	-- walks the cells 1..count along one edge and builds one part per run
	-- of cells where the edge is wanted
	local function addRuns(count: number, isEdgeWanted: (number) -> boolean, build: (runStart: number, runLength: number) -> ())
		local runStart = nil
		for index = 1, count + 1 do
			local isWanted = index <= count and isEdgeWanted(index)
			if isWanted and not runStart then
				runStart = index
			elseif not isWanted and runStart then
				build(runStart, index - runStart)
				runStart = nil
			end
		end
	end
	-- an edge is drawn wherever a buildable cell touches either side of it
	for column = 0, grid.columns do
		addRuns(
			grid.rows,
			function(row: number): boolean
				return isBuildable(column, row) or isBuildable(column + 1, row)
			end,
			function(runStart: number, runLength: number)
				addLine(
					`Column{column}_{runStart}`,
					Vector3.new(GRID_LINE_THICKNESS_STUDS, GRID_LINE_THICKNESS_STUDS, runLength * grid.cellSizeStuds),
					Vector3.new((column - grid.columns / 2) * grid.cellSizeStuds, 0, (runStart - 1 + runLength / 2 - grid.rows / 2) * grid.cellSizeStuds)
				)
			end
		)
	end
	for row = 0, grid.rows do
		addRuns(
			grid.columns,
			function(column: number): boolean
				return isBuildable(column, row) or isBuildable(column, row + 1)
			end,
			function(runStart: number, runLength: number)
				addLine(
					`Row{row}_{runStart}`,
					Vector3.new(runLength * grid.cellSizeStuds, GRID_LINE_THICKNESS_STUDS, GRID_LINE_THICKNESS_STUDS),
					Vector3.new((runStart - 1 + runLength / 2 - grid.columns / 2) * grid.cellSizeStuds, 0, (row - grid.rows / 2) * grid.cellSizeStuds)
				)
			end
		)
	end
	folder.Parent = gridFolder
	view.lines = folder
end

function ClientDefenseTableManager:eraseZone(view: ZoneView)
	if view.lines then
		view.lines:Destroy()
		view.lines = nil
	end
end

function ClientDefenseTableManager:applyModeToZones()
	for _, view in self.zonesByPart do
		if self.isBuildMode then
			self:drawZone(view)
		else
			self:eraseZone(view)
		end
	end
end

function ClientDefenseTableManager:trackZone(part: Instance)
	if not part:IsA("BasePart") or self.zonesByPart[part] then
		return
	end
	local catalog = self.catalog
	if not catalog then
		return
	end
	local view: ZoneView = {
		part = part,
		index = readNumber(part:GetAttribute(Attributes.DEFENSIVE_ZONE_INDEX), 0),
		grid = PlacementRules.measureZone(part.CFrame, part.Size, catalog.cellSizeStuds),
		reserved = PlacementRules.decodeCells(part:GetAttribute(Attributes.DEFENSIVE_ZONE_RESERVED_CELLS)),
		lines = nil,
	}
	self.zonesByPart[part] = view
	part:GetAttributeChangedSignal(Attributes.DEFENSIVE_ZONE_INDEX):Connect(
		function()
			view.index = readNumber(part:GetAttribute(Attributes.DEFENSIVE_ZONE_INDEX), 0)
		end
	)
	part:GetAttributeChangedSignal(Attributes.DEFENSIVE_ZONE_RESERVED_CELLS):Connect(
		function()
			view.reserved = PlacementRules.decodeCells(part:GetAttribute(Attributes.DEFENSIVE_ZONE_RESERVED_CELLS))
			if view.lines then
				self:eraseZone(view)
				self:drawZone(view)
			end
		end
	)
	if self.isBuildMode then
		self:drawZone(view)
	end
end

function ClientDefenseTableManager:untrackZone(part: Instance)
	local view = self.zonesByPart[part :: BasePart]
	if not view then
		return
	end
	self:eraseZone(view)
	self.zonesByPart[part :: BasePart] = nil
	if self.targetZone == view then
		self.targetZone = nil
		self.targetCell = nil
	end
	if self.cameraZone == view then
		self.cameraZone = nil
	end
end

-- the cells nothing may go on in one zone: the reserved strip along the
-- fortifications, then what the standing placements cover, from their shadows
function ClientDefenseTableManager:occupancyFor(view: ZoneView): PlacementRules.Occupancy
	local occupancy: PlacementRules.Occupancy = {}
	PlacementRules.reserve(occupancy, view.reserved)
	local catalog = self.catalog
	if not catalog then
		return occupancy
	end
	for _, shadow in ClientPlacementManager:getTrackedShadows() do
		if readNumber(shadow:GetAttribute(Attributes.DEFENSIVE_ZONE_INDEX), 0) ~= view.index then
			continue
		end
		local footprint = ClientPlacementManager:footprintOf(shadow, catalog)
		local anchor = {
			column = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_COLUMN), 0),
			row = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_ROW), 0),
		}
		local id = shadow:GetAttribute(Attributes.PLACEMENT_ID)
		for _, cell in PlacementRules.footprintCells(anchor, footprint) do
			occupancy[PlacementRules.occupancyKey(cell)] = if typeof(id) == "string" then id else shadow.Name
		end
	end
	return occupancy
end

-- the zone a point on the ground falls in, if any
function ClientDefenseTableManager:findZone(position: Vector3): ZoneView?
	for _, view in self.zonesByPart do
		if view.index > 0 and PlacementRules.isCellInside(view.grid, PlacementRules.cellFromPosition(view.grid, position)) then
			return view
		end
	end
	return nil
end

-- the lowest-numbered zone: the one the camera opens over
function ClientDefenseTableManager:findFirstZone(): ZoneView?
	local first: ZoneView? = nil
	for _, view in self.zonesByPart do
		if view.index > 0 and (not first or view.index < first.index) then
			first = view
		end
	end
	return first
end

-- where a screen position meets the build surface of the camera's zone.
-- Input positions and ScreenPointToRay share the space under the top bar
function ClientDefenseTableManager:worldPoint(screenPosition: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	local zone = self.cameraZone
	if not camera or not zone then
		return nil
	end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	return BuildCameraRules.pointOnPlane(ray.Origin, ray.Direction, zone.grid.cframe.Position.Y)
end

function ClientDefenseTableManager:setPreviewColor(selection: Selection, canPlace: boolean)
	local wantRed = not canPlace
	if selection.isTintedRed == wantRed then
		return
	end
	selection.isTintedRed = wantRed
	for part, color in selection.colorByPart do
		part.Color = if wantRed then CANNOT_PLACE_COLOR else color
	end
end

-- whether the ghost could be built where it stands, recomputed when it
-- moves and when a placement appears or goes
function ClientDefenseTableManager:refreshGhost()
	local selection = self.selection
	if not selection then
		return
	end
	local view = self.targetZone
	local cell = self.targetCell
	local wasPlaceable = self.canPlaceHere
	local moveShadow = self.moveShadow
	local movedId = if moveShadow then moveShadow:GetAttribute(Attributes.PLACEMENT_ID) else nil
	local occupancy = if view then self:occupancyFor(view) else {}
	self.canPlaceHere = view ~= nil and cell ~= nil and PlacementRules.canPlace(view.grid, occupancy, cell, selection.footprint, if typeof(movedId) == "string" then movedId else nil)
	-- the build just asked for has landed under the ghost: step aside
	if self.isAdvancePending and not self.canPlaceHere and view and cell then
		self.isAdvancePending = false
		local nextCell = PlacementRules.nextFreeAnchor(view.grid, occupancy, cell, selection.footprint)
		if nextCell then
			self.targetCell = nextCell
			self:poseGhost(selection, view, nextCell)
			self.canPlaceHere = true
		end
	end
	self:setPreviewColor(selection, self.canPlaceHere)
	if wasPlaceable ~= self.canPlaceHere then
		self:renderPanel()
	end
end

-- the ghost's grid-aligned pose on its cells; the model inside is turned
-- by the selection's quarter turns
function ClientDefenseTableManager:ghostCFrame(selection: Selection, view: ZoneView, cell: PlacementRules.Cell): CFrame
	return PlacementRules.footprintCFrame(view.grid, cell, selection.footprint)
end

function ClientDefenseTableManager:poseGhost(selection: Selection, view: ZoneView, cell: PlacementRules.Cell)
	selection.preview:PivotTo(self:ghostCFrame(selection, view, cell) * PlacementRules.rotationCFrame(selection.rotation))
end

-- the ghost snapped to the cells nearest a point on the ground
function ClientDefenseTableManager:moveGhost(position: Vector3)
	local selection = self.selection
	if not selection then
		return
	end
	local view = self:findZone(position) or self.targetZone or self.cameraZone
	if not view then
		return
	end
	local anchor = PlacementRules.clampAnchor(view.grid, PlacementRules.anchorFromPosition(view.grid, position, selection.footprint), selection.footprint)
	if not anchor then
		return
	end
	self.targetZone = view
	self.targetCell = anchor
	-- the player chose a spot themselves; nothing is left to step aside from
	self.isAdvancePending = false
	self:poseGhost(selection, view, anchor)
	self:refreshGhost()
end

-- the ghost a quarter turn on, kept centred where it stands (the Rotate
-- button, or R); a turned footprint that no longer fits is pulled back
-- inside the grid
function ClientDefenseTableManager:rotate()
	local selection = self.selection
	if not selection then
		return
	end
	local view = self.targetZone
	local cell = self.targetCell
	local center = if view and cell then self:ghostCFrame(selection, view, cell).Position else selection.preview:GetPivot().Position
	selection.rotation = PlacementRules.normalizeRotation(selection.rotation + 1)
	selection.footprint = PlacementRules.rotatedFootprint(selection.baseFootprint, selection.rotation)
	self.isAdvancePending = false
	if view then
		local anchor = PlacementRules.clampAnchor(view.grid, PlacementRules.anchorFromPosition(view.grid, center, selection.footprint), selection.footprint)
		if anchor then
			self.targetCell = anchor
			self:poseGhost(selection, view, anchor)
		end
	end
	self:refreshGhost()
end

-- whether a point on the ground is on the ghost's own cells
function ClientDefenseTableManager:isOnGhost(position: Vector3): boolean
	local selection = self.selection
	local view = self.targetZone
	local anchor = self.targetCell
	if not selection or not view or not anchor then
		return false
	end
	local cell = PlacementRules.cellFromPosition(view.grid, position)
	return cell.column >= anchor.column and cell.column < anchor.column + selection.footprint[1] and cell.row >= anchor.row and cell.row < anchor.row + selection.footprint[2]
end

function ClientDefenseTableManager:cancel()
	local selection = self.selection
	if not selection then
		return
	end
	self.selection = nil
	selection.preview:Destroy()
	self.targetZone = nil
	self.targetCell = nil
	self.canPlaceHere = false
	self.moveShadow = nil
	self.isAdvancePending = false
	self:renderAffordability()
end

-- a ring of a Tower's reach drawn as flat segments on the ground about a
-- pose (decided 2026-09-22)
function ClientDefenseTableManager:buildRangeRing(pivot: CFrame, radius: number, transparency: number): Model
	local ring = Instance.new("Model")
	ring.Name = RANGE_RING_NAME
	local segmentLength = 2 * math.pi * radius / RANGE_RING_SEGMENTS + RANGE_RING_THICKNESS_STUDS
	for index = 1, RANGE_RING_SEGMENTS do
		local angle = (index - 0.5) / RANGE_RING_SEGMENTS * 2 * math.pi
		local segment = Instance.new("Part")
		segment.Name = "Segment"
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = RANGE_RING_COLOR
		segment.Transparency = transparency
		segment.Size = Vector3.new(segmentLength, RANGE_RING_HEIGHT_STUDS, RANGE_RING_THICKNESS_STUDS)
		-- each segment sits on the circle, turned to run along it
		segment.CFrame = pivot * CFrame.Angles(0, -angle, 0) * CFrame.new(0, RANGE_RING_LIFT_STUDS, -radius)
		segment.Parent = ring
	end
	return ring
end

-- how far a Tower kind reaches at a level, past the edge of its footprint
function ClientDefenseTableManager:reachFor(tower: PlacementRules.TowerData, level: number): number
	local catalog = self.catalog
	local stats = PlacementRules.towerStats(tower, level)
	return TowerRules.reachStuds(stats.RANGE_STUDS, tower.FOOTPRINT_CELLS, if catalog then catalog.cellSizeStuds else 4)
end

-- a Tower ghost carries a ring of its reach so the player sees what the
-- spot covers before building; it moves with the ghost because it is part
-- of the model, and never tints red
function ClientDefenseTableManager:addRangeRing(preview: Model, placementKind: number, typeKind: number)
	local catalog = self.catalog
	if not catalog or placementKind ~= Enums.PlacementKind.TOWER then
		return
	end
	local tower = catalog.towers[typeKind]
	if not tower then
		return
	end
	local ring = self:buildRangeRing(preview:GetPivot(), self:reachFor(tower, PlacementRules.STARTING_LEVEL), RANGE_RING_TRANSPARENCY)
	ring.Parent = preview
end

-- every standing Tower's ring, at its level, redrawn whenever a placement
-- changes while the mode is on, so the gaps in the camp's coverage show
-- (decided 2026-10-02)
function ClientDefenseTableManager:drawTowerRanges()
	local previous = self.rangeFolder
	if previous then
		previous:Destroy()
		self.rangeFolder = nil
	end
	local catalog = self.catalog
	local gridFolder = self.gridFolder
	if not self.isBuildMode or not catalog or not gridFolder then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = RANGE_FOLDER_NAME
	for _, shadow in ClientPlacementManager:getTrackedShadows() do
		local tower = ClientPlacementManager:getTowerData(shadow)
		if not tower then
			continue
		end
		local level = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_LEVEL), PlacementRules.STARTING_LEVEL)
		local ring = self:buildRangeRing(ClientPlacementManager:basePose(shadow), self:reachFor(tower, level), STANDING_RING_TRANSPARENCY)
		ring.Name = shadow.Name
		ring.Parent = folder
	end
	folder.Parent = gridFolder
	self.rangeFolder = folder
end

-- brings out an item's ghost at a point on the ground, turned `rotation`
-- quarter turns; false when it cannot
function ClientDefenseTableManager:beginGhost(placementKind: number, typeKind: number, position: Vector3, rotation: number): boolean
	local catalog = self.catalog
	if not catalog or not self.isBuildMode or not self.cameraZone then
		return false
	end
	self:cancel()
	self:closeSellPanel()
	local baseFootprint = PlacementRules.footprintFor(catalog, placementKind, typeKind)
	if not baseFootprint then
		return false
	end
	local footprint = PlacementRules.rotatedFootprint(baseFootprint, rotation)
	local shadowSize = Vector3.new(baseFootprint[1] * catalog.cellSizeStuds, 1, baseFootprint[2] * catalog.cellSizeStuds)
	local preview = ClientPlacementManager:buildModel(placementKind, typeKind, shadowSize)
	preview.Name = "PlacementPreview"
	local colorByPart: { [BasePart]: Color3 } = {}
	for _, descendant in preview:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Transparency = math.max(descendant.Transparency, PREVIEW_TRANSPARENCY)
			colorByPart[descendant] = descendant.Color
		end
	end
	self:addRangeRing(preview, placementKind, typeKind)
	preview.Parent = ClientPlacementManager:getBodiesFolder()
	self.selection = {
		placementKind = placementKind,
		typeKind = typeKind,
		baseFootprint = baseFootprint,
		footprint = footprint,
		rotation = PlacementRules.normalizeRotation(rotation),
		preview = preview,
		colorByPart = colorByPart,
		isTintedRed = false,
	}
	self:moveGhost(position)
	self:renderAffordability()
	return true
end

-- an item from the bar: its ghost comes out in the middle of the view
function ClientDefenseTableManager:select(placementKind: number, typeKind: number)
	self:beginGhost(placementKind, typeKind, self.focus, 0)
end

-- one of the player's own placements picked up: its ghost comes out where
-- it stands, turned as it stands, and Place becomes Move
function ClientDefenseTableManager:startMove(shadow: BasePart)
	local placementKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_KIND), 0)
	local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
	local rotation = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_ROTATION), 0)
	if not self:beginGhost(placementKind, typeKind, shadow.Position, rotation) then
		return
	end
	self.moveShadow = shadow
	self:refreshGhost()
	self:renderAffordability()
end

-- an entry tapped: its ghost comes out, or goes away if it was the one out
function ClientDefenseTableManager:toggleEntry(placementKind: number, typeKind: number)
	local selection = self.selection
	if selection and selection.placementKind == placementKind and selection.typeKind == typeKind then
		self:cancel()
		return
	end
	if self:isEntryLocked(placementKind, typeKind) and self.catalog then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(string.format(StoreRules.LOCKED_FORMAT, PlacementRules.requiredCampLevel(self.catalog, placementKind, typeKind)))
		return
	end
	self:select(placementKind, typeKind)
end

-- a build that cannot go through is refused here with the Fail sound and
-- the reason; the server checks again regardless. The ghost stays out for
-- the next one
function ClientDefenseTableManager:place()
	local selection = self.selection
	local view = self.targetZone
	local cell = self.targetCell
	if not selection or not self.catalog then
		return
	end
	if not view or not cell then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_OUTSIDE_ZONE)
		return
	end
	if not self.canPlaceHere then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NO_SPACE)
		return
	end
	local moveShadow = self.moveShadow
	if moveShadow then
		local movedId = moveShadow:GetAttribute(Attributes.PLACEMENT_ID)
		if typeof(movedId) == "string" then
			ClientNetManager:fireServer(NetEventNames.TRY_MOVE_PLACEMENT, {
				id = movedId,
				zoneIndex = view.index,
				column = cell.column,
				row = cell.row,
				rotation = selection.rotation,
			})
		end
		self:cancel()
		return
	end
	if not self:canAffordEntry(selection.placementKind, selection.typeKind) then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_BUILD_PLACEMENT, {
		placementKind = selection.placementKind,
		typeKind = selection.typeKind,
		zoneIndex = view.index,
		column = cell.column,
		row = cell.row,
		rotation = selection.rotation,
	})
	self.isAdvancePending = true
end

function ClientDefenseTableManager:closeSellPanel()
	if self.sellConnection then
		self.sellConnection:Disconnect()
		self.sellConnection = nil
	end
	self.sellShadow = nil
	if self.sellPanel then
		self.sellPanel.Visible = false
	end
end

-- one of the player's own Traps tapped: Sell floats under it
function ClientDefenseTableManager:openSellPanel(shadow: BasePart)
	local catalog = self.catalog
	local panel = self.sellPanel
	if not catalog or not panel then
		return
	end
	self:closeSellPanel()
	self.sellShadow = shadow
	-- a Trap that went off or was destroyed takes its panel with it
	self.sellConnection = shadow.AncestryChanged:Connect(
		function(_child: Instance, parent: Instance?)
			if parent == nil then
				self:closeSellPanel()
			end
		end
	)
	if self.sellPriceLabel then
		local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
		self.sellPriceLabel.Text = tostring(PlacementRules.sellValueFor(catalog, Enums.PlacementKind.TRAP, typeKind, PlacementRules.STARTING_LEVEL))
	end
	panel.Visible = true
end

function ClientDefenseTableManager:sellOpenTrap()
	local shadow = self.sellShadow
	local id = if shadow then shadow:GetAttribute(Attributes.PLACEMENT_ID) else nil
	self:closeSellPanel()
	if typeof(id) == "string" then
		ClientNetManager:fireServer(NetEventNames.TRY_SELL_PLACEMENT, { id = id })
	end
end

-- a tap on the ground with no ghost out: one of the player's own Towers
-- opens its menu, one of their Traps its Sell panel
function ClientDefenseTableManager:tapPlacement(position: Vector3)
	self:closeSellPanel()
	local view = self:findZone(position)
	if not view then
		return
	end
	local id = self:occupancyFor(view)[PlacementRules.occupancyKey(PlacementRules.cellFromPosition(view.grid, position))]
	local shadow = if id then ClientPlacementManager:findShadowById(id) else nil
	if not shadow then
		return
	end
	if readNumber(shadow:GetAttribute(Attributes.PLACEMENT_OWNER_USER_ID), PlacementRules.NOBODY) ~= Players.LocalPlayer.UserId then
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOT_YOURS)
		return
	end
	if shadow:GetAttribute(Attributes.PLACEMENT_KIND) == Enums.PlacementKind.TOWER then
		ClientTowerMenuManager:openMenu(shadow)
	else
		self:openSellPanel(shadow)
	end
end

function ClientDefenseTableManager:tap(screenPosition: Vector2)
	local position = self:worldPoint(screenPosition)
	if not position then
		return
	end
	if self.selection then
		if self:findZone(position) then
			self:moveGhost(position)
		else
			ClientPlayerFeedbackManager:giveLocal(FEEDBACK_OUTSIDE_ZONE)
		end
		return
	end
	self:tapPlacement(position)
end

-- how many studs of ground one pixel covers, across and up the screen; the
-- tilt stretches the ground up the screen
function ClientDefenseTableManager:getStudsPerPixel(): (number, number)
	local camera = workspace.CurrentCamera
	if not camera then
		return 0, 0
	end
	local across = BuildCameraRules.studsPerPixel(self.distanceStuds, camera.FieldOfView, camera.ViewportSize.Y)
	return across, across / math.max(math.sin(math.rad(self:getPitchDegrees())), 0.2)
end

function ClientDefenseTableManager:zoom(steps: number)
	local minStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_MIN_DISTANCE_STUDS), DEFAULT_CAMERA_MIN_DISTANCE_STUDS)
	local maxStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_MAX_DISTANCE_STUDS), DEFAULT_CAMERA_MAX_DISTANCE_STUDS)
	self.distanceStuds = BuildCameraRules.zoomDistance(self.distanceStuds, steps, ZOOM_STEP_SHARE, minStuds, maxStuds)
end

function ClientDefenseTableManager:onPointerMoved(position: Vector2)
	local pointer = self.pointer
	if not pointer then
		return
	end
	if not pointer.isDragging and (position - pointer.startPosition).Magnitude < DRAG_THRESHOLD_PX then
		return
	end
	pointer.isDragging = true
	local delta = position - pointer.lastPosition
	pointer.lastPosition = position
	if pointer.isOnGhost then
		local point = self:worldPoint(position)
		if point then
			self:moveGhost(point)
		end
		return
	end
	-- the ground follows the finger, so the view moves the other way
	local across, up = self:getStudsPerPixel()
	self.focus = BuildCameraRules.panFocus(self.focus, self.forwardX, self.forwardZ, -delta.X * across, delta.Y * up)
end

function ClientDefenseTableManager:onSurfaceInputBegan(input: InputObject)
	if not self.isBuildMode or ClientOverlayManager:isOverlayActive() then
		return
	end
	local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if not isMouse and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if self.pointer then
		-- a second finger: a pinch is starting, which is never a tap or a pan
		self.pointer = nil
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local point = self:worldPoint(position)
	self.pointer = {
		input = input,
		isMouse = isMouse,
		startPosition = position,
		lastPosition = position,
		isDragging = false,
		isOnGhost = point ~= nil and self:isOnGhost(point),
	}
end

function ClientDefenseTableManager:onInputChanged(input: InputObject)
	local pointer = self.pointer
	if not pointer then
		return
	end
	-- a touch keeps its InputObject; the mouse moves as a separate one
	local isPointerMove = if pointer.isMouse then input.UserInputType == Enum.UserInputType.MouseMovement else input == pointer.input
	if isPointerMove then
		self:onPointerMoved(Vector2.new(input.Position.X, input.Position.Y))
	end
end

function ClientDefenseTableManager:onInputEnded(input: InputObject)
	local pointer = self.pointer
	if not pointer then
		return
	end
	local isPointerEnd = if pointer.isMouse then input.UserInputType == Enum.UserInputType.MouseButton1 else input == pointer.input
	if not isPointerEnd then
		return
	end
	self.pointer = nil
	if not pointer.isDragging and self.isBuildMode and not ClientOverlayManager:isOverlayActive() then
		self:tap(pointer.startPosition)
	end
end

-- two fingers: the view closes as they spread
function ClientDefenseTableManager:onTouchPinch(scale: number, state: Enum.UserInputState)
	if not self.isBuildMode or ClientOverlayManager:isOverlayActive() then
		return
	end
	self.pointer = nil
	if state == Enum.UserInputState.Begin or not self.pinchStartDistanceStuds then
		self.pinchStartDistanceStuds = self.distanceStuds
	end
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		self.pinchStartDistanceStuds = nil
		return
	end
	local minStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_MIN_DISTANCE_STUDS), DEFAULT_CAMERA_MIN_DISTANCE_STUDS)
	local maxStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_MAX_DISTANCE_STUDS), DEFAULT_CAMERA_MAX_DISTANCE_STUDS)
	self.distanceStuds = math.clamp((self.pinchStartDistanceStuds :: number) / math.max(scale, 0.01), minStuds, maxStuds)
end

function ClientDefenseTableManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not self.isBuildMode or ClientOverlayManager:isOverlayActive() then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == ROTATE_KEY then
			self:rotate()
			return
		end
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		local entry = if index then self.entries[index] else nil
		if entry then
			self:toggleEntry(entry.placementKind, entry.typeKind)
		end
	end
end

-- a panel floated beside a flat box in the world (its grid-aligned pose
-- and half extents across the ground): to the right of the box's
-- widest point on screen, level with its middle, or to its left when the
-- right would run off the screen, so it never covers what it acts on
-- (decided 2026-10-02). Kept on screen and above the bar
function ClientDefenseTableManager:floatPanel(panel: GuiObject, cframe: CFrame, halfX: number, halfZ: number)
	local camera = workspace.CurrentCamera
	local gui = self.gui
	if not camera or not gui then
		return
	end
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local leftShare = math.huge
	local rightShare = -math.huge
	local middleShare = 0
	for _, corner in { Vector3.new(-halfX, 0, -halfZ), Vector3.new(halfX, 0, -halfZ), Vector3.new(-halfX, 0, halfZ), Vector3.new(halfX, 0, halfZ) } do
		local screenPoint = camera:WorldToScreenPoint(cframe:PointToWorldSpace(corner))
		leftShare = math.min(leftShare, screenPoint.X / size.X)
		rightShare = math.max(rightShare, screenPoint.X / size.X)
		middleShare += screenPoint.Y / size.Y / 4
	end
	local panelWidthShare = panel.AbsoluteSize.X / size.X
	local isRight = rightShare + PANEL_GAP_SHARE + panelWidthShare <= 1 - PANEL_EDGE_SHARE / 2
	panel.AnchorPoint = if isRight then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
	local x = if isRight then rightShare + PANEL_GAP_SHARE else math.max(leftShare - PANEL_GAP_SHARE, panelWidthShare)
	local y = math.clamp(middleShare, PANEL_EDGE_SHARE, PANEL_BOTTOM_SHARE)
	panel.Position = UDim2.fromScale(x, y)
end

-- the zone under the camera, once it has streamed in: the view opens over
-- its middle, looking from the Refinery's side out toward the monsters
function ClientDefenseTableManager:adoptCameraZoneIfNeeded()
	if self.cameraZone then
		return
	end
	local zone = self:findFirstZone()
	if not zone then
		return
	end
	self.cameraZone = zone
	local center = zone.grid.cframe.Position
	local zoneLook = zone.grid.cframe.LookVector
	local homePosition = ClientDataManager:getGameMetadata(Attributes.COMPASS_HOME_POSITION)
	local towardZoneX, towardZoneZ = BuildCameraRules.flatDirection(if typeof(homePosition) == "Vector3" then homePosition else center, center, -zoneLook.X, -zoneLook.Z)
	self.forwardX, self.forwardZ = BuildCameraRules.snapToGridAxis(zone.grid, towardZoneX, towardZoneZ)
	self.focus = center
	self:renderPanel()
end

-- every frame in Build Mode: the keys pan, the camera is put where the
-- focus and the zoom say, and the floating panels follow what they act on
function ClientDefenseTableManager:step(deltaSec: number)
	self:adoptCameraZoneIfNeeded()
	local camera = workspace.CurrentCamera
	local zone = self.cameraZone
	if not camera or not zone then
		return
	end
	if not ClientOverlayManager:isOverlayActive() and not UserInputService:GetFocusedTextBox() then
		local pan = Vector2.zero
		for keyCode, direction in PAN_KEYS do
			if UserInputService:IsKeyDown(keyCode) then
				pan += direction
			end
		end
		if pan.Magnitude > 0 then
			local across = self:getStudsPerPixel()
			local screensPerSec = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_PAN_SCREENS_PER_SEC), DEFAULT_CAMERA_PAN_SCREENS_PER_SEC)
			local studs = across * camera.ViewportSize.Y * screensPerSec * deltaSec
			self.focus = BuildCameraRules.panFocus(self.focus, self.forwardX, self.forwardZ, pan.Unit.X * studs, pan.Unit.Y * studs)
		end
	end
	self.focus = BuildCameraRules.clampFocus(zone.grid, self.focus)
	local overhead = BuildCameraRules.cameraCFrame(self.focus, self.forwardX, self.forwardZ, self:getPitchDegrees(), self.distanceStuds)
	-- the rise from the player's view eases into the overhead one, which
	-- keeps moving under it as the player pans and zooms
	local fromCFrame = self.transitionFromCFrame
	if fromCFrame then
		local now = workspace:GetServerTimeNow()
		local startTime = self.transitionStartTime or now
		self.transitionStartTime = startTime
		local share = math.clamp((now - startTime) / math.max(self:getTransitionSec(), 0.01), 0, 1)
		overhead = fromCFrame:Lerp(overhead, TweenService:GetValue(share, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
		if share >= 1 then
			self.transitionFromCFrame = nil
			self.transitionStartTime = nil
		end
	end
	camera.CFrame = overhead
	camera.Focus = CFrame.new(self.focus)

	local selection = self.selection
	local targetZone = self.targetZone
	local targetCell = self.targetCell
	if selection and self.placePanel and targetZone and targetCell then
		local cellSize = targetZone.grid.cellSizeStuds
		self:floatPanel(self.placePanel, self:ghostCFrame(selection, targetZone, targetCell), selection.footprint[1] * cellSize / 2, selection.footprint[2] * cellSize / 2)
	end
	local sellShadow = self.sellShadow
	if sellShadow and self.sellPanel then
		self:floatPanel(self.sellPanel, sellShadow.CFrame, sellShadow.Size.X / 2, sellShadow.Size.Z / 2)
	end
end

function ClientDefenseTableManager:setCharacterFrozen(isFrozen: boolean)
	if isFrozen then
		local character = Players.LocalPlayer.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = true
			self.anchoredRootPart = rootPart
		end
	elseif self.anchoredRootPart then
		self.anchoredRootPart.Anchored = false
		self.anchoredRootPart = nil
	end
end

-- the camera comes back down to the view saved on the way in over the
-- transition time, the character staying frozen until it lands; first
-- person then takes its facing from the camera it is handed
function ClientDefenseTableManager:beginExitTween(camera: Camera?)
	local savedCFrame = self.savedCameraCFrame
	local savedType = self.savedCameraType or Enum.CameraType.Custom
	local function land()
		self.exitTween = nil
		if camera then
			if savedCFrame then
				camera.CFrame = savedCFrame
			end
			camera.CameraType = savedType
		end
		self.savedCameraType = nil
		self.savedCameraCFrame = nil
		self:setCharacterFrozen(false)
	end
	if not camera or not savedCFrame then
		land()
		return
	end
	local tween = TweenService:Create(camera, TweenInfo.new(self:getTransitionSec(), Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = savedCFrame })
	self.exitTween = tween
	tween.Completed:Connect(
		function(state: Enum.PlaybackState)
			-- a cancelled fall means Build Mode began again; that entry owns the camera now
			if state == Enum.PlaybackState.Completed and self.exitTween == tween then
				land()
			end
		end
	)
	tween:Play()
end

function ClientDefenseTableManager:setBuildMode(isBuildMode: boolean)
	if self.isBuildMode == isBuildMode then
		return
	end
	self.isBuildMode = isBuildMode
	local camera = workspace.CurrentCamera
	if isBuildMode then
		self.cameraZone = nil
		self.distanceStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.BUILD_CAMERA_DISTANCE_STUDS), DEFAULT_CAMERA_DISTANCE_STUDS)
		-- back in before the camera finished coming down: it rises again from
		-- where it is, and the view saved on the way in is kept for the way out
		local exitTween = self.exitTween
		if exitTween then
			exitTween:Cancel()
			self.exitTween = nil
		end
		if camera then
			if not exitTween then
				self.savedCameraType = camera.CameraType
				self.savedCameraCFrame = camera.CFrame
			end
			self.transitionFromCFrame = camera.CFrame
			self.transitionStartTime = nil
			camera.CameraType = Enum.CameraType.Scriptable
		end
		self.stepConnection = RunService.RenderStepped:Connect(
			function(deltaSec: number)
				self:step(deltaSec)
			end
		)
	else
		self:cancel()
		self:closeSellPanel()
		self.pointer = nil
		self.pinchStartDistanceStuds = nil
		if ClientTowerMenuManager:getIsMenuOpen() then
			ClientTowerMenuManager:closeMenu()
		end
		if self.stepConnection then
			self.stepConnection:Disconnect()
			self.stepConnection = nil
		end
		self.transitionFromCFrame = nil
		self.transitionStartTime = nil
		self:beginExitTween(camera)
		self.cameraZone = nil
	end
	if isBuildMode then
		self:setCharacterFrozen(true)
	end
	-- nothing in the world is in reach from up here, and the character
	-- does not move, so its prompts and touch controls step aside
	ProximityPromptService.Enabled = not isBuildMode
	GuiService.TouchControlsEnabled = not isBuildMode
	if self.gui then
		self.gui.Enabled = isBuildMode
	end
	if self.surfaceGui then
		self.surfaceGui.Enabled = isBuildMode
	end
	ClientToolBarManager:setHidden(isBuildMode)
	self:applyModeToZones()
	self:drawTowerRanges()
	if isBuildMode then
		self:renderEntries()
		self:renderTowerCount()
		self:renderPanel()
		self:step(0)
	end
end

-- the Tower Menu opening hides the bar; it comes back with the menu closed.
-- The overlay manager unfreezes the character as it closes, which Build
-- Mode undoes
function ClientDefenseTableManager:notifyBeginOverlay()
	self.pointer = nil
	if self.gui then
		self.gui.Enabled = false
	end
end

function ClientDefenseTableManager:notifyEndOverlay()
	if self.gui then
		self.gui.Enabled = self.isBuildMode
	end
	if self.isBuildMode then
		self:setCharacterFrozen(true)
	end
end

function ClientDefenseTableManager:readCatalog()
	self.catalog = PlacementRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.DEFENSE_CATALOG))
	for _, view in self.zonesByPart do
		if self.catalog then
			view.grid = PlacementRules.measureZone(view.part.CFrame, view.part.Size, self.catalog.cellSizeStuds)
		end
	end
	-- a zone that arrived before the catalogue could not be measured then
	for _, part in CollectionService:GetTagged(Tags.DEFENSIVE_ZONE) do
		self:trackZone(part)
	end
	if self.isBuildMode then
		self:renderEntries()
	end
	self:renderTowerCount()
end

-- the word, the Iron icon, and the number inside a Place or Sell button
function ClientDefenseTableManager:bindActionButton(panel: Instance?, buttonName: string, onActivated: () -> ()): TextLabel?
	local button = if panel then panel:FindFirstChild(buttonName) else nil
	if not button or not button:IsA("GuiButton") then
		return nil
	end
	button.Activated:Connect(onActivated)
	local priceRow = button:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ROW)
	local priceIcon = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ICON) else nil
	if priceIcon and priceIcon:IsA("ImageLabel") then
		local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
		priceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
	end
	local priceLabel = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_LABEL) else nil
	return if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil
end

function ClientDefenseTableManager:bindDismissButton(panel: Instance?, buttonName: string, onActivated: () -> ())
	local button = if panel then panel:FindFirstChild(buttonName) else nil
	if button and button:IsA("GuiButton") then
		button.Activated:Connect(onActivated)
	end
end

function ClientDefenseTableManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.BUILD_BAR_GUI_NAME, 10)
	local surfaceGui = playerGui:WaitForChild(Constants.BUILD_SURFACE_GUI_NAME, 10)
	local surface = if surfaceGui then surfaceGui:FindFirstChild(Constants.BUILD_SURFACE_BUTTON) else nil
	if not gui or not gui:IsA("ScreenGui") or not surfaceGui or not surfaceGui:IsA("ScreenGui") or not surface or not surface:IsA("GuiButton") then
		warn("ClientDefenseTableManager: no BuildBar and BuildSurface ScreenGuis; run scripts/studio/build_build_bar_gui.luau")
		return
	end
	gui.Enabled = false
	surfaceGui.Enabled = false
	local entriesFrame = gui:FindFirstChild(Constants.BUILD_BAR_ENTRIES_FRAME)
	local template = if entriesFrame then entriesFrame:FindFirstChild(Constants.BUILD_BAR_ENTRY_TEMPLATE) else nil
	if not entriesFrame or not entriesFrame:IsA("GuiObject") or not template or not template:IsA("GuiButton") then
		warn("ClientDefenseTableManager: BuildBar is missing Entries.EntryTemplate; rebuild it with scripts/studio/build_build_bar_gui.luau")
		return
	end
	self.gui = gui
	self.surfaceGui = surfaceGui
	self.entriesFrame = entriesFrame
	self.entryTemplate = template
	template.Visible = false

	surface.InputBegan:Connect(
		function(input: InputObject)
			self:onSurfaceInputBegan(input)
		end
	)
	-- the wheel only zooms while the mouse is over the world, so the bar keeps its own scroll
	for steps, signal in { [1] = surface.MouseWheelForward, [-1] = surface.MouseWheelBackward } do
		signal:Connect(
			function()
				if self.isBuildMode and not ClientOverlayManager:isOverlayActive() then
					self:zoom(steps)
				end
			end
		)
	end

	local hintLabel = gui:FindFirstChild(Constants.BUILD_BAR_HINT_LABEL)
	self.hintLabel = if hintLabel and hintLabel:IsA("TextLabel") then hintLabel else nil
	local towerCount = gui:FindFirstChild(Constants.BUILD_BAR_TOWER_COUNT_FRAME)
	local towerCountLabel = if towerCount then towerCount:FindFirstChild(Constants.BUILD_BAR_TOWER_COUNT_LABEL) else nil
	self.towerCountLabel = if towerCountLabel and towerCountLabel:IsA("TextLabel") then towerCountLabel else nil
	local towerCountIcon = if towerCount then towerCount:FindFirstChild(Constants.BUILD_BAR_TOWER_COUNT_ICON) else nil
	if towerCountIcon and towerCountIcon:IsA("ImageLabel") then
		local imageId = Icons.UI.TOWER
		towerCountIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		-- the disc stands in only while there is no image
		towerCountIcon.BackgroundTransparency = if Icons.isPlaceholder(imageId) then 0 else 1
	end
	local exitButton = gui:FindFirstChild(Constants.BUILD_BAR_EXIT_BUTTON)
	if exitButton and exitButton:IsA("GuiButton") then
		exitButton.Activated:Connect(
			function()
				ClientNetManager:fireServer(NetEventNames.TRY_EXIT_BUILD_MODE, {})
			end
		)
	end

	local placePanel = gui:FindFirstChild(Constants.BUILD_BAR_PLACE_PANEL)
	self.placePanel = if placePanel and placePanel:IsA("GuiObject") then placePanel else nil
	local placeButton = if placePanel then placePanel:FindFirstChild(Constants.BUILD_BAR_PLACE_BUTTON) else nil
	self.placeButton = if placeButton and placeButton:IsA("GuiButton") then placeButton else nil
	self.placePriceLabel = self:bindActionButton(
		placePanel,
		Constants.BUILD_BAR_PLACE_BUTTON,
		function()
			self:place()
		end
	)
	self:bindDismissButton(
		placePanel,
		Constants.BUILD_BAR_CANCEL_BUTTON,
		function()
			self:cancel()
		end
	)
	local rotateButton = if placePanel then placePanel:FindFirstChild(Constants.BUILD_BAR_ROTATE_BUTTON) else nil
	self.rotateButton = if rotateButton and rotateButton:IsA("GuiButton") then rotateButton else nil
	self:bindDismissButton(
		placePanel,
		Constants.BUILD_BAR_ROTATE_BUTTON,
		function()
			self:rotate()
		end
	)
	local sellPanel = gui:FindFirstChild(Constants.BUILD_BAR_SELL_PANEL)
	self.sellPanel = if sellPanel and sellPanel:IsA("GuiObject") then sellPanel else nil
	self.sellPriceLabel = self:bindActionButton(
		sellPanel,
		Constants.BUILD_BAR_SELL_BUTTON,
		function()
			self:sellOpenTrap()
		end
	)
	self:bindDismissButton(
		sellPanel,
		Constants.BUILD_BAR_CLOSE_BUTTON,
		function()
			self:closeSellPanel()
		end
	)
	self:bindDismissButton(
		sellPanel,
		Constants.BUILD_BAR_MOVE_BUTTON,
		function()
			local shadow = self.sellShadow
			self:closeSellPanel()
			if shadow then
				self:startMove(shadow)
			end
		end
	)
	self:renderPanel()
end

function ClientDefenseTableManager:init()
	self:readCatalog()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.DEFENSE_CATALOG,
		function()
			self:readCatalog()
		end
	)
	self:findGui()
	local gridFolder = Instance.new("Folder")
	gridFolder.Name = Constants.PLACEMENT_GRID_FOLDER
	gridFolder.Parent = workspace
	self.gridFolder = gridFolder

	for _, part in CollectionService:GetTagged(Tags.DEFENSIVE_ZONE) do
		self:trackZone(part)
	end
	CollectionService:GetInstanceAddedSignal(Tags.DEFENSIVE_ZONE):Connect(
		function(part: Instance)
			self:trackZone(part)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.DEFENSIVE_ZONE):Connect(
		function(part: Instance)
			self:untrackZone(part)
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.TOWER_LOADOUT,
		function()
			if self.isBuildMode then
				self:renderEntries()
			end
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.BALANCE_IRON_BARS,
		function()
			self:renderAffordability()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.ACTIVE_TOWER_COUNT,
		function()
			self:renderTowerCount()
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_SCALING_COUNT,
		function()
			self:renderTowerCount()
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.CAMP_LEVEL,
		function()
			self:renderAffordability()
		end
	)
	-- a placement appearing or going can free or take the ghost's cells,
	-- and changes the rings of reach on show
	ClientPlacementManager:subscribeChanged(
		function()
			self:refreshGhost()
			self:drawTowerRanges()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	UserInputService.InputChanged:Connect(
		function(input: InputObject)
			self:onInputChanged(input)
		end
	)
	UserInputService.InputEnded:Connect(
		function(input: InputObject)
			self:onInputEnded(input)
		end
	)
	UserInputService.TouchPinch:Connect(
		function(_touchPositions: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState, _isGameProcessed: boolean)
			self:onTouchPinch(scale, state)
		end
	)
	local function applyBuildMode(value: any)
		self:setBuildMode(value == true)
	end
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.IS_IN_BUILD_MODE, applyBuildMode)
	applyBuildMode(ClientDataManager:getCurrentPlayerAttribute(Attributes.IS_IN_BUILD_MODE))
	ClientOverlayManager:addOverlayNotifier(self)
	-- the Tower Menu's Move button hands the Tower over once the menu has closed
	ClientTowerMenuManager:setMoveHandler(
		function(shadow: BasePart)
			if self.isBuildMode then
				self:startMove(shadow)
			end
		end
	)
end

function ClientDefenseTableManager.new(): ClientDefenseTableManager
	local self = setmetatable({}, ClientDefenseTableManager) :: ClientDefenseTableManager
	self.gui = nil
	self.surfaceGui = nil
	self.entriesFrame = nil
	self.entryTemplate = nil
	self.placePanel = nil
	self.placeButton = nil
	self.placePriceLabel = nil
	self.rotateButton = nil
	self.sellPanel = nil
	self.sellPriceLabel = nil
	self.hintLabel = nil
	self.towerCountLabel = nil
	self.isBuildMode = false
	self.catalog = nil
	self.entries = {}
	self.zonesByPart = {}
	self.gridFolder = nil
	self.rangeFolder = nil
	self.selection = nil
	self.targetZone = nil
	self.targetCell = nil
	self.canPlaceHere = false
	self.moveShadow = nil
	self.isAdvancePending = false
	self.sellShadow = nil
	self.sellConnection = nil
	self.cameraZone = nil
	self.focus = Vector3.zero
	self.distanceStuds = DEFAULT_CAMERA_DISTANCE_STUDS
	self.forwardX = 0
	self.forwardZ = -1
	self.savedCameraType = nil
	self.savedCameraCFrame = nil
	self.transitionFromCFrame = nil
	self.transitionStartTime = nil
	self.exitTween = nil
	self.anchoredRootPart = nil
	self.stepConnection = nil
	self.pointer = nil
	self.pinchStartDistanceStuds = nil
	return self
end

return ClientDefenseTableManager.new()
