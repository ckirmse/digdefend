--!strict

-- The Blockfaces (GDD "Monster Types": Blockface, M68): faces in the rock that
-- burst. A Blockface is a small set of rock cells held here in Lua, never a
-- body: it is not registered in DamageableManager, so no weapon can touch
-- it, and it is not a MonsterManager monster, so it never counts toward a
-- night and the Camp Map does not draw it. BlockfacesData.COUNT of them are
-- seated at run start from the mine's seed (pure BlockfaceRules), each asleep
-- inside one stone cell. A cleared neighbour wakes one: from then on its
-- cells are published to every client (NOTIFY_BLOCKFACES, the whole awake list,
-- small); it never moves or grows (the drift and the spread of the first
-- design were cut on 2026-10-26). A swing at any of its cells is taken
-- by MiningManager's interceptor and breaks the block outright, whatever
-- the pick (designer, 2026-10-26: one hit, and the damage is the break,
-- not the swing). Every broken cell of an awake Blockface, by a swing or by
-- dynamite, bursts: MineManager's cell-cleared hook takes the cell off
-- the Blockface, every player within BURST_RADIUS_STUDS is hurt through
-- ReviveManager with the Blockface as the attacker (so the run report names
-- it), and the clients are told so they play the laugh and smoke and
-- shove whoever stood in it. A Blockface with no cells is gone. Sleeping Blockfaces
-- never travel to a client.
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local BlockfaceRules = require("@game/ReplicatedStorage/Shared/BlockfaceRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local BlockfacesData = require("@game/ServerScriptService/GameData/Monsters/Blockfaces")
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

local BlockfaceManager = {}
BlockfaceManager.__index = BlockfaceManager

type Cell = BlockfaceRules.Cell

type Blockface = {
	id: number,
	cells: { Cell },
	isAwake: boolean,
	nextHumTime: number,
	-- the dev tool's marker over a sleeping Blockface while the locations are shown
	marker: BasePart?,
}

export type BlockfaceManager = typeof(setmetatable(
	{} :: {
		blockfaces: { Blockface },
		-- every held cell, awake or asleep, by BlockfaceRules.cellKey
		occupied: { [string]: boolean },
		-- cells whose Blockface woke since the last publish, announced after it
		wokenCells: { Cell },
		-- cells of an awake Blockface cleared since the last publish, announced
		-- before it
		brokenCells: { Cell },
		random: Random,
		nextId: number,
		isLocationsVisible: boolean,
		markersFolder: Folder?,
	},
	BlockfaceManager
))

local MARKER_TEXT = "Blockface"
local MARKER_COLOR = Color3.fromRGB(200, 90, 255)

local TRY_REQUEST_BLOCKFACES_SHAPE = {}

local function isStone(rock: number): boolean
	local definition = RockDefinitionsData.ROCKS[rock]
	return definition ~= nil and definition.kind == Enums.RockKind.FILLER
end

function BlockfaceManager:getAwakeCount(): number
	local count = 0
	for _, blockface in self.blockfaces do
		if blockface.isAwake then
			count += 1
		end
	end
	return count
end

function BlockfaceManager:getBlockfaceCount(): number
	return #self.blockfaces
end

function BlockfaceManager:findBlockfaceAt(depth: number, height: number, width: number): (Blockface?, number?)
	if not self.occupied[BlockfaceRules.cellKey(depth, height, width)] then
		return nil, nil
	end
	for _, blockface in self.blockfaces do
		local index = BlockfaceRules.indexOfCell(blockface.cells, depth, height, width)
		if index then
			return blockface, index
		end
	end
	return nil, nil
end

function BlockfaceManager:cellCentre(cell: Cell): Vector3?
	local space = MineManager:getSpace()
	if not space then
		return nil
	end
	return MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width)
end

-- every awake Blockface's cells, flat, for the clients
function BlockfaceManager:encodeAwake(): { number }
	local cells: { Cell } = {}
	for _, blockface in self.blockfaces do
		if not blockface.isAwake then
			continue
		end
		for _, cell in blockface.cells do
			table.insert(cells, cell)
		end
	end
	return BlockfaceRules.encodeCells(cells)
end

-- the awake list, then the cells that woke since the last publish, so a
-- client has the block before it is asked to play its wake sound
function BlockfaceManager:publish()
	for _, cell in self.brokenCells do
		NetManager:notifyAllClients(NetEventNames.NOTIFY_BLOCKFACE_BROKEN, {
			depth = cell.depth,
			height = cell.height,
			width = cell.width,
			radiusStuds = BlockfacesData.BURST_RADIUS_STUDS,
			knockbackStuds = BlockfacesData.BURST_KNOCKBACK_STUDS,
		})
	end
	self.brokenCells = {}
	NetManager:notifyAllClients(NetEventNames.NOTIFY_BLOCKFACES, { cells = self:encodeAwake() })
	for _, cell in self.wokenCells do
		NetManager:notifyAllClients(NetEventNames.NOTIFY_BLOCKFACE_WOKEN, {
			depth = cell.depth,
			height = cell.height,
			width = cell.width,
		})
	end
	self.wokenCells = {}
