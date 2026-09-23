--!strict

-- Pure rules for how a monster fights (GDD "Monster Creation & Behavior"),
-- M29: what its data looks like, which target it picks (the Refinery
-- first, then its TargetPriorities in order, anything within its
-- DetectionRange, a Decoy drawing a player hunter from further), when it
-- is close enough to hit (its AttackRange), what else a blast hurts, how long a projectile flies, and the visual catalogue the
-- server publishes so clients can dress monsters without GameData. The
-- server (MonsterManager) decides with these; candidates are snapshots so
-- this never touches an instance.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local MonsterRules = {}

-- one GameData/Monsters/Roster entry
export type MonsterData = {
	DIFFICULTY_VALUE: number,
	MAX_HP: number,
	DAMAGE: number,
	SPEED_STUDS_PER_SEC: number,
	TARGET_PRIORITIES: { number },
	TARGET_DAMAGE_TYPES: { number },
	ATTACK_TYPE: number,
	-- how far it notices a target and walks to it (decided 2026-09-23)
	DETECTION_RANGE_STUDS: number,
	ATTACK_RANGE_STUDS: number,
	ATTACK_RADIUS_STUDS: number,
	DIE_ON_ATTACK: boolean,
	DAMAGE_ON_DEATH: boolean,
	TRAVERSAL: number,
	-- AIR only: how high above the ground its feet cruise
	FLIGHT_HEIGHT_STUDS: number?,
	WALK_ANIMATION_ID: string,
	IDLE_ANIMATION_ID: string?,
	ATTACK_ANIMATION_ID: string,
	DEATH_ANIMATION_ID: string,
	PROJECTILE: string?,
	ATTACK_INTERVAL_SEC: number?,
}

-- something a monster could attack. A box target (a wall, a Tower) is
-- measured to its surface; a point target (a player) to its position.
-- A Decoy is a PLAYERS candidate that draws from drawRangeStuds
export type Candidate = {
	id: string,
	targetType: number,
	position: Vector3,
	cframe: CFrame?,
	size: Vector3?,
	-- half the box's flat diagonal, for a cheap reject before the exact measure
	radiusStuds: number?,
	drawRangeStuds: number?,
}

export type CandidatesByType = { [number]: { Candidate } }

-- what a client needs to dress one kind
export type Visual = {
	-- the template under GameAssets/Monsters: the kind's enum key
	model: string,
	-- for the HP bar's numbers; the snapshot carries only the share
	maxHp: number,
	isAir: boolean,
	walkAnimationId: string,
	idleAnimationId: string?,
	attackAnimationId: string,
	deathAnimationId: string,
	projectile: string?,
}

export type VisualCatalog = { [number]: Visual }

function MonsterRules.isRanged(data: MonsterData): boolean
	return data.ATTACK_TYPE == Enums.MonsterAttackType.RANGED
end

function MonsterRules.isAir(data: MonsterData): boolean
	return data.TRAVERSAL == Enums.MonsterTraversal.AIR
end

function MonsterRules.attackIntervalSec(data: MonsterData, defaultSec: number): number
	local interval = data.ATTACK_INTERVAL_SEC
	return if interval and interval > 0 then interval else defaultSec
end

-- distance from a point to a candidate: to the side of its box (0 inside)
-- measured flat, since a wall is tall and a Tower's footprint is thin and
-- neither height should matter; to a point target (a player) in 3D
function MonsterRules.distanceTo(position: Vector3, candidate: Candidate): number
	local cframe = candidate.cframe
	local size = candidate.size
	if cframe and size then
		local localPosition = cframe:PointToObjectSpace(position)
		local outsideX = math.max(math.abs(localPosition.X) - size.X / 2, 0)
		local outsideZ = math.max(math.abs(localPosition.Z) - size.Z / 2, 0)
		return math.sqrt(outsideX * outsideX + outsideZ * outsideZ)
	end
	return (candidate.position - position).Magnitude
end

-- the point of a candidate a monster walks to: the nearest point on its
-- box's flat footprint, at the monster's height, or its position
function MonsterRules.closestPoint(position: Vector3, candidate: Candidate): Vector3
	local cframe = candidate.cframe
	local size = candidate.size
	if cframe and size then
		local localPosition = cframe:PointToObjectSpace(position)
		local clamped = Vector3.new(math.clamp(localPosition.X, -size.X / 2, size.X / 2), localPosition.Y, math.clamp(localPosition.Z, -size.Z / 2, size.Z / 2))
		return (cframe:PointToWorldSpace(clamped))
	end
	return candidate.position
end

-- a box candidate's radius for the cheap reject
function MonsterRules.boxRadius(size: Vector3): number
	return math.sqrt(size.X * size.X + size.Z * size.Z) / 2
end

-- a cheap bound before the exact measure: the flat distance to the
-- candidate's centre less its radius, so never more than distanceTo. The
-- radius is worked out from the box when the builder did not store it
function MonsterRules.roughDistanceTo(position: Vector3, candidate: Candidate): number
	local radius = candidate.radiusStuds
	if radius == nil then
		local size = candidate.size
		radius = if size then MonsterRules.boxRadius(size) else 0
	end
	local deltaX = candidate.position.X - position.X
	local deltaZ = candidate.position.Z - position.Z
	return math.sqrt(deltaX * deltaX + deltaZ * deltaZ) - (radius :: number)
