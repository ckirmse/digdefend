--!strict

-- The mine on this client: receives the header and encoded chunks from
-- MineManager, rebuilds the grid, and renders it as pooled block parts. Only
-- exposed blocks (those with an air face) within the streaming radius of the
-- player exist as parts, so a solid chamber costs its surfaces, not its
-- volume, and digging exposes new faces. Rendered parts collide, which is
-- enough because character physics is client-owned. The server never holds a
-- rock part.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineGridCodec = require("@game/ReplicatedStorage/Shared/MineGridCodec")
local MineGridQuery = require("@game/ReplicatedStorage/Shared/MineGridQuery")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)

local ClientMineManager = {}
ClientMineManager.__index = ClientMineManager

export type Header = {
	version: number,
	seed: number,
	depth: number,
	height: number,
	width: number,
	centrelineWidth: number,
	floorHeight: number,
	origin: Vector3,
	facing: number,
	blockSize: number,
	chunkCount: number,
	encodedBytes: number,
	streamRadiusBlocks: number,
	maxRenderedBlocks: number,
	streamPollSec: number,
	fillerOrder: { number },
	rockHp: { [number]: number },
	chambers: { MineGenerator.ChamberFill },
}

export type Stats = {
	version: number,
	seed: number,
	bytesReceived: number,
	chunksReceived: number,
	chunkCount: number,
	renderedCount: number,
	pooledCount: number,
	exposedInRadius: number,
	lastRefreshMs: number,
}

export type ClientMineManager = typeof(setmetatable(
	{} :: {
		header: Header?,
		chunks: { [number]: buffer },
		chunksReceived: number,
		bytesReceived: number,
		grid: MineGenerator.MineGrid?,
		space: MineSpace.MineSpace?,
		-- every exposed cell index, computed once per grid and maintained as
		-- blocks break, so a refresh only walks candidates
		exposedCells: { [number]: boolean },
		-- crack stage per damaged cell (MiningRules.crackStage), kept off the
		-- part so a recycled or re-streamed block shows the right state
		crackStageByCell: { [number]: number },
		blocksFolder: Folder?,
		-- cell index -> the part showing that block
		rendered: { [number]: BasePart },
		renderedCount: number,
		-- rock name -> free parts waiting to be reused
		poolByRock: { [number]: { BasePart } },
		pooledCount: number,
		exposedInRadius: number,
		lastRefreshMs: number,
		lastCell: { number }?,
		isDirty: boolean,
		stopPolling: (() -> ())?,
		warnedMissingTemplates: { [number]: boolean },
	},
	ClientMineManager
))

local FALLBACK_COLOR = Color3.fromRGB(120, 120, 120)

function ClientMineManager:getStats(): Stats
	local header = self.header
	return {
		version = if header then header.version else 0,
		seed = if header then header.seed else 0,
		bytesReceived = self.bytesReceived,
		chunksReceived = self.chunksReceived,
		chunkCount = if header then header.chunkCount else 0,
		renderedCount = self.renderedCount,
		pooledCount = self.pooledCount,
		exposedInRadius = self.exposedInRadius,
		lastRefreshMs = self.lastRefreshMs,
	}
end

function ClientMineManager:getGrid(): MineGenerator.MineGrid?
	return self.grid
end

function ClientMineManager:getSpace(): MineSpace.MineSpace?
	return self.space
end

function ClientMineManager:getRockMaxHp(rock: number): number?
	local header = self.header
	return if header and header.rockHp then header.rockHp[rock] else nil
end

-- the grid cell a rendered block part shows, from the attribute stamped at render
function ClientMineManager:getCellFromPart(part: Instance): (number?, number?, number?)
	local grid = self.grid
	local cellIndex = part:GetAttribute(Attributes.MINE_CELL_INDEX)
	if not grid or typeof(cellIndex) ~= "number" then
		return nil, nil, nil
	end
	local zeroBased = cellIndex - 1
	return zeroBased // (grid.width * grid.height), (zeroBased // grid.width) % grid.height, zeroBased % grid.width
end

