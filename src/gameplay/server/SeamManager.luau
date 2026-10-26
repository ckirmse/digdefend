--!strict

-- The Seams (GDD "Monster Types": Seam, M68): faces in the rock that
-- burst. A Seam is a small set of rock cells held here in Lua, never a
-- body: it is not registered in DamageableManager, so no weapon can touch
-- it, and it is not a MonsterManager monster, so it never counts toward a
-- night and the Camp Map does not draw it. SeamsData.COUNT of them are
-- seated at run start from the mine's seed (pure SeamRules), each asleep
-- inside one stone cell. A cleared neighbour wakes one: from then on its
-- cells are published to every client (NOTIFY_SEAMS, the whole awake list,
-- small), it drifts a cell at a time over the exposed stone around it and
-- spreads onto neighbouring stone. A swing at any of its cells is taken
-- by MiningManager's interceptor and breaks the block outright, whatever
-- the pick (designer, 2026-10-26: one hit, and the damage is the break,
-- not the swing). Every broken cell of an awake Seam, by a swing or by
-- dynamite, bursts: MineManager's cell-cleared hook takes the cell off
-- the Seam, every player within BURST_RADIUS_STUDS is hurt through
-- ReviveManager with the Seam as the attacker (so the run report names
-- it), and the clients are told so they play the laugh and smoke and
-- shove whoever stood in it. A Seam with no cells is gone. Sleeping Seams
-- never travel to a client.
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SeamRules = require("@game/ReplicatedStorage/Shared/SeamRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local SeamsData = require("@game/ServerScriptService/GameData/Monsters/Seams")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local MineManager = require(script.Parent.MineManager)
local MiningManager = require(script.Parent.MiningManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SeamManager = {}
SeamManager.__index = SeamManager

type Cell = SeamRules.Cell

type Seam = {
	id: number,
	cells: { Cell },
	isAwake: boolean,
	nextDriftTime: number,
	nextSpreadTime: number,
	nextHumTime: number,
	-- the dev tool's marker over a sleeping Seam while the locations are shown
	marker: BasePart?,
}

export type SeamManager = typeof(setmetatable(
	{} :: {
		seams: { Seam },
		-- every held cell, awake or asleep, by SeamRules.cellKey
		occupied: { [string]: boolean },
		-- cells whose Seam woke since the last publish, announced after it
		wokenCells: { Cell },
		-- cells of an awake Seam cleared since the last publish, announced
		-- before it
		brokenCells: { Cell },
		random: Random,
		nextId: number,
		isLocationsVisible: boolean,
		markersFolder: Folder?,
	},
	SeamManager
))

local MARKER_TEXT = "Seam"
local MARKER_COLOR = Color3.fromRGB(200, 90, 255)

local TRY_REQUEST_SEAMS_SHAPE = {}

local function isStone(rock: number): boolean
	local definition = RockDefinitionsData.ROCKS[rock]
	return definition ~= nil and definition.kind == Enums.RockKind.FILLER
end

function SeamManager:getAwakeCount(): number
	local count = 0
	for _, seam in self.seams do
		if seam.isAwake then
			count += 1
		end
	end
	return count
end

function SeamManager:getSeamCount(): number
	return #self.seams
end

function SeamManager:findSeamAt(depth: number, height: number, width: number): (Seam?, number?)
	if not self.occupied[SeamRules.cellKey(depth, height, width)] then
		return nil, nil
	end
	for _, seam in self.seams do
		local index = SeamRules.indexOfCell(seam.cells, depth, height, width)
		if index then
			return seam, index
		end
	end
	return nil, nil
end

function SeamManager:cellCentre(cell: Cell): Vector3?
	local space = MineManager:getSpace()
	if not space then
		return nil
	end
	return MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width)
end

-- every awake Seam's cells, flat, for the clients
function SeamManager:encodeAwake(): { number }
	local cells: { Cell } = {}
	for _, seam in self.seams do
		if not seam.isAwake then
			continue
		end
		for _, cell in seam.cells do
			table.insert(cells, cell)
		end
	end
	return SeamRules.encodeCells(cells)
end

-- the awake list, then the cells that woke since the last publish, so a
-- client has the block before it is asked to play its wake sound
function SeamManager:publish()
	for _, cell in self.brokenCells do
		NetManager:notifyAllClients(NetEventNames.NOTIFY_SEAM_BROKEN, {
			depth = cell.depth,
			height = cell.height,
			width = cell.width,
			radiusStuds = SeamsData.BURST_RADIUS_STUDS,
			knockbackStuds = SeamsData.BURST_KNOCKBACK_STUDS,
		})
	end
	self.brokenCells = {}
	NetManager:notifyAllClients(NetEventNames.NOTIFY_SEAMS, { cells = self:encodeAwake() })
	for _, cell in self.wokenCells do
		NetManager:notifyAllClients(NetEventNames.NOTIFY_SEAM_WOKEN, {
			depth = cell.depth,
			height = cell.height,
			width = cell.width,
		})
	end
	self.wokenCells = {}
end

function SeamManager:sendTo(player: Player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_SEAMS, { cells = self:encodeAwake() })
end

-- the dev tool's markers (M68, the spiders' pattern): an anchored
-- invisible part over every sleeping Seam's block carrying the spider
-- billboard with its own text, so a tester can dig straight to one. A
-- marker goes when its Seam wakes. Server parts replicate to every
-- client, which is fine for a dev tool
function SeamManager:getMarkersFolder(): Folder
	local folder = self.markersFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.SEAM_MARKERS_FOLDER
	folder.Parent = workspace
	self.markersFolder = folder
	return folder