end

-- the priority order a monster checks: the Refinery, then its list
function MonsterRules.priorityOrder(data: MonsterData): { number }
	local order = { Enums.MonsterTargetType.REFINERY }
	for _, targetType in data.TARGET_PRIORITIES do
		if targetType ~= Enums.MonsterTargetType.REFINERY and not table.find(order, targetType) then
			table.insert(order, targetType)
		end
	end
	return order
end

-- how far a monster notices targets: its DetectionRange, but never less
-- than it can hit from, so a Launcher still shells walls from afar
function MonsterRules.detectionRangeStuds(data: MonsterData): number
	return math.max(data.DETECTION_RANGE_STUDS, data.ATTACK_RANGE_STUDS)
end

-- the target a monster at `position` goes for, or nil to keep walking.
-- `reachStuds` is how far past its range its own body reaches (half its
-- width), so a big monster does not have to stand inside a wall. The first
-- type in priority order with anything detected wins; within a type the
-- nearest does. A detected target out of attack range is walked to
function MonsterRules.pickTarget(position: Vector3, data: MonsterData, reachStuds: number, candidatesByType: CandidatesByType): Candidate?
	local range = MonsterRules.detectionRangeStuds(data) + reachStuds
	for _, targetType in MonsterRules.priorityOrder(data) do
		local candidates = candidatesByType[targetType]
		if not candidates then
			continue
		end
		local best: Candidate? = nil
		local bestDistance = math.huge
		for _, candidate in candidates do
			local limit = math.max(range, candidate.drawRangeStuds or 0)
			if MonsterRules.roughDistanceTo(position, candidate) > limit then
				continue
			end
			local distance = MonsterRules.distanceTo(position, candidate)
			if distance <= limit and distance < bestDistance then
				best = candidate
				bestDistance = distance
			end
		end
		if best then
			return best
		end
	end
	return nil
end

-- whether a picked target is close enough to hit now (one picked from
-- further, within detection or a Decoy's draw, is walked to first)
function MonsterRules.isInAttackRange(position: Vector3, data: MonsterData, reachStuds: number, candidate: Candidate): boolean
	return MonsterRules.distanceTo(position, candidate) <= data.ATTACK_RANGE_STUDS + reachStuds
end

-- everything a blast at `center` hurts: the candidates of the listed types
-- within the radius, never the primary target (which is hurt anyway)
function MonsterRules.blastVictims(center: Vector3, radiusStuds: number, damageTypes: { number }, candidatesByType: CandidatesByType, primaryId: string?): { Candidate }
	local victims = {}
	if radiusStuds <= 0 then
		return victims
	end
	for _, targetType in damageTypes do
		for _, candidate in candidatesByType[targetType] or {} do
			if candidate.id == primaryId then
				continue
			end
			if MonsterRules.roughDistanceTo(center, candidate) > radiusStuds then
				continue
			end
			if MonsterRules.distanceTo(center, candidate) <= radiusStuds then
				table.insert(victims, candidate)
			end
		end
	end
	return victims
end

function MonsterRules.flightSec(from: Vector3, to: Vector3, speedStudsPerSec: number): number
	if speedStudsPerSec <= 0 then
		return 0
	end
	return (to - from).Magnitude / speedStudsPerSec
end

-- one step toward a destination; returns the new position and whether it
-- arrived. A slow is already in the speed passed in
function MonsterRules.stepToward(position: Vector3, destination: Vector3, speedStudsPerSec: number, deltaSec: number): (Vector3, boolean)
	local offset = destination - position
	local distance = offset.Magnitude
	local step = speedStudsPerSec * deltaSec
	if distance <= step or distance < 1e-6 then
		return destination, true
	end
	return position + offset * (step / distance), false
end

-- a kind's template is named by its enum key ("BRUTE_2")
function MonsterRules.modelNameFor(kind: number): string
	return Enums.getName(Enums.MonsterKind, kind) or ""
end

function MonsterRules.visualFor(kind: number, data: MonsterData): Visual
	return {
		model = MonsterRules.modelNameFor(kind),
		maxHp = data.MAX_HP,
		isAir = MonsterRules.isAir(data),
		walkAnimationId = data.WALK_ANIMATION_ID,
		idleAnimationId = data.IDLE_ANIMATION_ID,
		attackAnimationId = data.ATTACK_ANIMATION_ID,
		deathAnimationId = data.DEATH_ANIMATION_ID,
		projectile = data.PROJECTILE,
	}
end

function MonsterRules.encodeVisualCatalog(roster: { [number]: MonsterData }): string
	local encoded = {}
	for kind, data in roster do
		encoded[tostring(kind)] = MonsterRules.visualFor(kind, data)
	end
	return HttpService:JSONEncode(encoded)
end

-- nil for anything but a catalogue this module encoded
function MonsterRules.decodeVisualCatalog(json: any): VisualCatalog?
	if typeof(json) ~= "string" or json == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not isSuccess or typeof(decoded) ~= "table" then
		return nil
	end
	local catalog: VisualCatalog = {}
	for key, visual in decoded do
		local kind = tonumber(key)
		if kind and typeof(visual) == "table" and typeof(visual.model) == "string" then
			catalog[kind] = visual
		end
	end
	return catalog
end

return MonsterRules