-- placeholder crack look until M46 art: the block darkens per stage
function ClientMineManager:applyCrackLook(part: BasePart, rock: number, stage: number)
	local template = self:getTemplate(rock)
	local baseColor = if template then template.Color else FALLBACK_COLOR
	part.Color = baseColor:Lerp(Color3.new(0, 0, 0), 0.3 * stage)
end

function ClientMineManager:setCrackStage(depth: number, height: number, width: number, stage: number)
	local grid = self.grid
	if not grid then
		return
	end
	local cellIndex = MineGenerator.cellIndex(grid, depth, height, width)
	self.crackStageByCell[cellIndex] = if stage > 0 then stage else nil
	local part = self.rendered[cellIndex]
	if part then
		self:applyCrackLook(part, grid.cells[cellIndex], stage)
	end
end

function ClientMineManager:getRenderedPart(depth: number, height: number, width: number): BasePart?
	local grid = self.grid
	if not grid then
		return nil
	end
	return self.rendered[MineGenerator.cellIndex(grid, depth, height, width)]
end

-- a block broke: clear it, release its part, and expose its neighbours
function ClientMineManager:clearCell(depth: number, height: number, width: number)
	local grid = self.grid
	if not grid or not MineGridQuery.isInBounds(grid, depth, height, width) then
		return
	end
	local cellIndex = MineGenerator.cellIndex(grid, depth, height, width)
	local rock = grid.cells[cellIndex]
	if rock == MineGenerator.AIR then
		return
	end
	local part = self.rendered[cellIndex]
	if part then
		self:releasePart(rock, part)
		self.rendered[cellIndex] = nil
		self.renderedCount -= 1
	end
	grid.cells[cellIndex] = MineGenerator.AIR
	self.exposedCells[cellIndex] = nil
	self.crackStageByCell[cellIndex] = nil
	for _, offset in { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } } do
		local nd = depth + offset[1]
		local nh = height + offset[2]
		local nw = width + offset[3]
		if MineGridQuery.isExposed(grid, nd, nh, nw) then
			self.exposedCells[MineGenerator.cellIndex(grid, nd, nh, nw)] = true
		end
	end
	self.isDirty = true
	self:poll()
end

function ClientMineManager:getBlocksFolder(): Folder
	local folder = self.blocksFolder
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.MINE_BLOCKS_FOLDER
	folder.Parent = workspace
	self.blocksFolder = folder
	return folder
end

function ClientMineManager:getTemplate(rock: number): BasePart?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local rocks = if gameAssets then gameAssets:FindFirstChild(Constants.ROCK_TEMPLATES_FOLDER) else nil
	local key = Enums.getName(Enums.RockName, rock)
	local template = if rocks and key then rocks:FindFirstChild(key) else nil
	if template and template:IsA("BasePart") then
		return template
	end
	if not self.warnedMissingTemplates[rock] then
		self.warnedMissingTemplates[rock] = true
		warn(`ClientMineManager: no template for rock {tostring(key)} under GameAssets.{Constants.ROCK_TEMPLATES_FOLDER}; using a grey cube`)
	end
	return nil
end

function ClientMineManager:createPart(rock: number): BasePart
	local template = self:getTemplate(rock)
	local part: BasePart
	if template then
		part = template:Clone()
	else
		local size = if self.header then self.header.blockSize else Constants.MINE_BLOCK_SIZE_STUDS
		local fallback = Instance.new("Part")
		fallback.Size = Vector3.new(size, size, size)
		fallback.Color = FALLBACK_COLOR
		fallback.Name = Enums.getName(Enums.RockName, rock) or "Rock"
		part = fallback
	end
	part.Anchored = true
	part.CanCollide = true
	return part
end

function ClientMineManager:acquirePart(rock: number): BasePart
	local pool = self.poolByRock[rock]
	if pool and #pool > 0 then
		self.pooledCount -= 1
		return table.remove(pool) :: BasePart
	end
	return self:createPart(rock)
end

function ClientMineManager:releasePart(rock: number, part: BasePart)
	part.Parent = nil
	part:SetAttribute(Attributes.MINE_CELL_INDEX, nil)
	local pool = self.poolByRock[rock]
	if not pool then
		pool = {}
		self.poolByRock[rock] = pool
	end
	table.insert(pool, part)
	self.pooledCount += 1
