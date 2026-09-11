--!strict

-- Every helicopter's visuals, on every client, in both places: models tagged
-- Tags.HELICOPTER carry a HelicopterPhase attribute set by the server
-- (HelicopterManager). SPINNING turns the rotor, FLYING flies the helicopter
-- away (climb, cruise, gone), IDLE winds the rotor down. The server never
-- animates; a Heartbeat loop rather than tweens because everything ramps
-- and chains.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local ClientHelicopterManager = {}
ClientHelicopterManager.__index = ClientHelicopterManager

type Craft = {
	model: Model,
	rotor: BasePart?,
	-- the model's pivot at rest and the rotor hub relative to it, so neither
	-- the spin nor the flight drifts
	restPivot: CFrame,
	rotorOffset: CFrame?,
	angle: number,
	-- rotor radians per second, ramped toward the target
	speed: number,
	-- flight progress (studs) and rates
	climb: number,
	climbSpeed: number,
	cruise: number,
	cruiseSpeed: number,
}

export type ClientHelicopterManager = typeof(setmetatable(
	{} :: {
		crafts: { Craft },
	},
	ClientHelicopterManager
))

local FULL_SPEED_RAD_PER_SEC = 25
local SPIN_UP_SEC = 3
local SPIN_DOWN_SEC = 4
-- flight path (designer request 2026-09-11): straight up, then straight
-- ahead along the model's facing, then gone
local CLIMB_HEIGHT_STUDS = 100
local CLIMB_ACCEL_STUDS_PER_SEC2 = 6
local CLIMB_MAX_SPEED_STUDS_PER_SEC = 20
local CRUISE_DISTANCE_STUDS = 1000
local CRUISE_ACCEL_STUDS_PER_SEC2 = 20
local CRUISE_MAX_SPEED_STUDS_PER_SEC = 80

local function findRotor(model: Model): BasePart?
	local rotorModel = model:FindFirstChild(Constants.HELICOPTER_ROTOR_MODEL)
	local rotorChild = if rotorModel then rotorModel:FindFirstChild(Constants.HELICOPTER_ROTOR_PART) else nil
	if rotorChild and rotorChild:IsA("BasePart") then
		return rotorChild
	end
	return nil
end

-- the rotor is resolved lazily: a freshly cloned model can be seen before its
-- children have replicated, and streaming can replace the part with a new
-- instance at any time. A newly found rotor sits at its server (rest) CFrame,
-- so the offset is taken against the rest pivot.
local function resolveRotorIfNeeded(craft: Craft)
	local rotor = craft.rotor
	if rotor and rotor.Parent ~= nil then
		return
	end
	rotor = findRotor(craft.model)
	craft.rotor = rotor
	craft.rotorOffset = if rotor then craft.restPivot:ToObjectSpace(rotor.CFrame) else nil
end

local function makeCraft(model: Model): Craft
	return {
		model = model,
		rotor = nil,
		restPivot = model:GetPivot(),
		rotorOffset = nil,
		angle = 0,
		speed = 0,
		climb = 0,
		climbSpeed = 0,
		cruise = 0,
		cruiseSpeed = 0,
	}
end

local function rampSpeed(current: number, target: number, accel: number, deltaSec: number): number
	return math.min(target, current + accel * deltaSec)
end

local function getPhase(craft: Craft): number
	local phase = craft.model:GetAttribute(Attributes.HELICOPTER_PHASE)
	return if typeof(phase) == "number" then phase else Enums.HelicopterPhase.IDLE
end

function ClientHelicopterManager:stepRotor(craft: Craft, isSpinning: boolean, deltaSec: number)
	local targetSpeed = if isSpinning then FULL_SPEED_RAD_PER_SEC else 0
	local rampSec = if targetSpeed > craft.speed then SPIN_UP_SEC else SPIN_DOWN_SEC
	local maxChange = FULL_SPEED_RAD_PER_SEC / rampSec * deltaSec
	craft.speed += math.clamp(targetSpeed - craft.speed, -maxChange, maxChange)
	craft.angle = (craft.angle + craft.speed * deltaSec) % (2 * math.pi)
end

function ClientHelicopterManager:getPivot(craft: Craft): CFrame
	local restPivot = craft.restPivot
	return restPivot + Vector3.new(0, craft.climb, 0) + restPivot.LookVector * craft.cruise
end

function ClientHelicopterManager:render(craft: Craft, isMoving: boolean)
	local pivot = self:getPivot(craft)
	if isMoving then
		craft.model:PivotTo(pivot)
	end
	resolveRotorIfNeeded(craft)
	local rotor = craft.rotor
	local rotorOffset = craft.rotorOffset
	if rotor and rotorOffset and craft.speed > 0 then
		-- spin about world up around the hub's own position, so the part's
		-- local axes (which the designer may orient any way) never tilt the spin
		local rotorRest = pivot * rotorOffset
		rotor.CFrame = CFrame.new(rotorRest.Position) * CFrame.Angles(0, craft.angle, 0) * rotorRest.Rotation
	end
end

-- climb to height, then cruise ahead; true once the path is complete
function ClientHelicopterManager:stepFlight(craft: Craft, deltaSec: number): boolean
	self:stepRotor(craft, true, deltaSec)
	if craft.climb < CLIMB_HEIGHT_STUDS then
		craft.climbSpeed = rampSpeed(craft.climbSpeed, CLIMB_MAX_SPEED_STUDS_PER_SEC, CLIMB_ACCEL_STUDS_PER_SEC2, deltaSec)
		craft.climb = math.min(CLIMB_HEIGHT_STUDS, craft.climb + craft.climbSpeed * deltaSec)
	else
		craft.cruiseSpeed = rampSpeed(craft.cruiseSpeed, CRUISE_MAX_SPEED_STUDS_PER_SEC, CRUISE_ACCEL_STUDS_PER_SEC2, deltaSec)
		craft.cruise += craft.cruiseSpeed * deltaSec
	end
	self:render(craft, true)
	return craft.cruise >= CRUISE_DISTANCE_STUDS
end

-- true when the craft is finished with (gone from the world, or flown off)
function ClientHelicopterManager:step(craft: Craft, deltaSec: number): boolean
	if craft.model.Parent == nil then
		return true
	end
	local phase = getPhase(craft)
	if phase == Enums.HelicopterPhase.FLYING then
		if self:stepFlight(craft, deltaSec) then
			-- the server destroys it after its lifetime; locally it is done now
			craft.model:Destroy()
			return true
		end
		return false
	end
	self:stepRotor(craft, phase == Enums.HelicopterPhase.SPINNING, deltaSec)
	self:render(craft, false)
	return false
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
	return self
end

return ClientHelicopterManager.new()
