--!strict

-- Every projectile in the air as this client draws it (2026-10-16; the
-- Rocket Launcher's rocket drawing of M25 moved here from
-- ClientPostManager). NotifyProjectileLaunched carries the launch (the
-- origin, direction, speed, gravity, a homing target) and this client
-- flies a client-only clone of the GameAssets/Projectiles part with the
-- same maths the server uses (ProjectileRules), with the trail authored
-- under its TailAttachment and the kind's 3D flight loop; a homing one
-- bends toward its target's drawn body. NotifyProjectileEnded says where
-- it stopped: the part goes, the kind's blast and burst sound play there
-- when it bursts, and the owner hears the hit confirm when it hurt
-- something. The server's projectile is the truth; this one only shows it.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local ProjectileRules = require("@game/ReplicatedStorage/Shared/ProjectileRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)

local ClientProjectileManager = {}
ClientProjectileManager.__index = ClientProjectileManager

type ProjectileView = {
	id: string,
	part: BasePart,
	flight: ProjectileRules.Flight,
	elapsedSec: number,
	position: Vector3,
	unitDirection: Vector3,
	homingTargetId: string?,
	homingTurnDegreesPerSec: number,
	-- a piercing projectile (a saw blade) spins about its heading
	isSpinning: boolean,
	spinRadians: number,
	tailOffset: Vector3,
}

export type ClientProjectileManager = typeof(setmetatable(
	{} :: {
		viewsById: { [string]: ProjectileView },
		warnedTemplates: { [string]: boolean },
	},
	ClientProjectileManager
))

local FIRE_SOUND_FULL_VOLUME_STUDS = 40
local EFFECT_RANGE_STUDS = 500
-- a burst up to a post's full range away is drawn and heard much further
-- than a gunshot: full volume near, tapering to silence past the far side
-- of the camp (decided 2026-09-18)
local BLAST_FULL_VOLUME_STUDS = 200
local BLAST_SILENT_STUDS = 800
local BLAST_SMOKE_LIFETIME_SEC = 2.5
local BLAST_SMOKE_COUNT = 40
local BLAST_FLASH_SEC = 0.15
-- a projectile that never hears its end (a lost message) is dropped after this
local MAX_LIFETIME_SEC = 12
local SPIN_RADIANS_PER_SEC = 24
-- the stand-in for a projectile with no part under GameAssets/Projectiles yet
local PLACEHOLDER_SIZE = Vector3.new(0.8, 0.8, 1.6)
local PLACEHOLDER_COLOR = Color3.fromRGB(230, 200, 90)

local NOTIFY_PROJECTILE_LAUNCHED_SHAPE = {
	projectileId = "string",
	userId = "integer",
	postWeaponKind = "nonnegativeInteger",
	weaponKind = "nonnegativeInteger",
	template = "string",
	blastTemplate = "string",
	origin = "vector3",
	direction = "vector3",
	speed = "positiveNumber",
	gravity = "nonnegativeNumber",
	homingTargetId = "string",
	homingTurn = "nonnegativeNumber",
	isPiercing = "boolean",
}
local NOTIFY_PROJECTILE_ENDED_SHAPE = {
	projectileId = "string",
	userId = "integer",
	postWeaponKind = "nonnegativeInteger",
	weaponKind = "nonnegativeInteger",
	position = "vector3",
	isBurst = "boolean",
	hitCount = "nonnegativeInteger",
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

-- the launcher's sounds: a post kind's set, or a weapon's secondary
function ClientProjectileManager:getSounds(postWeaponKind: number, weaponKind: number): (string?, string?, string?)
	if postWeaponKind ~= 0 and Enums.isValidValue(Enums.PostWeaponKind, postWeaponKind) then
		local set = SoundNames.PostWeaponSfxByKindName[Enums.getName(Enums.PostWeaponKind, postWeaponKind) :: string]
		if set then
			return set.FLIGHT, set.EXPLODE, set.HIT
		end
	end
	if weaponKind ~= 0 and Enums.isValidValue(Enums.WeaponKind, weaponKind) then
		local set = SoundNames.WeaponSfxByKindName[Enums.getName(Enums.WeaponKind, weaponKind) :: string]
		if set then
			return nil, set.SECONDARY_EXPLODE, set.HIT
		end
	end
	return nil, nil, nil
end

function ClientProjectileManager:findTemplate(templateName: string): BasePart?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("BasePart") then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`ClientProjectileManager: no part named {templateName} under GameAssets.{Constants.PROJECTILE_TEMPLATES_FOLDER}; a placeholder flies instead`)
	end
	return nil
end

