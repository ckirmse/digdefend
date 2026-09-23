--!strict

-- Draws every monster (GDD "Monster Performance"), M29. The server sends
-- no monster instances: a NotifyMonstersSpawned names each id's kind, and
-- positions arrive as packed snapshots (MonsterSnapshotCodec) on the
-- monster UnreliableRemoteEvent, a few times a second. Each monster keeps
-- its last few samples and is drawn INTERPOLATION_DELAY_SEC behind the
-- server, blended between the two samples around that moment, so movement
-- is smooth whatever the packet timing; a monster past its newest sample
-- (a far one, sent less often) carries on at its last speed for a moment.
-- Level of detail, re-ranked a few times a second by distance from the
-- camera: the NEAR_ANIMATED_MAX closest are the full rig animated (walk,
-- idle, attack, death clips from the visual catalogue), the rest within
-- HELD_POSE_DISTANCE_STUDS are the rig standing still, and anything
-- further is the template's one-part Proxy. Nothing is ever hidden for
-- distance. Rigs and proxies come from pools (GameAssets/Monsters, one
-- per kind's template), are never parented in and out, and every frame all
-- of them move in one workspace:BulkMoveTo. Projectiles fly on the
-- client from the launch message; blasts reuse the Post rocket's effect.
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

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MonsterRules = require("@game/ReplicatedStorage/Shared/MonsterRules")
local MonsterSnapshotCodec = require("@game/ReplicatedStorage/Shared/MonsterSnapshotCodec")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientPostManager = require(script.Parent.ClientPostManager)

local ClientMonsterManager = {}
ClientMonsterManager.__index = ClientMonsterManager

type Sample = {
	time: number,
	position: Vector3,
	yawDegrees: number,
}

type Rig = {
	key: string,
	model: Model,
	root: BasePart,
	animator: Animator?,
	tracksById: { [string]: AnimationTrack },
	loopId: string?,
}

-- a kind's hit box, measured from its template's Proxy
type BodyMetrics = {
	boxSize: Vector3,
	-- the box centre's height above the root
	boxOffsetY: number,
}

type ProxyEntry = {
	key: string,
	part: BasePart,
	-- the proxy's place relative to the root
	offset: CFrame,
}

type ClientMonster = {
	id: number,
	kind: number,
	damageableId: string,
	visual: MonsterRules.Visual,
	samples: { Sample },
	hpShare: number,
	action: number,
	attackCounter: number,
	shownAttackCounter: number,
	mode: number,
	rig: Rig?,
	proxy: ProxyEntry?,
	renderCFrame: CFrame?,
	distance: number,
	speedStudsPerSec: number,
	body: BodyMetrics,
}

type Dying = {
	rig: Rig?,
	proxy: ProxyEntry?,
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
		nearAnimatedMax: number,
		heldPoseDistanceStuds: number,
		folder: Folder?,
		rigPools: { [string]: { Rig } },
		proxyPools: { [string]: { ProxyEntry } },
		dying: { Dying },
		projectiles: { Projectile },
		lastRankTime: number,
		bulkParts: { BasePart },
		bulkCFrames: { CFrame },
		bytesThisSecond: number,
		packetsThisSecond: number,
		statsWindowStart: number,
		stats: Stats,
		warnedModels: { [string]: boolean },
		bodyMetricsByKey: { [string]: BodyMetrics },
		hpBillboard: BillboardGui?,
		aimedMonster: ClientMonster?,
		hpBarUntil: number,
		lastAimTime: number,
		shownHpMonsterId: number?,
		shownHpShare: number,
		hasWarnedHpTemplate: boolean,
	},
	ClientMonsterManager
))

local MODE_NONE = 0
local MODE_ANIMATED = 1
local MODE_HELD = 2
local MODE_PROXY = 3

