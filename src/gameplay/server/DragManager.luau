--!strict

-- The Drags (GDD "Monster Types": Drag, M68; the name is a placeholder):
-- the chase. DragsData.COUNT_PER_ZONE of them sleep sealed in the pockets
-- of every zone from MIN_ZONE_INDEX down (never a pocket the spiders
-- hold), picked from the mine's seed zone by zone. Opening a pocket wakes its Drag, which floats up
-- in the room's middle as a MonsterManager crawler (so it never counts
-- toward a night, is never pushed apart, and dies to no forced dawn),
-- stepped here through MonsterManager:setCrawlStepperForKind, and hunts
-- its waker through the mine's open air cell to cell (pure DragRules: a
-- breadth-first search over air, the victim's trail when sight is lost).
-- Inside the mine nothing hurts it: its Damageable takes damage at zero,
-- so every weapon and tower already passes through it. A touch is the
-- kind's melee (DAMAGE 100, a kill). Dynamite within its blast staggers
-- it (DamageableManager:applyStun). The moment its position leaves the
-- mine (MineSpace.containsPosition) it is expired, day or night (designer,
-- 2026-10-26), and the pocket stays empty. If its victim dies, it is
-- expired and its pocket sleeps again, to wake on the next block cleared
-- into it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DragRules = require("@game/ReplicatedStorage/Shared/DragRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local LurkerRules = require("@game/ReplicatedStorage/Shared/LurkerRules")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MonsterRules = require("@game/ReplicatedStorage/Shared/MonsterRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local DragsData = require("@game/ServerScriptService/GameData/Monsters/Drags")
local DamageableManager = require(script.Parent.DamageableManager)
local DynamiteManager = require(script.Parent.DynamiteManager)
local LurkerManager = require(script.Parent.LurkerManager)
local MineManager = require(script.Parent.MineManager)
local MonsterManager = require(script.Parent.MonsterManager)
local ReviveManager = require(script.Parent.ReviveManager)

local DragManager = {}
DragManager.__index = DragManager

type Cell = DragRules.Cell

type DragPocket = {
	pocket: MineGenerator.Pocket,
	pocketIndex: number,
	isWoken: boolean,
	monsterId: number?,
	-- the dev tool's marker over it while the pockets are shown
	marker: BasePart?,
}

-- the chase's state for one Drag, beside its Monster record
type Drag = {
	entry: DragPocket,
	victimUserId: number?,
	-- the victim's recent cells, newest last
	trail: { Cell },
	nextTrailTime: number,
	path: { Cell },
	pathIndex: number,
	nextSearchTime: number,
	lastPosition: Vector3,
	damageableId: string?,
	-- the chase begins here; until then it hangs where it woke
	chaseStartTime: number,
	-- its Monster record, kept from its first step so a death handler can
	-- retire it outside the tick
	monster: MonsterManager.Monster?,
}

export type DragManager = typeof(setmetatable(
	{} :: {
		dragPockets: { DragPocket },
		dragById: { [number]: Drag },
		isPocketsVisible: boolean,
		markersFolder: Folder?,
	},
	DragManager
))

local MARKER_TEXT = "Drag"
local MARKER_COLOR = Color3.fromRGB(90, 200, 255)
-- the dev spawn seats the Drag up to this far ahead along the player's look
local DEV_SPAWN_AHEAD_STUDS = 16

function DragManager:getPocketCount(): number
	return #self.dragPockets
end

function DragManager:getAwakeCount(): number
	local count = 0
	for _ in self.dragById do
		count += 1
	end
	return count
end

function DragManager:cellCentre(cell: Cell): Vector3?
	local space = MineManager:getSpace()
	if not space then
		return nil
	end
	return MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width)
end

-- where it floats for a cell: the middle of the open column the cell sits
-- in, so a passage of any height carries it down its centre
function DragManager:floatPoint(cell: Cell): Vector3?
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	if not space or not grid then
		return nil
	end
	return MineSpace.cellToWorld(space, cell.depth, DragRules.columnCentreHeight(grid, cell), cell.width)
end

function DragManager:cellAt(position: Vector3): Cell?
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	if not space or not grid then
		return nil
	end
	local depth, height, width = MineSpace.worldToCell(space, position)
	if not LurkerRules.isInBounds(grid, depth, height, width) then
		return nil
	end
	return { depth = depth, height = height, width = width }
end

function DragManager:isInsideMine(position: Vector3): boolean
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	if not space or not grid then
		return false
	end
	return MineSpace.containsPosition(space, grid.depth, grid.height, grid.width, position)
