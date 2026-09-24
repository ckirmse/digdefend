--!strict

-- Draws every monster (GDD "Monster Performance"), M29. The server sends
-- no monster instances: a NotifyMonstersSpawned names each id's kind, and
-- positions arrive as packed snapshots (MonsterSnapshotCodec) on the
-- monster UnreliableRemoteEvent, a few times a second. Each monster keeps
-- its last few samples in a ring of plain numbers and is drawn
-- INTERPOLATION_DELAY_SEC behind the server, blended between the two
-- samples around that moment, so movement is smooth whatever the packet
-- timing; a monster past its newest sample (a far one, sent less often)
-- carries on at its last speed for a moment.
-- Level of detail, re-ranked a few times a second by distance from the
-- camera with a little hysteresis so nobody flickers between bodies: the
-- budget's nearAnimatedMax closest are the full rig animated (walk, idle,
-- attack, death clips from the visual catalogue), the rest within
-- heldPoseDistanceStuds and beyond are the template's one-part Held body
-- (its own shape baked into one union, so a far monster still looks like
-- itself; the Proxy block only stands in for a template without one, and
-- the rig standing still for one with neither). Nothing is ever hidden
-- for distance; a far body is placed every other frame. The budget is the server's
-- DRAW_BUDGETS tier for this device (touch and low graphics quality draw
-- less; decided 2026-09-24). Bodies come from pools (GameAssets/Monsters,
-- one per kind's template), are never parented in and out, and every
-- frame those that moved go in one workspace:BulkMoveTo; a monster that
-- stood still costs nothing, and a Proxy is placed every other frame.
-- Projectiles fly on the client from the launch message; blasts reuse the
-- Post rocket's effect. A hit flashes an animated rig's own pooled
-- Highlight (the engine draws at most 31; a few at once is plenty).
-- HP bar (decided 2026-09-23): one bar only, on the damaged monster under
-- the reticle (the screen centre). Monster parts take no queries, so the
-- aim is the weapons' ray-against-box maths over the drawn positions, cut
-- short by the world first so nothing behind a wall lights up. The bar is
-- the StructureHp billboard every HP bar shares, and it lingers a moment
-- after the reticle moves off so sweeping a crowd does not flicker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MonsterRules = require("@game/ReplicatedStorage/Shared/MonsterRules")
local MonsterSnapshotCodec = require("@game/ReplicatedStorage/Shared/MonsterSnapshotCodec")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientPostManager = require(script.Parent.ClientPostManager)

local ClientMonsterManager = {}
ClientMonsterManager.__index = ClientMonsterManager

local NOTIFY_MONSTERS_SPAWNED_SHAPE = {
	ids = {
		type = "array",
		elementType = "positiveInteger",
	},
	kinds = {
		type = "array",
		elementType = "number",
	},
	damageableIds = {
		type = "array",
		elementType = "string",
	},
}
local NOTIFY_MONSTERS_DIED_SHAPE = {
	ids = {
		type = "array",
		elementType = "positiveInteger",
	},
}
local NOTIFY_MONSTER_PROJECTILE_SHAPE = {
	monsterId = "positiveInteger",
	projectile = "string",
	from = "vector3",
	to = "vector3",
	flightSec = "number",
}
local NOTIFY_MONSTER_BLAST_SHAPE = {
	position = "vector3",
	radius = "number",
}

type Rig = {
	key: string,
	model: Model,
	root: BasePart,
	animator: Animator?,
	tracksById: { [string]: AnimationTrack },
	loopId: string?,
	loopSpeed: number,
	-- its own hit flash, toggled rather than made and destroyed
	highlight: Highlight,
	flashUntil: number,
}

-- a kind's hit box, measured from its template's Proxy
type BodyMetrics = {
	boxSize: Vector3,
	-- the box centre's height above the root
	boxOffsetY: number,
}

-- a one-part body (a Held or a Proxy) and the pool it goes back to
type BodyEntry = {
	part: BasePart,
	-- the part's place relative to the root
	offset: CFrame,
	pool: { BodyEntry },
}

type ClientMonster = {
	id: number,
	kind: number,
	damageableId: string,
	visual: MonsterRules.Visual,
	body: BodyMetrics,
	-- the sample ring: slot `sampleHead` is the newest of `sampleCount`
	sampleCount: number,
	sampleHead: number,
	sampleTimes: { number },
	sampleXs: { number },
	sampleYs: { number },
	sampleZs: { number },
	sampleYaws: { number },
	hpShare: number,
	action: number,
	attackCounter: number,
	shownAttackCounter: number,
	mode: number,
	rig: Rig?,
	held: BodyEntry?,
	proxy: BodyEntry?,
	-- where it was last drawn, and the numbers it was built from so an
	-- unmoved monster is skipped
	renderCFrame: CFrame?,
	renderX: number,
	renderY: number,
	renderZ: number,
	renderYaw: number,
	-- the body changed and must be placed even if the numbers did not
	isBodyDirty: boolean,
	distance: number,
	speedStudsPerSec: number,
}

type Dying = {
	rig: Rig?,
	body: BodyEntry?,
	cframe: CFrame,
	startTime: number,
}

type Projectile = {
	part: BasePart,
	from: Vector3,
	to: Vector3,
	startTime: number,
	flightSec: number,
}

export type Stats = {
	aliveCount: number,
	animatedCount: number,
	heldCount: number,
	proxyCount: number,
	bytesPerSec: number,
	packetsPerSec: number,
	renderMs: number,
}

export type ClientMonsterManager = typeof(setmetatable(
	{} :: {
		monstersById: { [number]: ClientMonster },
		monsterByDamageableId: { [string]: ClientMonster },
		catalog: MonsterRules.VisualCatalog,
		interpolationDelaySec: number,
		budgets: MonsterRules.DrawBudgets?,
		nearAnimatedMax: number,
		heldPoseDistanceStuds: number,
		folder: Folder?,
		rigPools: { [string]: { Rig } },
		heldPools: { [string]: { BodyEntry } },
		proxyPools: { [string]: { BodyEntry } },
		-- templates without a Held part, so the miss is looked up once
		hasNoHeldPart: { [string]: boolean },
		dying: { Dying },
		projectiles: { Projectile },
		flashing: { Rig },
		lastRankTime: number,
		isRankPending: boolean,
		rigClonesLeft: number,
		frameCount: number,
		bulkParts: { BasePart },
		bulkCFrames: { CFrame },
		bulkCount: number,
		packetServerTime: number,
		recordVisitor: MonsterSnapshotCodec.RecordVisitor,
		bytesThisSecond: number,
		packetsThisSecond: number,
		statsWindowStart: number,
		stats: Stats,
		warnedModels: { [string]: boolean },
		bodyMetricsByKey: { [string]: BodyMetrics },
		hpBillboard: BillboardGui?,
		aimParameters: RaycastParams,
		aimedMonster: ClientMonster?,
		hpBarUntil: number,
		lastAimTime: number,
		shownHpMonsterId: number?,
		shownHpShare: number,
		shownAdornee: BasePart?,
		hasWarnedHpTemplate: boolean,
	},
	ClientMonsterManager
))

local MODE_NONE = 0
local MODE_ANIMATED = 1
local MODE_HELD = 2
local MODE_PROXY = 3

local FOLDER_NAME = "Monsters"
-- a pooled body waits out of sight here rather than leaving the Workspace;
-- above FallenPartsDestroyHeight so the engine never sweeps it
local PARKED_CFRAME = CFrame.new(0, -400, 0)
local RANK_INTERVAL_SEC = 0.2
-- a monster keeps its body a little past the line it earned it at
local DEMOTE_DISTANCE_SHARE = 1.1
local DEMOTE_RANK_SHARE = 1.25
-- cloning a rig walks every descendant; a night's first crowd is dressed
-- over a few frames instead of one hitch, proxies standing in meanwhile
local MAX_RIG_CLONES_PER_FRAME = 5
local MAX_SAMPLES = 5
-- a monster past its newest sample keeps moving at its last speed this long
local MAX_EXTRAPOLATE_SEC = 0.5
-- the default walk clip is paced for this speed; faster monsters step faster
local WALK_CLIP_SPEED_STUDS_PER_SEC = 10
local LOOP_SPEED_MIN_CHANGE = 0.1
local DEATH_HOLD_SEC = 1
local DEATH_SINK_SEC = 0.6
local DEATH_SINK_STUDS = 3
local HIT_FLASH_SEC = 0.12
local HIT_FLASH_COLOR = Color3.fromRGB(255, 255, 255)
local MAX_FLASHES = 8
-- a projectile's path bows up by this share of its length
local PROJECTILE_ARC_SHARE = 0.12
local PROJECTILE_PLACEHOLDER_SIZE = 1.6
local PROJECTILE_PLACEHOLDER_COLOR = Color3.fromRGB(255, 120, 30)
-- the Post rocket's blast stands in for every monster blast until art exists
local BLAST_TEMPLATE = "RocketBlast"
local BLAST_PLACEHOLDER_COLOR = Color3.fromRGB(255, 150, 60)
local BLAST_PLACEHOLDER_SEC = 0.35
local AIM_INTERVAL_SEC = 0.05
-- no distance limit on the bar (decided 2026-09-23); a ray needs a length,
-- so this is simply past the far end of any map
local AIM_RAY_LENGTH_STUDS = 10000
local HP_BAR_LINGER_SEC = 0.5
local HP_BAR_LIFT_STUDS = 1.5
local DEFAULT_BODY: BodyMetrics = {
	boxSize = Vector3.new(4, 5, 1),
	boxOffsetY = -0.5,
}
-- neutral stand-ins until the server's catalogue and budgets arrive; the
-- real numbers are GameData, never copied here
local DEFAULT_VISUAL: MonsterRules.Visual = {
	model = "",
	maxHp = 1,
	isAir = false,
	walkAnimationId = "",
	idleAnimationId = nil,
	attackAnimationId = "",
	deathAnimationId = "",
	projectile = nil,
}
local DEFAULT_INTERPOLATION_DELAY_SEC = 0
local DEFAULT_NEAR_ANIMATED_MAX = 0
local DEFAULT_HELD_POSE_DISTANCE_STUDS = 0

local function yawLerp(from: number, to: number, alpha: number): number
	local delta = (to - from + 180) % 360 - 180
	return from + delta * alpha
end

-- one allocation per placement: the rotation as a quaternion about Y
local function yawCFrame(x: number, y: number, z: number, yawDegrees: number): CFrame
	local half = math.rad(yawDegrees) / 2
	return CFrame.new(x, y, z, 0, math.sin(half), 0, math.cos(half))
end

-- the ring slot of the k-th oldest of `count` samples ending at `head`
local function ringSlot(head: number, count: number, k: number): number
	return (head - count + k - 1) % MAX_SAMPLES + 1
end

-- the saved graphics quality as 1 to 10, nil for Automatic
local function savedQualityLevel(): number?
	local isSuccess, setting = pcall(
		function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel
		end
	)
	if not isSuccess or setting == Enum.SavedQualitySetting.Automatic then
		return nil
	end
	return setting.Value
end

function ClientMonsterManager:getFolder(): Folder
	local folder = self.folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	self.folder = created
	return created
end

function ClientMonsterManager:findTemplate(modelName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER) else nil
	local template = if folder and modelName ~= "" then folder:FindFirstChild(modelName) else nil
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	if not self.warnedModels[modelName] then
		self.warnedModels[modelName] = true
		warn(`ClientMonsterManager: no monster template {modelName} with a PrimaryPart under GameAssets.{Constants.MONSTER_TEMPLATES_FOLDER}`)
	end
	return nil
end

function ClientMonsterManager:poolKey(visual: MonsterRules.Visual): string
	return visual.model
end

function ClientMonsterManager:getBodyMetrics(visual: MonsterRules.Visual): BodyMetrics
	local key = self:poolKey(visual)
	local cached = self.bodyMetricsByKey[key]
	if cached then
		return cached
	end
	local template = self:findTemplate(visual.model)
	local proxy = if template then template:FindFirstChild(Constants.MONSTER_PROXY_PART) else nil
	local metrics = DEFAULT_BODY
	if template and proxy and proxy:IsA("BasePart") then
		local root = template.PrimaryPart :: BasePart
		metrics = {
			boxSize = proxy.Size,
			boxOffsetY = proxy.Position.Y - root.Position.Y,
		}
	end
	self.bodyMetricsByKey[key] = metrics
	return metrics
end

-- a pooled rig, or a new clone while the frame's clone budget lasts
function ClientMonsterManager:acquireRig(visual: MonsterRules.Visual): Rig?
	local key = self:poolKey(visual)
	local pool = self.rigPools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: Rig
	end
	if self.rigClonesLeft <= 0 then
		return nil
	end
	local template = self:findTemplate(visual.model)
	if not template then
		return nil
	end
	self.rigClonesLeft -= 1
	local model = template:Clone()
	for _, partName in { Constants.MONSTER_PROXY_PART, Constants.MONSTER_HELD_PART } do
		local spare = model:FindFirstChild(partName)
		if spare then
			spare:Destroy()
		end
	end
	local root = model.PrimaryPart :: BasePart
	-- anything the designer adds to a monster (a bomb, a club) is only ever
	-- looked at: the server decides every hit, so no part collides, takes
	-- queries, casts a shadow, or weighs anything, and only the root is anchored
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end
	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = if controller then controller:FindFirstChildOfClass("Animator") else nil
	local highlight = Instance.new("Highlight")
	highlight.FillColor = HIT_FLASH_COLOR
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model
	model:PivotTo(PARKED_CFRAME)
	model.Parent = self:getFolder()
	return {
		key = key,
		model = model,
		root = root,
		animator = animator,
		tracksById = {},
		loopId = nil,
		loopSpeed = 1,
		highlight = highlight,
		flashUntil = 0,
	}
end

function ClientMonsterManager:stopTracks(rig: Rig)
	for _, track in rig.tracksById do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
	rig.loopId = nil
end

function ClientMonsterManager:releaseRig(rig: Rig)
	self:stopTracks(rig)
	rig.highlight.Enabled = false
	rig.flashUntil = 0
	rig.root.CFrame = PARKED_CFRAME
	local pool = self.rigPools[rig.key]
	if not pool then
		pool = {}
		self.rigPools[rig.key] = pool
	end
	table.insert(pool, rig)
end

-- a one-part body cloned from the named part of the kind's template
function ClientMonsterManager:acquireBody(visual: MonsterRules.Visual, partName: string, pools: { [string]: { BodyEntry } }): BodyEntry?
	local key = self:poolKey(visual)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	if #pool > 0 then
		return table.remove(pool) :: BodyEntry
	end
	local template = self:findTemplate(visual.model)
	local templatePart = if template then template:FindFirstChild(partName) else nil
	if not template or not templatePart or not templatePart:IsA("BasePart") then
		return nil
	end
	local root = template.PrimaryPart :: BasePart
	local part = templatePart:Clone()
	-- the template's copy is invisible so it never hides the model being
	-- edited in Studio; drawn out here, it is the monster
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = PARKED_CFRAME
	part.Parent = self:getFolder()
	return {
		part = part,
		offset = root.CFrame:ToObjectSpace(templatePart.CFrame),
		pool = pool,
	}
end

function ClientMonsterManager:acquireProxy(visual: MonsterRules.Visual): BodyEntry?
	return self:acquireBody(visual, Constants.MONSTER_PROXY_PART, self.proxyPools)
end

-- nil for a template without a Held part; the rig stands in then
function ClientMonsterManager:acquireHeld(visual: MonsterRules.Visual): BodyEntry?
	local key = self:poolKey(visual)
	if self.hasNoHeldPart[key] then
		return nil
	end
	local entry = self:acquireBody(visual, Constants.MONSTER_HELD_PART, self.heldPools)
	if not entry then
		self.hasNoHeldPart[key] = true
	end
	return entry
end

function ClientMonsterManager:releaseBody(entry: BodyEntry)
	entry.part.CFrame = PARKED_CFRAME
	table.insert(entry.pool, entry)
end

function ClientMonsterManager:getTrack(rig: Rig, animationId: string?): AnimationTrack?
	local animator = rig.animator
	if not animator or not animationId or animationId == "" then
		return nil
	end
	local track = rig.tracksById[animationId]
	if track then
		return track
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local isSuccess, loaded = pcall(animator.LoadAnimation, animator, animation)
	if not isSuccess then
		return nil
	end
	rig.tracksById[animationId] = loaded
	return loaded
end

-- the looping clip for what the monster is doing: walk while moving, idle
-- (or nothing) while engaged, paced to its speed
function ClientMonsterManager:playLoop(monster: ClientMonster, rig: Rig)
	local visual = monster.visual
	local isMoving = monster.action == Enums.MonsterAction.MOVING
	local loopId = if isMoving then visual.walkAnimationId else visual.idleAnimationId
	if rig.loopId ~= loopId then
		local previous = if rig.loopId then rig.tracksById[rig.loopId] else nil
		if previous then
			previous:Stop(0.15)
		end
		rig.loopId = loopId
		local track = self:getTrack(rig, loopId)
		if track then
			track.Looped = true
			track:Play(0.15)
		end
	end
	if not isMoving then
		return
	end
	local loop = if rig.loopId then rig.tracksById[rig.loopId] else nil
	local speed = math.clamp(monster.speedStudsPerSec / WALK_CLIP_SPEED_STUDS_PER_SEC, 0.5, 2.5)
	if loop and math.abs(speed - rig.loopSpeed) >= LOOP_SPEED_MIN_CHANGE then
		rig.loopSpeed = speed
		loop:AdjustSpeed(speed)
	end
end

function ClientMonsterManager:playAttackIfNeeded(monster: ClientMonster, rig: Rig)
	if monster.attackCounter == monster.shownAttackCounter then
		return
	end
	monster.shownAttackCounter = monster.attackCounter
	local attack = self:getTrack(rig, monster.visual.attackAnimationId)
	if attack then
		attack.Looped = false
		attack:Play(0.05)
	end
end

-- gives the monster the body its mode wants: the rig when animated, else
-- the template's one-part Held union at any distance (decided 2026-09-24:
-- a far monster keeps its own shape), the Proxy block only for a template
-- with no Held yet, and the rig standing still for one with neither. A rig
-- the clone budget refuses leaves it a one-part body and asks for another
-- ranking next frame
function ClientMonsterManager:setMode(monster: ClientMonster, mode: number)
	if monster.mode == mode then
		return
	end
	local key = self:poolKey(monster.visual)
	if mode ~= MODE_ANIMATED and not monster.held and self.hasNoHeldPart[key] ~= true then
		monster.held = self:acquireHeld(monster.visual)
	end
	local wantsRig = mode == MODE_ANIMATED or (mode == MODE_HELD and monster.held == nil)
	if wantsRig and not monster.rig then
		monster.rig = self:acquireRig(monster.visual)
		if not monster.rig then
			self.isRankPending = true
			mode = MODE_PROXY
			wantsRig = false
		end
	end
	monster.mode = mode
	monster.isBodyDirty = true
	local spareRig: Rig? = monster.rig
	if spareRig and not wantsRig then
		self:releaseRig(spareRig)
		monster.rig = nil
	end
	local spareHeld: BodyEntry? = monster.held
	if spareHeld and wantsRig then
		self:releaseBody(spareHeld)
		monster.held = nil
	end
	local spareProxy: BodyEntry? = monster.proxy
	if not wantsRig and not monster.held then
		monster.proxy = spareProxy or self:acquireProxy(monster.visual)
	elseif spareProxy then
		self:releaseBody(spareProxy)
		monster.proxy = nil
	end
	local rig = monster.rig
	if not rig then
		return
	end
	if mode == MODE_ANIMATED then
		monster.shownAttackCounter = monster.attackCounter
		self:playLoop(monster, rig)
	else
		self:stopTracks(rig)
	end