end

function SeamManager:findMarkerTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.SPIDER_SPAWN_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`SeamManager: no {Constants.SPIDER_SPAWN_BILLBOARD} billboard under GameAssets/{Constants.GUI_TEMPLATES_FOLDER}; run build_spider_spawn_billboard.luau`)
		return nil
	end
	return template
end

function SeamManager:placeMarker(seam: Seam)
	local cell = seam.cells[1]
	local position = if cell then self:cellCentre(cell) else nil
	if seam.marker or seam.isAwake or not position then
		return
	end
	local template = self:findMarkerTemplate()
	if not template then
		return
	end
	local marker = Instance.new("Part")
	marker.Name = MARKER_TEXT
	marker.Size = Vector3.one
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CFrame = CFrame.new(position)
	local billboard = template:Clone()
	local label = billboard:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = UiStyle.formatTitle(MARKER_TEXT)
		label.TextColor3 = MARKER_COLOR
	end
	billboard.Adornee = marker
	billboard.Parent = marker
	marker.Parent = self:getMarkersFolder()
	seam.marker = marker
end

function SeamManager:removeMarker(seam: Seam)
	local marker = seam.marker
	if marker then
		marker:Destroy()
		seam.marker = nil
	end
end

function SeamManager:setLocationsVisible(isVisible: boolean)
	self.isLocationsVisible = isVisible
	if isVisible then
		for _, seam in self.seams do
			self:placeMarker(seam)
		end
		return
	end
	for _, seam in self.seams do
		self:removeMarker(seam)
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
end

function SeamManager:wake(seam: Seam, now: number)
	self:removeMarker(seam)
	seam.isAwake = true
	seam.nextDriftTime = now + SeamsData.DRIFT_INTERVAL_SEC
	seam.nextSpreadTime = now + SeamsData.SPREAD_INTERVAL_SEC
	seam.nextHumTime = now
	local cell = seam.cells[1]
	if cell then
		table.insert(self.wokenCells, cell)
	end
end

function SeamManager:removeCell(seam: Seam, index: number)
	local cell = table.remove(seam.cells, index)
	if cell then
		self.occupied[SeamRules.cellKey(cell.depth, cell.height, cell.width)] = nil
	end
end

function SeamManager:removeSeam(seam: Seam)
	self:removeMarker(seam)
	for index = #seam.cells, 1, -1 do
		self:removeCell(seam, index)
	end
	local position = table.find(self.seams, seam)
	if position then
		table.remove(self.seams, position)
	end
end

-- the burst of a broken awake cell: every player standing in the smoke's
-- reach takes the damage, the Seam named as the attacker
function SeamManager:burst(cell: Cell)
	local centre = self:cellCentre(cell)
	if not centre then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") and (root.Position - centre).Magnitude <= SeamsData.BURST_RADIUS_STUDS then
			ReviveManager:damagePlayer(player, SeamsData.BURST_DAMAGE, SeamsData.KIND)
		end
	end
	table.insert(self.brokenCells, cell)
end

-- a cleared cell: a Seam's own cell bursts and goes (a swing or dynamite),
-- and any sleeping Seam whose face it uncovered wakes
function SeamManager:onCellCleared(depth: number, height: number, width: number)
	local now = workspace:GetServerTimeNow()
	local isChanged = false
	local seam, index = self:findSeamAt(depth, height, width)
	if seam and index then
		if seam.isAwake then
			self:burst({ depth = depth, height = height, width = width })
		end
		self:removeCell(seam, index)
		if #seam.cells == 0 then
			self:removeSeam(seam)
		end
		isChanged = isChanged or seam.isAwake
	end
	for _, candidate in self.seams do
		if not candidate.isAwake and SeamRules.isWokenBy(candidate.cells, depth, height, width) then
			self:wake(candidate, now)
			isChanged = true
		end
	end
	if isChanged then
		self:publish()
	end
