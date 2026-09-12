--!strict

-- The run's mine, server side: generated from the map's mine file when the
-- run starts, held as Lua data (never parts), and streamed to clients as
-- run-length-encoded buffer chunks over the single RemoteEvent. Rock HP is
-- tracked here by cell index so damage survives a client recycling the part
-- that showed the block (GDD "Runtime"). A version number ties every chunk
-- to its header so a regenerate mid-stream cannot mix two mines.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineGridCodec = require("@game/ReplicatedStorage/Shared/MineGridCodec")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RockRules = require("@game/ReplicatedStorage/Shared/RockRules")
local DifficultyData = require("@game/ServerScriptService/GameData/Control/Difficulty")
local GenerationData = require("@game/ServerScriptService/GameData/Mines/Generation")
local MineRegistryData = require("@game/ServerScriptService/GameData/Mines/Registry")
local StreamingData = require("@game/ServerScriptService/GameData/Mines/Streaming")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local WeightsData = require("@game/ServerScriptService/GameData/Rocks/Weights")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)

local MineManager = {}
MineManager.__index = MineManager

export type MineManager = typeof(setmetatable(
	{} :: {
		result: MineGenerator.GenerateResult?,
		encoded: buffer?,
		chunks: { buffer },
		version: number,
		origin: Vector3?,
		facing: number?,
		-- damage dealt per cell index; a block breaks when it reaches the rock's hp
		damageByCell: { [number]: number },
	},
	MineManager
))

function MineManager:getGrid(): MineGenerator.MineGrid?
	local result = self.result
	return if result then result.grid else nil
end

function MineManager:getVersion(): number
	return self.version
end

function MineManager:buildConfig(difficulty: number): MineGenerator.GeneratorConfig
	return {
		rockTable = RockDefinitionsData,
		spread = WeightsData.SPREAD,
		minCenter = WeightsData.MIN_CENTER,
		maxCenter = WeightsData.MAX_CENTER,
		hardnessShift = DifficultyData.HARDNESS_SHIFT,
		difficultyValue = DifficultyData.DIFFICULTY_VALUE[difficulty],
		veinDivisor = DifficultyData.VEIN_DIVISOR[difficulty],
		pickaxeReachBlocks = GenerationData.PICKAXE_REACH_BLOCKS,
		isClimbingEnabled = GenerationData.IS_CLIMBING_ENABLED,
		maxPartyUraniumTargetMultiplier = GenerationData.MAX_PARTY_URANIUM_TARGET_MULTIPLIER,
	}
end

-- generates the mine for the map and difficulty; seed nil draws a fresh one
function MineManager:generate(map: number, difficulty: number, seed: number?): boolean
	local definition = MineRegistryData[map]
	if not definition then
		warn(`MineManager: no mine definition registered for map {Enums.getName(Enums.Map, map)}`)
		return false
	end
	local origin, facing = MapManager:getMineEntrance()
	if not origin or not facing then
		warn("MineManager: the loaded map has no Mine.Entrance part; mine not generated")
		return false
	end

	local result, errors, warnings = MineGenerator.generate(definition, self:buildConfig(difficulty), seed)
	for _, warning in warnings do
		warn("MineManager: " .. warning)
	end
	if not result then
		for _, err in errors do
			warn("MineManager: FATAL " .. err)
		end
		return false
	end

	self.result = result
	self.origin = origin
	self.facing = facing
	self.damageByCell = {}
	self.version += 1
	-- filler is re-rolled client side from the seed, so it travels as one symbol
	self.encoded = MineGridCodec.encode(MineGenerator.collapseFiller(result.grid.cells, RockDefinitionsData.FILLER_ORDER))
	self.chunks = MineGridCodec.split(self.encoded :: buffer, StreamingData.CHUNK_BYTES)
	SplendidReplicationManager:setGameMetadata(Attributes.MINE_SEED, result.report.seed)
	print(MineGenerator.formatReport(result.report))
	print(`[MineManager] mine v{self.version}: {#result.grid.cells} cells encoded to {buffer.len(self.encoded :: buffer)} bytes in {#self.chunks} chunk(s)`)

	for _, player in GameController:getReadyPlayers() do
		self:sendTo(player)
	end
	return true
end

