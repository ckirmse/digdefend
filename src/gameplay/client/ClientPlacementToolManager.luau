--!strict

-- Build Mode (GDD "Building Towers", "Placing Traps"), M26. Equipping
-- the Defenses tool is Build Mode (decided 2026-09-21, replacing the
-- Hammer: in first person the cursor is locked, so nothing that needs a
-- click can be the way in). While it is equipped this manager hides the
-- tool bar and shows the BuildBar in its place: one numbered slot per
-- Tower the loadout brought and one per Trap kind carried, styled like a
-- tool bar slot with the kind as a badge, the name above, and the Iron
-- price or the Trap count under it, greyed while the player cannot pay, and draws the grid and outline over every Defensive Zone
-- part. A number key, or a tap, brings out a preview of that model ten
-- studs in front of the player, snapped to the nearest zone's grid, green
-- where every cell is inside and free and red otherwise. A click, the
-- touch action button, or the Build button asks the server
-- (TryBuildPlacement) with the zone and anchor cell; the server decides.
-- One entry is always selected while the mode is on (decided 2026-09-21:
-- there is no "nothing out" state); a right click on PC, B on gamepad, or
-- the touch Exit button leaves Build Mode by unequipping the tool. The
-- grid, the snapping, and the colour run the same PlacementRules maths the
-- server checks with.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
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

local ClientPlacementToolManager = {}
ClientPlacementToolManager.__index = ClientPlacementToolManager

type Entry = {
	placementKind: number,
	typeKind: number,
	frame: GuiButton,
}

type ZoneView = {
	part: BasePart,
	index: number,
	grid: PlacementRules.Grid,
	lines: Folder?,
	outline: SelectionBox?,
}

type Selection = {
	placementKind: number,
	typeKind: number,
	footprint: { number },
	preview: Model,
	-- every part's own colour, put back when the preview is placeable; the
	-- parts themselves go red when it is not (a Highlight did not read
	-- through the translucent preview, 2026-09-21)
	colorByPart: { [BasePart]: Color3 },
	isTintedRed: boolean,
}

export type ClientPlacementToolManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		entriesFrame: Frame?,
		entryTemplate: GuiButton?,
		exitButton: GuiButton?,
		placementPanel: GuiObject?,
		buildButton: GuiButton?,
		buildPriceLabel: TextLabel?,
		buildPriceRow: GuiObject?,
		buildTextLabel: TextLabel?,
		hintLabel: TextLabel?,
		exitKeyLabel: TextLabel?,
		towerCountLabel: TextLabel?,
		isTouchOnly: boolean,
		-- whether the aim point is inside a zone: the preview only shows there
		isInZone: boolean,
		hasWarnedBillboard: boolean,
		isBuildMode: boolean,
		catalog: PlacementRules.Catalog?,
		entries: { Entry },
		zonesByPart: { [BasePart]: ZoneView },
		gridFolder: Folder?,
		selection: Selection?,
		-- where the preview stands right now, if it fits anywhere
		targetZone: ZoneView?,
		targetCell: PlacementRules.Cell?,
		canPlaceHere: boolean,
		stepConnection: RBXScriptConnection?,
	},
	ClientPlacementToolManager
))