end

function ClientMineManager:clearRendered()
	local grid = self.grid
	for cellIndex, part in self.rendered do
		local rock = if grid then grid.cells[cellIndex] else nil
		if rock and rock ~= MineGenerator.AIR then
			self:releasePart(rock, part)
		else
			part:Destroy()
		end
	end
	self.rendered = {}
	self.renderedCount = 0
end

function ClientMineManager:getPlayerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

function ClientMineManager:rebuildExposedCells()
	local grid = self.grid
	local exposed: { [number]: boolean } = {}
	local count = 0
	if grid then
		for depth = 0, grid.depth - 1 do
			for height = 0, grid.height - 1 do
				for width = 0, grid.width - 1 do
					if MineGridQuery.isExposed(grid, depth, height, width) then
						exposed[MineGenerator.cellIndex(grid, depth, height, width)] = true
						count += 1
					end
				end
			end
		end
	end
	self.exposedCells = exposed
	return count
end

-- rebuilds the set of rendered blocks around the player's cell
function ClientMineManager:refresh(playerDepth: number, playerHeight: number, playerWidth: number)
	local grid = self.grid
	local space = self.space
	local header = self.header
	if not grid or not space or not header then
		return
	end
	local startClock = workspace:GetServerTimeNow()
	local radius = header.streamRadiusBlocks
	local width = grid.width
	local height = grid.height
	local desired: { [number]: number } = {}
	local desiredCount = 0
	for cellIndex in self.exposedCells do
		local zeroBased = cellIndex - 1
		local dw = zeroBased % width - playerWidth
		local dh = (zeroBased // width) % height - playerHeight
		local dd = zeroBased // (width * height) - playerDepth
		if math.abs(dd) > radius or math.abs(dh) > radius or math.abs(dw) > radius then
			continue
		end
		desired[cellIndex] = dd * dd + dh * dh + dw * dw
		desiredCount += 1
	end
	self.exposedInRadius = desiredCount

	-- over budget: keep the nearest blocks so the ground under the player
	-- and the wall in front always render first
	if desiredCount > header.maxRenderedBlocks then
		local ordered = {}
		for cellIndex, distance in desired do
			table.insert(ordered, { cellIndex = cellIndex, distance = distance })
		end
		table.sort(
			ordered,
			function(a: { cellIndex: number, distance: number }, b: { cellIndex: number, distance: number })
				return a.distance < b.distance
			end
		)
		desired = {}
		for index = 1, header.maxRenderedBlocks do
			desired[ordered[index].cellIndex] = ordered[index].distance
		end
	end

	for cellIndex, part in self.rendered do
		if desired[cellIndex] == nil then
			self:releasePart(grid.cells[cellIndex], part)
			self.rendered[cellIndex] = nil
			self.renderedCount -= 1
		end
	end
	local folder = self:getBlocksFolder()
	for cellIndex in desired do
		if self.rendered[cellIndex] then
			continue
		end
		local rock = grid.cells[cellIndex]
		local zeroBased = cellIndex - 1
		local cellWidth = zeroBased % width
		local cellHeight = (zeroBased // width) % height
		local cellDepth = zeroBased // (width * height)
		local part = self:acquirePart(rock)
		part.CFrame = CFrame.new(MineSpace.cellToWorld(space, cellDepth, cellHeight, cellWidth))
		part:SetAttribute(Attributes.MINE_CELL_INDEX, cellIndex)
		self:applyCrackLook(part, rock, self.crackStageByCell[cellIndex] or 0)
		part.Parent = folder
		self.rendered[cellIndex] = part
		self.renderedCount += 1
	end
	self.lastRefreshMs = (workspace:GetServerTimeNow() - startClock) * 1000
	-- mirrored onto the folder so the numbers are inspectable in the Explorer
	folder:SetAttribute(Attributes.MINE_RENDERED_COUNT, self.renderedCount)
	folder:SetAttribute(Attributes.MINE_POOLED_COUNT, self.pooledCount)
	folder:SetAttribute(Attributes.MINE_LAST_REFRESH_MS, self.lastRefreshMs)
end

function ClientMineManager:poll()
	local space = self.space
	if not space then
		return
	end
	local position = self:getPlayerPosition()
	if not position then
		return
	end
	local depth, height, width = MineSpace.worldToCell(space, position)
	local last = self.lastCell
	if not self.isDirty and last and last[1] == depth and last[2] == height and last[3] == width then
		return
	end
	self.lastCell = { depth, height, width }
	self.isDirty = false
	self:refresh(depth, height, width)
end

function ClientMineManager:startPolling()
	if self.stopPolling then
		return
	end
	local header = self.header :: Header
	self.stopPolling = ClientTicker.every(
		header.streamPollSec,
		function()
			self:poll()
		end
	)
end

function ClientMineManager:onMineComplete()
	local header = self.header :: Header
	local ordered = {}
	for index = 1, header.chunkCount do
		table.insert(ordered, self.chunks[index])
	end
	local cells, err = MineGridCodec.decode(MineGridCodec.join(ordered))
	if not cells then
		warn("ClientMineManager: mine data rejected: " .. tostring(err))
		return
	end
	local expected = header.depth * header.height * header.width
	if #cells ~= expected then
		warn(`ClientMineManager: mine has {#cells} cells but the header says {expected}`)
		return
	end
	self:clearRendered()
	local grid: MineGenerator.MineGrid = {
		depth = header.depth,
		height = header.height,
		width = header.width,
		centrelineWidth = header.centrelineWidth,
		floorHeight = header.floorHeight,
		cells = cells,
	}
	local startClock = workspace:GetServerTimeNow()
	MineGenerator.expandFiller(grid, header.chambers, header.seed, header.fillerOrder)
	self.grid = grid
	self.crackStageByCell = {}
	local exposedCount = self:rebuildExposedCells()
	self.space = MineSpace.new(header.origin, header.facing, header.centrelineWidth, header.floorHeight, header.blockSize)
	self.isDirty = true
	print(string.format("[ClientMineManager] mine v%d (seed %d) received: %d bytes in %d chunk(s); filler and exposure rebuilt in %.1f ms, %d exposed cells", header.version, header.seed, self.bytesReceived, header.chunkCount, (workspace:GetServerTimeNow() - startClock) * 1000, exposedCount))
	self:startPolling()
	self:poll()
end

function ClientMineManager:onHeader(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.version) ~= "number" then
		warn("ClientMineManager: malformed mine header")
		return
	end
	self.header = payload :: Header
	self.chunks = {}
	self.chunksReceived = 0
	self.bytesReceived = 0
	if payload.chunkCount == 0 then
		self:onMineComplete()
	end
end

function ClientMineManager:onChunk(payload: any)
	local header = self.header
	if typeof(payload) ~= "table" or typeof(payload.data) ~= "buffer" or typeof(payload.index) ~= "number" then
		warn("ClientMineManager: malformed mine chunk")
		return
	end
	if not header or payload.version ~= header.version then
		-- a chunk from a mine that was regenerated mid-stream; its header will follow
		return
	end
	if self.chunks[payload.index] ~= nil then
		return
	end
	self.chunks[payload.index] = payload.data
	self.chunksReceived += 1
	self.bytesReceived += buffer.len(payload.data)
	if self.chunksReceived == header.chunkCount then
		self:onMineComplete()
	end
end

function ClientMineManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MINE_HEADER,
		function(payload: any)
			self:onHeader(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MINE_CHUNK,
		function(payload: any)
			self:onChunk(payload)
		end
	)
end

function ClientMineManager.new(): ClientMineManager
	local self = setmetatable({}, ClientMineManager) :: ClientMineManager
	self.header = nil
	self.chunks = {}
	self.chunksReceived = 0
	self.bytesReceived = 0
	self.grid = nil
	self.space = nil
	self.exposedCells = {}
	self.crackStageByCell = {}
	self.blocksFolder = nil
	self.rendered = {}
	self.renderedCount = 0
	self.poolByRock = {}
	self.pooledCount = 0
	self.exposedInRadius = 0
	self.lastRefreshMs = 0
	self.lastCell = nil
	self.isDirty = false
	self.stopPolling = nil
	self.warnedMissingTemplates = {}
	return self
end

return ClientMineManager.new()