end

-- where the monster is at renderTime, from the samples around it, as
-- plain numbers written to its render fields; false with no samples
function ClientMonsterManager:sampleInto(monster: ClientMonster, renderTime: number): boolean
	local count = monster.sampleCount
	if count == 0 then
		return false
	end
	local head = monster.sampleHead
	local times = monster.sampleTimes
	local xs = monster.sampleXs
	local ys = monster.sampleYs
	local zs = monster.sampleZs
	local yaws = monster.sampleYaws
	local oldest = ringSlot(head, count, 1)
	if count == 1 or renderTime <= times[oldest] then
		monster.renderX = xs[oldest]
		monster.renderY = ys[oldest]
		monster.renderZ = zs[oldest]
		monster.renderYaw = yaws[oldest]
		return true
	end
	if renderTime >= times[head] then
		local before = ringSlot(head, count, count - 1)
		local span = times[head] - times[before]
		local ahead = math.min(renderTime - times[head], MAX_EXTRAPOLATE_SEC)
		local rate = if span > 1e-4 then ahead / span else 0
		monster.renderX = xs[head] + (xs[head] - xs[before]) * rate
		monster.renderY = ys[head] + (ys[head] - ys[before]) * rate
		monster.renderZ = zs[head] + (zs[head] - zs[before]) * rate
		monster.renderYaw = yaws[head]
		return true
	end
	for k = 1, count - 1 do
		local from = ringSlot(head, count, k)
		local to = ringSlot(head, count, k + 1)
		if renderTime >= times[from] and renderTime < times[to] then
			local alpha = (renderTime - times[from]) / (times[to] - times[from])
			monster.renderX = xs[from] + (xs[to] - xs[from]) * alpha
			monster.renderY = ys[from] + (ys[to] - ys[from]) * alpha
			monster.renderZ = zs[from] + (zs[to] - zs[from]) * alpha
			monster.renderYaw = yawLerp(yaws[from], yaws[to], alpha)
			return true
		end
	end
	monster.renderX = xs[head]
	monster.renderY = ys[head]
	monster.renderZ = zs[head]
	monster.renderYaw = yaws[head]
	return true