end

-- the dev tool's markers (the spiders' pattern): the spider billboard with
-- its own text over every sleeping Drag's room
function DragManager:getMarkersFolder(): Folder
	local folder = self.markersFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.DRAG_MARKERS_FOLDER
	folder.Parent = workspace
	self.markersFolder = folder
	return folder
end

function DragManager:findMarkerTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.SPIDER_SPAWN_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`DragManager: no {Constants.SPIDER_SPAWN_BILLBOARD} billboard under GameAssets/{Constants.GUI_TEMPLATES_FOLDER}; run build_spider_spawn_billboard.luau`)
		return nil
	end
	return template
end

function DragManager:placeMarker(entry: DragPocket)
	local position = self:cellCentre(DragRules.pocketCentreCell(entry.pocket))
	if entry.marker or entry.isWoken or not position then
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
	entry.marker = marker
end

function DragManager:removeMarker(entry: DragPocket)
	local marker = entry.marker
	if marker then
		marker:Destroy()
		entry.marker = nil
	end
end

function DragManager:setPocketsVisible(isVisible: boolean)
	self.isPocketsVisible = isVisible
	if isVisible then
		for _, entry in self.dragPockets do
			self:placeMarker(entry)
		end
		return
	end
	for _, entry in self.dragPockets do
		self:removeMarker(entry)
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
end

-- the player nearest a position who is alive: the waker, when a pocket opens
function DragManager:findNearestPlayer(position: Vector3): Player?
	local best: Player? = nil
	local bestDistance = math.huge
	for _, player in Players:GetPlayers() do
		if ReviveManager:isDead(player) then
			continue
		end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = player
			end
		end
	end
	return best
end

-- wakes a sleeper: it floats up in its room's middle, unhurtable, after the
-- nearest living player
function DragManager:wake(entry: DragPocket, victim: Player?): number?
	local space = MineManager:getSpace()
	local centre = self:floatPoint(DragRules.pocketCentreCell(entry.pocket))
	if not space or not centre then
		return nil
	end
	local id = MonsterManager:spawnCrawler(DragsData.KIND, centre, -space.forward)
	if not id then
		return nil
	end
	entry.isWoken = true
	entry.monsterId = id
	self:removeMarker(entry)
	self.dragById[id] = {
		entry = entry,
		victimUserId = if victim then victim.UserId else nil,
		trail = {},
		nextTrailTime = 0,
		path = {},
		pathIndex = 1,
		nextSearchTime = 0,
		lastPosition = centre,
		damageableId = nil,
		chaseStartTime = workspace:GetServerTimeNow() + DragsData.WAKE_DELAY_SEC,
		monster = nil,
	}
	MonsterManager:queueAlert(id)
	return id
end

-- the dev tool: a Drag in the air cell the player stands in, after them
function DragManager:spawnAtPlayer(player: Player): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local space = MineManager:getSpace()
	if not root or not root:IsA("BasePart") or not space or not self:isInsideMine(root.Position) then
		return false
	end
	-- the farthest air cell along the look, so the tester has a stretch to run
	local grid = MineManager:getGrid()
	local cell: Cell? = nil
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.xAxis
	for studs = DEV_SPAWN_AHEAD_STUDS, 4, -4 do
		local candidate = self:cellAt(root.Position + look * studs)
		if candidate and grid and LurkerRules.isAir(grid, candidate.depth, candidate.height, candidate.width) then
			cell = candidate
			break
		end
	end
	if not cell then
		cell = self:cellAt(root.Position)
	end
	if not cell then
		return false
	end
	local entry: DragPocket = {
		pocket = { zoneIndex = 0, depth = cell.depth, height = cell.height, width = cell.width, radius = 1 },
		pocketIndex = 0,
		isWoken = false,
		monsterId = nil,
		marker = nil,
	}
	return self:wake(entry, player) ~= nil
end

-- a cleared block that opens into a sleeping Drag's room wakes it, after
-- whoever stands nearest
function DragManager:onCellCleared(depth: number, height: number, width: number)
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	for _, entry in self.dragPockets do
		if entry.isWoken or not LurkerRules.isCellOpeningPocket(grid, entry.pocket, depth, height, width) then
			continue
		end
		local centre = self:cellCentre(DragRules.pocketCentreCell(entry.pocket))
		self:wake(entry, if centre then self:findNearestPlayer(centre) else nil)
	end
end