-- a stand-in part until the designer's model lands: its nose is -Z, so
-- its tail attachment sits at +Z like a rocket's
function ClientProjectileManager:makePlaceholder(): BasePart
	local part = Instance.new("Part")
	part.Name = "ProjectilePlaceholder"
	part.Size = PLACEHOLDER_SIZE
	part.Color = PLACEHOLDER_COLOR
	part.Material = Enum.Material.Neon
	local tail = Instance.new("Attachment")
	tail.Name = Constants.PROJECTILE_TAIL_ATTACHMENT
	tail.Position = Vector3.new(0, 0, PLACEHOLDER_SIZE.Z / 2)
	tail.Parent = part
	return part
end

-- the flight loop rides the projectile: an AudioEmitter on the part, fed
-- by a copy of the authored player, kept alive for the flight
function ClientProjectileManager:attachFlightSound(part: BasePart, name: string?)
	if name then
		ClientSoundManager:attachLoop(part, name, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
end

-- the smoke trail streams from the TailAttachment in flight. The designer
-- authors it on the template (any ParticleEmitter or light under the
-- attachment is used as is); this placeholder is only built when the
-- attachment carries nothing
function ClientProjectileManager:attachTrail(tail: Attachment)
	local hasAuthoredTrail = false
	for _, child in tail:GetChildren() do
		if child:IsA("ParticleEmitter") then
			child.Enabled = true
			hasAuthoredTrail = true
		end
	end
	if hasAuthoredTrail then
		return
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Trail"
	smoke.Color = ColorSequence.new(Color3.fromRGB(220, 215, 205), Color3.fromRGB(110, 105, 100))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Rate = 60
	smoke.LightEmission = 0.1
	smoke.Parent = tail
	local flame = Instance.new("PointLight")
	flame.Name = "Flame"
	flame.Brightness = 3
	flame.Range = 12
	flame.Color = Color3.fromRGB(255, 170, 90)
	flame.Parent = tail
end

function ClientProjectileManager:onLaunched(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_PROJECTILE_LAUNCHED_SHAPE) then
		warn("ClientProjectileManager: malformed NotifyProjectileLaunched")
		return
	end
	local template = self:findTemplate(payload.template)
	local part = if template then template:Clone() else self:makePlaceholder()
	part.Name = payload.projectileId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local tail = part:FindFirstChild(Constants.PROJECTILE_TAIL_ATTACHMENT)
	local tailOffset = if tail and tail:IsA("Attachment") then tail.Position else Vector3.zero
	local direction: Vector3 = payload.direction
	local unitDirection = if direction.Magnitude > 0.001 then direction.Unit else Vector3.zAxis
	part.CFrame = PostRules.projectileFrame(payload.origin, unitDirection, tailOffset)
	if tail and tail:IsA("Attachment") then
		self:attachTrail(tail)
	end
	part.Parent = workspace
	local flightSound = self:getSounds(payload.postWeaponKind, payload.weaponKind)
	self:attachFlightSound(part, flightSound)
	-- a template's launch sound for the crewmates; the shooter's own client
	-- already played it when it fired
	local launchSound = SoundNames.ProjectileLaunchSfxByTemplate[payload.template]
	if launchSound and payload.userId ~= Players.LocalPlayer.UserId then
		ClientSoundManager:playSfxAt(payload.origin, launchSound, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
	self.viewsById[payload.projectileId] = {
		id = payload.projectileId,
		part = part,
		flight = {
			origin = payload.origin,
			unitDirection = unitDirection,
			speedStudsPerSec = payload.speed,
			gravityStudsPerSec2 = payload.gravity,
		},
		elapsedSec = 0,
		position = payload.origin,
		unitDirection = unitDirection,
		homingTargetId = if payload.homingTargetId ~= "" then payload.homingTargetId else nil,
		homingTurnDegreesPerSec = payload.homingTurn,
		isSpinning = payload.isPiercing,
		spinRadians = 0,
		tailOffset = tailOffset,
	}
	Debris:AddItem(part, MAX_LIFETIME_SEC)
end

-- the authored blast: the template's part at the point, every emitter
-- fired once for its BurstCount, every light on for the flash. Nil when
-- there is no template, and the placeholder below is used instead
function ClientProjectileManager:playAuthoredBlast(position: Vector3, templateName: string): boolean
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if not template or not template:IsA("BasePart") then
		return false
	end
	local part = template:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	local longestLifeSec = BLAST_FLASH_SEC
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			descendant:Emit(readNumber(descendant:GetAttribute(Attributes.BURST_COUNT), BLAST_SMOKE_COUNT))
			longestLifeSec = math.max(longestLifeSec, descendant.Lifetime.Max)
		elseif descendant:IsA("Light") then
			descendant.Enabled = true
			Debris:AddItem(descendant, BLAST_FLASH_SEC)
		end
	end
	Debris:AddItem(part, longestLifeSec + 0.2)
	return true
end

-- the blast at the burst point: the authored effect when there is one,
-- else a ball of smoke and a flash
function ClientProjectileManager:playBlast(position: Vector3, blastTemplate: string)
	if blastTemplate ~= "" and self:playAuthoredBlast(position, blastTemplate) then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "ProjectileBlast"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(200, 60, 20))
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 8),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.Speed = NumberRange.new(10, 25)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.LightEmission = 1
	fire.Rate = 0
	fire.Parent = anchor
	fire:Emit(BLAST_SMOKE_COUNT)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(40, 38, 36))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 10),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.2, BLAST_SMOKE_LIFETIME_SEC)
	smoke.Speed = NumberRange.new(6, 16)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(BLAST_SMOKE_COUNT)
	local flash = Instance.new("PointLight")
	flash.Brightness = 10
	flash.Range = 40
	flash.Color = Color3.fromRGB(255, 190, 110)
	flash.Parent = anchor
	Debris:AddItem(flash, BLAST_FLASH_SEC)
	Debris:AddItem(anchor, BLAST_SMOKE_LIFETIME_SEC + 0.2)