end

-- one record of a snapshot applied to its monster; an unreliable packet
-- that arrives behind a newer one is dropped, the next is on its way
function ClientMonsterManager:applyRecord(id: number, x: number, y: number, z: number, yawDegrees: number, hpShare: number, action: number, attackCounter: number)
	local monster = self.monstersById[id]
	if not monster then
		return
	end
	local time = self.packetServerTime
	local count = monster.sampleCount
	local head = monster.sampleHead
	if count > 0 and time <= monster.sampleTimes[head] then
		return
	end
	local slot = head % MAX_SAMPLES + 1
	monster.sampleHead = slot
	monster.sampleCount = math.min(count + 1, MAX_SAMPLES)
	monster.sampleTimes[slot] = time
	monster.sampleXs[slot] = x
	monster.sampleYs[slot] = y
	monster.sampleZs[slot] = z
	monster.sampleYaws[slot] = yawDegrees
	if count > 0 then
		local deltaX = x - monster.sampleXs[head]
		local deltaZ = z - monster.sampleZs[head]
		monster.speedStudsPerSec = math.sqrt(deltaX * deltaX + deltaZ * deltaZ) / (time - monster.sampleTimes[head])
	end
	monster.hpShare = hpShare
	monster.action = action
	monster.attackCounter = attackCounter
	local rig = monster.rig
	if rig and monster.mode == MODE_ANIMATED then
		self:playLoop(monster, rig)
		self:playAttackIfNeeded(monster, rig)
	end
