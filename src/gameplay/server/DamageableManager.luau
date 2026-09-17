--!strict

-- Everything a weapon can hurt (M24). A target registers a name, a hit box,
-- and its HP, and gets a shadow part back: one invisible anchored part
-- tagged Tags.DAMAGEABLE carrying the Damageable* attributes, which clients
-- dress locally (the shadow system). HP and the hit box live here in Lua;
-- WeaponManager tests its rays against getHitBoxes with pure maths
-- (WeaponRules), never against the shadow. The dev-tool target dummy is the
-- only target until enemies register at M29. Players and camp structures
-- are never registered, so they cannot be shot.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")

local DamageableManager = {}
DamageableManager.__index = DamageableManager

export type Registration = {
	name: string,
	cframe: CFrame,
	size: Vector3,
	maxHp: number,
	-- called once, after the entry is gone, when HP reaches zero
	onDestroyed: ((attacker: Player?) -> ())?,
}

type Damageable = {
	id: string,
	hp: number,
	maxHp: number,
	cframe: CFrame,
	size: Vector3,
	shadow: BasePart,
	onDestroyed: ((attacker: Player?) -> ())?,
}

export type DamageableManager = typeof(setmetatable(
	{} :: {
		damageableById: { [string]: Damageable },
		nextId: number,
		shadowFolder: Folder?,
	},
	DamageableManager
))

local SHADOW_FOLDER = "DamageableShadows"
local SHADOW_SIZE = Vector3.one
local ID_PREFIX = "Damageable"

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
	CollectionService:AddTag(shadow, Tags.DAMAGEABLE)
	self.damageableById[id] = {
		id = id,
		hp = registration.maxHp,
		maxHp = registration.maxHp,
		cframe = registration.cframe,
		size = registration.size,
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

function DamageableManager.new(): DamageableManager
	local self = setmetatable({}, DamageableManager) :: DamageableManager
	self.damageableById = {}
	self.nextId = 1
	self.shadowFolder = nil
	return self
end

return DamageableManager.new()