end

function ClientProjectileManager:onEnded(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_PROJECTILE_ENDED_SHAPE) then
		warn("ClientProjectileManager: malformed NotifyProjectileEnded")
		return
	end
	local view = self.viewsById[payload.projectileId]
	local blastTemplate = ""
	if view then
		self.viewsById[payload.projectileId] = nil
		blastTemplate = (view.part:GetAttribute(Attributes.BLAST_TEMPLATE) :: string?) or ""
		view.part:Destroy()
	end
	local _flightSound, explodeSound, hitSound = self:getSounds(payload.postWeaponKind, payload.weaponKind)
	local camera = workspace.CurrentCamera
	if payload.isBurst and camera and (camera.CFrame.Position - payload.position).Magnitude <= BLAST_SILENT_STUDS then
		if explodeSound then
			ClientSoundManager:playSfxAt(payload.position, explodeSound, BLAST_FULL_VOLUME_STUDS, BLAST_SILENT_STUDS)
		end
		self:playBlast(payload.position, blastTemplate)
	end
	if payload.userId == Players.LocalPlayer.UserId and payload.hitCount > 0 and hitSound then
		ClientSoundManager:playSfx(hitSound)
	end
end

-- one frame of flight for every projectile, the server's maths: a homing
-- one turns toward its target's drawn body, the rest follow the launch
function ClientProjectileManager:step(deltaTime: number)
	for id, view in self.viewsById do
		if not view.part.Parent then
			self.viewsById[id] = nil
			continue
		end
		local targetId = view.homingTargetId
		if targetId then
			local targetPosition = ClientDamageableManager:getBodyPosition(targetId)
			if targetPosition then
				view.unitDirection = ProjectileRules.turnToward(view.unitDirection, view.position, targetPosition, view.homingTurnDegreesPerSec * deltaTime)
			end
			view.position += view.unitDirection * view.flight.speedStudsPerSec * deltaTime
		else
			view.elapsedSec += deltaTime
			view.position = ProjectileRules.positionAt(view.flight, view.elapsedSec)
			view.unitDirection = ProjectileRules.headingAt(view.flight, view.elapsedSec)
		end
		local frame = PostRules.projectileFrame(view.position, view.unitDirection, view.tailOffset)
		if view.isSpinning then
			view.spinRadians += SPIN_RADIANS_PER_SEC * deltaTime
			frame = frame * CFrame.Angles(0, 0, view.spinRadians)
		end
		view.part.CFrame = frame
	end
end

function ClientProjectileManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PROJECTILE_LAUNCHED,
		function(payload: any)
			-- the blast template rides the part so the end knows it
			self:onLaunched(payload)
			local view = self.viewsById[payload.projectileId]
			if view and typeof(payload.blastTemplate) == "string" then
				view.part:SetAttribute(Attributes.BLAST_TEMPLATE, payload.blastTemplate)
			end
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PROJECTILE_ENDED,
		function(payload: any)
			self:onEnded(payload)
		end
	)
	RunService.RenderStepped:Connect(
		function(deltaTime: number)
			self:step(deltaTime)
		end
	)
end

function ClientProjectileManager.new(): ClientProjectileManager
	local self = setmetatable({}, ClientProjectileManager) :: ClientProjectileManager
	self.viewsById = {}
	self.warnedTemplates = {}
	return self
end

return ClientProjectileManager.new()