end

function ClientMonsterManager:onSnapshot(packet: any)
	if typeof(packet) ~= "buffer" then
		return
	end
	-- the visitor reads the time from here, so a packet is one pass with
	-- no record tables
	self.packetServerTime = 0
	local isSuccess, headerTime = pcall(buffer.readf64, packet, 0)
	if not isSuccess then
		return
	end
	self.packetServerTime = headerTime
	local serverTime = MonsterSnapshotCodec.forEachRecord(packet, self.recordVisitor)
	if not serverTime then
		return
	end
	self.bytesThisSecond += buffer.len(packet)
	self.packetsThisSecond += 1
end

function ClientMonsterManager:onSpawned(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_MONSTERS_SPAWNED_SHAPE)
	if not isValid then
		warn("ClientMonsterManager: malformed NotifyMonstersSpawned:", errorMessage)
		return
	end
	for index, id in payload.ids do
		local kind = payload.kinds[index]
		local damageableId = payload.damageableIds[index]
		if typeof(kind) ~= "number" or typeof(damageableId) ~= "string" then
			continue
		end
		local previous = self.monstersById[id]
		if previous then
			self:removeMonster(previous, false)
		end
		local visual = self.catalog[kind] or DEFAULT_VISUAL
		local monster: ClientMonster = {
			id = id,
			kind = kind,
			damageableId = damageableId,
			visual = visual,
			body = self:getBodyMetrics(visual),
			sampleCount = 0,
			sampleHead = MAX_SAMPLES,
			sampleTimes = table.create(MAX_SAMPLES, 0),
			sampleXs = table.create(MAX_SAMPLES, 0),
			sampleYs = table.create(MAX_SAMPLES, 0),
			sampleZs = table.create(MAX_SAMPLES, 0),
			sampleYaws = table.create(MAX_SAMPLES, 0),
			hpShare = 1,
			action = Enums.MonsterAction.MOVING,
			attackCounter = 0,
			shownAttackCounter = 0,
			mode = MODE_NONE,
			rig = nil,
			held = nil,
			proxy = nil,
			renderCFrame = nil,
			renderX = 0,
			renderY = 0,
			renderZ = 0,
			renderYaw = 0,
			isBodyDirty = true,
			distance = math.huge,
			speedStudsPerSec = 0,
		}
		self.monstersById[id] = monster
		self.monsterByDamageableId[damageableId] = monster
	end
	-- a fresh crowd is ranked on the next frame
	self.isRankPending = true
