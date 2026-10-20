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

-- a kind that fires a projectile rather than a ray: straight, or a lob
-- pulled down by GRAVITY_STUDS_PER_SEC2; IS_PIERCING flies on through
-- what it hits (the Saw Gun); HOMING bends it toward a locked target
export type ProjectileData = {
	TEMPLATE: string,
	BLAST_TEMPLATE: string?,
	SPEED_STUDS_PER_SEC: number,
	SPLASH_RADIUS_STUDS: number,
	GRAVITY_STUDS_PER_SEC2: number?,
	IS_PIERCING: boolean?,
	HOMING: { TURN_DEGREES_PER_SEC: number }?,
}

-- the class posts' blocks (2026-10-16); GameData/Posts/PostWeapons says
-- what each does
export type SpinUpData = { SEC: number }
export type ChargeData = { SEC: number }
export type PierceData = { COUNT: number, COUNT_PER_DAMAGE_LEVEL: number }
export type PoolData = { RADIUS_STUDS: number, SEC: number, BURN_DAMAGE_PER_SEC: number, BURN_SEC: number, TICK_SEC: number }
export type LockData = { SEC: number, ANGLE_DEGREES: number, COUNT: number, DUMB_FIRE_DAMAGE_SHARE: number }
export type MinesData = { MAX_ARMED: number, TRIGGER_RADIUS_STUDS: number, ARM_SEC: number }
export type ChainData = { COUNT: number, JUMP_STUDS: number }
export type SalvageData = { IRON_PER_KILL: number, CAP_PER_NIGHT: number }
export type PullData = { RADIUS_STUDS: number, SEC: number, SPEED_STUDS_PER_SEC: number }

-- a gun that overheats: full after FULL_SEC of fire, cool COOL_SEC later
export type HeatData = {
	FULL_SEC: number,
	COOL_SEC: number,
}

export type KindData = {
	-- scales a hitscan shot that lands in the head; the data's default when absent
	HEADSHOT_MULTIPLIER: number?,
	PROJECTILE: ProjectileData?,
	HEAT: HeatData?,
	SPIN_UP: SpinUpData?,
	CHARGE: ChargeData?,
	PIERCE: PierceData?,
	POOL: PoolData?,
	LOCK: LockData?,
	MINES: MinesData?,
	CHAIN: ChainData?,
	SALVAGE: SalvageData?,
	PULL: PullData?,
	IS_UNMANNED: boolean?,
	-- the Enums.PostAttribute values this kind offers, in menu order
	-- (decided 2026-09-29: the Machine Gun trades Range for Cooldown)
	UPGRADE_ATTRIBUTES: { number },
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

-- what the server publishes as GameMetadata: entry N of the price list is
-- the Iron price of upgrade N (Gold before M63); the list's length is the upgrade cap
export type Catalog = {
	claimPriceGold: number,
	upgradePriceByLevel: { number },
	-- the share of the base stat each upgrade adds, by Enums.PostAttribute
	bonusPerLevelByAttribute: { [number]: number },
	-- what a hit in the head does for a kind without its own HEADSHOT_MULTIPLIER
	headshotMultiplier: number,
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
	-- nil for a kind that does not overheat; shortened by Cooldown
	coolSec: number?,
	-- the class posts (2026-10-16): nil where the kind has no such block.
	-- Fire Rate shortens a charge but never a spin-up (2026-10-19), Damage
	-- adds pierces, Range lengthens a chain's jump and widens a pull
	spinUpSec: number?,
	chargeSec: number?,
	pierceCount: number?,
	-- what a hit in the head does (2026-10-19): the kind's own multiple or
	-- the catalogue's default, plus the Headshot bonus per level
	headshotMultiplier: number,
	chainJumpStuds: number?,
	pullRadiusStuds: number?,
	-- Damage widens the pool
	poolRadiusStuds: number?,
}

export type Offer = {
	status: number,
	-- the upgrade the buy would be, nil when maxed
	level: number?,
	price: number?,
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
	[Enums.PostAttribute.COOLDOWN] = Attributes.POST_UPGRADE_COOLDOWN,
	[Enums.PostAttribute.HEADSHOT] = Attributes.POST_UPGRADE_HEADSHOT,
}

PostRules.NO_POST = 0
PostRules.NOBODY = 0

-- a cool time never shrinks below this share of its base, whatever the levels
local MIN_COOL_SHARE = 0.05
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
		-- Cooldown takes the same share off every level (3 / 2.5 / 2 /
		-- 1.5 / 1 s), where a divide like Fire Rate's would give ever
		-- smaller steps for ever dearer rungs (decided 2026-09-29)
		coolSec = if data.HEAT then data.HEAT.COOL_SEC * math.max(1 - (bonuses[Enums.PostAttribute.COOLDOWN] or 0) * PostRules.upgradeLevel(upgrades, Enums.PostAttribute.COOLDOWN), MIN_COOL_SHARE) else nil,
		spinUpSec = if data.SPIN_UP then data.SPIN_UP.SEC else nil,
		chargeSec = if data.CHARGE then data.CHARGE.SEC / fireRateMultiplier else nil,
		pierceCount = if data.PIERCE then data.PIERCE.COUNT + data.PIERCE.COUNT_PER_DAMAGE_LEVEL * PostRules.upgradeLevel(upgrades, Enums.PostAttribute.DAMAGE) else nil,
		-- an added quarter per level (3x, 3.25x ... 4x), not a share of the
		-- base, so the step reads the same on every rung
		headshotMultiplier = (data.HEADSHOT_MULTIPLIER or catalog.headshotMultiplier) + (bonuses[Enums.PostAttribute.HEADSHOT] or 0) * PostRules.upgradeLevel(upgrades, Enums.PostAttribute.HEADSHOT),
		chainJumpStuds = if data.CHAIN then data.CHAIN.JUMP_STUDS * multiplierFor(Enums.PostAttribute.RANGE) else nil,
		pullRadiusStuds = if data.PULL then data.PULL.RADIUS_STUDS * multiplierFor(Enums.PostAttribute.RANGE) else nil,
		poolRadiusStuds = if data.POOL then data.POOL.RADIUS_STUDS * multiplierFor(Enums.PostAttribute.DAMAGE) else nil,
	}
