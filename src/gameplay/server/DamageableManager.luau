--!strict

-- Everything a weapon, a Tower, or a Trap can hurt (M24, grown in M27). A
-- target registers a name, a hit box, its HP, and whether it flies, and
-- gets a shadow part back: one invisible anchored part tagged
-- Tags.DAMAGEABLE carrying the Damageable* attributes, which clients dress
-- locally (the shadow system). HP, the hit box, the status effects (slow,
-- stun, burn; StatusRules), and an optional walk live here in Lua;
-- WeaponManager and the Towers test against getHitBoxes and getTargets
-- with pure maths, never against the shadow. A walking target moves its
-- shadow every Heartbeat at its speed times its slow, and stops against a
-- barrier when the blocker query (TrapBehaviorManager) says one is in the
-- way, so a Trap that blocks and a Tower that slows can both be seen to
-- work. The dev-tool dummies are the only targets until enemies register
-- at M29 through the same door. Players and camp structures are never
-- registered, so they cannot be shot.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local StatusRules = require("@game/ReplicatedStorage/Shared/StatusRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")

local DamageableManager = {}
DamageableManager.__index = DamageableManager

export type Registration = {
	name: string,
	cframe: CFrame,
	size: Vector3,
	maxHp: number,
	isAirborne: boolean?,
	-- what it does per second to a barrier that blocks its walk
	attackDamagePerSec: number?,
	-- called once, after the entry is gone, when HP reaches zero
	onDestroyed: ((attacker: Player?) -> ())?,
}

export type Walk = {
	destination: Vector3,
	speedStudsPerSec: number,
}

-- what the Towers and Traps read: a snapshot, never the live entry
export type Target = {
	id: string,
	cframe: CFrame,
	position: Vector3,
	size: Vector3,
	hp: number,
	maxHp: number,
	isAirborne: boolean,
}

export type BlockedTarget = {
	id: string,
	placementId: string,
	attackDamagePerSec: number,
}

-- the placement id standing where a walker wants to go, or nil
export type BlockerQuery = (position: Vector3, size: Vector3) -> string?

type Damageable = {
	id: string,
	hp: number,
	maxHp: number,
	cframe: CFrame,
	size: Vector3,
	isAirborne: boolean,
	attackDamagePerSec: number,
	effects: StatusRules.Effects,
	lastBurnTickTime: number,
	replicatedSpeedMultiplier: number,
	replicatedIsBurning: boolean,
	walk: Walk?,
	blockedByPlacementId: string?,
	shadow: BasePart,
	onDestroyed: ((attacker: Player?) -> ())?,
}

export type DamageableManager = typeof(setmetatable(
	{} :: {
		damageableById: { [string]: Damageable },
		nextId: number,
		shadowFolder: Folder?,
		blockerQuery: BlockerQuery?,
	},
	DamageableManager
))

local SHADOW_FOLDER = "DamageableShadows"
local SHADOW_SIZE = Vector3.one
local ID_PREFIX = "Damageable"
-- the shown slow only changes at this grain, so a slow ticking down does
-- not replicate every frame
local SPEED_MULTIPLIER_GRAIN = 0.05

function DamageableManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = SHADOW_FOLDER
	created.Parent = workspace
	self.shadowFolder = created
	return created
end