end

-- a death keeps the body a moment for its clip, then sinks it away; a
-- monster never drawn simply goes
function ClientMonsterManager:removeMonster(monster: ClientMonster, isDeath: boolean)
	self.monstersById[monster.id] = nil
	self.monsterByDamageableId[monster.damageableId] = nil
	local cframe = monster.renderCFrame
	local body = monster.held or monster.proxy
	if isDeath and cframe and (monster.rig or body) then
		local rig = monster.rig
		if rig and monster.mode == MODE_ANIMATED then
			self:stopTracks(rig)
			local track = self:getTrack(rig, monster.visual.deathAnimationId)
			if track then
				track.Looped = false
				track:Play(0.1)
			end
		end
		table.insert(self.dying, {
			rig = rig,
			body = body,
			cframe = cframe,
			startTime = workspace:GetServerTimeNow(),
		})
		return
	end
	if monster.rig then
		self:releaseRig(monster.rig :: Rig)
	end
	if body then
		self:releaseBody(body)
	end
end

function ClientMonsterManager:onDied(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_MONSTERS_DIED_SHAPE)
	if not isValid then
		warn("ClientMonsterManager: malformed NotifyMonstersDied:", errorMessage)
		return
	end
	for _, id in payload.ids do
		local monster = self.monstersById[id]
		if monster then
			self:removeMonster(monster, true)
		end
	end
end

function ClientMonsterManager:onProjectile(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_MONSTER_PROJECTILE_SHAPE)
	if not isValid then
		warn("ClientMonsterManager: malformed NotifyMonsterProjectile:", errorMessage)
		return
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER) else nil
	local template = if folder and payload.projectile ~= "" then folder:FindFirstChild(payload.projectile) else nil
	local part: BasePart
	if template and template:IsA("BasePart") then
		part = template:Clone()
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * PROJECTILE_PLACEHOLDER_SIZE
		ball.Material = Enum.Material.Neon
		ball.Color = PROJECTILE_PLACEHOLDER_COLOR
		part = ball
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(payload.from)
	part.Parent = self:getFolder()
	table.insert(self.projectiles, {
		part = part,
		from = payload.from,
		to = payload.to,
		startTime = workspace:GetServerTimeNow(),
		flightSec = math.max(payload.flightSec, 0.05),
	})
end

function ClientMonsterManager:onBlast(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_MONSTER_BLAST_SHAPE)
	if not isValid then
		warn("ClientMonsterManager: malformed NotifyMonsterBlast:", errorMessage)
		return
	end
	if ClientPostManager:playAuthoredBlast(payload.position, BLAST_TEMPLATE) then
		return
	end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = BLAST_PLACEHOLDER_COLOR
	ball.Transparency = 0.4
	ball.Size = Vector3.one * payload.radius * 2
	ball.CFrame = CFrame.new(payload.position)
	ball.Parent = self:getFolder()
	Debris:AddItem(ball, BLAST_PLACEHOLDER_SEC)
end

-- the ids a Tower or a weapon hit name the monster by its damageable id
function ClientMonsterManager:getBodyPosition(damageableId: string): Vector3?
	local monster = self.monsterByDamageableId[damageableId]
	local cframe = if monster then monster.renderCFrame else nil
	return if cframe then cframe.Position else nil
end

-- an animated rig flashes its own Highlight; a body further away, or one
-- past the flash cap, takes the hit silently
function ClientMonsterManager:flashHit(damageableId: string): boolean
	local monster = self.monsterByDamageableId[damageableId]
	if not monster then
		return false
	end
	local rig = monster.rig
	if not rig or monster.mode ~= MODE_ANIMATED then
		return true
	end
	local now = workspace:GetServerTimeNow()
	if rig.flashUntil <= now then
		if #self.flashing >= MAX_FLASHES then
			return true
		end
		table.insert(self.flashing, rig)
		rig.highlight.Enabled = true
	end
	rig.flashUntil = now + HIT_FLASH_SEC
	return true
end

