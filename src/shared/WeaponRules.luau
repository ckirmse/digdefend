--!strict

-- Pure rules for handheld weapons (GDD "Weapon (Default Tool)", S12): when a
-- shot may be fired, what a magazine does, whether the origin a client sent
-- is believable, and what a hitscan ray hits among boxes. The server owns
-- every decision; the client runs the same maths only to draw its tracer.
-- Tuning is passed in from GameData so this stays unit testable.
local Enums = require(script.Parent.Enums)

local WeaponRules = {}

export type WeaponData = {
	DAMAGE: number,
	FIRE_INTERVAL_SEC: number,
	FIRE_COOLDOWN_SEC: number,
	RANGE_STUDS: number,
	MAGAZINE_SIZE: number,
	RELOAD_SEC: number,
}

export type HitBox = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

local TEMPLATE_PREFIX = "WEAPON_"

function WeaponRules.canFire(lastFireTime: number?, now: number, cooldownSec: number): boolean
	return lastFireTime == nil or now - lastFireTime >= cooldownSec
end

-- reloadEndTime is 0 when no reload is running
function WeaponRules.isReloading(reloadEndTime: number, now: number): boolean
	return reloadEndTime > 0 and now < reloadEndTime
end

function WeaponRules.canReload(ammo: number, magazineSize: number, reloadEndTime: number, now: number): boolean
	return ammo < magazineSize and not WeaponRules.isReloading(reloadEndTime, now)
end

-- the ray starts at the camera, which in first person sits in the head; the
-- tolerance covers latency and a jet pack's speed
function WeaponRules.isOriginPlausible(headPosition: Vector3, origin: Vector3, toleranceStuds: number): boolean
	return (origin - headPosition).Magnitude <= toleranceStuds
end

-- distance along the ray to the box, nil on a miss or past the range. The
-- slab test in the box's own space; a ray that starts inside hits at 0
function WeaponRules.rayBoxDistance(origin: Vector3, unitDirection: Vector3, boxCFrame: CFrame, boxSize: Vector3, rangeStuds: number): number?
	local localOrigin = boxCFrame:PointToObjectSpace(origin)
	local localDirection = boxCFrame:VectorToObjectSpace(unitDirection)
	local half = boxSize / 2
	local nearest = 0
	local farthest = rangeStuds
	for _, axis in { "X", "Y", "Z" } do
		local start = (localOrigin :: any)[axis] :: number
		local step = (localDirection :: any)[axis] :: number
		local extent = (half :: any)[axis] :: number
		if math.abs(step) < 1e-9 then
			if math.abs(start) > extent then
				return nil
			end
			continue
		end
		local enter = (-extent - start) / step
		local leave = (extent - start) / step
		if enter > leave then
			enter, leave = leave, enter
		end
		nearest = math.max(nearest, enter)
		farthest = math.min(farthest, leave)
		if nearest > farthest then
			return nil
		end
	end
	return nearest
end

-- the first box along the ray, no further than maxDistance (the world the
-- ray would have struck first, or the weapon's range)
function WeaponRules.findClosestHit(origin: Vector3, unitDirection: Vector3, maxDistance: number, boxes: { HitBox }): (string?, number?)
	local closestId: string? = nil
	local closestDistance: number? = nil
	for _, box in boxes do
		local distance = WeaponRules.rayBoxDistance(origin, unitDirection, box.cframe, box.size, maxDistance)
		if distance and (closestDistance == nil or distance < closestDistance) then
			closestId = box.id
			closestDistance = distance
		end
	end
	return closestId, closestDistance
end

-- "WEAPON_RIFLE": the GameAssets/Tools model for a carried weapon
function WeaponRules.templateNameFor(weaponKind: number): string
	return TEMPLATE_PREFIX .. (Enums.getName(Enums.WeaponKind, weaponKind) or "?")
end

-- the loadout saves an unlock name; either the enum key or the public name
-- finds the weapon, anything else is the default
function WeaponRules.resolveLoadoutWeapon(unlockName: string?, defaultKind: number): number
	if unlockName == nil or unlockName == "" then
		return defaultKind
	end
	for _, kind in Enums.getAllValues(Enums.WeaponKind) do
		if Enums.getName(Enums.WeaponKind, kind) == string.upper(unlockName) or Enums.getPublicName(Enums.WeaponKind, kind) == unlockName then
			return kind
		end
	end
	return defaultKind
end

return WeaponRules