local FOLDER_NAME = "Monsters"
-- a pooled body waits out of sight here rather than leaving the Workspace
local PARKED_CFRAME = CFrame.new(0, -10000, 0)
local RANK_INTERVAL_SEC = 0.2
local MAX_SAMPLES = 5
-- a monster past its newest sample keeps moving at its last speed this long
local MAX_EXTRAPOLATE_SEC = 0.5
-- the default walk clip is paced for this speed; faster monsters step faster
local WALK_CLIP_SPEED_STUDS_PER_SEC = 10
local DEATH_HOLD_SEC = 1
local DEATH_SINK_SEC = 0.6
local DEATH_SINK_STUDS = 3
local HIT_FLASH_SEC = 0.12
local HIT_FLASH_COLOR = Color3.fromRGB(255, 255, 255)
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
local HP_FULL_COLOR = Color3.fromRGB(90, 200, 110)
local HP_EMPTY_COLOR = Color3.fromRGB(220, 70, 60)
local DEFAULT_BODY: BodyMetrics = {
	boxSize = Vector3.new(4, 5, 1),
	boxOffsetY = -0.5,
}
local DEFAULT_VISUAL: MonsterRules.Visual = {
	model = "ZOMBIE_1",
	maxHp = 100,
	isAir = false,
	walkAnimationId = "",
	idleAnimationId = nil,
	attackAnimationId = "",
	deathAnimationId = "",
	projectile = nil,
}

local function yawLerp(from: number, to: number, alpha: number): number
	local delta = (to - from + 180) % 360 - 180
	return from + delta * alpha
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
	local template = if folder then folder:FindFirstChild(modelName) else nil
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