function DamageableManager:register(registration: Registration): string
	local id = ID_PREFIX .. self.nextId
	self.nextId += 1
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = SHADOW_SIZE
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = registration.cframe
	shadow:SetAttribute(Attributes.DAMAGEABLE_ID, id)
	shadow:SetAttribute(Attributes.DAMAGEABLE_NAME, registration.name)
	shadow:SetAttribute(Attributes.DAMAGEABLE_SIZE, registration.size)
	shadow:SetAttribute(Attributes.DAMAGEABLE_HP, registration.maxHp)
	shadow:SetAttribute(Attributes.DAMAGEABLE_MAX_HP, registration.maxHp)
	shadow:SetAttribute(Attributes.DAMAGEABLE_IS_AIRBORNE, registration.isAirborne == true)
	shadow:SetAttribute(Attributes.DAMAGEABLE_SPEED_MULTIPLIER, 1)
	shadow:SetAttribute(Attributes.DAMAGEABLE_IS_BURNING, false)
	CollectionService:AddTag(shadow, Tags.DAMAGEABLE)
	self.damageableById[id] = {
		id = id,
		hp = registration.maxHp,
		maxHp = registration.maxHp,
		cframe = registration.cframe,
		size = registration.size,
		isAirborne = registration.isAirborne == true,
		attackDamagePerSec = registration.attackDamagePerSec or 0,
		effects = StatusRules.newEffects(),
		lastBurnTickTime = workspace:GetServerTimeNow(),
		replicatedSpeedMultiplier = 1,
		replicatedIsBurning = false,
		walk = nil,
		blockedByPlacementId = nil,
		shadow = shadow,
		onDestroyed = registration.onDestroyed,
	}
	shadow.Parent = self:getShadowFolder()
	return id
end

function DamageableManager:unregister(id: string)
	local damageable = self.damageableById[id]
	if not damageable then
		return
	end
	self.damageableById[id] = nil
	damageable.shadow:Destroy()
end

function DamageableManager:unregisterAll()
	for id in self.damageableById do
		self:unregister(id)
	end
end

function DamageableManager:getCount(): number
	local count = 0
	for _ in self.damageableById do
		count += 1
	end
	return count
end

function DamageableManager:getHitBoxes(): { WeaponRules.HitBox }
	local boxes = {}
	for id, damageable in self.damageableById do
		table.insert(boxes, {
			id = id,
			cframe = damageable.cframe,
			size = damageable.size,
		})
	end
	return boxes
end

function DamageableManager:snapshot(damageable: Damageable): Target
	return {
		id = damageable.id,
		cframe = damageable.cframe,
		position = damageable.cframe.Position,
		size = damageable.size,
		hp = damageable.hp,
		maxHp = damageable.maxHp,
		isAirborne = damageable.isAirborne,
	}
end

function DamageableManager:getTarget(id: string): Target?
	local damageable = self.damageableById[id]
	return if damageable then self:snapshot(damageable) else nil
end

-- in id order, so a Tower choosing between equal targets is deterministic
function DamageableManager:getTargets(): { Target }
	local ids = {}
	for id in self.damageableById do
		table.insert(ids, id)
	end
	table.sort(ids)
	local targets = {}
	for _, id in ids do
		table.insert(targets, self:snapshot(self.damageableById[id]))
	end
	return targets
end

-- the walkers a barrier is holding up, for the Traps to take their hits
function DamageableManager:getBlockedTargets(): { BlockedTarget }
	local blocked = {}
	for id, damageable in self.damageableById do
		local placementId = damageable.blockedByPlacementId
		if placementId then
			table.insert(blocked, {
				id = id,
				placementId = placementId,
				attackDamagePerSec = damageable.attackDamagePerSec,
			})
		end
	end
	return blocked
end

function DamageableManager:setCFrame(id: string, cframe: CFrame)
	local damageable = self.damageableById[id]
	if not damageable then
		return
	end
	damageable.cframe = cframe
	damageable.shadow.CFrame = cframe
end

-- start (or redirect) a straight walk; nil stops it
function DamageableManager:setWalk(id: string, walk: Walk?)
	local damageable = self.damageableById[id]
	if not damageable then
		return
	end
	damageable.walk = walk
	damageable.blockedByPlacementId = nil
end

function DamageableManager:setBlockerQuery(query: BlockerQuery?)
	self.blockerQuery = query
end

function DamageableManager:applySlow(id: string, share: number, durationSec: number)
	local damageable = self.damageableById[id]
	if not damageable then
		return
	end
	StatusRules.applySlow(damageable.effects, share, durationSec, workspace:GetServerTimeNow())
	self:replicateEffects(damageable, workspace:GetServerTimeNow())
end

function DamageableManager:applyStun(id: string, durationSec: number)
	self:applySlow(id, 1, durationSec)
end

