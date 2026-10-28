--!strict

-- Every helicopter's visuals, on every client, in both places: models tagged
-- Tags.HELICOPTER carry a HelicopterPhase attribute set by the server
-- (HelicopterManager). SPINNING turns the rotors (the main one about the
-- model's up, the tail's BackBlades about the model's right), IDLE winds
-- them down, APPROACHING flies the helicopter in onto its pad and FLYING
-- flies it away (M75): both are pure HelicopterFlightRules poses sampled
-- against the server time the flight began, the pad's CFrame, and the
-- heading (the way out, which the approach also comes in along), all
-- attributes on the model, with the flight config from GameMetadata,
-- so every client draws the same flight and a late viewer joins it
-- mid-air. The server never animates; a Heartbeat loop rather than tweens
-- because the rotor ramps and the flights chain. The rotor loop (the
-- AudioPlayer HelicopterManager attaches silent to the model) plays from
-- the first turn of the rotor until it is still again or the model is
-- gone; this client's own rotor speed is the truth, so the sound and the
-- blades always agree (decided 2026-09-16). The template's Searchlight is
-- lit on the way in; touchdown kicks the pad's Dust and plays its sound,
-- and lift-off plays its own.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local HelicopterFlightRules = require("@game/ReplicatedStorage/Shared/HelicopterFlightRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.ClientDataManager)
local ClientSoundManager = require(script.Parent.ClientSoundManager)

local ClientHelicopterManager = {}
ClientHelicopterManager.__index = ClientHelicopterManager

type Craft = {
	model: Model,
	rotor: BasePart?,
	-- the model's pivot at rest and the rotor hub relative to it, so neither
	-- the spin nor the flight drifts; an approach's rest is the pad it lands on
	restPivot: CFrame,
	rotorOffset: CFrame?,
	tailRotor: BasePart?,
	tailRotorOffset: CFrame?,
	angle: number,
	-- rotor radians per second, ramped toward the target
	speed: number,
	-- the rotor loop, resolved lazily like the rotor; playing iff speed > 0
	sound: AudioPlayer?,
	isSoundPlaying: boolean,
	-- the phase drawn last frame, so a change is seen once
	lastPhase: number,
	-- the flight start a client assumes when the attribute has not arrived
	assumedFlightStartTime: number?,
	searchlight: Light?,
	isSearchlightOn: boolean,
}

export type ClientHelicopterManager = typeof(setmetatable(
	{} :: {
		crafts: { Craft },
		config: HelicopterFlightRules.Config,
	},
	ClientHelicopterManager
))

-- doubled from 25 (designer, 2026-10-27)
local FULL_SPEED_RAD_PER_SEC = 50
local SPIN_UP_SEC = 3
local SPIN_DOWN_SEC = 4
-- the tail rotor turns this many times faster than the main one
local TAIL_ROTOR_SPEED_MULTIPLE = 2
-- how far the touchdown and the lift-off carry
local FLIGHT_SFX_FULL_VOLUME_STUDS = 60
local FLIGHT_SFX_SILENT_STUDS = 450
local DUST_PARTICLE_COUNT = 60

local function findRotor(model: Model): BasePart?
	local rotorModel = model:FindFirstChild(Constants.HELICOPTER_ROTOR_MODEL)
	local rotorChild = if rotorModel then rotorModel:FindFirstChild(Constants.HELICOPTER_ROTOR_PART) else nil
	if rotorChild and rotorChild:IsA("BasePart") then
		return rotorChild
	end
	return nil
end

local function findTailRotor(model: Model): BasePart?
	local part = model:FindFirstChild(Constants.HELICOPTER_TAIL_ROTOR_PART)
	return if part and part:IsA("BasePart") then part else nil
end

-- the rotor is resolved lazily: a freshly cloned model can be seen before its
-- children have replicated, and streaming can replace the part with a new
-- instance at any time. A newly found rotor sits at its server CFrame, so
-- the offset is taken against the model's current pivot (the rest pivot on
-- the ground; the server's own placement in the air, which is the start)
local function resolveRotorIfNeeded(craft: Craft)
	local rotor = craft.rotor
	if rotor and rotor.Parent ~= nil then
		return
	end
	rotor = findRotor(craft.model)
	craft.rotor = rotor
	craft.rotorOffset = if rotor then craft.model:GetPivot():ToObjectSpace(rotor.CFrame) else nil
end

-- the tail rotor the same way; a template without one is fine
local function resolveTailRotorIfNeeded(craft: Craft)
	local tailRotor = craft.tailRotor
	if tailRotor and tailRotor.Parent ~= nil then
		return
	end
	tailRotor = findTailRotor(craft.model)
	craft.tailRotor = tailRotor
	craft.tailRotorOffset = if tailRotor then craft.model:GetPivot():ToObjectSpace(tailRotor.CFrame) else nil
end

local function resolveSoundIfNeeded(craft: Craft)
	local sound = craft.sound
	if sound and sound.Parent ~= nil then
		return
	end
	local found = craft.model:FindFirstChild(SoundNames.Sfx.HELICOPTER, true)
	craft.sound = if found and found:IsA("AudioPlayer") then found else nil
	craft.isSoundPlaying = false
end

local function resolveSearchlightIfNeeded(craft: Craft)
	local light = craft.searchlight
	if light and light.Parent ~= nil then
		return
	end
	local found = craft.model:FindFirstChild(Constants.HELICOPTER_SEARCHLIGHT, true)
	craft.searchlight = if found and found:IsA("Light") then found else nil
	craft.isSearchlightOn = false
end

local function getPhase(craft: Craft): number
	local phase = craft.model:GetAttribute(Attributes.HELICOPTER_PHASE)
	return if typeof(phase) == "number" then phase else Enums.HelicopterPhase.IDLE
end

local function isAirborne(phase: number): boolean
	return phase == Enums.HelicopterPhase.APPROACHING or phase == Enums.HelicopterPhase.FLYING
end

local function makeCraft(model: Model): Craft
	local pivot = model:GetPivot()
	local phase = model:GetAttribute(Attributes.HELICOPTER_PHASE)
	local isInAir = typeof(phase) == "number" and isAirborne(phase)
	return {
		model = model,
		rotor = nil,
		restPivot = pivot,
		rotorOffset = nil,
		tailRotor = nil,
		tailRotorOffset = nil,
		angle = 0,
		-- one first seen in the air has its rotor at full speed already
		speed = if isInAir then FULL_SPEED_RAD_PER_SEC else 0,
		sound = nil,
		isSoundPlaying = false,
		lastPhase = if typeof(phase) == "number" then phase else Enums.HelicopterPhase.IDLE,
		assumedFlightStartTime = nil,
		searchlight = nil,
		isSearchlightOn = false,
	}
end

function ClientHelicopterManager:stepRotor(craft: Craft, isSpinning: boolean, deltaSec: number)
	local targetSpeed = if isSpinning then FULL_SPEED_RAD_PER_SEC else 0
	local rampSec = if targetSpeed > craft.speed then SPIN_UP_SEC else SPIN_DOWN_SEC
	local maxChange = FULL_SPEED_RAD_PER_SEC / rampSec * deltaSec
	craft.speed += math.clamp(targetSpeed - craft.speed, -maxChange, maxChange)
	craft.angle = (craft.angle + craft.speed * deltaSec) % (2 * math.pi)
	self:syncSound(craft)
end

-- the loop follows the blades: on with the first turn, off once they stop
function ClientHelicopterManager:syncSound(craft: Craft)
	resolveSoundIfNeeded(craft)
	local sound = craft.sound
	if not sound then
		return
	end
	local shouldPlay = craft.speed > 0
	if shouldPlay == craft.isSoundPlaying then
		return
	end
	craft.isSoundPlaying = shouldPlay
	if shouldPlay then
		sound:Play()
	else
		sound:Stop()
	end
end

function ClientHelicopterManager:syncSearchlight(craft: Craft, isOn: boolean)
	resolveSearchlightIfNeeded(craft)
	local light = craft.searchlight
	if not light or craft.isSearchlightOn == isOn then
		return
	end
	craft.isSearchlightOn = isOn
	light.Enabled = isOn
end

-- the server time a flight began: the attribute, else the moment this
-- client first saw it in the air (a late-replicated attribute corrects it)
function ClientHelicopterManager:getFlightStartTime(craft: Craft): number
	local startTime = craft.model:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME)
	if typeof(startTime) == "number" then
		return startTime
	end
	local assumed = craft.assumedFlightStartTime
	if assumed then
		return assumed
	end
	local now = workspace:GetServerTimeNow()
	craft.assumedFlightStartTime = now
	return now
end

function ClientHelicopterManager:getPadCFrame(craft: Craft): CFrame
	local padCFrame = craft.model:GetAttribute(Attributes.HELICOPTER_PAD_CFRAME)
	return if typeof(padCFrame) == "CFrame" then padCFrame else craft.restPivot
end

function ClientHelicopterManager:getHeading(craft: Craft): Vector3
	local heading = craft.model:GetAttribute(Attributes.HELICOPTER_HEADING)
	return if typeof(heading) == "Vector3" then heading else craft.restPivot.LookVector
end

function ClientHelicopterManager:render(craft: Craft, pivot: CFrame, isMoving: boolean)
	if isMoving then
		craft.model:PivotTo(pivot)
	end
	resolveRotorIfNeeded(craft)
	local rotor = craft.rotor
	local rotorOffset = craft.rotorOffset
	if rotor and rotorOffset and craft.speed > 0 then
		-- spin about the hub's own up around its own position, so the part's
		-- local axes (which the designer may orient any way) never tilt the spin
		local rotorRest = pivot * rotorOffset
		rotor.CFrame = CFrame.new(rotorRest.Position) * CFrame.fromAxisAngle(pivot.UpVector, craft.angle) * rotorRest.Rotation
	end
	resolveTailRotorIfNeeded(craft)
	local tailRotor = craft.tailRotor
	local tailRotorOffset = craft.tailRotorOffset
	if tailRotor and tailRotorOffset and craft.speed > 0 then
		-- the tail rotor spins about the model's X axis (designer, 2026-10-27)
		local tailRest = pivot * tailRotorOffset
		tailRotor.CFrame = CFrame.new(tailRest.Position) * CFrame.fromAxisAngle(pivot.RightVector, craft.angle * TAIL_ROTOR_SPEED_MULTIPLE) * tailRest.Rotation
	end
end

-- the pad's Dust emitter, if the map has one, kicked on touchdown
function ClientHelicopterManager:emitDust(craft: Craft)
	local pad = craft.model.Parent
	local dustPart = if pad then pad:FindFirstChild(Constants.PAD_DUST_PART) else nil
	local emitter = if dustPart then dustPart:FindFirstChildWhichIsA("ParticleEmitter", true) else nil
	if emitter then
		emitter:Emit(DUST_PARTICLE_COUNT)
	end
end

-- a phase change seen once: the end of an approach is the touchdown, and
-- the first FLYING frame is the lift-off
function ClientHelicopterManager:onPhaseChanged(craft: Craft, phase: number)
	local wasApproaching = craft.lastPhase == Enums.HelicopterPhase.APPROACHING
	craft.lastPhase = phase
	craft.assumedFlightStartTime = nil
	-- an approach that ends in FLYING was called off in the air (the run
	-- lost under it) and never touched down
	if wasApproaching and (phase == Enums.HelicopterPhase.SPINNING or phase == Enums.HelicopterPhase.IDLE) then
		-- the pad is where it rests from now on
		craft.restPivot = self:getPadCFrame(craft)
		craft.model:PivotTo(craft.restPivot)
		self:emitDust(craft)
		ClientSoundManager:playSfxAt(craft.restPivot.Position, SoundNames.Sfx.HELICOPTER_TOUCHDOWN, FLIGHT_SFX_FULL_VOLUME_STUDS, FLIGHT_SFX_SILENT_STUDS)
	end
	if phase == Enums.HelicopterPhase.FLYING then
		ClientSoundManager:playSfxAt(craft.model:GetPivot().Position, SoundNames.Sfx.HELICOPTER_LIFTOFF, FLIGHT_SFX_FULL_VOLUME_STUDS, FLIGHT_SFX_SILENT_STUDS)
	end
end

function ClientHelicopterManager:stepApproach(craft: Craft, deltaSec: number)
	self:stepRotor(craft, true, deltaSec)
	local elapsedSec = workspace:GetServerTimeNow() - self:getFlightStartTime(craft)
	local pose = HelicopterFlightRules.approachPose(self:getPadCFrame(craft), self:getHeading(craft), self.config, elapsedSec)
	self:render(craft, pose, true)
end

-- true once the departure is flown out
function ClientHelicopterManager:stepDeparture(craft: Craft, deltaSec: number): boolean
	self:stepRotor(craft, true, deltaSec)
	local elapsedSec = workspace:GetServerTimeNow() - self:getFlightStartTime(craft)
	local pose = HelicopterFlightRules.departurePose(self:getPadCFrame(craft), self:getHeading(craft), self.config, elapsedSec)
	self:render(craft, pose, true)
	return HelicopterFlightRules.isDepartureDone(self.config, elapsedSec)
end

-- true when the craft is finished with (gone from the world, or flown off)
function ClientHelicopterManager:step(craft: Craft, deltaSec: number): boolean
	if craft.model.Parent == nil then
		return true
	end
	local phase = getPhase(craft)
	if phase ~= craft.lastPhase then
		self:onPhaseChanged(craft, phase)
	end
	self:syncSearchlight(craft, phase == Enums.HelicopterPhase.APPROACHING)
	if phase == Enums.HelicopterPhase.APPROACHING then
		self:stepApproach(craft, deltaSec)
		return false
	end
	if phase == Enums.HelicopterPhase.FLYING then
		if self:stepDeparture(craft, deltaSec) then
			-- the server destroys it after its lifetime; locally it is done
			-- now, but it stays in the world unseen rather than destroyed,
			-- since a rider's seat going would end their ride early
			-- (2026-10-27)
			for _, descendant in craft.model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") then
					descendant.Enabled = false
				end
			end
			return true
		end
		return false
	end
	self:stepRotor(craft, phase == Enums.HelicopterPhase.SPINNING, deltaSec)
	self:render(craft, craft.restPivot, false)
	return false
end

-- the pivot a watched helicopter is drawn at this frame, for a camera
-- that follows it; nil for a model this client is not drawing
function ClientHelicopterManager:getDrawnPivot(model: Model): CFrame?
	for _, craft in self.crafts do
		if craft.model == model then
			return craft.model:GetPivot()
		end
	end
	return nil
end

function ClientHelicopterManager:watch(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	for _, craft in self.crafts do
		if craft.model == instance then
			return
		end
	end
	table.insert(self.crafts, makeCraft(instance))
end

function ClientHelicopterManager:init()
	self.config = HelicopterFlightRules.decodeConfig(ClientDataManager:getGameMetadata(Attributes.HELICOPTER_FLIGHT_CONFIG))
	for _, instance in CollectionService:GetTagged(Tags.HELICOPTER) do
		self:watch(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tags.HELICOPTER):Connect(
		function(instance: Instance)
			self:watch(instance)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			for index = #self.crafts, 1, -1 do
				if self:step(self.crafts[index], deltaSec) then
					table.remove(self.crafts, index)
				end
			end
		end
	)
end

function ClientHelicopterManager.new(): ClientHelicopterManager
	local self = setmetatable({}, ClientHelicopterManager) :: ClientHelicopterManager
	self.crafts = {}
	self.config = HelicopterFlightRules.DEFAULT_CONFIG
	return self
end

return ClientHelicopterManager.new()