end

-- a wind-up (a spin-up or a charge) is done once the trigger has been
-- held windupSec, less a tolerance for clock jitter
function PostRules.isWoundUp(triggerStartTime: number?, now: number, windupSec: number, toleranceSec: number): boolean
	return triggerStartTime ~= nil and now - triggerStartTime >= windupSec - toleranceSec
end

-- how far a wind-up has come, 0 to 1, for the status bar
function PostRules.windupProgress(triggerStartTime: number?, now: number, windupSec: number): number
	if triggerStartTime == nil or windupSec <= 0 then
		return 0
	end
	return math.clamp((now - triggerStartTime) / windupSec, 0, 1)
end

-- a charge shot's damage as a share of full: the square of the charge
-- reached (decided 2026-10-19), so a half charge does a quarter and a
-- snap shot a sliver. Proportional damage made a tap every half second
-- worth exactly a full four-second hold; the square makes holding pay
function PostRules.chargeDamageShare(chargeProgress: number): number
	local progress = math.clamp(chargeProgress, 0, 1)
	return progress * progress
end

-- how many bodies a charge shot goes through: one under half charge, one
-- short of the full count until full, the full count at full. The column
-- shot is the patient Sniper's
PostRules.CHARGE_PIERCE_HALF = 0.5
function PostRules.chargePierceCount(chargeProgress: number, fullCount: number): number
	if chargeProgress >= 1 then
		return fullCount
	end
	if chargeProgress >= PostRules.CHARGE_PIERCE_HALF then
		return math.max(1, fullCount - 1)
	end
	return 1
end

-- the angle in degrees between the barrel and the line to a point
function PostRules.angleToDegrees(muzzle: Vector3, unitDirection: Vector3, point: Vector3): number
	local offset = point - muzzle
	if offset.Magnitude < 1e-6 then
		return 0
	end
	return math.deg(math.acos(math.clamp(offset.Unit:Dot(unitDirection), -1, 1)))
end

-- the yaw and pitch that point the barrel at a world position from a
-- Spawn: the Spawn's X is up and its +Z faces out of the camp at yaw 0,
-- and baseFrame turns the base about X by -yaw, so the barrel at a yaw
-- lies along (sin yaw, cos yaw) in the Spawn's (Y, Z)
function PostRules.aimAnglesToward(spawnCFrame: CFrame, targetPosition: Vector3): (number, number)
	local localPosition = spawnCFrame:PointToObjectSpace(targetPosition)
	local flat = math.sqrt(localPosition.Y * localPosition.Y + localPosition.Z * localPosition.Z)
	local yaw = if flat > 1e-6 then math.deg(math.atan2(localPosition.Y, localPosition.Z)) else 0
	local pitch = math.deg(math.atan2(localPosition.X, flat))
	return PostRules.wrapDegrees(yaw), pitch
end

-- the pitch that points a barrel at a target from where the barrel is,
-- in world terms: up is positive. The unmanned post aims its pitch from
-- its muzzle, not its base (2026-10-19): the gun sits above the base and
-- the muzzle above the gun, so a pitch worked out from the base shot
-- over a near monster and never settled within the fire tolerance on one
-- below the post
function PostRules.pitchDegreesToward(origin: Vector3, targetPosition: Vector3): number
	local offset = targetPosition - origin
	local flat = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
	return math.deg(math.atan2(offset.Y, flat))
end