function ClientMonsterManager:acquireRig(visual: MonsterRules.Visual): Rig?
	local key = self:poolKey(visual)
	local pool = self.rigPools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: Rig
	end
	local template = self:findTemplate(visual.model)
	if not template then
		return nil
	end
	local model = template:Clone()
	local proxy = model:FindFirstChild(Constants.MONSTER_PROXY_PART)
	if proxy then
		proxy:Destroy()
	end
	local root = model.PrimaryPart :: BasePart
	-- anything the designer adds to a monster (a bomb, a club) is only ever
	-- looked at: the server decides every hit, so no part collides, takes
	-- queries, or weighs anything, and only the root is anchored
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = if controller then controller:FindFirstChildOfClass("Animator") else nil
	model:PivotTo(PARKED_CFRAME)
	model.Parent = self:getFolder()
	return {
		key = key,
		model = model,
		root = root,
		animator = animator,
		tracksById = {},
		loopId = nil,
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
	for _, descendant in rig.model:GetChildren() do
		if descendant:IsA("Highlight") then
			descendant:Destroy()
		end
	end
	rig.root.CFrame = PARKED_CFRAME
	local pool = self.rigPools[rig.key]
	if not pool then
		pool = {}
		self.rigPools[rig.key] = pool
	end
	table.insert(pool, rig)
end

function ClientMonsterManager:acquireProxy(visual: MonsterRules.Visual): ProxyEntry?
	local key = self:poolKey(visual)
	local pool = self.proxyPools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: ProxyEntry
	end
	local template = self:findTemplate(visual.model)
	local templateProxy = if template then template:FindFirstChild(Constants.MONSTER_PROXY_PART) else nil
	if not template or not templateProxy or not templateProxy:IsA("BasePart") then
		return nil
	end
	local root = template.PrimaryPart :: BasePart
	local part = templateProxy:Clone()
	-- the template's Proxy is invisible so it never hides the model being
	-- edited in Studio; drawn far away, it is the monster
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = PARKED_CFRAME
	part.Parent = self:getFolder()
	local offset = root.CFrame:ToObjectSpace(templateProxy.CFrame)
	return {
		key = key,
		part = part,
		offset = offset,
	}
end

function ClientMonsterManager:releaseProxy(entry: ProxyEntry)
	entry.part.CFrame = PARKED_CFRAME
	local pool = self.proxyPools[entry.key]
	if not pool then
		pool = {}
		self.proxyPools[entry.key] = pool
	end
	table.insert(pool, entry)
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
-- (or nothing) while engaged
function ClientMonsterManager:playLoop(monster: ClientMonster, rig: Rig)
	local visual = monster.visual
	local loopId = if monster.action == Enums.MonsterAction.MOVING then visual.walkAnimationId else visual.idleAnimationId
	if rig.loopId == loopId then
		return
	end
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

function ClientMonsterManager:setMode(monster: ClientMonster, mode: number)
	if monster.mode == mode then
		return
	end
	monster.mode = mode
	if mode == MODE_PROXY then
		if monster.rig then
			self:releaseRig(monster.rig :: Rig)
			monster.rig = nil
		end
		if not monster.proxy then
			monster.proxy = self:acquireProxy(monster.visual)
		end
		return
	end
	if monster.proxy then
		self:releaseProxy(monster.proxy :: ProxyEntry)
		monster.proxy = nil
	end
	if not monster.rig then
		monster.rig = self:acquireRig(monster.visual)
	end
	local rig = monster.rig
	if not rig then
		return
	end
	if mode == MODE_HELD then
		self:stopTracks(rig)
	else
		monster.shownAttackCounter = monster.attackCounter
		self:playLoop(monster, rig)
	end
end

-- where the monster is drawn at renderTime, from the samples around it
function ClientMonsterManager:sampleAt(monster: ClientMonster, renderTime: number): CFrame?
	local samples = monster.samples
	local count = #samples
	if count == 0 then
		return nil
	end
	local position: Vector3
	local yaw: number
	if count == 1 or renderTime <= samples[1].time then
		position = samples[1].position
		yaw = samples[1].yawDegrees
	elseif renderTime >= samples[count].time then
		local last = samples[count]
		local before = samples[count - 1]
		local span = last.time - before.time
		local ahead = math.min(renderTime - last.time, MAX_EXTRAPOLATE_SEC)
		local velocity = if span > 1e-4 then (last.position - before.position) / span else Vector3.zero
		position = last.position + velocity * ahead
		yaw = last.yawDegrees
	else
		position = samples[count].position
		yaw = samples[count].yawDegrees
		for index = 1, count - 1 do
			local from = samples[index]
			local to = samples[index + 1]
			if renderTime >= from.time and renderTime < to.time then
				local alpha = (renderTime - from.time) / (to.time - from.time)
				position = from.position:Lerp(to.position, alpha)
				yaw = yawLerp(from.yawDegrees, to.yawDegrees, alpha)
				break
			end
		end
	end
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
end

function ClientMonsterManager:addSample(monster: ClientMonster, sample: Sample)
	local samples = monster.samples
	local count = #samples
	if count > 0 and sample.time <= samples[count].time then
		-- an unreliable packet arrived out of order: slot it in, or drop a duplicate
		for index = count, 1, -1 do
			if samples[index].time == sample.time then
				return
			end
			if samples[index].time < sample.time then
				table.insert(samples, index + 1, sample)
				break
			end
			if index == 1 then
				table.insert(samples, 1, sample)
			end
		end
	else
		table.insert(samples, sample)
	end
	while #samples > MAX_SAMPLES do
		table.remove(samples, 1)
	end
	local newest = samples[#samples]
	local previous = samples[#samples - 1]
	if previous and newest.time > previous.time then
		local offset = newest.position - previous.position
		monster.speedStudsPerSec = Vector3.new(offset.X, 0, offset.Z).Magnitude / (newest.time - previous.time)
	end
end

function ClientMonsterManager:onSnapshot(packet: any)
	local serverTime, records = MonsterSnapshotCodec.decode(packet)
	if not serverTime or not records then
		return
	end
	self.bytesThisSecond += buffer.len(packet)
	self.packetsThisSecond += 1
	for _, record in records do
		local monster = self.monstersById[record.id]
		if not monster then
			continue
		end
		self:addSample(monster, {
			time = serverTime,
			position = record.position,
			yawDegrees = record.yawDegrees,
		})
		monster.hpShare = record.hpShare
		monster.action = record.action
		monster.attackCounter = record.attackCounter
	end
end

function ClientMonsterManager:onSpawned(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.ids) ~= "table" or typeof(payload.kinds) ~= "table" or typeof(payload.damageableIds) ~= "table" then
		warn("ClientMonsterManager: malformed NotifyMonstersSpawned")
		return
	end
	for index, id in payload.ids do
		local kind = payload.kinds[index]
		local damageableId = payload.damageableIds[index]
		if typeof(id) ~= "number" or typeof(kind) ~= "number" or typeof(damageableId) ~= "string" then
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
			samples = {},
			hpShare = 1,
			action = Enums.MonsterAction.MOVING,
			attackCounter = 0,
			shownAttackCounter = 0,
			mode = MODE_NONE,
			rig = nil,
			proxy = nil,
			renderCFrame = nil,
			distance = math.huge,
			speedStudsPerSec = 0,
			body = self:getBodyMetrics(visual),
		}
		self.monstersById[id] = monster
		self.monsterByDamageableId[damageableId] = monster
	end
	-- a fresh crowd is ranked on the next frame
	self.lastRankTime = 0
end

-- a death keeps the body a moment for its clip, then sinks it away; a
-- monster never drawn simply goes
function ClientMonsterManager:removeMonster(monster: ClientMonster, isDeath: boolean)
	self.monstersById[monster.id] = nil
	self.monsterByDamageableId[monster.damageableId] = nil
	local cframe = monster.renderCFrame
	if isDeath and cframe and (monster.rig or monster.proxy) then
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
			proxy = monster.proxy,
			cframe = cframe,
			startTime = workspace:GetServerTimeNow(),
		})
		return
	end
	if monster.rig then
		self:releaseRig(monster.rig :: Rig)
	end
	if monster.proxy then
		self:releaseProxy(monster.proxy :: ProxyEntry)
	end
