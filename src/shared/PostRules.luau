--!strict

-- Pure rules for posts and post weapons (GDD "Posts"), M25: what a weapon's
-- stats are after its upgrades, what the next upgrade costs and needs,
-- how far a base may have turned since the last report, and where the gun,
-- the camera, the muzzle, and the gunner sit for a given yaw and pitch.
-- The server owns every decision; the client runs the same maths to draw
-- the weapon a frame ahead of the echo. Tuning is passed in from GameData
-- (as the catalogue the server publishes) so this stays unit testable.
local HttpService = game:GetService("HttpService")

local Attributes = require(script.Parent.Attributes)
local Constants = require(script.Parent.Constants)
local Enums = require(script.Parent.Enums)
local WeaponRules = require(script.Parent.WeaponRules)

local PostRules = {}

-- a kind that fires a rocket rather than a ray
export type ProjectileData = {
	TEMPLATE: string,
	BLAST_TEMPLATE: string?,
	SPEED_STUDS_PER_SEC: number,
	SPLASH_RADIUS_STUDS: number,
}

-- a gun that overheats: full after FULL_SEC of fire, cool COOL_SEC later
export type HeatData = {
	FULL_SEC: number,
	COOL_SEC: number,
}

export type KindData = {
	PROJECTILE: ProjectileData?,
	HEAT: HeatData?,
	-- a gun that reloads after every shot
	RELOAD_SEC: number?,
	DAMAGE: number,
	FIRE_INTERVAL_SEC: number,
	FIRE_COOLDOWN_SEC: number,
	TURN_SPEED_DEGREES_PER_SEC: number,
	RANGE_STUDS: number,
	FIELD_OF_VIEW: number,
	PITCH_MIN_DEGREES: number,
	PITCH_MAX_DEGREES: number,
}

-- what the server publishes as GameMetadata: entry N of the two lists is
-- the Gold price of upgrade N and the Camp Level it needs; the price list's
-- length is the upgrade cap
export type Catalog = {
	claimPriceGold: number,
	upgradePriceByLevel: { number },
	requiredCampLevelByLevel: { number },
	-- the share of the base stat each upgrade adds, by Enums.PostAttribute
	bonusPerLevelByAttribute: { [number]: number },
	kinds: { [number]: KindData },
}

-- Enums.PostAttribute -> how many upgrades were bought (0 to the cap)
export type Upgrades = { [number]: number }

export type Stats = {
	damage: number,
	fireIntervalSec: number,
	fireCooldownSec: number,
	-- nil for a kind that does not reload; shortened by Fire Rate like the interval
	reloadSec: number?,
	turnSpeedDegreesPerSec: number,
	rangeStuds: number,
}

export type Offer = {
	status: number,
	-- the upgrade the buy would be, nil when maxed
	level: number?,
	price: number?,
	requiredCampLevel: number?,
}

-- what a weapon model's parts are relative to each other, measured once
-- from the template so every frame is a few CFrame multiplies. The Spawn
-- cylinder is the pivot: its X axis is up and its +Z faces out of the camp
export type Rig = {
	-- the gun at pitch 0, relative to the Spawn
	gunOffset: CFrame,
	-- the camera relative to the gun (it tilts with it)
	cameraOffset: CFrame,
	-- the muzzle relative to the gun
	muzzleOffset: Vector3,
	-- the gunner's feet relative to the Spawn (turns, never tilts)
	characterOffset: CFrame,
	-- gun-local: which way the barrel points, and the axis a positive pitch
	-- turns about (barrel × up, so positive lifts the barrel)
	barrel: Vector3,
	pitchAxis: Vector3,
}

-- the private CurrentPlayer attribute carrying each attribute's upgrade count
PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE = {
	[Enums.PostAttribute.DAMAGE] = Attributes.POST_UPGRADE_DAMAGE,
	[Enums.PostAttribute.FIRE_RATE] = Attributes.POST_UPGRADE_FIRE_RATE,
	[Enums.PostAttribute.TURN_SPEED] = Attributes.POST_UPGRADE_TURN_SPEED,
	[Enums.PostAttribute.RANGE] = Attributes.POST_UPGRADE_RANGE,
}

PostRules.NO_POST = 0
PostRules.NOBODY = 0
PostRules.LOCKED_FORMAT = "Camp Level %d required"

local FULL_TURN_DEGREES = 360
local HALF_TURN_DEGREES = 180

function PostRules.multiplier(bonusPerLevel: number, level: number): number
	return 1 + bonusPerLevel * level
end

function PostRules.upgradeCap(catalog: Catalog): number
	return #catalog.upgradePriceByLevel
end

function PostRules.upgradeLevel(upgrades: Upgrades, attribute: number): number
	return upgrades[attribute] or 0
end

