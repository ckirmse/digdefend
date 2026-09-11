--!strict

-- Spins each pad helicopter's rotor while its party is Boarding or Departing
-- (designer request 2026-09-11). Purely visual, so it runs on the client from
-- the replicated pad state; the rotor hub is rotated and the blades follow
-- through their welds. A Heartbeat loop rather than a tween because the spin
-- is continuous and ramps up and down.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local ClientHelicopterManager = {}
ClientHelicopterManager.__index = ClientHelicopterManager

type RotorView = {
	padModel: Model,
	rotor: BasePart?,
	-- the rotor's CFrame at rest, so the spin never drifts
	restCFrame: CFrame?,
	angle: number,
	-- radians per second, ramped toward the target
	speed: number,
}

export type ClientHelicopterManager = typeof(setmetatable(
	{} :: {
		views: { RotorView },
	},
	ClientHelicopterManager
))

local FULL_SPEED_RAD_PER_SEC = 25
local SPIN_UP_SEC = 3
local SPIN_DOWN_SEC = 4

local function findRotor(padModel: Model): BasePart?
	local helicopter = padModel:FindFirstChild(Constants.HELICOPTER_TEMPLATE)
	local rotorModel = if helicopter then helicopter:FindFirstChild(Constants.HELICOPTER_ROTOR_MODEL) else nil
	local rotor = if rotorModel then rotorModel:FindFirstChild(Constants.HELICOPTER_ROTOR_PART) else nil
	if rotor and rotor:IsA("BasePart") then
		return rotor
	end
	return nil
end

function ClientHelicopterManager:isSpinning(view: RotorView): boolean
	local state = view.padModel:GetAttribute(Attributes.PAD_STATE)
	return state == Enums.PadState.BOARDING or state == Enums.PadState.DEPARTING
end

function ClientHelicopterManager:step(view: RotorView, deltaSec: number)
	local rotor = view.rotor
	-- the helicopter is re-cloned after every departure (M13), so re-find it
	if not rotor or rotor.Parent == nil then
		rotor = findRotor(view.padModel)
		view.rotor = rotor
		view.restCFrame = if rotor then rotor.CFrame else nil
		view.angle = 0
		view.speed = 0
	end
	local restCFrame = view.restCFrame
	if not rotor or not restCFrame then
		return
	end

	local targetSpeed = if self:isSpinning(view) then FULL_SPEED_RAD_PER_SEC else 0
	local rampSec = if targetSpeed > view.speed then SPIN_UP_SEC else SPIN_DOWN_SEC
	local maxChange = FULL_SPEED_RAD_PER_SEC / rampSec * deltaSec
	view.speed += math.clamp(targetSpeed - view.speed, -maxChange, maxChange)
	if view.speed == 0 then
		return
	end

	view.angle = (view.angle + view.speed * deltaSec) % (2 * math.pi)
	-- spin about world up around the hub's own position, so the part's local
	-- axes (which the designer may orient any way) never tilt the spin
	rotor.CFrame = CFrame.new(restCFrame.Position) * CFrame.Angles(0, view.angle, 0) * restCFrame.Rotation
end

function ClientHelicopterManager:watchPad(padModel: Model)
	table.insert(
		self.views,
		{
			padModel = padModel,
			rotor = nil,
			restCFrame = nil,
			angle = 0,
			speed = 0,
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
				self:step(view, deltaSec)
			end
		end
	)
end

function ClientHelicopterManager.new(): ClientHelicopterManager
	local self = setmetatable({}, ClientHelicopterManager) :: ClientHelicopterManager
	self.views = {}
	return self
end

return ClientHelicopterManager.new()
