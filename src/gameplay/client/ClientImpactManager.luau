--!strict

-- What a bullet leaves where it lands (M24), on this client only: a small
-- dust puff out of the surface and a bullet hole decal that fades away
-- after a few seconds. Both come from pools built once and reused in turn,
-- so sustained fire from a full crew never creates or destroys instances:
-- the oldest hole is simply moved to the newest hit. The hole's look is the
-- designer's Decal at GameAssets/Effects/BulletHole (texture, tint,
-- transparency are read from it); without it there are no holes, only dust.
-- A hole is a thin invisible part carrying the decal, laid flat on the
-- surface. Things that move or vanish get dust but no hole, since a hole
-- would be left hanging in the air: damageable targets and players. A hole
-- also watches the part it sits on and goes the moment that part moves or
-- leaves the world (a mined rock, a swinging gate door, an upgraded wall).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local ClientImpactManager = {}
ClientImpactManager.__index = ClientImpactManager

type Hole = {
	part: Part,
	decal: Decal,
	-- the latest use of this slot, so an earlier hit's timers leave a reused
	-- hole alone
	token: number,
	fade: Tween?,
	-- watching the surface the hole sits on
	connections: { RBXScriptConnection },
}

export type ClientImpactManager = typeof(setmetatable(
	{} :: {
		dustEmitters: { ParticleEmitter },
		nextDustIndex: number,
		holes: { Hole },
		nextHoleIndex: number,
		holeTransparency: number,
		folder: Folder?,
		random: Random,
	},
	ClientImpactManager
))

local FOLDER_NAME = "WeaponImpacts"
local DUST_POOL_SIZE = 8
local DUST_PARTICLE_COUNT = 6
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local DUST_COLOR = Color3.fromRGB(190, 175, 150)
-- six players emptying magazines for the whole lifetime stay under this
local HOLE_POOL_SIZE = 64
local HOLE_LIFETIME_SEC = 10
-- the last of the lifetime is spent fading, so holes never pop out
local HOLE_FADE_SEC = 1
local HOLE_SIZE_STUDS = 0.6
local HOLE_THICKNESS_STUDS = 0.05
-- lifted off the surface so the decal never z-fights with it
local HOLE_LIFT_STUDS = 0.02

function ClientImpactManager:getFolder(): Folder
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

function ClientImpactManager:findHoleTemplate(): Decal?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local effects = if gameAssets then gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER) else nil
	local template = if effects then effects:FindFirstChild(Constants.BULLET_HOLE_DECAL) else nil
	if template and template:IsA("Decal") then
		return template
	end
	warn(`ClientImpactManager: no Decal GameAssets.{Constants.EFFECT_TEMPLATES_FOLDER}.{Constants.BULLET_HOLE_DECAL}; shots will leave no bullet holes`)
	return nil
end

function ClientImpactManager:buildDustPool()
	for _ = 1, DUST_POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "ImpactDust"
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Texture = DUST_TEXTURE
		emitter.Color = ColorSequence.new(DUST_COLOR)
		emitter.LightEmission = 0
		emitter.Lifetime = NumberRange.new(0.3, 0.55)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Drag = 4
		emitter.Acceleration = Vector3.new(0, -3, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1.1),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		-- particles leave along the attachment's front, which is pointed
		-- out of the surface
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Parent = attachment
		attachment.Parent = workspace.Terrain
		table.insert(self.dustEmitters, emitter)
	end
end

function ClientImpactManager:buildHolePool()
	local template = self:findHoleTemplate()
	if not template then
		return
	end
	self.holeTransparency = template.Transparency
	for index = 1, HOLE_POOL_SIZE do
		local part = Instance.new("Part")
		part.Name = "BulletHole" .. index
		part.Size = Vector3.new(HOLE_SIZE_STUDS, HOLE_SIZE_STUDS, HOLE_THICKNESS_STUDS)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local decal = template:Clone()
		-- the part's front is laid against the surface, facing out of it
		decal.Face = Enum.NormalId.Front
		decal.Parent = part
		table.insert(self.holes, {
			part = part,
			decal = decal,
			token = 0,
			fade = nil,
			connections = {},
		})
	end