local FEEDBACK_NOT_ENOUGH_IRON = "You don't have enough Iron Bars"
local FEEDBACK_NO_SPACE = "Not enough space"
local FEEDBACK_OUTSIDE_ZONE = "Go to the Defensive Zone to place Defenses"
local HINT_CANNOT_PLACE = "Cannot place here"
local BUILD_TEXT = "Build"
-- keyboard and gamepad cannot tap the buttons (the cursor is locked), so
-- they read a hint instead; the gamepad names follow the connected controller
local HINT_KEYBOARD = "LMB to place, RMB to exit"
local HINT_GAMEPAD_FORMAT = "%s to place, %s to exit"
-- the Exit button's shortcut, shown in the button's corner for keyboard and gamepad
local EXIT_KEY_KEYBOARD = "[RMB]"
local EXIT_KEY_GAMEPAD_FORMAT = "[%s]"
local GAMEPAD_BUILD_NAME_XBOX = "RT"
local GAMEPAD_BUILD_NAME_PLAYSTATION = "R2"
local GAMEPAD_EXIT_NAME_XBOX = "B"
local GAMEPAD_EXIT_NAME_PLAYSTATION = "Circle"
local COUNT_FORMAT = "x%d"
local TOWER_COUNT_FORMAT = "%d / %d"
local PREVIEW_TRANSPARENCY = 0.45
local CANNOT_PLACE_COLOR = Color3.fromRGB(230, 70, 60)
local GRID_LINE_COLOR = Color3.fromRGB(245, 200, 80)
local GRID_LINE_THICKNESS_STUDS = 0.12
local GRID_LINE_LIFT_STUDS = 0.06
local OUTLINE_THICKNESS_STUDS = 0.15
-- the range ring around a Tower preview (decided 2026-09-22): a circle
-- of the Tower's reach drawn as flat segments on the ground
local RANGE_RING_NAME = "RangeRing"
local RANGE_RING_SEGMENTS = 64
local RANGE_RING_THICKNESS_STUDS = 0.35
local RANGE_RING_HEIGHT_STUDS = 0.1
local RANGE_RING_LIFT_STUDS = 0.15
local RANGE_RING_COLOR = Color3.fromRGB(120, 200, 255)
local RANGE_RING_TRANSPARENCY = 0.25
local GREYED_TRANSPARENCY = 0.55
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

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientPlacementToolManager:getIron(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS), 0)
end

function ClientPlacementToolManager:getTrapCounts(): { [number]: number }
	return PlacementRules.decodeTrapCounts(ClientDataManager:getCurrentPlayerAttribute(Attributes.TRAP_COUNTS))
end

function ClientPlacementToolManager:getLoadout(): { number }
	return PlacementRules.decodeTowerLoadout(ClientDataManager:getCurrentPlayerAttribute(Attributes.TOWER_LOADOUT))
end

function ClientPlacementToolManager:getIsPlacing(): boolean
	return self.selection ~= nil
end

function ClientPlacementToolManager:getIsGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

-- Roblox names the button for the connected controller
function ClientPlacementToolManager:getIsPlayStation(): boolean
	return string.find(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA), "Cross") ~= nil
end

-- "[RMB]" or "[B]" in the Exit button's corner; touch taps the button itself
function ClientPlacementToolManager:renderExitButton()
	local keyLabel = self.exitKeyLabel
	if not keyLabel then
		return
	end
	keyLabel.Visible = not self.isTouchOnly
	local text = EXIT_KEY_KEYBOARD
	if self:getIsGamepad() then
		text = string.format(EXIT_KEY_GAMEPAD_FORMAT, if self:getIsPlayStation() then GAMEPAD_EXIT_NAME_PLAYSTATION else GAMEPAD_EXIT_NAME_XBOX)
	end
	keyLabel.Text = UiStyle.formatTitle(text)
end

-- what an entry costs the player to place: Iron for a Tower, one carried Trap for a Trap
function ClientPlacementToolManager:canAffordEntry(placementKind: number, typeKind: number): boolean
	local catalog = self.catalog
	if not catalog then
		return false
	end
	if placementKind == Enums.PlacementKind.TOWER then
		return PlacementRules.canAfford(self:getIron(), PlacementRules.buildPrice(catalog, placementKind, typeKind))
	end
	return (self:getTrapCounts()[typeKind] or 0) > 0
end

function ClientPlacementToolManager:renderEntry(entry: Entry, index: number)
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
		priceIcon.Visible = isTower
	end
	if priceLabel and priceLabel:IsA("TextLabel") then
		if isTower then
			priceLabel.Text = tostring(PlacementRules.buildPrice(catalog, entry.placementKind, entry.typeKind))
		else
			priceLabel.Text = string.format(COUNT_FORMAT, self:getTrapCounts()[entry.typeKind] or 0)
		end
		priceLabel.TextColor3 = if isAffordable then UiStyle.TEXT_COLOR else UiStyle.NEGATIVE_COLOR
	end
end