end

function ClientMonsterManager:onDied(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.ids) ~= "table" then
		warn("ClientMonsterManager: malformed NotifyMonstersDied")
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
	if typeof(payload) ~= "table" or typeof(payload.from) ~= "Vector3" or typeof(payload.to) ~= "Vector3" or typeof(payload.flightSec) ~= "number" then
		warn("ClientMonsterManager: malformed NotifyMonsterProjectile")
		return
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER) else nil
	local template = if folder and typeof(payload.projectile) == "string" then folder:FindFirstChild(payload.projectile) else nil
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
	if typeof(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
		warn("ClientMonsterManager: malformed NotifyMonsterBlast")
		return
	end
	if ClientPostManager:playAuthoredBlast(payload.position, BLAST_TEMPLATE) then
		return
	end
	local radius = if typeof(payload.radius) == "number" then payload.radius else 5
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = BLAST_PLACEHOLDER_COLOR
	ball.Transparency = 0.4
	ball.Size = Vector3.one * radius * 2
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

function ClientMonsterManager:flashHit(damageableId: string): boolean
	local monster = self.monsterByDamageableId[damageableId]
	if not monster then
		return false
	end
	local rig = monster.rig
	if rig then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = HIT_FLASH_COLOR
		highlight.FillTransparency = 0.3
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = rig.model
		Debris:AddItem(highlight, HIT_FLASH_SEC)
	end
	return true
end

function ClientMonsterManager:getStats(): Stats
	return self.stats
end

-- the damaged monster under the screen centre, nearest first; the world
-- is cast first so a monster behind a wall is never picked
function ClientMonsterManager:findAimedMonster(camera: Camera): ClientMonster?
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { self:getFolder() }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(excluded, character)
	end
	params.FilterDescendantsInstances = excluded
	local worldHit = workspace:Raycast(origin, direction * AIM_RAY_LENGTH_STUDS, params)
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
		fill.BackgroundColor3 = HP_EMPTY_COLOR:Lerp(HP_FULL_COLOR, share)
	end
end

-- aims a few times a second; the bar follows whichever body (rig or
-- proxy) the monster is drawn with, and is rewritten only when it changes
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
	local adornee = if monster and monster.rig then (monster.rig :: Rig).root elseif monster and monster.proxy then (monster.proxy :: ProxyEntry).part else nil
	if not monster or not adornee or monster.hpShare >= 1 then
		billboard.Enabled = false
		billboard.Adornee = nil
		self.shownHpMonsterId = nil
		return
	end
	billboard.Adornee = adornee
	-- the proxy is centred on the body, the rig's root sits at its middle
	local topOffset = if monster.rig then monster.body.boxOffsetY + monster.body.boxSize.Y / 2 else monster.body.boxSize.Y / 2
	billboard.StudsOffsetWorldSpace = Vector3.new(0, topOffset + HP_BAR_LIFT_STUDS, 0)
	billboard.Enabled = true
	if self.shownHpMonsterId ~= monster.id or self.shownHpShare ~= monster.hpShare then
		self.shownHpMonsterId = monster.id
		self.shownHpShare = monster.hpShare
		self:writeHpBar(billboard, monster)
	end
end

-- which monsters are animated, held, or proxies, by distance from the camera
function ClientMonsterManager:rank(cameraPosition: Vector3)
	local ordered = {}
	for _, monster in self.monstersById do
		local cframe = monster.renderCFrame
		monster.distance = if cframe then (cframe.Position - cameraPosition).Magnitude else math.huge
		table.insert(ordered, monster)
	end
	table.sort(
		ordered,
		function(first: ClientMonster, second: ClientMonster): boolean
			return first.distance < second.distance
		end
	)
	local animated = 0
	for _, monster in ordered do
		if monster.distance == math.huge then
			continue
		end
		if monster.distance <= self.heldPoseDistanceStuds and animated < self.nearAnimatedMax then
			animated += 1
			self:setMode(monster, MODE_ANIMATED)
		elseif monster.distance <= self.heldPoseDistanceStuds then
			self:setMode(monster, MODE_HELD)
		else
			self:setMode(monster, MODE_PROXY)
		end
	end
end

function ClientMonsterManager:stepProjectiles(now: number)
	if #self.projectiles == 0 then
		return
	end
	local flying = {}
	for _, projectile in self.projectiles do
		local alpha = (now - projectile.startTime) / projectile.flightSec
		if alpha >= 1 then
			projectile.part:Destroy()
			continue
		end
		local length = (projectile.to - projectile.from).Magnitude
		local lift = math.sin(alpha * math.pi) * length * PROJECTILE_ARC_SHARE
		table.insert(self.bulkParts, projectile.part)
		table.insert(self.bulkCFrames, CFrame.new(projectile.from:Lerp(projectile.to, alpha) + Vector3.new(0, lift, 0)))
		table.insert(flying, projectile)
	end
	self.projectiles = flying
end

function ClientMonsterManager:stepDying(now: number)
	if #self.dying == 0 then
		return
	end
	local remaining = {}
	for _, entry in self.dying do
		local age = now - entry.startTime
		if age >= DEATH_HOLD_SEC + DEATH_SINK_SEC then
			if entry.rig then
				self:releaseRig(entry.rig :: Rig)
			end
			if entry.proxy then
				self:releaseProxy(entry.proxy :: ProxyEntry)
			end
			continue
		end
		local sink = math.max(0, age - DEATH_HOLD_SEC) / DEATH_SINK_SEC * DEATH_SINK_STUDS
		local cframe = entry.cframe - Vector3.new(0, sink, 0)
		if entry.rig then
			table.insert(self.bulkParts, (entry.rig :: Rig).root)
			table.insert(self.bulkCFrames, cframe)
		end
		if entry.proxy then
			local proxy = entry.proxy :: ProxyEntry
			table.insert(self.bulkParts, proxy.part)
			table.insert(self.bulkCFrames, cframe * proxy.offset)
		end
		table.insert(remaining, entry)
	end
	self.dying = remaining
end

function ClientMonsterManager:render()
	local startTime = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local renderTime = startTime - self.interpolationDelaySec
	if camera and startTime - self.lastRankTime >= RANK_INTERVAL_SEC then
		self.lastRankTime = startTime
		self:rank(camera.CFrame.Position)
	end
	table.clear(self.bulkParts)
	table.clear(self.bulkCFrames)
	local animatedCount = 0
	local heldCount = 0
	local proxyCount = 0
	local aliveCount = 0
	for _, monster in self.monstersById do
		aliveCount += 1
		local cframe = self:sampleAt(monster, renderTime)
		monster.renderCFrame = cframe
		if not cframe then
			continue
		end
		local rig = monster.rig
		if rig then
			table.insert(self.bulkParts, rig.root)
			table.insert(self.bulkCFrames, cframe)
			if monster.mode == MODE_ANIMATED then
				animatedCount += 1
				self:playLoop(monster, rig)
				local loop = if rig.loopId then rig.tracksById[rig.loopId] else nil
				if loop and monster.action == Enums.MonsterAction.MOVING then
					loop:AdjustSpeed(math.clamp(monster.speedStudsPerSec / WALK_CLIP_SPEED_STUDS_PER_SEC, 0.5, 2.5))
				end
				if monster.attackCounter ~= monster.shownAttackCounter then
					monster.shownAttackCounter = monster.attackCounter
					local attack = self:getTrack(rig, monster.visual.attackAnimationId)
					if attack then
						attack.Looped = false
						attack:Play(0.05)
					end
				end
			else
				heldCount += 1
			end
		end
		local proxy = monster.proxy
		if proxy then
			proxyCount += 1
			table.insert(self.bulkParts, proxy.part)
			table.insert(self.bulkCFrames, cframe * proxy.offset)
		end
	end
	self:stepDying(startTime)
	self:stepProjectiles(startTime)
	self:updateHpBar(startTime)
	if #self.bulkParts > 0 then
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

function ClientMonsterManager:readTuning()
	local catalog = MonsterRules.decodeVisualCatalog(ClientDataManager:getGameMetadata(Attributes.MONSTER_VISUAL_CATALOG))
	if catalog then
		self.catalog = catalog
	end
	local delay = ClientDataManager:getGameMetadata(Attributes.MONSTER_INTERPOLATION_DELAY_SEC)
	if typeof(delay) == "number" then
		self.interpolationDelaySec = delay
	end
	local nearMax = ClientDataManager:getGameMetadata(Attributes.MONSTER_NEAR_ANIMATED_MAX)
	if typeof(nearMax) == "number" then
		self.nearAnimatedMax = nearMax
	end
	local heldDistance = ClientDataManager:getGameMetadata(Attributes.MONSTER_HELD_POSE_DISTANCE_STUDS)
	if typeof(heldDistance) == "number" then
		self.heldPoseDistanceStuds = heldDistance
	end
end

function ClientMonsterManager:init()
	self:readTuning()
	ClientDamageableManager:setBodyProvider(self)
	for _, key in { Attributes.MONSTER_VISUAL_CATALOG, Attributes.MONSTER_INTERPOLATION_DELAY_SEC, Attributes.MONSTER_NEAR_ANIMATED_MAX, Attributes.MONSTER_HELD_POSE_DISTANCE_STUDS } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function(_value: any)
				self:readTuning()
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
			self.lastRankTime = 0
		end
	)
end

function ClientMonsterManager.new(): ClientMonsterManager
	local self = setmetatable({}, ClientMonsterManager) :: ClientMonsterManager
	self.monstersById = {}
	self.monsterByDamageableId = {}
	self.catalog = {}
	self.interpolationDelaySec = 0.15
	self.nearAnimatedMax = 40
	self.heldPoseDistanceStuds = 250
	self.folder = nil
	self.rigPools = {}
	self.proxyPools = {}
	self.dying = {}
	self.projectiles = {}
	self.lastRankTime = 0
	self.bulkParts = {}
	self.bulkCFrames = {}
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
	self.aimedMonster = nil
	self.hpBarUntil = 0
	self.lastAimTime = 0
	self.shownHpMonsterId = nil
	self.shownHpShare = 1
	self.hasWarnedHpTemplate = false
	return self
end

return ClientMonsterManager.new()