end

function BlockfaceManager:sendTo(player: Player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_BLOCKFACES, { cells = self:encodeAwake() })
end

-- the dev tool's markers (M68, the spiders' pattern): an anchored
-- invisible part over every sleeping Blockface's block carrying the spider
-- billboard with its own text, so a tester can dig straight to one. A
-- marker goes when its Blockface wakes. Server parts replicate to every
-- client, which is fine for a dev tool
function BlockfaceManager:getMarkersFolder(): Folder
	local folder = self.markersFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.BLOCKFACE_MARKERS_FOLDER
	folder.Parent = workspace
	self.markersFolder = folder
	return folder
end

function BlockfaceManager:findMarkerTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.SPIDER_SPAWN_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`BlockfaceManager: no {Constants.SPIDER_SPAWN_BILLBOARD} billboard under GameAssets/{Constants.GUI_TEMPLATES_FOLDER}; run build_spider_spawn_billboard.luau`)
		return nil
	end
	return template
end

function BlockfaceManager:placeMarker(blockface: Blockface)
	local cell = blockface.cells[1]
	local position = if cell then self:cellCentre(cell) else nil
	if blockface.marker or blockface.isAwake or not position then
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
	blockface.marker = marker
end

function BlockfaceManager:removeMarker(blockface: Blockface)
	local marker = blockface.marker
	if marker then
		marker:Destroy()
		blockface.marker = nil
	end
end

function BlockfaceManager:setLocationsVisible(isVisible: boolean)
	self.isLocationsVisible = isVisible
	if isVisible then
		for _, blockface in self.blockfaces do
			self:placeMarker(blockface)
		end
		return
	end
	for _, blockface in self.blockfaces do
		self:removeMarker(blockface)
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
end

function BlockfaceManager:wake(blockface: Blockface, now: number)
	self:removeMarker(blockface)
	blockface.isAwake = true
	blockface.nextHumTime = now
	local cell = blockface.cells[1]
	if cell then
		table.insert(self.wokenCells, cell)
	end
end

function BlockfaceManager:removeCell(blockface: Blockface, index: number)
	local cell = table.remove(blockface.cells, index)
	if cell then
		self.occupied[BlockfaceRules.cellKey(cell.depth, cell.height, cell.width)] = nil
	end
end

function BlockfaceManager:removeBlockface(blockface: Blockface)
	self:removeMarker(blockface)
	for index = #blockface.cells, 1, -1 do
		self:removeCell(blockface, index)
	end
	local position = table.find(self.blockfaces, blockface)
	if position then
		table.remove(self.blockfaces, position)
	end
end

-- the burst of a broken awake cell: every player standing in the smoke's
-- reach takes the damage, the Blockface named as the attacker
function BlockfaceManager:burst(cell: Cell)
	local centre = self:cellCentre(cell)
	if not centre then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") and (root.Position - centre).Magnitude <= BlockfacesData.BURST_RADIUS_STUDS then
			ReviveManager:damagePlayer(player, BlockfacesData.BURST_DAMAGE, BlockfacesData.KIND)
		end
	end
	table.insert(self.brokenCells, cell)
end

-- a cleared cell: a Blockface's own cell bursts and goes (a swing or dynamite),
-- and any sleeping Blockface whose face it uncovered wakes
function BlockfaceManager:onCellCleared(depth: number, height: number, width: number)
	local now = workspace:GetServerTimeNow()
	local isChanged = false
	local blockface, index = self:findBlockfaceAt(depth, height, width)
	if blockface and index then
		if blockface.isAwake then
			self:burst({ depth = depth, height = height, width = width })
		end
		self:removeCell(blockface, index)
		if #blockface.cells == 0 then
			self:removeBlockface(blockface)
		end
		isChanged = isChanged or blockface.isAwake
	end
	for _, candidate in self.blockfaces do
		if not candidate.isAwake and BlockfaceRules.isWokenBy(candidate.cells, depth, height, width) then
			self:wake(candidate, now)
			isChanged = true
		end
	end
	if isChanged then
		self:publish()
	end
end

-- a swing at an awake Blockface's cell breaks the block in one hit, whatever
-- the pick: the clear runs the burst through the cell-cleared hook, and
-- the clients are told the rock broke as for any break
function BlockfaceManager:onSwing(player: Player, depth: number, height: number, width: number): boolean
	local blockface = self:findBlockfaceAt(depth, height, width)
	if not blockface or not blockface.isAwake then
		return false
	end
	self:breakCell(player, { depth = depth, height = height, width = width })
	return true