function ClientPlacementToolManager:renderEntries()
	local entriesFrame = self.entriesFrame
	local template = self.entryTemplate
	if not entriesFrame or not template then
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
	for kind in self:getTrapCounts() do
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
				self:select(entry.placementKind, entry.typeKind)
			end
		)
		frame.Parent = entriesFrame
		table.insert(self.entries, entry)
		self:renderEntry(entry, order)
	end
	-- a Trap that ran out mid-preview hands the selection to the first entry
	local selection = self.selection
	if selection and not self:findEntry(selection.placementKind, selection.typeKind) then
		self:cancel()
	end
	if not self.selection and self.isBuildMode then
		self:selectEntryIndex(1)
	end
end

function ClientPlacementToolManager:findEntry(placementKind: number, typeKind: number): Entry?
	for _, entry in self.entries do
		if entry.placementKind == placementKind and entry.typeKind == typeKind then
			return entry
		end
	end
	return nil
end

-- Towers standing against the limit; red once it is reached
function ClientPlacementToolManager:renderTowerCount()
	local label = self.towerCountLabel
	local catalog = self.catalog
	if not label or not catalog then
		return
	end
	local count = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.ACTIVE_TOWER_COUNT), 0)
	label.Text = string.format(TOWER_COUNT_FORMAT, count, catalog.maxActiveTowersPerPlayer)
	label.TextColor3 = if count >= catalog.maxActiveTowersPerPlayer then UiStyle.NEGATIVE_COLOR else UiStyle.TEXT_COLOR
end

function ClientPlacementToolManager:renderAffordability()
	for index, entry in self.entries do
		self:renderEntry(entry, index)
	end
	self:renderPanel()
end

-- the Build button shows the price in red when the player is short, and
-- only appears while the preview is green (GDD: a red preview has no button)
function ClientPlacementToolManager:renderPanel()
	local panel = self.placementPanel
	local selection = self.selection
	local catalog = self.catalog
	if not panel then
		return
	end
	-- touch gets the buttons once the preview is in the zone; everyone
	-- reads the zone message while it is not
	panel.Visible = selection ~= nil and self.isTouchOnly and self.isInZone
	local hintLabel = self.hintLabel
	if hintLabel then
		hintLabel.Visible = selection ~= nil and (not self.isTouchOnly or not self.isInZone or not self.canPlaceHere)
		local hint = FEEDBACK_OUTSIDE_ZONE
		if self.isInZone and not self.canPlaceHere then
			hint = HINT_CANNOT_PLACE
		elseif self.isInZone then
			hint = HINT_KEYBOARD
			if self:getIsGamepad() then
				local isPlayStation = self:getIsPlayStation()
				hint = string.format(HINT_GAMEPAD_FORMAT, if isPlayStation then GAMEPAD_BUILD_NAME_PLAYSTATION else GAMEPAD_BUILD_NAME_XBOX, if isPlayStation then GAMEPAD_EXIT_NAME_PLAYSTATION else GAMEPAD_EXIT_NAME_XBOX)
			end
		end
		hintLabel.Text = UiStyle.formatTitle(hint)
	end
	if not selection or not catalog then
		return
	end
	local button = self.buildButton
	if button then
		button.Visible = self.canPlaceHere
	end
	local price = PlacementRules.buildPrice(catalog, selection.placementKind, selection.typeKind)
	local isTower = selection.placementKind == Enums.PlacementKind.TOWER
	if self.buildPriceRow then
		self.buildPriceRow.Visible = isTower
	end
	if self.buildPriceLabel then
		self.buildPriceLabel.Text = tostring(price)
		self.buildPriceLabel.TextColor3 = if PlacementRules.canAfford(self:getIron(), price) then UiStyle.ACCENT_STROKE_COLOR else UiStyle.NEGATIVE_COLOR
	end
	if self.buildTextLabel then
		self.buildTextLabel.Text = UiStyle.formatTitle(BUILD_TEXT)
	end
end

function ClientPlacementToolManager:findZoneBillboardTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.DEFENSIVE_ZONE_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedBillboard then
		self.hasWarnedBillboard = true
		warn(`ClientPlacementToolManager: no {Constants.DEFENSIVE_ZONE_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_defensive_zone_billboard.luau`)
	end
	return nil
end