function MineManager:buildHeader(): { [string]: any }
	local result = self.result :: MineGenerator.GenerateResult
	local grid = result.grid
	local chambers = {}
	for _, chamber in result.chambers do
		table.insert(chambers, {
			index = chamber.index,
			unlockCampLevel = chamber.unlockCampLevel,
			hasCorridor = chamber.hasCorridor,
			depthStart = chamber.depthStart,
			depth = chamber.depth,
			heightStart = chamber.heightStart,
			height = chamber.height,
			widthStart = chamber.widthStart,
			width = chamber.width,
			fillerWeights = chamber.fillerWeights,
		})
	end
	return {
		version = self.version,
		fillerOrder = RockDefinitionsData.FILLER_ORDER,
		seed = result.report.seed,
		depth = grid.depth,
		height = grid.height,
		width = grid.width,
		centrelineWidth = grid.centrelineWidth,
		floorHeight = grid.floorHeight,
		origin = self.origin,
		facing = self.facing,
		blockSize = Constants.MINE_BLOCK_SIZE_STUDS,
		chunkCount = #self.chunks,
		encodedBytes = buffer.len(self.encoded :: buffer),
		streamRadiusBlocks = StreamingData.STREAM_RADIUS_BLOCKS,
		maxRenderedBlocks = StreamingData.MAX_RENDERED_BLOCKS,
		streamPollSec = StreamingData.STREAM_POLL_SEC,
		chambers = chambers,
	}
end

-- header first, then chunks paced apart so a slow connection is not hit
-- with the whole mine in one frame; a newer version aborts the send
function MineManager:sendTo(player: Player)
	if not self.result then
		return
	end
	local version = self.version
	task.spawn(
		function()
			NetManager:notifyClient(player, NetEventNames.NOTIFY_MINE_HEADER, self:buildHeader())
			for index, chunk in self.chunks do
				if self.version ~= version or player.Parent == nil then
					return
				end
				NetManager:notifyClient(player, NetEventNames.NOTIFY_MINE_CHUNK, {
					version = version,
					index = index,
					data = chunk,
				})
				task.wait(StreamingData.CHUNK_INTERVAL_SEC)
			end
		end
	)
end

-- ready-sequence entry: a player who becomes Ready after generation gets the mine
function MineManager:onPlayerReady(player: Player)
	self:sendTo(player)
end

function MineManager:getRockAt(depth: number, height: number, width: number): number?
	local grid = self:getGrid()
	if not grid then
		return nil
	end
	if depth < 0 or depth >= grid.depth or height < 0 or height >= grid.height or width < 0 or width >= grid.width then
		return nil
	end
	return MineGenerator.getCell(grid, depth, height, width)
end

-- applies damage to a diggable block; returns whether it broke and the hp
-- left. Breaking clears the cell; broadcasting the change is M18's job.
function MineManager:applyDamage(depth: number, height: number, width: number, amount: number): (boolean, number)
	local grid = self:getGrid()
	local rock = self:getRockAt(depth, height, width)
	if not grid or not rock or rock == MineGenerator.AIR then
		return false, 0
	end
	local definition = RockDefinitionsData.ROCKS[rock]
	if not definition or not definition.hp then
		-- bedrock and gates take no damage
		return false, 0
	end
	local cellIndex = MineGenerator.cellIndex(grid, depth, height, width)
	local damage = (self.damageByCell[cellIndex] or 0) + amount
	if damage >= definition.hp then
		self.damageByCell[cellIndex] = nil
		grid.cells[cellIndex] = MineGenerator.AIR
		return true, 0
	end
	self.damageByCell[cellIndex] = damage
	return false, definition.hp - damage
end

function MineManager:onRunStarted(map: number, difficulty: number)
	self:generate(map, difficulty, nil)
end

function MineManager:init()
	local isValid, message = RockRules.validateRockTable(RockDefinitionsData)
	if not isValid then
		error("MineManager: GameData/Rocks/RockDefinitions is invalid: " .. tostring(message))
	end
	GameController:registerPlaceManager(self)
end

function MineManager.new(): MineManager
	local self = setmetatable({}, MineManager) :: MineManager
	self.result = nil
	self.encoded = nil
	self.chunks = {}
	self.version = 0
	self.origin = nil
	self.facing = nil
	self.damageByCell = {}
	return self
end

return MineManager.new()