end

function BlockfaceManager:breakCell(breaker: Player, cell: Cell): boolean
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

function BlockfaceManager:hum(blockface: Blockface)
	local cell = blockface.cells[1]
	local centre = if cell then self:cellCentre(cell) else nil
	if centre then
		SpatialSoundManager:playAt(centre, SoundNames.Sfx.BLOCKFACE_HUM, BlockfacesData.HUM_FULL_VOLUME_STUDS, BlockfacesData.HUM_SILENT_STUDS)
	end
end

function BlockfaceManager:step()
	if not RunCycleManager:isRunOn() then
		return
	end
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, blockface in self.blockfaces do
		if not blockface.isAwake then
			continue
		end
		if now >= blockface.nextHumTime then
			blockface.nextHumTime = now + BlockfacesData.HUM_INTERVAL_SEC
			self:hum(blockface)
		end
	end
end

-- an awake Blockface on the exposed stone cell nearest a position, for the dev
-- panel; nil when none is within reach
function BlockfaceManager:spawnNear(position: Vector3, maxStuds: number): boolean
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
				if not BlockfaceRules.isHoldable(grid, depth, height, width, isStone, self.occupied) or not BlockfaceRules.isExposedRock(grid, depth, height, width) then
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
	local blockface = self:addBlockface({ best })
	self:wake(blockface, workspace:GetServerTimeNow())
	self:publish()
	return true
end

-- clears the nearest awake Blockface block within reach of a position, the
-- way a dynamite blast would, for the dev panel: the cell-cleared hook
-- then takes it off the Blockface and the clients are told the rock broke
function BlockfaceManager:breakNearest(player: Player, position: Vector3, maxStuds: number): boolean
	local space = MineManager:getSpace()
	if not space then
		return false
	end
	local best: Cell? = nil
	local bestDistance = math.huge
	for _, blockface in self.blockfaces do
		if not blockface.isAwake then
			continue
		end
		for _, cell in blockface.cells do
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

-- wakes every sleeping Blockface, for the dev panel
function BlockfaceManager:wakeAll(): number
	local now = workspace:GetServerTimeNow()
	local count = 0
	for _, blockface in self.blockfaces do
		if not blockface.isAwake then
			self:wake(blockface, now)
			count += 1
		end
	end
	if count > 0 then
		self:publish()
	end
	return count
end

function BlockfaceManager:addBlockface(cells: { Cell }): Blockface
	local blockface: Blockface = {
		id = self.nextId,
		cells = cells,
		isAwake = false,
		nextHumTime = 0,
		marker = nil,
	}
	self.nextId += 1
	for _, cell in cells do
		self.occupied[BlockfaceRules.cellKey(cell.depth, cell.height, cell.width)] = true
	end
	table.insert(self.blockfaces, blockface)
	return blockface
end

-- the first depth row of the first zone a Blockface may lie in
function BlockfaceManager:minDepthForZone(zoneIndex: number): number?
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

function BlockfaceManager:onRunStarted()
	self.blockfaces = {}
	self.occupied = {}
	self.wokenCells = {}
	self.brokenCells = {}
	self.nextId = 1
	local grid = MineManager:getGrid()
	local seed = MineManager:getSeed() or 0
	local minDepth = self:minDepthForZone(BlockfacesData.MIN_ZONE_INDEX)
	self.random = Random.new(seed + BlockfacesData.SEED_OFFSET + 1)
	if not grid or not minDepth then
		warn("[BlockfaceManager] no mine or no eligible zone: no Blockfaces this run")
		self:publish()
		return
	end
	local cells = BlockfaceRules.pickBlockfaceCells(grid, BlockfacesData.COUNT, Random.new(seed + BlockfacesData.SEED_OFFSET), minDepth, isStone, MineManager:getPockets())
	for _, cell in cells do
		self:addBlockface({ cell })
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
	print(`[BlockfaceManager] {#cells} Blockfaces seated from block {minDepth} down ({BlockfacesData.COUNT} asked)`)
end

function BlockfaceManager:getNetHandlers()
	return {
		[NetEventNames.TRY_REQUEST_BLOCKFACES] = {
			shape = TRY_REQUEST_BLOCKFACES_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:sendTo(player)
			end,
		},
	}
end

function BlockfaceManager:init()
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

function BlockfaceManager.new(): BlockfaceManager
	local self = setmetatable({}, BlockfaceManager)
	self.blockfaces = {}
	self.occupied = {}
	self.wokenCells = {}
	self.brokenCells = {}
	self.random = Random.new()
	self.nextId = 1
	self.isLocationsVisible = false
	self.markersFolder = nil
	return self
end

return BlockfaceManager.new()