function ClientMonsterManager:stepFlashes(now: number)
	local flashing = self.flashing
	local index = #flashing
	while index > 0 do
		local rig = flashing[index]
		if now >= rig.flashUntil then
			rig.highlight.Enabled = false
			flashing[index] = flashing[#flashing]
			flashing[#flashing] = nil
		end
		index -= 1
	end
end

function ClientMonsterManager:getStats(): Stats
	return self.stats
end

-- the world the aim ray stops at: every monster body and this character
-- are see-through
function ClientMonsterManager:refreshAimFilter()
	local excluded: { Instance } = { self:getFolder() }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(excluded, character)
	end
	self.aimParameters.FilterDescendantsInstances = excluded
end

-- the damaged monster under the screen centre, nearest first; the world
-- is cast first so a monster behind a wall is never picked
function ClientMonsterManager:findAimedMonster(camera: Camera): ClientMonster?
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	local worldHit = workspace:Raycast(origin, direction * AIM_RAY_LENGTH_STUDS, self.aimParameters)
	local reach = if worldHit then worldHit.Distance else AIM_RAY_LENGTH_STUDS
	local best: ClientMonster? = nil
	local bestDistance = reach
	for _, monster in self.monstersById do
		local cframe = monster.renderCFrame
		if not cframe or monster.hpShare >= 1 then
			continue
		end
		local body = monster.body
		if (cframe.Position - origin).Magnitude > bestDistance + body.boxSize.Magnitude then
			continue
		end
		local distance = WeaponRules.rayBoxDistance(origin, direction, cframe * CFrame.new(0, body.boxOffsetY, 0), body.boxSize, bestDistance)
		if distance and distance < bestDistance then
			best = monster
			bestDistance = distance
		end
	end
	return best
end

function ClientMonsterManager:getHpBillboard(): BillboardGui?
	local billboard = self.hpBillboard
	if billboard and billboard.Parent then
		return billboard
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.STRUCTURE_HP_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		if not self.hasWarnedHpTemplate then
			self.hasWarnedHpTemplate = true
			warn(`ClientMonsterManager: no {Constants.STRUCTURE_HP_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_structure_hp_billboard.luau`)
		end
		return nil
	end
	local created = template:Clone()
	created.Enabled = false
	-- the bar is aimed at, never scattered over a crowd, so it shows at any
	-- distance
	created.MaxDistance = math.huge
	local root = created:FindFirstChild(Constants.STRUCTURE_HP_ROOT_FRAME)
	local costRow = if root then root:FindFirstChild(Constants.STRUCTURE_HP_COST_ROW) else nil
	-- the repair price row belongs to Repair Mode only
	if costRow and costRow:IsA("GuiObject") then
		costRow.Visible = false
	end
	created.Parent = self:getFolder()
	self.hpBillboard = created
	return created
end

function ClientMonsterManager:writeHpBar(billboard: BillboardGui, monster: ClientMonster)
	local root = billboard:FindFirstChild(Constants.STRUCTURE_HP_ROOT_FRAME)
	local nameLabel = if root then root:FindFirstChild(Constants.STRUCTURE_HP_NAME_LABEL) else nil
	local bar = if root then root:FindFirstChild(Constants.STRUCTURE_HP_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_FILL) else nil
	local valueLabel = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_VALUE_LABEL) else nil
	local share = math.clamp(monster.hpShare, 0, 1)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.MonsterKind, monster.kind) or "")
	end
	if valueLabel and valueLabel:IsA("TextLabel") then
		local maxHp = monster.visual.maxHp
		valueLabel.Text = `{math.ceil(share * maxHp)} / {maxHp}`
	end
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(share, 1)
		fill.BackgroundColor3 = UiStyle.HP_EMPTY_COLOR:Lerp(UiStyle.HP_FULL_COLOR, share)
	end
end

-- the part the bar hangs on: the rig's root, else the one-part body
function ClientMonsterManager:adorneeOf(monster: ClientMonster): BasePart?
	if monster.rig then
		return (monster.rig :: Rig).root
	end
	local body = monster.held or monster.proxy
	return if body then body.part else nil
end

-- aims a few times a second; the bar follows whichever body the monster is
-- drawn with, and every write happens only when its value changes
function ClientMonsterManager:updateHpBar(now: number)
	local camera = workspace.CurrentCamera
	if camera and now - self.lastAimTime >= AIM_INTERVAL_SEC then
		self.lastAimTime = now
		local aimed = self:findAimedMonster(camera)
		if aimed then
			self.aimedMonster = aimed
			self.hpBarUntil = now + HP_BAR_LINGER_SEC
		elseif now > self.hpBarUntil then
			self.aimedMonster = nil
		end
	end
	local monster = self.aimedMonster
	if monster and self.monstersById[monster.id] ~= monster then
		monster = nil
		self.aimedMonster = nil
	end
	local billboard = self:getHpBillboard()
	if not billboard then
		return
	end
	local adornee = if monster then self:adorneeOf(monster) else nil
	if not monster or not adornee or monster.hpShare >= 1 then
		if self.shownAdornee ~= nil then
			billboard.Enabled = false
			billboard.Adornee = nil
			self.shownAdornee = nil
			self.shownHpMonsterId = nil
		end
		return
	end
	if self.shownAdornee ~= adornee then
		self.shownAdornee = adornee
		billboard.Adornee = adornee
		-- the one-part bodies are centred on the box, the rig's root sits at its middle
		local topOffset = if monster.rig then monster.body.boxOffsetY + monster.body.boxSize.Y / 2 else monster.body.boxSize.Y / 2
		billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffset + HP_BAR_LIFT_STUDS, 0)
		billboard.Enabled = true
	end
	if self.shownHpMonsterId ~= monster.id or self.shownHpShare ~= monster.hpShare then
		self.shownHpMonsterId = monster.id
		self.shownHpShare = monster.hpShare
		self:writeHpBar(billboard, monster)
	end
end

