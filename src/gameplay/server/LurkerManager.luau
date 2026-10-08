--!strict

-- The pocket lurkers (GDD "Pocket lurkers", M62, 2026-10-08): Cave
-- Spiders that sleep in some of the mine's pockets and hunt whoever
-- opens one. At run start the mine's pockets are drawn from the seed
-- (LurkerRules.pickLurkerPockets) and each chosen pocket waits; the first
-- block broken within a cell of its sphere wakes it, and a spider is
-- spawned on the pocket's ceiling as a crawler in MonsterManager, so it
-- is a Damageable target, streams in the one snapshot event, and is drawn
-- by every client like any monster. It never counts toward a wave.
--
-- Each tick this manager steps every crawler (MonsterManager's crawl
-- stepper): the nearest living player within detection range is the
-- target; in attack range it bites (MonsterManager:attack, the usual
-- damage path); with a straight line of air to the player it moves down
-- the line; otherwise, every SEARCH_INTERVAL_SEC, it searches the air
-- round it up to SEARCH_MAX_CELLS and follows what it finds; with nothing
-- to chase it drifts to a random neighbouring cell now and then. It moves
-- cell centre to cell centre, so it is always in air, and a client lays
-- it on the nearest face. All of that is cells and lines on the grid the
-- server already holds; no path field, no raycasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local LurkerRules = require("@game/ReplicatedStorage/Shared/LurkerRules")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MonsterRules = require("@game/ReplicatedStorage/Shared/MonsterRules")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local LurkersData = require("@game/ServerScriptService/GameData/Monsters/Lurkers")
local GameController = require(script.Parent.Parent.Server.GameController)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MineManager = require(script.Parent.MineManager)
local MonsterManager = require(script.Parent.MonsterManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)

local LurkerManager = {}
LurkerManager.__index = LurkerManager

type LurkerPocket = {
	pocket: any,
	isWoken: boolean,
	-- where the sleeper rests, for the skitter a close player hears
	restingPosition: Vector3?,
	-- the dev tool's marker over it while the spawns are shown
	marker: BasePart?,
}

-- the hunt's state for one spider, beside its Monster record
type Lurker = {
	-- the cells still to walk and the next one's index
	path: { LurkerRules.Cell },
	pathIndex: number,
	nextWanderTime: number,
	nextSearchTime: number,
	-- the player it is after, so taking a new one is announced (the alert cry)
	targetId: string?,
	nextAlertTime: number,
}

export type LurkerManager = typeof(setmetatable(
	{} :: {
		lurkerPockets: { LurkerPocket },
		lurkerById: { [number]: Lurker },
		random: Random,
		sleepingSoundAccumulatorSec: number,
		-- the dev tool: a billboard over every sleeping pocket
		isSpawnsVisible: boolean,
		markersFolder: Folder?,
	},
	LurkerManager
))

function LurkerManager:getPocketCount(): number
	return #self.lurkerPockets
end

function LurkerManager:getWokenCount(): number
	local count = 0
	for _, entry in self.lurkerPockets do
		if entry.isWoken then
			count += 1
		end
	end
	return count
end

-- the cell a world position is in, nil outside the mine's air
function LurkerManager:airCellAt(position: Vector3): LurkerRules.Cell?
	local grid = MineManager:getGrid()
	local space = MineManager:getSpace()
	if not grid or not space then
		return nil
	end
	local depth, height, width = MineSpace.worldToCell(space, position)
	if not LurkerRules.isAir(grid, depth, height, width) then
		return nil
	end
	return { depth = depth, height = height, width = width }
end

-- the surface cell to hunt or stand on for a world position: the cell
-- itself when it touches rock, else the first below it that does
function LurkerManager:surfaceCellAt(position: Vector3): LurkerRules.Cell?
	local grid = MineManager:getGrid()
	local cell = self:airCellAt(position)
	if not grid or not cell then
		return nil
	end
	return LurkerRules.surfaceCellBelow(grid, cell, LurkersData.GOAL_MAX_DROP_CELLS)