end

-- a swing at an awake Seam's cell breaks the block in one hit, whatever
-- the pick: the clear runs the burst through the cell-cleared hook, and
-- the clients are told the rock broke as for any break
function SeamManager:onSwing(player: Player, depth: number, height: number, width: number): boolean
	local seam = self:findSeamAt(depth, height, width)
	if not seam or not seam.isAwake then
		return false
	end
	self:breakCell(player, { depth = depth, height = height, width = width })
	return true
end

function SeamManager:breakCell(breaker: Player, cell: Cell): boolean
	local rock = MineManager:getRockAt(cell.depth, cell.height, cell.width)
	if not rock or not MineManager:clearCell(cell.depth, cell.height, cell.width) then
		return false
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_ROCK_BROKEN, {
		depth = cell.depth,
		height = cell.height,
		width = cell.width,
		rock = rock,
		breakerUserId = breaker.UserId,
	})
	return true
end

-- one face of an awake Seam steps to a neighbouring exposed stone cell
function SeamManager:drift(seam: Seam, grid: MineGenerator.MineGrid): boolean
	if #seam.cells == 0 then
		return false
	end
	local fromIndex = self.random:NextInteger(1, #seam.cells)
	local from = seam.cells[fromIndex]
	local options = SeamRules.exposedHoldableNeighbours(grid, from, isStone, self.occupied)
	if #options == 0 then
		return false
	end
	local to = options[self.random:NextInteger(1, #options)]
	self.occupied[SeamRules.cellKey(from.depth, from.height, from.width)] = nil
	self.occupied[SeamRules.cellKey(to.depth, to.height, to.width)] = true
	seam.cells[fromIndex] = to
	return true
end

-- an awake Seam takes a neighbouring exposed stone cell as well
function SeamManager:spread(seam: Seam, grid: MineGenerator.MineGrid): boolean
	if #seam.cells == 0 or #seam.cells >= SeamsData.SPREAD_MAX_BLOCKS then
		return false
	end
	local options: { Cell } = {}
	for _, cell in seam.cells do
		for _, option in SeamRules.exposedHoldableNeighbours(grid, cell, isStone, self.occupied) do
			table.insert(options, option)
		end
	end
	if #options == 0 then
		return false
	end
	local to = options[self.random:NextInteger(1, #options)]
	self.occupied[SeamRules.cellKey(to.depth, to.height, to.width)] = true
	table.insert(seam.cells, to)
	local centre = self:cellCentre(to)
	if centre then
		SpatialSoundManager:playAt(centre, SoundNames.Sfx.SEAM_CRACK, SeamsData.CRACK_FULL_VOLUME_STUDS, SeamsData.CRACK_SILENT_STUDS)
	end
	return true
end

function SeamManager:hum(seam: Seam)
	local cell = seam.cells[1]
	local centre = if cell then self:cellCentre(cell) else nil
	if centre then
		SpatialSoundManager:playAt(centre, SoundNames.Sfx.SEAM_HUM, SeamsData.HUM_FULL_VOLUME_STUDS, SeamsData.HUM_SILENT_STUDS)
	end
end

function SeamManager:step()
	if not RunCycleManager:isRunOn() then
		return
	end
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	local now = workspace:GetServerTimeNow()
	local isChanged = false
	for _, seam in self.seams do
		if not seam.isAwake then
			continue
		end
		if now >= seam.nextDriftTime then
			seam.nextDriftTime = now + SeamsData.DRIFT_INTERVAL_SEC
			if self:drift(seam, grid) then
				isChanged = true
			end
		end
		if now >= seam.nextSpreadTime then
			seam.nextSpreadTime = now + SeamsData.SPREAD_INTERVAL_SEC
			if self:spread(seam, grid) then
				isChanged = true
			end
		end
		if now >= seam.nextHumTime then
			seam.nextHumTime = now + SeamsData.HUM_INTERVAL_SEC
			self:hum(seam)
		end
	end
	if isChanged then
		self:publish()
	end
end

-- an awake Seam on the exposed stone cell nearest a position, for the dev
-- panel; nil when none is within reach
function SeamManager:spawnNear(position: Vector3, maxStuds: number): boolean
	local grid = MineManager:getGrid()
	local space = MineManager:getSpace()
	if not grid or not space then
		return false
	end
	local centreDepth, centreHeight, centreWidth = MineSpace.worldToCell(space, position)
	local radius = math.ceil(maxStuds / space.blockSize)
	local best: Cell? = nil
	local bestDistance = math.huge
	for depth = centreDepth - radius, centreDepth + radius do
		for height = centreHeight - radius, centreHeight + radius do
			for width = centreWidth - radius, centreWidth + radius do
				if not SeamRules.isHoldable(grid, depth, height, width, isStone, self.occupied) or not SeamRules.isExposedRock(grid, depth, height, width) then
					continue
				end
				local distance = (MineSpace.cellToWorld(space, depth, height, width) - position).Magnitude
				if distance < bestDistance and distance <= maxStuds then
					bestDistance = distance
					best = { depth = depth, height = height, width = width }
				end
			end
		end
	end
	if not best then
		return false
	end
	local seam = self:addSeam({ best })
	self:wake(seam, workspace:GetServerTimeNow())
	self:publish()
	return true
end

-- clears the nearest awake Seam block within reach of a position, the
-- way a dynamite blast would, for the dev panel: the cell-cleared hook
-- then takes it off the Seam and the clients are told the rock broke
function SeamManager:breakNearest(player: Player, position: Vector3, maxStuds: number): boolean
	local space = MineManager:getSpace()
	if not space then
		return false
	end
	local best: Cell? = nil
	local bestDistance = math.huge
	for _, seam in self.seams do
		if not seam.isAwake then
			continue
		end
		for _, cell in seam.cells do
			local distance = (MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width) - position).Magnitude
			if distance < bestDistance and distance <= maxStuds then
				bestDistance = distance
				best = cell
			end
		end
	end
	if not best then
		return false
	end
	return self:breakCell(player, best)
end

-- wakes every sleeping Seam, for the dev panel
function SeamManager:wakeAll(): number
	local now = workspace:GetServerTimeNow()
	local count = 0
	for _, seam in self.seams do
		if not seam.isAwake then
			self:wake(seam, now)
			count += 1
		end
	end
	if count > 0 then
		self:publish()
	end
	return count
end

function SeamManager:addSeam(cells: { Cell }): Seam
	local seam: Seam = {
		id = self.nextId,
		cells = cells,
		isAwake = false,
		nextDriftTime = 0,
		nextSpreadTime = 0,
		nextHumTime = 0,
		marker = nil,
	}
	self.nextId += 1
	for _, cell in cells do
		self.occupied[SeamRules.cellKey(cell.depth, cell.height, cell.width)] = true
	end
	table.insert(self.seams, seam)
	return seam
end

-- the first depth row of the first zone a Seam may lie in
function SeamManager:minDepthForZone(zoneIndex: number): number?
	local grid = MineManager:getGrid()
	if not grid then
		return nil
	end
	for depth = 0, grid.depth - 1 do
		local index = MineManager:getZoneIndexAt(depth)
		if index and index >= zoneIndex then
			return depth
		end
	end
	return nil
end

function SeamManager:onRunStarted()
	self.seams = {}
	self.occupied = {}
	self.wokenCells = {}
	self.brokenCells = {}
	self.nextId = 1
	local grid = MineManager:getGrid()
	local seed = MineManager:getSeed() or 0
	local minDepth = self:minDepthForZone(SeamsData.MIN_ZONE_INDEX)
	self.random = Random.new(seed + SeamsData.SEED_OFFSET + 1)
	if not grid or not minDepth then
		warn("[SeamManager] no mine or no eligible zone: no Seams this run")
		self:publish()
		return
	end
	local cells = SeamRules.pickSeamCells(grid, SeamsData.COUNT, Random.new(seed + SeamsData.SEED_OFFSET), minDepth, isStone, MineManager:getPockets())
	for _, cell in cells do
		self:addSeam({ cell })
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
	if self.isLocationsVisible then
		self:setLocationsVisible(true)
	end
	self:publish()
	print(`[SeamManager] {#cells} Seams seated from block {minDepth} down ({SeamsData.COUNT} asked)`)
end

function SeamManager:getNetHandlers()
	return {
		[NetEventNames.TRY_REQUEST_SEAMS] = {
			shape = TRY_REQUEST_SEAMS_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:sendTo(player)
			end,
		},
	}
end

function SeamManager:init()
	GameController:registerPlaceManager(self)
	MiningManager:setHitInterceptor(
		function(player: Player, depth: number, height: number, width: number)
			return self:onSwing(player, depth, height, width)
		end
	)
	MineManager:subscribeCellCleared(
		function(depth: number, height: number, width: number)
			self:onCellCleared(depth, height, width)
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function SeamManager.new(): SeamManager
	local self = setmetatable({}, SeamManager)
	self.seams = {}
	self.occupied = {}
	self.wokenCells = {}
	self.brokenCells = {}
	self.random = Random.new()
	self.nextId = 1
	self.isLocationsVisible = false
	self.markersFolder = nil
	return self
end

return SeamManager.new()