-- which monsters are animated, held, or proxies, by distance from the
-- camera. A monster keeps the body it has a little past the line it
-- earned it at, so one hovering on a line does not swap bodies every rank
function ClientMonsterManager:rank(cameraPosition: Vector3)
	self.isRankPending = false
	self.rigClonesLeft = MAX_RIG_CLONES_PER_FRAME
	local ordered: { ClientMonster } = {}
	for _, monster in self.monstersById do
		local cframe = monster.renderCFrame
		monster.distance = if cframe then (cframe.Position - cameraPosition).Magnitude else math.huge
		if cframe then
			table.insert(ordered, monster)
		end
	end
	table.sort(
		ordered,
		function(first: ClientMonster, second: ClientMonster): boolean
			return first.distance < second.distance
		end
	)
	local heldLimit = self.heldPoseDistanceStuds
	local keepHeldLimit = heldLimit * DEMOTE_DISTANCE_SHARE
	local animatedSlots = self.nearAnimatedMax
	local keepAnimatedRank = math.floor(animatedSlots * DEMOTE_RANK_SHARE)
	-- pass one: the animated that are still close enough keep their rigs
	local animated = 0
	for rankIndex, monster in ordered do
		if monster.mode == MODE_ANIMATED and rankIndex <= keepAnimatedRank and monster.distance <= keepHeldLimit and animated < animatedSlots then
			animated += 1
		else
			monster.distance = -monster.distance
		end
	end
	-- pass two: the nearest others fill the slots left; the sign marks who
	-- was kept in pass one
	for _, monster in ordered do
		if monster.distance >= 0 then
			continue
		end
		local distance = -monster.distance
		monster.distance = distance
		if animated < animatedSlots and distance <= heldLimit then
			animated += 1
			self:setMode(monster, MODE_ANIMATED)
		elseif distance <= heldLimit or (monster.mode == MODE_HELD and distance <= keepHeldLimit) then
			self:setMode(monster, MODE_HELD)
		else
			self:setMode(monster, MODE_PROXY)
		end
	end
end

function ClientMonsterManager:pushBulk(part: BasePart, cframe: CFrame)
	local count = self.bulkCount + 1
	self.bulkCount = count
	self.bulkParts[count] = part
	self.bulkCFrames[count] = cframe
end