end

function LurkerManager:cellCentre(cell: LurkerRules.Cell): Vector3?
	local space = MineManager:getSpace()
	if not space then
		return nil
	end
	return MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width)
end

-- one spider awake at a cell; the facing is along the tunnel so the
-- first sight of it is head on
function LurkerManager:spawnAtCell(cell: LurkerRules.Cell): number?
	local space = MineManager:getSpace()
	local centre = self:cellCentre(cell)
	if not space or not centre then
		return nil
	end
	local id = MonsterManager:spawnCrawler(LurkersData.KIND, centre, -space.forward)
	if not id then
		return nil
	end
	self.lurkerById[id] = {
		path = {},
		pathIndex = 1,
		nextWanderTime = 0,
		nextSearchTime = 0,
		targetId = nil,
		nextAlertTime = 0,
	}
	return id
end

-- the dev tool: a spider in the surface cell the player stands in
function LurkerManager:spawnAtPlayer(player: Player): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	local cell = self:surfaceCellAt(root.Position)
	if not cell then
		return false
	end
	return self:spawnAtCell(cell) ~= nil
end

-- the skitter from every sleeping pocket a living player is near
function LurkerManager:playSleepingSounds()
	local sound = MonsterManager:getRosterData(LurkersData.KIND)
	local walk = if sound and sound.SOUNDS then sound.SOUNDS.WALK else nil
	if not walk then
		return
	end
	local positions = {}
	for _, player in GameController:getReadyPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	if #positions == 0 then
		return
	end
	local silentStuds = LurkersData.SLEEPING_SOUND_SILENT_STUDS
	for _, entry in self.lurkerPockets do
		local resting = entry.restingPosition
		if entry.isWoken or not resting then
			continue
		end
		for _, position in positions do
			if (position - resting).Magnitude <= silentStuds then
				SpatialSoundManager:playAt(resting, walk.NAME, LurkersData.SLEEPING_SOUND_FULL_VOLUME_STUDS, silentStuds)
				break
			end
		end
	end
end

function LurkerManager:step(deltaSec: number)
	if not RunCycleManager:isRunOn() then
		return
	end
	self.sleepingSoundAccumulatorSec += deltaSec
	if self.sleepingSoundAccumulatorSec < LurkersData.SLEEPING_SOUND_INTERVAL_SEC then
		return
	end
	self.sleepingSoundAccumulatorSec = 0
	self:playSleepingSounds()
end

-- the dev tool's markers (M62): an anchored invisible part at every
-- sleeping pocket's resting cell carrying the SpiderSpawn billboard, on
-- top of everything and seen from afar, so a tester can walk to one.
-- Server parts replicate to every client, which is fine for a dev tool
function LurkerManager:getMarkersFolder(): Folder
	local folder = self.markersFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.SPIDER_SPAWN_MARKERS_FOLDER
	folder.Parent = workspace
	self.markersFolder = folder
	return folder
end

function LurkerManager:findMarkerTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.SPIDER_SPAWN_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`LurkerManager: no {Constants.SPIDER_SPAWN_BILLBOARD} billboard under GameAssets/{Constants.GUI_TEMPLATES_FOLDER}; run build_spider_spawn_billboard.luau`)
		return nil
	end
	return template
end

function LurkerManager:placeMarker(entry: LurkerPocket)
	local position = entry.restingPosition
	if entry.marker or entry.isWoken or not position then
		return
	end
	local template = self:findMarkerTemplate()
	if not template then
		return
	end
	local marker = Instance.new("Part")
	marker.Name = Constants.SPIDER_SPAWN_BILLBOARD
	marker.Size = Vector3.one
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CFrame = CFrame.new(position)
	local billboard = template:Clone()
	billboard.Adornee = marker
	billboard.Parent = marker
	marker.Parent = self:getMarkersFolder()
	entry.marker = marker
end