-- the weapon's numbers after its upgrades; fire rate shortens both the
-- interval and the cooldown by the same share so the server keeps refusing
-- only what is faster than the client can legitimately send
function PostRules.statsFor(catalog: Catalog, kind: number, upgrades: Upgrades): Stats?
	local data = catalog.kinds[kind]
	if not data then
		return nil
	end
	local bonuses = catalog.bonusPerLevelByAttribute
	local function multiplierFor(attribute: number): number
		return PostRules.multiplier(bonuses[attribute] or 0, PostRules.upgradeLevel(upgrades, attribute))
	end
	local fireRateMultiplier = multiplierFor(Enums.PostAttribute.FIRE_RATE)
	return {
		damage = data.DAMAGE * multiplierFor(Enums.PostAttribute.DAMAGE),
		fireIntervalSec = data.FIRE_INTERVAL_SEC / fireRateMultiplier,
		fireCooldownSec = data.FIRE_COOLDOWN_SEC / fireRateMultiplier,
		reloadSec = if data.RELOAD_SEC then data.RELOAD_SEC / fireRateMultiplier else nil,
		turnSpeedDegreesPerSec = data.TURN_SPEED_DEGREES_PER_SEC * multiplierFor(Enums.PostAttribute.TURN_SPEED),
		rangeStuds = data.RANGE_STUDS * multiplierFor(Enums.PostAttribute.RANGE),
	}
end

-- what the next upgrade of one attribute would be for a player, given the
-- crew's Camp Level; mirrors StoreRules.getOffer
function PostRules.getUpgradeOffer(catalog: Catalog, upgrades: Upgrades, attribute: number, campLevel: number): Offer
	local nextLevel = PostRules.upgradeLevel(upgrades, attribute) + 1
	if nextLevel > PostRules.upgradeCap(catalog) then
		return {
			status = Enums.StoreOffer.MAXED,
			level = nil,
			price = nil,
			requiredCampLevel = nil,
		}
	end
	local requiredCampLevel = catalog.requiredCampLevelByLevel[nextLevel] or 1
	return {
		status = if campLevel < requiredCampLevel then Enums.StoreOffer.LOCKED else Enums.StoreOffer.AVAILABLE,
		level = nextLevel,
		price = catalog.upgradePriceByLevel[nextLevel],
		requiredCampLevel = requiredCampLevel,
	}
end

function PostRules.canAfford(gold: number, price: number): boolean
	return gold >= price
end

-- into (-180, 180], so a base that turned through north compares sanely
function PostRules.wrapDegrees(degrees: number): number
	local wrapped = degrees % FULL_TURN_DEGREES
	if wrapped > HALF_TURN_DEGREES then
		wrapped -= FULL_TURN_DEGREES
	end
	return wrapped
end

function PostRules.clampPitch(pitchDegrees: number, data: KindData): number
	return math.clamp(pitchDegrees, data.PITCH_MIN_DEGREES, data.PITCH_MAX_DEGREES)
end

-- how far the base may turn in elapsedSec at this turn speed
function PostRules.maxYawStep(turnSpeedDegreesPerSec: number, elapsedSec: number): number
	return turnSpeedDegreesPerSec * math.max(0, elapsedSec)
end

-- the client's turn: the input wants wantedDelta degrees this frame, the
-- base gives at most the turn speed allows
function PostRules.turnYaw(yawDegrees: number, wantedDeltaDegrees: number, turnSpeedDegreesPerSec: number, deltaSec: number): number
	local maxStep = PostRules.maxYawStep(turnSpeedDegreesPerSec, deltaSec)
	return PostRules.wrapDegrees(yawDegrees + math.clamp(wantedDeltaDegrees, -maxStep, maxStep))
end

-- the server's check: a report is believable if the base could have turned
-- that far since the last one, plus a tolerance for clock jitter
function PostRules.isYawStepAllowed(previousYawDegrees: number, newYawDegrees: number, turnSpeedDegreesPerSec: number, elapsedSec: number, toleranceDegrees: number): boolean
	local step = math.abs(PostRules.wrapDegrees(newYawDegrees - previousYawDegrees))
	return step <= PostRules.maxYawStep(turnSpeedDegreesPerSec, elapsedSec) + toleranceDegrees
end

-- heat cools only once the trigger has rested longer than the fire
-- interval (plus a little slack), so holding the trigger never cools
PostRules.HEAT_REST_SLACK = 1.5
local HEAT_FULL_TOLERANCE = 1e-6

-- the heat one shot adds: FULL_SEC of shots at the interval reaches 1
function PostRules.heatPerShot(heat: HeatData, fireIntervalSec: number): number
	return fireIntervalSec / heat.FULL_SEC
end