-- a yaw stepped toward a wanted yaw at the turn speed, the short way round
function PostRules.stepYawToward(yawDegrees: number, wantedYawDegrees: number, turnSpeedDegreesPerSec: number, deltaSec: number): number
	return PostRules.turnYaw(yawDegrees, PostRules.wrapDegrees(wantedYawDegrees - yawDegrees), turnSpeedDegreesPerSec, deltaSec)
end

-- where an attribute sits in a kind's upgrade menu, nil when the kind
-- does not offer it; a kind that lists nothing offers every attribute
function PostRules.attributeOrder(catalog: Catalog, kind: number, attribute: number): number?
	local data = catalog.kinds[kind]
	if not data then
		return nil
	end
	local attributes = data.UPGRADE_ATTRIBUTES
	if attributes == nil or #attributes == 0 then
		return attribute
	end
	return table.find(attributes, attribute)
end

function PostRules.kindHasAttribute(catalog: Catalog, kind: number, attribute: number): boolean
	return PostRules.attributeOrder(catalog, kind, attribute) ~= nil
end

-- what the next upgrade of one attribute would be for a player; mirrors
-- StoreRules.getOffer
function PostRules.getUpgradeOffer(catalog: Catalog, upgrades: Upgrades, attribute: number): Offer
	local nextLevel = PostRules.upgradeLevel(upgrades, attribute) + 1
	if nextLevel > PostRules.upgradeCap(catalog) then
		return {
			status = Enums.StoreOffer.MAXED,
			level = nil,
			price = nil,
		}
	end
	return {
		status = Enums.StoreOffer.AVAILABLE,
		level = nextLevel,
		price = catalog.upgradePriceByLevel[nextLevel],
	}
end

function PostRules.canAfford(balance: number, price: number): boolean
	return balance >= price
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
-- interval (plus a little slack), so holding the trigger never cools. The
-- slack has a floor in seconds (2026-10-19): shots are sent once a frame
-- at most, so a fast gun's shots arrive a frame or two late on a slow
-- machine, and a slack of 1.5 intervals (0.09 s for the Minigun) read
-- every such gap as a rest, cooling the gun between its own shots
PostRules.HEAT_REST_SLACK = 1.5
PostRules.HEAT_REST_MIN_SEC = 0.25
local HEAT_FULL_TOLERANCE = 1e-6

-- how long the trigger may go between shots and still count as held
function PostRules.heatRestSlackSec(fireIntervalSec: number): number
	return math.max(fireIntervalSec * PostRules.HEAT_REST_SLACK, PostRules.HEAT_REST_MIN_SEC)
end

-- the heat one shot adds: the time the trigger has been held since the
-- last shot, so FULL_SEC of holding reaches 1 whatever the frame rate
-- delivers; a shot with no held time behind it (the first, or one after a
-- rest) adds one interval's worth, which is what FULL_SEC / interval
-- shots at the interval add up to
function PostRules.heatPerShot(heat: HeatData, fireIntervalSec: number, elapsedSec: number?): number
	local heldSec = fireIntervalSec
	if elapsedSec ~= nil and elapsedSec <= PostRules.heatRestSlackSec(fireIntervalSec) then
		heldSec = elapsedSec
	end
	return heldSec / heat.FULL_SEC
end

-- the heat now, cooled for the time the trigger has rested since the last
-- shot; coolSec is the upgraded time from full to cool (Stats.coolSec)
function PostRules.cooledHeat(heatAtLastShot: number, lastShotTime: number?, now: number, fireIntervalSec: number, coolSec: number): number
	if lastShotTime == nil then
		return 0
	end
	local restingSec = now - lastShotTime - PostRules.heatRestSlackSec(fireIntervalSec)
	if restingSec <= 0 then
		return heatAtLastShot
	end
	return math.max(0, heatAtLastShot - restingSec / math.max(coolSec, 1e-6))
end

-- what a shot does to the heat: the new heat, whether the gun just
-- overheated, and whether it may fire at all (an overheated gun waits for 0);
-- elapsedSec is the time since the last shot, nil for the first
function PostRules.heatAfterShot(currentHeat: number, isOverheated: boolean, heat: HeatData, fireIntervalSec: number, elapsedSec: number?): (boolean, number, boolean)
	if isOverheated and currentHeat > 0 then
		return false, currentHeat, true
	end
	local newHeat = currentHeat + PostRules.heatPerShot(heat, fireIntervalSec, elapsedSec)
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
		bonusPerLevelByAttribute = encodeNumberKeys(catalog.bonusPerLevelByAttribute),
		headshotMultiplier = catalog.headshotMultiplier,
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
		bonusPerLevelByAttribute = decodeNumberKeys(decoded.bonusPerLevelByAttribute),
		headshotMultiplier = decoded.headshotMultiplier or 1,
		kinds = decodeNumberKeys(decoded.kinds),
	}
end

return PostRules