-- the grid over one zone: thin bars along every column and row edge, on
-- the top face, plus a box around the part; both local and only in Build Mode
function ClientPlacementToolManager:drawZone(view: ZoneView)
	if view.lines then
		return
	end
	local gridFolder = self.gridFolder
	if not gridFolder then
		return
	end
	local grid = view.grid
	local folder = Instance.new("Folder")
	folder.Name = view.part.Name
	local width = grid.columns * grid.cellSizeStuds
	local depth = grid.rows * grid.cellSizeStuds
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
		line.Transparency = 0.35
		line.CFrame = grid.cframe * CFrame.new(offset + Vector3.new(0, GRID_LINE_LIFT_STUDS, 0))
		line.Parent = folder
	end
	for column = 0, grid.columns do
		addLine(`Column{column}`, Vector3.new(GRID_LINE_THICKNESS_STUDS, GRID_LINE_THICKNESS_STUDS, depth), Vector3.new((column - grid.columns / 2) * grid.cellSizeStuds, 0, 0))
	end
	for row = 0, grid.rows do
		addLine(`Row{row}`, Vector3.new(width, GRID_LINE_THICKNESS_STUDS, GRID_LINE_THICKNESS_STUDS), Vector3.new(0, 0, (row - grid.rows / 2) * grid.cellSizeStuds))
	end
	folder.Parent = gridFolder
	view.lines = folder
	local billboardTemplate = self:findZoneBillboardTemplate()
	if billboardTemplate then
		local billboard = billboardTemplate:Clone()
		billboard.Adornee = view.part
		billboard.Parent = folder
	end
	local outline = Instance.new("SelectionBox")
	outline.Name = "Outline"
	outline.Adornee = view.part
	outline.Color3 = GRID_LINE_COLOR
	outline.LineThickness = OUTLINE_THICKNESS_STUDS
	outline.SurfaceTransparency = 1
	outline.Parent = folder
	view.outline = outline
end

function ClientPlacementToolManager:eraseZone(view: ZoneView)
	if view.lines then
		view.lines:Destroy()
		view.lines = nil
		view.outline = nil
	end
end

function ClientPlacementToolManager:applyModeToZones()
	for _, view in self.zonesByPart do
		if self.isBuildMode then
			self:drawZone(view)
		else
			self:eraseZone(view)
		end
	end
end

function ClientPlacementToolManager:trackZone(part: Instance)
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
		lines = nil,
		outline = nil,
	}
	self.zonesByPart[part] = view
	part:GetAttributeChangedSignal(Attributes.DEFENSIVE_ZONE_INDEX):Connect(
		function()
			view.index = readNumber(part:GetAttribute(Attributes.DEFENSIVE_ZONE_INDEX), 0)
		end
	)
	if self.isBuildMode then
		self:drawZone(view)
	end
end

function ClientPlacementToolManager:untrackZone(part: Instance)
	local view = self.zonesByPart[part :: BasePart]
	if not view then
		return
	end
	self:eraseZone(view)
	self.zonesByPart[part :: BasePart] = nil
	if self.targetZone == view then
		self.targetZone = nil
	end
end

-- the cells the standing placements cover in one zone, from their shadows
function ClientPlacementToolManager:occupancyFor(view: ZoneView): PlacementRules.Occupancy
	local occupancy: PlacementRules.Occupancy = {}
	local catalog = self.catalog
	if not catalog then
		return occupancy
	end
	for _, shadow in ClientPlacementManager:getTrackedShadows() do
		if readNumber(shadow:GetAttribute(Attributes.DEFENSIVE_ZONE_INDEX), 0) ~= view.index then
			continue
		end
		local placementKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_KIND), 0)
		local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
		local footprint = PlacementRules.footprintFor(catalog, placementKind, typeKind) or { 1, 1 }
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

-- the zone the aim point falls in; none means the player is too far from
-- any zone to see what they would build, so no preview shows (decided 2026-09-21)
function ClientPlacementToolManager:findZone(position: Vector3): ZoneView?
	for _, view in self.zonesByPart do
		if view.index > 0 and PlacementRules.isCellInside(view.grid, PlacementRules.cellFromPosition(view.grid, position)) then
			return view
		end
	end
	return nil
