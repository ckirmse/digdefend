--!strict

-- Every pad helicopter's visuals, on every client, from the replicated pad
-- state: the rotor spins while Boarding or Departing, and a Departing
-- helicopter flies away (climb, then cruise off, then gone). The server
-- renames the launched model and clones a fresh one onto the pad, so a
-- flight is tracked apart from the pad's current helicopter. A Heartbeat
-- loop rather than tweens because everything here ramps and chains.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local ClientHelicopterManager = {}
ClientHelicopterManager.__index = ClientHelicopterManager

-- one helicopter being animated: the pad's resting one or a departed one
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

type PadView = {
	padModel: Model,
	craft: Craft?,
}

export type ClientHelicopterManager = typeof(setmetatable(
	{} :: {
		views: { PadView },
		flights: { Craft },
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
	local restPivot = model:GetPivot()
	return {
		model = model,
		rotor = nil,
		restPivot = restPivot,
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

function ClientHelicopterManager:getState(view: PadView): number
	local state = view.padModel:GetAttribute(Attributes.PAD_STATE)
	return if typeof(state) == "number" then state else Enums.PadState.IDLE
end

function ClientHelicopterManager:isInFlight(model: Model): boolean
	for _, flight in self.flights do
		if flight.model == model then
			return true
		end
	end
	return false
end

-- the pad's current helicopter: re-found whenever ours is gone or has been
-- handed to a flight (the server names a fresh clone the same way)
function ClientHelicopterManager:refreshCraftIfNeeded(view: PadView)
	local craft = view.craft
	if craft and craft.model.Parent ~= nil then
		return
	end
	view.craft = nil
	local model = view.padModel:FindFirstChild(Constants.HELICOPTER_TEMPLATE)
	if model and model:IsA("Model") and not self:isInFlight(model) then
		view.craft = makeCraft(model)
	end
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

function ClientHelicopterManager:stepFlights(deltaSec: number)
	for index = #self.flights, 1, -1 do
		local flight = self.flights[index]
		-- the server destroys the model after its lifetime; the flight may
		-- finish first, in which case the local copy goes away here
		local isGone = flight.model.Parent == nil
		if not isGone and self:stepFlight(flight, deltaSec) then
			flight.model:Destroy()
			isGone = true
		end
		if isGone then
			table.remove(self.flights, index)
		end
	end
end

function ClientHelicopterManager:stepPad(view: PadView, deltaSec: number)
	self:refreshCraftIfNeeded(view)
	local craft = view.craft
	if not craft then
		return
	end
	local state = self:getState(view)
	if state == Enums.PadState.DEPARTING then
		-- the pad's helicopter becomes a flight; the pad picks up the fresh
		-- clone once the server has reset
		table.insert(self.flights, craft)
		view.craft = nil
		return
	end
	self:stepRotor(craft, state == Enums.PadState.BOARDING, deltaSec)
	self:render(craft, false)
end

function ClientHelicopterManager:watchPad(padModel: Model)
	table.insert(
		self.views,
		{
			padModel = padModel,
			craft = nil,
		}
	)
end

function ClientHelicopterManager:init()
	local padsFolder = workspace:WaitForChild(Constants.HELICOPTER_PADS_FOLDER)
	for _, pad in padsFolder:GetChildren() do
		if pad:IsA("Model") and pad:GetAttribute(Attributes.PAD_INDEX) ~= nil then
			self:watchPad(pad)
		end
	end
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			for _, view in self.views do
				self:stepPad(view, deltaSec)
			end
			self:stepFlights(deltaSec)
		end
	)
end

function ClientHelicopterManager.new(): ClientHelicopterManager
	local self = setmetatable({}, ClientHelicopterManager) :: ClientHelicopterManager
	self.views = {}
	self.flights = {}
	return self
end

return ClientHelicopterManager.new()