-- its victim died: every Drag after them goes back to sleep at once. The
-- tick would do it on its next step, but a solo death pauses the run and
-- the tick with it, so this runs from the death itself and flushes the
-- death notice the paused tick would have held (designer, 2026-10-26: it
-- stood over the body)
function DragManager:onPlayerDied(player: Player)
	local isAnyRetired = false
	for _, drag in self.dragById do
		local monster = drag.monster
		if monster and drag.victimUserId == player.UserId then
			self:retire(monster, drag, true)
			isAnyRetired = true
		end
	end
	if isAnyRetired then
		MonsterManager:flushNotifies()
	end
end

-- gone for good (it left the mine) or back to sleep (its victim died)
function DragManager:retire(monster: MonsterManager.Monster, drag: Drag, isSleepingAgain: boolean)
	self.dragById[monster.id] = nil
	drag.entry.monsterId = nil
	if isSleepingAgain then
		drag.entry.isWoken = false
		if self.isPocketsVisible then
			self:placeMarker(drag.entry)
		end
	end
	MonsterManager:expire(monster)
end

function DragManager:findVictim(drag: Drag): Player?
	local userId = drag.victimUserId
	if not userId then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player or ReviveManager:isDead(player) then
		return nil
	end
	return player
end

-- its pace: the victim's walk speed less the data's margin, never under
-- the roster's speed, so a faster player is still a chase
function DragManager:chaseSpeed(monster: MonsterManager.Monster, victim: Player?): number
	local base = monster.data.SPEED_STUDS_PER_SEC
	local character = if victim then victim.Character else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		base = math.max(base, humanoid.WalkSpeed - DragsData.SPEED_UNDER_VICTIM_STUDS_PER_SEC)
	end
	return base
end

-- moves toward a point at the chase speed (stunned to a stop by dynamite
-- like any monster), facing the way it goes; true when it got there
function DragManager:moveToward(monster: MonsterManager.Monster, destination: Vector3, deltaSec: number, speedShare: number, victim: Player?): boolean
	local speed = self:chaseSpeed(monster, victim) * DamageableManager:getSpeedMultiplier(monster.damageableId) * speedShare
	local position, isArrived = MonsterRules.stepToward(monster.position, destination, speed, deltaSec)
	if (destination - monster.position).Magnitude > DragsData.ARRIVE_STUDS then
		MonsterManager:face(monster, destination)
	end
	monster.position = position
	monster.action = Enums.MonsterAction.MOVING
	return isArrived or (destination - position).Magnitude <= DragsData.ARRIVE_STUDS
end

function DragManager:followPath(monster: MonsterManager.Monster, drag: Drag, deltaSec: number, victim: Player): boolean
	local cell = drag.path[drag.pathIndex]
	local centre = if cell then self:floatPoint(cell) else nil
	if not centre then
		return false
	end
	if self:moveToward(monster, centre, deltaSec, 1, victim) then
		drag.pathIndex += 1
	end
	return true
end