end

function ClientPlacementToolManager:setPreviewColor(selection: Selection, canPlace: boolean)
	local wantRed = not canPlace
	if selection.isTintedRed == wantRed then
		return
	end
	selection.isTintedRed = wantRed
	for part, color in selection.colorByPart do
		part.Color = if wantRed then CANNOT_PLACE_COLOR else color
	end
end

-- every frame with a preview out: it stands in front of the player,
-- snapped to the grid, coloured by whether it could be built
function ClientPlacementToolManager:step()
	local selection = self.selection
	local catalog = self.catalog
	if not selection or not catalog then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local forward = root.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	forward = if forward.Magnitude > 0.001 then forward.Unit else Vector3.zAxis
	local aimPoint = root.Position + forward * catalog.previewDistanceStuds
	local view = self:findZone(aimPoint)
	local wasPlaceable = self.canPlaceHere
	local wasInZone = self.isInZone
	self.isInZone = view ~= nil
	if not view then
		self.targetZone = nil
		self.targetCell = nil
		self.canPlaceHere = false
		-- out of the zone the preview is put away, not shown somewhere the player cannot see
		selection.preview.Parent = nil
	else
		local anchor = PlacementRules.clampAnchor(view.grid, PlacementRules.anchorFromPosition(view.grid, aimPoint, selection.footprint), selection.footprint)
		self.targetZone = view
		self.targetCell = anchor
		if anchor then
			selection.preview:PivotTo(PlacementRules.footprintCFrame(view.grid, anchor, selection.footprint))
			self.canPlaceHere = PlacementRules.canPlace(view.grid, self:occupancyFor(view), anchor, selection.footprint)
		else
			self.canPlaceHere = false
		end
		selection.preview.Parent = ClientPlacementManager:getBodiesFolder()
	end
	self:setPreviewColor(selection, self.canPlaceHere)
	if wasPlaceable ~= self.canPlaceHere or wasInZone ~= self.isInZone then
		self:renderPanel()
	end
end

function ClientPlacementToolManager:cancel()
	local selection = self.selection
	if not selection then
		return
	end
	self.selection = nil
	selection.preview:Destroy()
	self.targetZone = nil
	self.targetCell = nil
	self.canPlaceHere = false
	self.isInZone = false
	if self.stepConnection then
		self.stepConnection:Disconnect()
		self.stepConnection = nil
	end
	self:renderAffordability()
end

-- a Tower preview carries a ring of its reach (TowerRules.reachStuds) so
-- the player sees what the spot covers before building; it moves with the
-- preview because it is part of the model, and never tints red
function ClientPlacementToolManager:addRangeRing(preview: Model, placementKind: number, typeKind: number, footprint: { number })
	local catalog = self.catalog
	if not catalog or placementKind ~= Enums.PlacementKind.TOWER then
		return
	end
	local tower = catalog.towers[typeKind]
	if not tower then
		return
	end
	local stats = PlacementRules.towerStats(tower, PlacementRules.STARTING_LEVEL)
	local radius = TowerRules.reachStuds(stats.RANGE_STUDS, footprint, catalog.cellSizeStuds)
	local ring = Instance.new("Model")
	ring.Name = RANGE_RING_NAME
	local pivot = preview:GetPivot()
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
		segment.Transparency = RANGE_RING_TRANSPARENCY
		segment.Size = Vector3.new(segmentLength, RANGE_RING_HEIGHT_STUDS, RANGE_RING_THICKNESS_STUDS)
		-- each segment sits on the circle, turned to run along it
		segment.CFrame = pivot * CFrame.Angles(0, -angle, 0) * CFrame.new(0, RANGE_RING_LIFT_STUDS, -radius)
		segment.Parent = ring
	end
	ring.Parent = preview
end

