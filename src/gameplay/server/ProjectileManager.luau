--!strict

-- Every projectile a weapon or a post launches (2026-10-16, the class
-- posts; the Rocket Launcher's rocket of M25 moved here). A projectile is
-- a few numbers stepped every Heartbeat, never a part: it flies straight,
-- or falls under gravity (a lob, the same formula the client uses so the
-- two agree), or bends toward a target (homing). Each step is cast
-- against the world and the damageables (DamageableManager's boxes with
-- WeaponRules' box maths); the first thing struck, or the end of its
-- range, ends it, except a piercing one, which hurts each damageable it
-- passes once and flies on. What a hit or the end does belongs to the
-- launcher (a splash, a pool, a mine, a pull), handed in as callbacks, so
-- this manager knows nothing about posts or weapons. Clients draw a copy
-- from NotifyProjectileLaunched and end it on NotifyProjectileEnded; the
-- server's projectile is the truth, theirs only shows it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ProjectileRules = require("@game/ReplicatedStorage/Shared/ProjectileRules")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local NetManager = require(script.Parent.Parent.Server.NetManager)
local DamageableManager = require(script.Parent.DamageableManager)

local ProjectileManager = {}
ProjectileManager.__index = ProjectileManager

export type Launch = {
	-- who fired it, for the hit confirm and the kill credit
	owner: Player?,
	-- the GameAssets/Projectiles part the clients fly, and the
	-- GameAssets/Effects part they burst at the end (nil for no burst)
	templateName: string,
	blastTemplateName: string?,
	-- whose sound set the clients play (one of the two, or neither)
	postWeaponKind: number?,
	weaponKind: number?,
	origin: Vector3,
	unitDirection: Vector3,
	speedStudsPerSec: number,
	-- 0 for a straight flight
	gravityStudsPerSec2: number,
	-- how far it flies along its path before ending in the air
	rangeStuds: number,
	-- world instances the flight passes through (the post's own gun, whose
	-- mesh the muzzle sits inside, 2026-10-20)
	excludedInstances: { Instance }?,
	-- flies on through every damageable it meets, hurting each once
	isPiercing: boolean?,
	-- bends toward this damageable at this rate (a straight flight only)
	homingTargetId: string?,
	homingTurnDegreesPerSec: number?,
	-- a piercing projectile passing a damageable
	onHit: ((hitId: string, position: Vector3) -> ())?,
	-- where it stopped, and the damageable it struck if any; a piercing
	-- one ends only on the world or its range
	onEnd: (position: Vector3, hitId: string?) -> (),
}

type Projectile = {
	id: string,
	launch: Launch,
	flight: ProjectileRules.Flight,
	elapsedSec: number,
	position: Vector3,
	unitDirection: Vector3,
	travelledStuds: number,
	hitIds: { [string]: boolean },
	hitCount: number,
}

export type ProjectileManager = typeof(setmetatable(
	{} :: {
		projectiles: { Projectile },
		nextId: number,
	},
	ProjectileManager
))

local ID_FORMAT = "Projectile%d"
local NO_KIND = 0
local NO_TARGET = ""

-- how far a segment runs before the world stops it: characters never
-- block (a crewmate in the lane must not catch a rocket), and the
-- projectile folder itself is nothing to hit
function ProjectileManager:getWorldDistance(origin: Vector3, unitDirection: Vector3, lengthStuds: number, excludedInstances: { Instance }?): (number, Vector3?)
	local excluded: { Instance } = if excludedInstances then table.clone(excludedInstances) else {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	table.insert(excluded, DamageableManager:getShadowFolder())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	local result = workspace:Raycast(origin, unitDirection * lengthStuds, params)
	if result then
		return result.Distance, result.Normal
	end
	return lengthStuds, nil
end

function ProjectileManager:launch(launch: Launch): string
	self.nextId += 1
	local id = string.format(ID_FORMAT, self.nextId)
	local unitDirection = if launch.unitDirection.Magnitude > 1e-6 then launch.unitDirection.Unit else Vector3.zAxis
	table.insert(self.projectiles, {
		id = id,
		launch = launch,
		flight = {
			origin = launch.origin,
			unitDirection = unitDirection,
			speedStudsPerSec = launch.speedStudsPerSec,
			gravityStudsPerSec2 = launch.gravityStudsPerSec2,
		},
		elapsedSec = 0,
		position = launch.origin,
		unitDirection = unitDirection,
		travelledStuds = 0,
		hitIds = {},
		hitCount = 0,
	})
	NetManager:notifyAllClients(NetEventNames.NOTIFY_PROJECTILE_LAUNCHED, {
		projectileId = id,
		userId = if launch.owner then launch.owner.UserId else 0,
		postWeaponKind = launch.postWeaponKind or NO_KIND,
		weaponKind = launch.weaponKind or NO_KIND,
		template = launch.templateName,
		blastTemplate = launch.blastTemplateName or "",
		origin = launch.origin,
		direction = unitDirection,
		speed = launch.speedStudsPerSec,
		gravity = launch.gravityStudsPerSec2,
		homingTargetId = launch.homingTargetId or NO_TARGET,
		homingTurn = launch.homingTurnDegreesPerSec or 0,
		isPiercing = launch.isPiercing == true,
	})
	return id
end

function ProjectileManager:finish(projectile: Projectile, position: Vector3, hitId: string?)
	local launch = projectile.launch
	NetManager:notifyAllClients(NetEventNames.NOTIFY_PROJECTILE_ENDED, {
		projectileId = projectile.id,
		userId = if launch.owner then launch.owner.UserId else 0,
		postWeaponKind = launch.postWeaponKind or NO_KIND,
		weaponKind = launch.weaponKind or NO_KIND,
		position = position,
		isBurst = launch.blastTemplateName ~= nil,
		hitCount = projectile.hitCount + (if hitId then 1 else 0),
	})
	launch.onEnd(position, hitId)
end

-- where the projectile wants to be after this step: the lob and the
-- straight flight follow the launch formula, the homing one turns first
function ProjectileManager:nextPosition(projectile: Projectile, deltaSec: number): Vector3
	local launch = projectile.launch
	local targetId = launch.homingTargetId
	if targetId then
		local target = DamageableManager:getTarget(targetId)
		if target then
			projectile.unitDirection = ProjectileRules.turnToward(projectile.unitDirection, projectile.position, target.position, (launch.homingTurnDegreesPerSec or 0) * deltaSec)
		end
		return projectile.position + projectile.unitDirection * launch.speedStudsPerSec * deltaSec
	end
	projectile.elapsedSec += deltaSec
	local position = ProjectileRules.positionAt(projectile.flight, projectile.elapsedSec)
	projectile.unitDirection = ProjectileRules.headingAt(projectile.flight, projectile.elapsedSec)
	return position
end

-- one Heartbeat of flight: the segment to the next position is cast
-- against the world and the damageables, and the first thing struck (or
-- the end of the range) is where it ends; a piercing one takes every
-- damageable on the segment and keeps going
function ProjectileManager:stepProjectile(projectile: Projectile, deltaSec: number, hitBoxes: { WeaponRules.HitBox }): boolean
	local launch = projectile.launch
	local wanted = self:nextPosition(projectile, deltaSec)
	local segment = wanted - projectile.position
	local segmentLength = segment.Magnitude
	if segmentLength < 1e-6 then
		return true
	end
	local stepDirection = segment.Unit
	local step = math.min(segmentLength, launch.rangeStuds - projectile.travelledStuds)
	local worldDistance = self:getWorldDistance(projectile.position, stepDirection, step, launch.excludedInstances)
	local endDistance = worldDistance
	local hitId: string? = nil
	if launch.isPiercing then
		for _, id in WeaponRules.findPierceHits(projectile.position, stepDirection, worldDistance, hitBoxes, math.huge) do
			if projectile.hitIds[id] then
				continue
			end
			projectile.hitIds[id] = true
			projectile.hitCount += 1
			if launch.onHit then
				launch.onHit(id, projectile.position)
			end
		end
	else
		local closestId, closestDistance = WeaponRules.findClosestHit(projectile.position, stepDirection, worldDistance, hitBoxes)
		if closestId and closestDistance then
			hitId = closestId
			endDistance = closestDistance
		end
	end
	projectile.position += stepDirection * endDistance
	projectile.travelledStuds += endDistance
	local isEnded = hitId ~= nil or worldDistance < step or projectile.travelledStuds >= launch.rangeStuds
	if isEnded then
		self:finish(projectile, projectile.position, hitId)
		return false
	end
	return true
end

function ProjectileManager:step(deltaSec: number)
	if #self.projectiles == 0 then
		return
	end
	local hitBoxes = DamageableManager:getHitBoxes()
	local survivors = {}
	for _, projectile in self.projectiles do
		if self:stepProjectile(projectile, deltaSec, hitBoxes) then
			table.insert(survivors, projectile)
		end
	end
	self.projectiles = survivors
end

-- a new run has a new camp; anything still in the air is gone with it
function ProjectileManager:clear()
	self.projectiles = {}
end

function ProjectileManager:init()
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ProjectileManager.new(): ProjectileManager
	local self = setmetatable({}, ProjectileManager) :: ProjectileManager
	self.projectiles = {}
	self.nextId = 0
	return self
end

return ProjectileManager.new()