-- the heat now, cooled for the time the trigger has rested since the last shot
function PostRules.cooledHeat(heatAtLastShot: number, lastShotTime: number?, now: number, fireIntervalSec: number, heat: HeatData): number
	if lastShotTime == nil then
		return 0
	end
	local restingSec = now - lastShotTime - fireIntervalSec * PostRules.HEAT_REST_SLACK
	if restingSec <= 0 then
		return heatAtLastShot
	end
	return math.max(0, heatAtLastShot - restingSec / heat.COOL_SEC)
end

-- what a shot does to the heat: the new heat, whether the gun just
-- overheated, and whether it may fire at all (an overheated gun waits for 0)
function PostRules.heatAfterShot(currentHeat: number, isOverheated: boolean, heat: HeatData, fireIntervalSec: number): (boolean, number, boolean)
	if isOverheated and currentHeat > 0 then
		return false, currentHeat, true
	end
	local newHeat = currentHeat + PostRules.heatPerShot(heat, fireIntervalSec)
	-- FULL_SEC / interval shots must reach 1 exactly; the sum lands a hair
	-- under it in floating point
	if newHeat >= 1 - HEAT_FULL_TOLERANCE then
		return true, 1, true
	end
	return true, newHeat, false
end

-- the reload bar's fill, 0 while the reload has just begun to 1 when done
function PostRules.reloadProgress(reloadEndTime: number, now: number, reloadSec: number): number
	if reloadEndTime <= 0 or reloadSec <= 0 then
		return 1
	end
	return math.clamp(1 - (reloadEndTime - now) / reloadSec, 0, 1)
end

-- how far a point is from the nearest point of a box (0 inside it)
function PostRules.distanceToBox(point: Vector3, boxCFrame: CFrame, boxSize: Vector3): number
	local localPoint = boxCFrame:PointToObjectSpace(point)
	local half = boxSize / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

-- every box a burst at this point reaches: within the radius of its surface
function PostRules.findSplashHits(point: Vector3, radiusStuds: number, boxes: { WeaponRules.HitBox }): { string }
	local ids = {}
	for _, box in boxes do
		if PostRules.distanceToBox(point, box.cframe, box.size) <= radiusStuds then
			table.insert(ids, box.id)
		end
	end
	return ids
end

-- a projectile's rotation: its nose (the end away from the tail attachment,
-- in the part's own space) along the flight direction
function PostRules.projectileFrame(position: Vector3, unitDirection: Vector3, tailOffset: Vector3): CFrame
	local nose = if tailOffset.Magnitude > 0.001 then -tailOffset.Unit else -Vector3.zAxis
	-- lookAt sends the part's -Z down the direction; the inverse of a frame
	-- looking along the nose turns the nose into -Z first
	return CFrame.lookAt(position, position + unitDirection) * CFrame.lookAt(Vector3.zero, nose):Inverse()
end

-- the signed unit axis a vector leans furthest along; nil for a zero vector
function PostRules.dominantAxis(vector: Vector3): Vector3?
	local best: Vector3? = nil
	local bestMagnitude = 0.01
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		local component = vector:Dot(axis)
		if math.abs(component) > bestMagnitude then
			bestMagnitude = math.abs(component)
			best = if component > 0 then axis else -axis
		end
	end
	return best
end

-- the Spawn turned about its own X (up) by the yaw; positive is to the
-- right as the gunner sees it (clockwise from above), so a mouse moved
-- right adds yaw
function PostRules.baseFrame(spawnCFrame: CFrame, yawDegrees: number): CFrame
	return spawnCFrame * CFrame.Angles(-math.rad(yawDegrees), 0, 0)
end

function PostRules.gunFrame(baseFrame: CFrame, rig: Rig, pitchDegrees: number): CFrame
	return baseFrame * rig.gunOffset * CFrame.fromAxisAngle(rig.pitchAxis, math.rad(pitchDegrees))
end

-- the camera sits at the CameraLocation and looks down the barrel
function PostRules.cameraFrame(gunFrame: CFrame, rig: Rig): CFrame
	local position = (gunFrame * rig.cameraOffset).Position
	return CFrame.lookAt(position, position + gunFrame:VectorToWorldSpace(rig.barrel))
end

function PostRules.muzzlePosition(gunFrame: CFrame, rig: Rig): Vector3
	return (gunFrame:PointToWorldSpace(rig.muzzleOffset))
end

function PostRules.barrelDirection(gunFrame: CFrame, rig: Rig): Vector3
	return (gunFrame:VectorToWorldSpace(rig.barrel))
end

function PostRules.characterFrame(baseFrame: CFrame, rig: Rig): CFrame
	return baseFrame * rig.characterOffset
end