function LurkerManager:removeMarker(entry: LurkerPocket)
	local marker = entry.marker
	if marker then
		marker:Destroy()
		entry.marker = nil
	end
end

function LurkerManager:setSpawnsVisible(isVisible: boolean)
	self.isSpawnsVisible = isVisible
	if isVisible then
		for _, entry in self.lurkerPockets do
			self:placeMarker(entry)
		end
		return
	end
	for _, entry in self.lurkerPockets do
		self:removeMarker(entry)
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
end

-- openedAt is the block just broken: the spider starts on the floor cell
-- farthest from it, across the room
function LurkerManager:wake(entry: LurkerPocket, openedAt: LurkerRules.Cell?)
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	entry.isWoken = true
	self:removeMarker(entry)
	local cell = LurkerRules.findRestingCell(grid, entry.pocket, openedAt)
	if self:spawnAtCell(cell) then
		print(`[LurkerManager] a {Enums.getPublicName(Enums.MonsterKind, LurkersData.KIND)} wakes in the pocket at block {entry.pocket.depth}`)
	end
end

-- a broken block that opens a sleeping pocket wakes its lurker
function LurkerManager:onCellCleared(depth: number, height: number, width: number)
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	for _, entry in self.lurkerPockets do
		if entry.isWoken then
			continue
		end
		if LurkerRules.isCellOpeningPocket(grid, entry.pocket, depth, height, width) then
			self:wake(entry, { depth = depth, height = height, width = width })
		end
	end
end

-- the nearest living player within detection range, as the tick's candidate
function LurkerManager:findTarget(monster: MonsterManager.Monster): MonsterRules.Candidate?
	local range = MonsterRules.detectionRangeStuds(monster.data)
	local best: MonsterRules.Candidate? = nil
	local bestDistance = range
	for _, candidate in MonsterManager:getPlayerCandidates() do
		local distance = (candidate.position - monster.position).Magnitude
		if distance <= bestDistance then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

-- moves toward a point at the kind's speed (slowed like any monster),
-- facing the way it goes; true when it got there
function LurkerManager:moveToward(monster: MonsterManager.Monster, destination: Vector3, deltaSec: number): boolean
	local speed = monster.data.SPEED_STUDS_PER_SEC * DamageableManager:getSpeedMultiplier(monster.damageableId)
	local position, isArrived = MonsterRules.stepToward(monster.position, destination, speed, deltaSec)
	if (destination - monster.position).Magnitude > LurkersData.ARRIVE_STUDS then
		MonsterManager:face(monster, destination)
	end
	monster.position = position
	monster.action = Enums.MonsterAction.MOVING
	return isArrived or (destination - position).Magnitude <= LurkersData.ARRIVE_STUDS
end

-- the next cell of the current path, or nil when it is walked
function LurkerManager:followPath(monster: MonsterManager.Monster, lurker: Lurker, deltaSec: number): boolean
	local cell = lurker.path[lurker.pathIndex]
	if not cell then
		return false
	end
	local centre = self:cellCentre(cell)
	if not centre then
		return false
	end
	if self:moveToward(monster, centre, deltaSec) then
		lurker.pathIndex += 1
	end
	return true
end