function DragManager:stepDrag(monster: MonsterManager.Monster, now: number, deltaSec: number)
	local drag = self.dragById[monster.id]
	if not drag then
		return
	end
	drag.lastPosition = monster.position
	drag.monster = monster
	if not drag.damageableId then
		-- nothing hurts it inside the mine: every hit on its body is scaled to zero
		drag.damageableId = monster.damageableId
		DamageableManager:setDamageTakenMultiplier(monster.damageableId, 0)
	end
	if not self:isInsideMine(monster.position) then
		self:retire(monster, drag, false)
		return
	end
	local victim = self:findVictim(drag)
	if not victim then
		self:retire(monster, drag, true)
		return
	end
	if now < drag.chaseStartTime then
		-- the wake: it hangs where it rose, the shriek playing, before it moves
		monster.action = Enums.MonsterAction.ENGAGED
		return
	end
	local character = victim.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	-- the victim out of the mine is the chase lost: it fades where it is
	-- rather than hanging at the mouth (designer, 2026-10-26)
	if not self:isInsideMine(root.Position) then
		self:retire(monster, drag, false)
		return
	end
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	-- the trail, sampled where the victim stands
	if now >= drag.nextTrailTime then
		drag.nextTrailTime = now + DragsData.TRAIL_SAMPLE_SEC
		local victimCell = self:cellAt(root.Position)
		if victimCell and LurkerRules.isAir(grid, victimCell.depth, victimCell.height, victimCell.width) then
			DragRules.pushTrail(drag.trail, victimCell, DragsData.TRAIL_MAX_CELLS)
		end
	end
	-- the touch
	local candidate = MonsterManager:getPlayerCandidate(victim)
	if candidate and MonsterRules.isInAttackRange(monster.position, monster.data, monster.reachStuds, candidate) then
		monster.action = Enums.MonsterAction.ENGAGED
		MonsterManager:face(monster, candidate.position)
		if now - monster.lastAttackTime >= MonsterRules.attackIntervalSec(monster.data, BehaviorData.DEFAULT_ATTACK_INTERVAL_SEC) then
			-- the touch: the kind's damage through the monster path, then the
			-- recoil, a slow on its own body (the status every monster has) so
			-- the victim can get clear
			MonsterManager:attack(monster, candidate, now)
			DamageableManager:applySlow(monster.damageableId, 1 - DragsData.RECOIL_SLOW_SHARE, DragsData.RECOIL_SLOW_SEC)
		end
		return
	end
	-- the chase: a fresh path now and then, the current one between
	if now >= drag.nextSearchTime then
		drag.nextSearchTime = now + DragsData.SEARCH_INTERVAL_SEC
		local from = self:cellAt(monster.position)
		local victimCell = self:cellAt(root.Position)
		if from then
			local path = DragRules.pickChasePath(grid, from, victimCell, drag.trail, DragsData.SEARCH_MAX_CELLS)
			if path then
				drag.path = path
				drag.pathIndex = 1
			end
		end
	end
	if self:followPath(monster, drag, deltaSec, victim) then
		return
	end
	-- no path left: a victim outside the grid (out of the mine, or at its
	-- mouth) is chased by straight line, which is how a chase ends at the
	-- mouth; a victim in sight is closed on; else it drifts toward where
	-- the victim was last known, slowly, so it never hangs still in a room
	local from = self:cellAt(monster.position)
	local victimCell = self:cellAt(root.Position)
	if not victimCell or (from and LurkerRules.hasLineOfSight(grid, from, victimCell)) then
		self:moveToward(monster, root.Position, deltaSec, 1, victim)
		return
	end
	local last = drag.trail[#drag.trail]
	local lastCentre = if last then self:floatPoint(last) else nil
	if lastCentre then
		self:moveToward(monster, lastCentre, deltaSec, DragsData.LOST_DRIFT_SHARE, victim)
	else
		monster.action = Enums.MonsterAction.ENGAGED
	end
end

-- a stick going off within its blast holds every Drag inside it still
function DragManager:onBlast(position: Vector3, radiusStuds: number)
	for _, drag in self.dragById do
		local damageableId = drag.damageableId
		if damageableId and (drag.lastPosition - position).Magnitude <= radiusStuds then
			DamageableManager:applyStun(damageableId, DragsData.DYNAMITE_STAGGER_SEC)
		end
	end
end

function DragManager:onRunStarted()
	self.dragById = {}
	self.dragPockets = {}
	local pockets = MineManager:getPockets()
	local seed = MineManager:getSeed() or 0
	local picked = DragRules.pickDragPockets(pockets, DragsData.COUNT_PER_ZONE, Random.new(seed + DragsData.SEED_OFFSET), DragsData.MIN_ZONE_INDEX, LurkerManager:getHeldPocketIndices())
	for index, pocket in pockets do
		if picked[index] then
			table.insert(self.dragPockets, {
				pocket = pocket,
				pocketIndex = index,
				isWoken = false,
				monsterId = nil,
				marker = nil,
			})
		end
	end
	local folder = self.markersFolder
	if folder then
		folder:Destroy()
		self.markersFolder = nil
	end
	if self.isPocketsVisible then
		self:setPocketsVisible(true)
	end
	print(`[DragManager] {#self.dragPockets} of {#pockets} pockets hold a Drag ({DragsData.COUNT_PER_ZONE} per zone from zone index {DragsData.MIN_ZONE_INDEX})`)
end

function DragManager:init()
	MonsterManager:setCrawlStepperForKind(
		DragsData.KIND,
		function(monster: MonsterManager.Monster, now: number, deltaSec: number)
			self:stepDrag(monster, now, deltaSec)
		end
	)
	MineManager:subscribeCellCleared(
		function(depth: number, height: number, width: number)
			self:onCellCleared(depth, height, width)
		end
	)
	DynamiteManager:subscribeBlast(
		function(position: Vector3, radiusStuds: number)
			self:onBlast(position, radiusStuds)
		end
	)
	ReviveManager:subscribeDied(
		function(player: Player)
			self:onPlayerDied(player)
		end
	)
end

function DragManager.new(): DragManager
	local self = setmetatable({}, DragManager)
	self.dragPockets = {}
	self.dragById = {}
	self.isPocketsVisible = false
	self.markersFolder = nil
	return self
end

return DragManager.new()