-- reads a weapon model's parts into a Rig; nil (with the reason) when the
-- model is missing one of the parts the contract names
function PostRules.measureRig(model: Model): (Rig?, string?)
	local spawn = model.PrimaryPart
	if not spawn then
		return nil, "no PrimaryPart (the Spawn cylinder)"
	end
	local muzzle = model:FindFirstChild(Constants.POST_WEAPON_MUZZLE_ATTACHMENT, true)
	if not muzzle or not muzzle:IsA("Attachment") then
		return nil, `no {Constants.POST_WEAPON_MUZZLE_ATTACHMENT} attachment`
	end
	local gun = muzzle.Parent
	if not gun or not gun:IsA("BasePart") then
		return nil, `{Constants.POST_WEAPON_MUZZLE_ATTACHMENT} is not under a part`
	end
	local camera = model:FindFirstChild(Constants.POST_WEAPON_CAMERA_PART)
	if not camera or not camera:IsA("BasePart") then
		return nil, `no {Constants.POST_WEAPON_CAMERA_PART} part`
	end
	local characterSpawn = model:FindFirstChild(Constants.POST_WEAPON_CHARACTER_SPAWN_PART)
	if not characterSpawn or not characterSpawn:IsA("BasePart") then
		return nil, `no {Constants.POST_WEAPON_CHARACTER_SPAWN_PART} part`
	end
	-- the barrel is the gun's own axis the muzzle lies furthest along: an
	-- attachment sitting a little above or beside the bore must not skew
	-- the aim, so the direction snaps to that axis rather than pointing at
	-- the attachment itself
	local up = (gun.CFrame:VectorToObjectSpace(spawn.CFrame.XVector))
	local toMuzzle = muzzle.Position
	local barrel = PostRules.dominantAxis(toMuzzle - up * toMuzzle:Dot(up))
	if not barrel then
		return nil, `{Constants.POST_WEAPON_MUZZLE_ATTACHMENT} sits on the gun's centre`
	end
	return {
		gunOffset = spawn.CFrame:ToObjectSpace(gun.CFrame),
		cameraOffset = gun.CFrame:ToObjectSpace(camera.CFrame),
		muzzleOffset = toMuzzle,
		characterOffset = spawn.CFrame:ToObjectSpace(characterSpawn.CFrame),
		barrel = barrel,
		pitchAxis = barrel:Cross(up).Unit,
	}, nil
end

-- "MACHINE_GUN": the GameAssets/PostWeapons model for a kind
function PostRules.templateNameFor(kind: number): string
	return Enums.getName(Enums.PostWeaponKind, kind) or "?"
end

-- the loadout saves an unlock name; either the enum key or the public name
-- finds the kind, anything else is the default
function PostRules.resolveLoadoutPost(unlockName: string?, defaultKind: number): number
	if unlockName == nil or unlockName == "" then
		return defaultKind
	end
	for _, kind in Enums.getAllValues(Enums.PostWeaponKind) do
		if Enums.getName(Enums.PostWeaponKind, kind) == string.upper(unlockName) or Enums.getPublicName(Enums.PostWeaponKind, kind) == unlockName then
			return kind
		end
	end
	return defaultKind
end

-- "Post4" -> 4; nil for anything else
function PostRules.postIndexFromName(name: string): number?
	if name:sub(1, #Constants.POST_NAME_PREFIX) ~= Constants.POST_NAME_PREFIX then
		return nil
	end
	return tonumber(name:sub(#Constants.POST_NAME_PREFIX + 1))
end

-- JSON turns numeric keys into strings; the codec turns them back
local function encodeNumberKeys(map: { [number]: any }): { [string]: any }
	local encoded = {}
	for key, value in map do
		encoded[tostring(key)] = value
	end
	return encoded
end

local function decodeNumberKeys(map: any): { [number]: any }
	local decoded = {}
	if typeof(map) == "table" then
		for key, value in map do
			local numberKey = tonumber(key)
			if numberKey then
				decoded[numberKey] = value
			end
		end
	end
	return decoded
end

function PostRules.encodeCatalog(catalog: Catalog): string
	return HttpService:JSONEncode({
		claimPriceGold = catalog.claimPriceGold,
		upgradePriceByLevel = catalog.upgradePriceByLevel,
		requiredCampLevelByLevel = catalog.requiredCampLevelByLevel,
		bonusPerLevelByAttribute = encodeNumberKeys(catalog.bonusPerLevelByAttribute),
		kinds = encodeNumberKeys(catalog.kinds),
	})
end

-- nil for anything but a catalogue this module encoded
function PostRules.decodeCatalog(json: any): Catalog?
	if typeof(json) ~= "string" or json == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.claimPriceGold) ~= "number" then
		return nil
	end
	return {
		claimPriceGold = decoded.claimPriceGold,
		upgradePriceByLevel = decoded.upgradePriceByLevel or {},
		requiredCampLevelByLevel = decoded.requiredCampLevelByLevel or {},
		bonusPerLevelByAttribute = decodeNumberKeys(decoded.bonusPerLevelByAttribute),
		kinds = decodeNumberKeys(decoded.kinds),
	}
end

return PostRules