function LurkerManager:stepLurker(monster: MonsterManager.Monster, now: number, deltaSec: number)
	local lurker = self.lurkerById[monster.id]
	local grid = MineManager:getGrid()
	if not lurker or not grid then
		return
	end
	local data = monster.data
	local target = self:findTarget(monster)
	-- a new quarry is announced, at most every few seconds so a player
	-- flickering at the edge of range does not make it shriek
	local targetId = if target then target.id else nil
	if targetId ~= lurker.targetId then
		lurker.targetId = targetId
		if targetId and now >= lurker.nextAlertTime then
			lurker.nextAlertTime = now + LurkersData.ALERT_COOLDOWN_SEC
			MonsterManager:queueAlert(monster.id)
		end
	end
	if target then
		if MonsterRules.isInAttackRange(monster.position, data, monster.reachStuds, target) then
			monster.action = Enums.MonsterAction.ENGAGED
			MonsterManager:face(monster, target.position)
			if now - monster.lastAttackTime >= MonsterRules.attackIntervalSec(data, BehaviorData.DEFAULT_ATTACK_INTERVAL_SEC) then
				MonsterManager:attack(monster, target, now)
			end
			return
		end
		local from = self:airCellAt(monster.position)
		local to = self:surfaceCellAt(target.position)
		-- it always walks cell to cell along the rock (a straight run cut
		-- corners through walls, 2026-10-08); a player it cannot reach in
		-- SEARCH_MAX_CELLS leaves it to finish what it was walking and drift
		-- (clearing the path here froze it in a sealed pocket)
		if from and to and now >= lurker.nextSearchTime then
			lurker.nextSearchTime = now + LurkersData.SEARCH_INTERVAL_SEC
			local path = LurkerRules.findPath(grid, from, to, LurkersData.SEARCH_MAX_CELLS)
			if path then
				lurker.path = path
				lurker.pathIndex = 1
			end
		end
	end
	if self:followPath(monster, lurker, deltaSec) then
		return
	end
	-- nothing to chase and nowhere to go: drift
	monster.action = Enums.MonsterAction.ENGAGED
	if now >= lurker.nextWanderTime then
		lurker.nextWanderTime = now + LurkersData.WANDER_INTERVAL_SEC
		local cell = self:airCellAt(monster.position)
		local neighbour = if cell then LurkerRules.randomAirNeighbour(grid, cell, self.random) else nil
		if neighbour then
			lurker.path = { neighbour }
			lurker.pathIndex = 1
		end
	end
end

-- the mine is fresh: draw which pockets hold a lurker
function LurkerManager:onRunStarted()
	self.lurkerById = {}
	self.lurkerPockets = {}
	local pockets = MineManager:getPockets()
	local seed = MineManager:getSeed() or 0
	-- the crew that teleported in sets the count, the mine's seed the pockets
	local run = RunManager:getRun()
	local crewSize = if run then run.playerCount else 1
	local count = LurkerRules.lurkerCount(crewSize, LurkersData.BASE_COUNT, LurkersData.COUNT_PER_EXTRA_CREW, LurkersData.MAX_COUNT)
	local picked = LurkerRules.pickLurkerPockets(pockets, count, Random.new(seed + LurkersData.SEED_OFFSET), LurkersData.MIN_ZONE_INDEX)
	local grid = MineManager:getGrid()
	for index, pocket in pockets do
		if picked[index] then
			local resting = if grid then LurkerRules.findRestingCell(grid, pocket) else nil
			table.insert(self.lurkerPockets, {
				pocket = pocket,
				isWoken = false,
				restingPosition = if resting then self:cellCentre(resting) else nil,
			})
		end
	end
	self.sleepingSoundAccumulatorSec = 0
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
	if self.isSpawnsVisible then
		self:setSpawnsVisible(true)
	end
	print(`[LurkerManager] {#self.lurkerPockets} of {#pockets} pockets hold a lurker ({count} asked for a crew of {crewSize})`)
end

function LurkerManager:init()
	MonsterManager:setCrawlStepper(
		function(monster: MonsterManager.Monster, now: number, deltaSec: number)
			self:stepLurker(monster, now, deltaSec)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
	MineManager:subscribeCellCleared(
		function(depth: number, height: number, width: number)
			self:onCellCleared(depth, height, width)
		end
	)
end

function LurkerManager.new(): LurkerManager
	local self = setmetatable({}, LurkerManager) :: LurkerManager
	self.lurkerPockets = {}
	self.lurkerById = {}
	self.random = Random.new()
	self.sleepingSoundAccumulatorSec = 0
	self.isSpawnsVisible = false
	self.markersFolder = nil
	return self
end

return LurkerManager.new()