function ClientPlacementToolManager:select(placementKind: number, typeKind: number)
	local catalog = self.catalog
	if not catalog or not self.isBuildMode then
		return
	end
	self:cancel()
	local footprint = PlacementRules.footprintFor(catalog, placementKind, typeKind)
	if not footprint then
		return
	end
	local shadowSize = Vector3.new(footprint[1] * catalog.cellSizeStuds, 1, footprint[2] * catalog.cellSizeStuds)
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
	self:addRangeRing(preview, placementKind, typeKind, footprint)
	preview.Parent = ClientPlacementManager:getBodiesFolder()
	self.selection = {
		placementKind = placementKind,
		typeKind = typeKind,
		footprint = footprint,
		preview = preview,
		colorByPart = colorByPart,
		isTintedRed = false,
	}
	self.stepConnection = RunService.RenderStepped:Connect(
		function()
			self:step()
		end
	)
	self:step()
	self:renderAffordability()
end

function ClientPlacementToolManager:selectEntryIndex(index: number)
	local entry = self.entries[index]
	if entry then
		self:select(entry.placementKind, entry.typeKind)
	end
end

-- a build that cannot go through is refused here with the Fail sound and
-- the reason; the server checks again regardless
function ClientPlacementToolManager:build()
	local selection = self.selection
	local catalog = self.catalog
	local view = self.targetZone
	local cell = self.targetCell
	if not selection or not catalog then
		return
	end
	if not view or not cell or not self.isInZone then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_OUTSIDE_ZONE)
		return
	end
	if not self.canPlaceHere then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NO_SPACE)
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
	})
	-- the entry stays selected for the next one; a Trap that ran out is
	-- handed over when its count arrives (renderEntries)
end

-- right click, gamepad B, or the touch Exit button: out of Build Mode,
-- which unequips the tool and brings the tool bar back
function ClientPlacementToolManager:exit()
	self:cancel()
	ClientToolBarManager:requestEquip(MiningRules.NO_TOOL)
end

function ClientPlacementToolManager:setBuildMode(isBuildMode: boolean)
	if self.isBuildMode == isBuildMode then
		return
	end
	self.isBuildMode = isBuildMode
	if not isBuildMode then
		self:cancel()
	end
	local gui = self.gui
	if gui then
		gui.Enabled = isBuildMode
	end
	ClientToolBarManager:setHidden(isBuildMode)
	self:applyModeToZones()
	if isBuildMode then
		-- renderEntries selects the first entry, so entering the mode is one press
		self:renderEntries()
		self:renderTowerCount()
	end
end

function ClientPlacementToolManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not self.isBuildMode or ClientOverlayManager:isOverlayActive() then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		if index then
			self:selectEntryIndex(index)
		end
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		if self.selection then
			self:build()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonB then
		self:exit()
	elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
		self:selectEntryIndex((self:selectedIndex() or 0) % math.max(#self.entries, 1) + 1)
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
		self:selectEntryIndex(((self:selectedIndex() or 1) - 2) % math.max(#self.entries, 1) + 1)
	end
end

function ClientPlacementToolManager:selectedIndex(): number?
	local selection = self.selection
	if not selection then
		return nil
	end
	for index, entry in self.entries do
		if entry.placementKind == selection.placementKind and entry.typeKind == selection.typeKind then
			return index
		end
	end
	return nil
end

-- a menu opening puts the preview away; the bar stays, hidden with the rest of the HUD
function ClientPlacementToolManager:notifyBeginOverlay()
	self:cancel()
	local gui = self.gui
	if gui then
		gui.Enabled = false
	end
end

function ClientPlacementToolManager:notifyEndOverlay()
	local gui = self.gui
	if gui then
		gui.Enabled = self.isBuildMode
	end
end

function ClientPlacementToolManager:readCatalog()
	self.catalog = PlacementRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.DEFENSE_CATALOG))
	for _, view in self.zonesByPart do
		if self.catalog then
			view.grid = PlacementRules.measureZone(view.part.CFrame, view.part.Size, self.catalog.cellSizeStuds)
		end
	end
	-- an zone that arrived before the catalogue could not be measured then
	for _, part in CollectionService:GetTagged(Tags.DEFENSIVE_ZONE) do
		self:trackZone(part)
	end
	if self.isBuildMode then
		self:renderEntries()
	end
	self:renderTowerCount()
end

function ClientPlacementToolManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.BUILD_BAR_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientPlacementToolManager: no BuildBar ScreenGui; run scripts/studio/build_build_bar_gui.luau")
		return
	end
	gui.Enabled = false
	self.gui = gui
	local entriesFrame = gui:FindFirstChild(Constants.BUILD_BAR_ENTRIES_FRAME)
	local template = if entriesFrame then entriesFrame:FindFirstChild(Constants.BUILD_BAR_ENTRY_TEMPLATE) else nil
	if not entriesFrame or not entriesFrame:IsA("Frame") or not template or not template:IsA("GuiButton") then
		warn("ClientPlacementToolManager: BuildBar is missing Entries.EntryTemplate")
		return
	end
	self.entriesFrame = entriesFrame
	self.entryTemplate = template
	template.Visible = false
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
		self.exitButton = exitButton
		exitButton.Visible = true
		local exitKeyLabel = exitButton:FindFirstChild(Constants.BUILD_BAR_EXIT_KEY_LABEL)
		self.exitKeyLabel = if exitKeyLabel and exitKeyLabel:IsA("TextLabel") then exitKeyLabel else nil
		self:renderExitButton()
		exitButton.Activated:Connect(
			function()
				self:exit()
			end
		)
	end
	local panel = gui:FindFirstChild(Constants.BUILD_BAR_PLACEMENT_PANEL)
	self.placementPanel = if panel and panel:IsA("GuiObject") then panel else nil
	local buildButton = if panel then panel:FindFirstChild(Constants.BUILD_BAR_BUILD_BUTTON) else nil
	if buildButton and buildButton:IsA("GuiButton") then
		self.buildButton = buildButton
		local priceRow = buildButton:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ROW)
		self.buildPriceRow = if priceRow and priceRow:IsA("GuiObject") then priceRow else nil
		local priceLabel = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_LABEL) else nil
		self.buildPriceLabel = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel else nil
		local priceIcon = if priceRow then priceRow:FindFirstChild(Constants.BUILD_BAR_BUILD_PRICE_ICON) else nil
		if priceIcon and priceIcon:IsA("ImageLabel") then
			local imageId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
			priceIcon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		end
		local text = buildButton:FindFirstChild(Constants.BUILD_BAR_BUILD_TEXT_LABEL)
		self.buildTextLabel = if text and text:IsA("TextLabel") then text else nil
		buildButton.Activated:Connect(
			function()
				self:build()
			end
		)
	end
	-- there is no cancel state any more: an entry is always selected
	local cancelButton = if panel then panel:FindFirstChild(Constants.BUILD_BAR_CANCEL_BUTTON) else nil
	if cancelButton and cancelButton:IsA("GuiObject") then
		cancelButton.Visible = false
	end
	self:renderPanel()
end

function ClientPlacementToolManager:init()
	self.isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
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
	for _, key in { Attributes.TOWER_LOADOUT, Attributes.TRAP_COUNTS } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				if self.isBuildMode then
					self:renderEntries()
				end
			end
		)
	end
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
	-- a placement appearing or going can free or take the preview's cells
	ClientPlacementManager:subscribeChanged(
		function()
			self:step()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	local function applyEquipped(value: any)
		self:setBuildMode(value == Enums.ToolKind.DEFENSES)
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
	ClientOverlayManager:addOverlayNotifier(self)
end

function ClientPlacementToolManager.new(): ClientPlacementToolManager
	local self = setmetatable({}, ClientPlacementToolManager) :: ClientPlacementToolManager
	self.gui = nil
	self.entriesFrame = nil
	self.entryTemplate = nil
	self.exitButton = nil
	self.placementPanel = nil
	self.buildButton = nil
	self.buildPriceLabel = nil
	self.buildPriceRow = nil
	self.buildTextLabel = nil
	self.hintLabel = nil
	self.exitKeyLabel = nil
	self.towerCountLabel = nil
	self.isTouchOnly = false
	self.isInZone = false
	self.hasWarnedBillboard = false
	self.isBuildMode = false
	self.catalog = nil
	self.entries = {}
	self.zonesByPart = {}
	self.gridFolder = nil
	self.selection = nil
	self.targetZone = nil
	self.targetCell = nil
	self.canPlaceHere = false
	self.stepConnection = nil
	return self
end

return ClientPlacementToolManager.new()