function ClientMonsterManager:stepProjectiles(now: number)
	local projectiles = self.projectiles
	local index = #projectiles
	while index > 0 do
		local projectile = projectiles[index]
		local alpha = (now - projectile.startTime) / projectile.flightSec
		if alpha >= 1 then
			projectile.part:Destroy()
			projectiles[index] = projectiles[#projectiles]
			projectiles[#projectiles] = nil
		else
			local length = (projectile.to - projectile.from).Magnitude
			local lift = math.sin(alpha * math.pi) * length * PROJECTILE_ARC_SHARE
			self:pushBulk(projectile.part, CFrame.new(projectile.from:Lerp(projectile.to, alpha) + Vector3.new(0, lift, 0)))
		end
		index -= 1
	end
end

function ClientMonsterManager:stepDying(now: number)
	local dying = self.dying
	local index = #dying
	while index > 0 do
		local entry = dying[index]
		local age = now - entry.startTime
		if age >= DEATH_HOLD_SEC + DEATH_SINK_SEC then
			if entry.rig then
				self:releaseRig(entry.rig :: Rig)
			end
			if entry.body then
				self:releaseBody(entry.body :: BodyEntry)
			end
			dying[index] = dying[#dying]
			dying[#dying] = nil
		else
			local sink = math.max(0, age - DEATH_HOLD_SEC) / DEATH_SINK_SEC * DEATH_SINK_STUDS
			local cframe: CFrame = entry.cframe * CFrame.new(0, -sink, 0)
			if entry.rig then
				self:pushBulk((entry.rig :: Rig).root, cframe)
			end
			if entry.body then
				local body = entry.body :: BodyEntry
				self:pushBulk(body.part, cframe * body.offset)
			end
		end
		index -= 1
	end
end

function ClientMonsterManager:render()
	local startTime = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local renderTime = startTime - self.interpolationDelaySec
	self.frameCount += 1
	if camera and (self.isRankPending or startTime - self.lastRankTime >= RANK_INTERVAL_SEC) then
		self.lastRankTime = startTime
		self:rank(camera.CFrame.Position)
	end
	self.bulkCount = 0
	local frameParity = self.frameCount % 2
	local animatedCount = 0
	local heldCount = 0
	local proxyCount = 0
	local aliveCount = 0
	for id, monster in self.monstersById do
		aliveCount += 1
		local mode = monster.mode
		if mode == MODE_ANIMATED then
			animatedCount += 1
		elseif mode == MODE_HELD then
			heldCount += 1
		elseif mode == MODE_PROXY then
			proxyCount += 1
			-- a far block is small on screen: half of them move each frame
			if id % 2 ~= frameParity and not monster.isBodyDirty then
				continue
			end
		end
		local previousX = monster.renderX
		local previousY = monster.renderY
		local previousZ = monster.renderZ
		local previousYaw = monster.renderYaw
		if not self:sampleInto(monster, renderTime) then
			continue
		end
		local isMoved = monster.renderCFrame == nil
			or previousX ~= monster.renderX
			or previousY ~= monster.renderY
			or previousZ ~= monster.renderZ
			or previousYaw ~= monster.renderYaw
		if not isMoved and not monster.isBodyDirty then
			continue
		end
		local cframe: CFrame = if isMoved or monster.renderCFrame == nil then yawCFrame(monster.renderX, monster.renderY, monster.renderZ, monster.renderYaw) else monster.renderCFrame :: CFrame
		monster.renderCFrame = cframe
		monster.isBodyDirty = false
		local rig = monster.rig
		if rig then
			self:pushBulk(rig.root, cframe)
		end
		local body = monster.held or monster.proxy
		if body then
			self:pushBulk(body.part, cframe * body.offset)
		end
	end
	self:stepDying(startTime)
	self:stepProjectiles(startTime)
	self:stepFlashes(startTime)
	self:updateHpBar(startTime)
	local bulkCount = self.bulkCount
	if bulkCount > 0 then
		-- the arrays are reused; anything past this frame's count is stale
		for index = #self.bulkParts, bulkCount + 1, -1 do
			self.bulkParts[index] = nil
			self.bulkCFrames[index] = nil
		end
		workspace:BulkMoveTo(self.bulkParts, self.bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local endTime = workspace:GetServerTimeNow()
	local stats = self.stats
	stats.aliveCount = aliveCount
	stats.animatedCount = animatedCount
	stats.heldCount = heldCount
	stats.proxyCount = proxyCount
	stats.renderMs = (endTime - startTime) * 1000
	if endTime - self.statsWindowStart >= 1 then
		local window = endTime - self.statsWindowStart
		stats.bytesPerSec = self.bytesThisSecond / window
		stats.packetsPerSec = self.packetsThisSecond / window
		self.bytesThisSecond = 0
		self.packetsThisSecond = 0
		self.statsWindowStart = endTime
	end
end

-- the budget for this device from the server's tiers
function ClientMonsterManager:applyBudget()
	local budgets = self.budgets
	if not budgets then
		return
	end
	local budget = MonsterRules.pickDrawBudget(budgets, UserInputService.TouchEnabled, savedQualityLevel())
	if budget.nearAnimatedMax ~= self.nearAnimatedMax or budget.heldPoseDistanceStuds ~= self.heldPoseDistanceStuds then
		self.nearAnimatedMax = budget.nearAnimatedMax
		self.heldPoseDistanceStuds = budget.heldPoseDistanceStuds
		self.isRankPending = true
	end
end

function ClientMonsterManager:readTuning()
	local catalog = MonsterRules.decodeVisualCatalog(ClientDataManager:getGameMetadata(Attributes.MONSTER_VISUAL_CATALOG))
	if catalog then
		self.catalog = catalog
	end
	local delay = ClientDataManager:getGameMetadata(Attributes.MONSTER_INTERPOLATION_DELAY_SEC)
	if typeof(delay) == "number" then
		self.interpolationDelaySec = delay
	end
	local budgets = MonsterRules.decodeDrawBudgets(ClientDataManager:getGameMetadata(Attributes.MONSTER_DRAW_BUDGETS))
	if budgets then
		self.budgets = budgets
	end
	self:applyBudget()
end

function ClientMonsterManager:init()
	self:readTuning()
	self:refreshAimFilter()
	ClientDamageableManager:setBodyProvider(self)
	for _, key in { Attributes.MONSTER_VISUAL_CATALOG, Attributes.MONSTER_INTERPOLATION_DELAY_SEC, Attributes.MONSTER_DRAW_BUDGETS } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function(_value: any)
				self:readTuning()
			end
		)
	end
	local isSuccess, gameSettings = pcall(
		function()
			return UserSettings():GetService("UserGameSettings")
		end
	)
	if isSuccess then
		gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(
			function()
				self:applyBudget()
			end
		)
	end
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MONSTERS_SPAWNED,
		function(payload: any)
			self:onSpawned(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MONSTERS_DIED,
		function(payload: any)
			self:onDied(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MONSTER_PROJECTILE,
		function(payload: any)
			self:onProjectile(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_MONSTER_BLAST,
		function(payload: any)
			self:onBlast(payload)
		end
	)
	task.spawn(
		function()
			local event = ReplicatedStorage:WaitForChild(Constants.MONSTER_SNAPSHOT_EVENT_NAME) :: UnreliableRemoteEvent
			event.OnClientEvent:Connect(
				function(packet: any)
					self:onSnapshot(packet)
				end
			)
		end
	)
	RunService.RenderStepped:Connect(
		function()
			self:render()
		end
	)
	Players.LocalPlayer.CharacterAdded:Connect(
		function()
			-- a respawned camera is somewhere new: rank again at once
			self.isRankPending = true
			self:refreshAimFilter()
		end
	)
end

function ClientMonsterManager.new(): ClientMonsterManager
	local self = setmetatable({}, ClientMonsterManager) :: ClientMonsterManager
	self.monstersById = {}
	self.monsterByDamageableId = {}
	self.catalog = {}
	self.interpolationDelaySec = DEFAULT_INTERPOLATION_DELAY_SEC
	self.budgets = nil
	self.nearAnimatedMax = DEFAULT_NEAR_ANIMATED_MAX
	self.heldPoseDistanceStuds = DEFAULT_HELD_POSE_DISTANCE_STUDS
	self.folder = nil
	self.rigPools = {}
	self.heldPools = {}
	self.proxyPools = {}
	self.hasNoHeldPart = {}
	self.dying = {}
	self.projectiles = {}
	self.flashing = {}
	self.lastRankTime = 0
	self.isRankPending = true
	self.rigClonesLeft = MAX_RIG_CLONES_PER_FRAME
	self.frameCount = 0
	self.bulkParts = {}
	self.bulkCFrames = {}
	self.bulkCount = 0
	self.packetServerTime = 0
	local visitor: MonsterSnapshotCodec.RecordVisitor = function(id: number, x: number, y: number, z: number, yawDegrees: number, hpShare: number, action: number, attackCounter: number, _isSlowed: boolean, _isBurning: boolean)
		self:applyRecord(id, x, y, z, yawDegrees, hpShare, action, attackCounter)
	end
	self.recordVisitor = visitor
	self.bytesThisSecond = 0
	self.packetsThisSecond = 0
	self.statsWindowStart = 0
	self.stats = {
		aliveCount = 0,
		animatedCount = 0,
		heldCount = 0,
		proxyCount = 0,
		bytesPerSec = 0,
		packetsPerSec = 0,
		renderMs = 0,
	}
	self.warnedModels = {}
	self.bodyMetricsByKey = {}
	self.hpBillboard = nil
	local aimParameters = RaycastParams.new()
	aimParameters.FilterType = Enum.RaycastFilterType.Exclude
	self.aimParameters = aimParameters
	self.aimedMonster = nil
	self.hpBarUntil = 0
	self.lastAimTime = 0
	self.shownHpMonsterId = nil
	self.shownHpShare = 1
	self.shownAdornee = nil
	self.hasWarnedHpTemplate = false
	return self
end

return ClientMonsterManager.new()