end

-- lookAt has no answer when the target is straight along its up vector,
-- which is every shot into a floor or a ceiling
function ClientImpactManager:surfaceCFrame(position: Vector3, normal: Vector3): CFrame
	local up = if math.abs(normal.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + normal, up)
end

function ClientImpactManager:playDust(position: Vector3, normal: Vector3)
	if #self.dustEmitters == 0 then
		return
	end
	self.nextDustIndex = self.nextDustIndex % #self.dustEmitters + 1
	local emitter = self.dustEmitters[self.nextDustIndex]
	local attachment = emitter.Parent
	if not attachment or not attachment:IsA("Attachment") then
		return
	end
	attachment.WorldCFrame = self:surfaceCFrame(position, normal)
	emitter:Emit(DUST_PARTICLE_COUNT)
end

-- a hole on something that moves or vanishes would be left in mid air
function ClientImpactManager:canHoldHole(surface: Instance?): boolean
	if not surface then
		return false
	end
	local damageableBodies = workspace:FindFirstChild(Constants.DAMAGEABLE_BODIES_FOLDER)
	if damageableBodies and surface:IsDescendantOf(damageableBodies) then
		return false
	end
	for _, player in Players:GetPlayers() do
		if player.Character and surface:IsDescendantOf(player.Character) then
			return false
		end
	end
	return true
end

-- takes a hole out of the world and frees its slot's timers and watchers
function ClientImpactManager:releaseHole(hole: Hole)
	hole.token += 1
	if hole.fade then
		hole.fade:Cancel()
		hole.fade = nil
	end
	for _, connection in hole.connections do
		connection:Disconnect()
	end
	table.clear(hole.connections)
	hole.part.Parent = nil
end

function ClientImpactManager:placeHole(position: Vector3, normal: Vector3, surface: Instance)
	if #self.holes == 0 then
		return
	end
	self.nextHoleIndex = self.nextHoleIndex % #self.holes + 1
	local hole = self.holes[self.nextHoleIndex]
	self:releaseHole(hole)
	local token = hole.token
	local function releaseIfCurrent()
		if hole.token == token then
			self:releaseHole(hole)
		end
	end
	table.insert(hole.connections, surface.AncestryChanged:Connect(releaseIfCurrent))
	if surface:IsA("BasePart") then
		table.insert(hole.connections, surface:GetPropertyChangedSignal("CFrame"):Connect(releaseIfCurrent))
	end
	hole.decal.Transparency = self.holeTransparency
	-- a random turn about the normal, so a wall of holes is not a stamp
	local turn = CFrame.Angles(0, 0, self.random:NextNumber(0, math.pi * 2))
	hole.part.CFrame = self:surfaceCFrame(position + normal * (HOLE_LIFT_STUDS + HOLE_THICKNESS_STUDS / 2), normal) * turn
	hole.part.Parent = self:getFolder()
	task.delay(
		HOLE_LIFETIME_SEC - HOLE_FADE_SEC,
		function()
			if hole.token ~= token then
				return
			end
			local fade = TweenService:Create(hole.decal, TweenInfo.new(HOLE_FADE_SEC), { Transparency = 1 })
			hole.fade = fade
			fade:Play()
		end
	)
	task.delay(HOLE_LIFETIME_SEC, releaseIfCurrent)
end

-- surface is what was hit, when this client knows; nil leaves only dust
function ClientImpactManager:play(position: Vector3, normal: Vector3, surface: Instance?)
	self:playDust(position, normal)
	if surface and self:canHoldHole(surface) then
		self:placeHole(position, normal, surface)
	end
end

function ClientImpactManager:init()
	self:buildDustPool()
	self:buildHolePool()
end

function ClientImpactManager.new(): ClientImpactManager
	local self = setmetatable({}, ClientImpactManager) :: ClientImpactManager
	self.dustEmitters = {}
	self.nextDustIndex = 0
	self.holes = {}
	self.nextHoleIndex = 0
	self.holeTransparency = 0
	self.folder = nil
	self.random = Random.new()
	return self
end

return ClientImpactManager.new()