function DamageableManager:applyBurn(id: string, damagePerSec: number, durationSec: number)
	local damageable = self.damageableById[id]
	if not damageable then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not StatusRules.isBurning(damageable.effects, now) then
		damageable.lastBurnTickTime = now
	end
	StatusRules.applyBurn(damageable.effects, damagePerSec, durationSec, now)
	self:replicateEffects(damageable, now)
end

function DamageableManager:getSpeedMultiplier(id: string): number
	local damageable = self.damageableById[id]
	return if damageable then StatusRules.speedMultiplier(damageable.effects, workspace:GetServerTimeNow()) else 1
end

-- returns the HP left, or nil for an unknown id
function DamageableManager:damage(id: string, amount: number, attacker: Player?): number?
	local damageable = self.damageableById[id]
	if not damageable or amount <= 0 then
		return nil
	end
	damageable.hp = math.max(0, damageable.hp - amount)
	if damageable.hp > 0 then
		damageable.shadow:SetAttribute(Attributes.DAMAGEABLE_HP, damageable.hp)
		return damageable.hp
	end
	self:unregister(id)
	if damageable.onDestroyed then
		damageable.onDestroyed(attacker)
	end
	return 0
end

-- the client tints a slowed or burning body from these; written on change only
function DamageableManager:replicateEffects(damageable: Damageable, now: number)
	local multiplier = StatusRules.speedMultiplier(damageable.effects, now)
	local shown = math.floor(multiplier / SPEED_MULTIPLIER_GRAIN + 0.5) * SPEED_MULTIPLIER_GRAIN
	if shown ~= damageable.replicatedSpeedMultiplier then
		damageable.replicatedSpeedMultiplier = shown
		damageable.shadow:SetAttribute(Attributes.DAMAGEABLE_SPEED_MULTIPLIER, shown)
	end
	local isBurning = StatusRules.isBurning(damageable.effects, now)
	if isBurning ~= damageable.replicatedIsBurning then
		damageable.replicatedIsBurning = isBurning
		damageable.shadow:SetAttribute(Attributes.DAMAGEABLE_IS_BURNING, isBurning)
	end
end

function DamageableManager:stepWalk(damageable: Damageable, now: number, deltaSec: number)
	local walk = damageable.walk
	if not walk then
		return
	end
	local multiplier = StatusRules.speedMultiplier(damageable.effects, now)
	local position, isArrived = StatusRules.moveToward(damageable.cframe.Position, walk.destination, walk.speedStudsPerSec, multiplier, deltaSec)
	local query = self.blockerQuery
	local blocker = if query and not damageable.isAirborne then query(position, damageable.size) else nil
	if blocker then
		damageable.blockedByPlacementId = blocker
		return
	end
	damageable.blockedByPlacementId = nil
	if position == damageable.cframe.Position then
		return
	end
	local facing = walk.destination - position
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local cframe = if flatFacing.Magnitude > 1e-3 then CFrame.lookAt(position, position + flatFacing) else damageable.cframe.Rotation + position
	self:setCFrame(damageable.id, cframe)
	if isArrived then
		damageable.walk = nil
	end
end

-- one Heartbeat: burns tick, slows expire, walkers walk
function DamageableManager:step(deltaSec: number)
	local now = workspace:GetServerTimeNow()
	for id, damageable in self.damageableById do
		local burnDamage = StatusRules.burnDamage(damageable.effects, damageable.lastBurnTickTime, now)
		damageable.lastBurnTickTime = now
		if burnDamage > 0 then
			-- burn has no attacker; a dummy killed by fire credits nobody
			if self:damage(id, burnDamage, nil) == 0 then
				continue
			end
		end
		StatusRules.prune(damageable.effects, now)
		self:replicateEffects(damageable, now)
		self:stepWalk(damageable, now, deltaSec)
	end
end

function DamageableManager:init()
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function DamageableManager.new(): DamageableManager
	local self = setmetatable({}, DamageableManager) :: DamageableManager
	self.damageableById = {}
	self.nextId = 1
	self.shadowFolder = nil
	self.blockerQuery = nil
	return self
end

return DamageableManager.new()
