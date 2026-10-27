--!strict

-- A rider's view of the escape (M75): the moment the local player is
-- seated in the rescue helicopter the camera leaves first person for a
-- chase shot behind and above it, rides the lift-off, swings ahead so the
-- camp recedes behind the helicopter, and RIDE_SEC after lift-off fades
-- to black into the Results Menu (ClientReviveManager holds the run's end
-- back until then; the menu opens in the dark and the black fades away).
-- The HUD hides while seated. The grounded crew keep their own camera.
-- A ride ends early (the seat lost, the run lost) by handing the camera
-- straight back. Only the flight itself is the server's: the pose the
-- camera follows is what ClientHelicopterManager drew this frame.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientHelicopterManager = require(script.Parent.Parent.Client.ClientHelicopterManager)
local ClientReviveManager = require(script.Parent.ClientReviveManager)

local ClientRescueCameraManager = {}
ClientRescueCameraManager.__index = ClientRescueCameraManager

export type ClientRescueCameraManager = typeof(setmetatable(
	{} :: {
		helicopter: Model?,
		isRiding: boolean,
		isHandingOff: boolean,
		savedCameraMode: Enum.CameraMode?,
		-- the camera's current spot, eased toward where the shot wants it
		cameraPosition: Vector3?,
		seatedConnection: RBXScriptConnection?,
		rideGeneration: number,
	},
	ClientRescueCameraManager
))

local RENDER_STEP_NAME = "RescueRideCamera"
-- the shot's offsets in the helicopter's yawed frame (behind is +Z):
-- over its shoulder on the pad, then out ahead and below as it climbs,
-- looking back at it with the camp beyond
local BOARDED_OFFSET = Vector3.new(6, 9, 26)
local DEPARTED_OFFSET = Vector3.new(14, -6, -36)
-- the swing from one to the other starts once the lift-off has the
-- helicopter off the ground, and takes this long
local OFFSET_SWING_START_SEC = 2
local OFFSET_SWING_SEC = 5
-- the camera never sinks closer to the pad's ground than this
local CAMERA_MIN_HEIGHT_STUDS = 4
local LOOK_AT_LIFT_STUDS = 2
-- how quickly the camera closes on its wanted spot, per second
local EASE_PER_SEC = 4
local FADE_SEC = 1
local DEFAULT_RIDE_SEC = 10

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function smoothstep(share: number): number
	local t = math.clamp(share, 0, 1)
	return t * t * (3 - 2 * t)
end

-- the helicopter a seat belongs to, if it is one
local function findHelicopter(seat: Instance): Model?
	local ancestor: Instance? = seat
	while ancestor do
		if ancestor:IsA("Model") and CollectionService:HasTag(ancestor, Tags.HELICOPTER) then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

function ClientRescueCameraManager:getRunState(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
end

-- one frame of the shot
function ClientRescueCameraManager:stepCamera(deltaSec: number)
	local helicopter = self.helicopter
	local camera = workspace.CurrentCamera
	if not helicopter or not camera or not self.isRiding then
		return
	end
	local pivot = ClientHelicopterManager:getDrawnPivot(helicopter) or helicopter:GetPivot()
	local phase = helicopter:GetAttribute(Attributes.HELICOPTER_PHASE)
	local swing = 0
	if phase == Enums.HelicopterPhase.FLYING then
		local startTime = helicopter:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME)
		local elapsedSec = workspace:GetServerTimeNow() - readNumber(startTime, workspace:GetServerTimeNow())
		swing = smoothstep((elapsedSec - OFFSET_SWING_START_SEC) / OFFSET_SWING_SEC)
	end
	local offset = BOARDED_OFFSET:Lerp(DEPARTED_OFFSET, swing)
	-- yaw only, so a bank or a nose-down never rolls the shot
	local look = pivot.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local wanted = (CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0)):PointToWorldSpace(offset)
	-- the pad is the ground the shot must stay above
	local padCFrame = helicopter:GetAttribute(Attributes.HELICOPTER_PAD_CFRAME)
	local groundY = if typeof(padCFrame) == "CFrame" then padCFrame.Position.Y else pivot.Position.Y
	wanted = Vector3.new(wanted.X, math.max(wanted.Y, groundY + CAMERA_MIN_HEIGHT_STUDS), wanted.Z)
	local current = self.cameraPosition or wanted
	local share = 1 - math.exp(-EASE_PER_SEC * deltaSec)
	local position = current:Lerp(wanted, share)
	self.cameraPosition = position
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, pivot.Position + Vector3.new(0, LOOK_AT_LIFT_STUDS, 0))
end

-- the lift-off has been watched long enough: into the dark, the Results
-- Menu, and out again. The ride's own camera stays under the menu
function ClientRescueCameraManager:handOffIfNeeded()
	local helicopter = self.helicopter
	if not helicopter or self.isHandingOff or not self.isRiding then
		return
	end
	if helicopter:GetAttribute(Attributes.HELICOPTER_PHASE) ~= Enums.HelicopterPhase.FLYING then
		return
	end
	local startTime = readNumber(helicopter:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME), workspace:GetServerTimeNow())
	local rideSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_RIDE_SEC), DEFAULT_RIDE_SEC)
	if workspace:GetServerTimeNow() - startTime < rideSec then
		return
	end
	self.isHandingOff = true
	local generation = self.rideGeneration
	task.spawn(
		function()
			ClientReviveManager:fade(0, FADE_SEC)
			if generation ~= self.rideGeneration then
				return
			end
			RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
			ClientReviveManager:setRunEndDeferred(false)
			ClientReviveManager:fade(1, FADE_SEC)
		end
	)
end

function ClientRescueCameraManager:startRide(helicopter: Model)
	if self.isRiding then
		return
	end
	self.isRiding = true
	self.isHandingOff = false
	self.rideGeneration += 1
	self.helicopter = helicopter
	self.cameraPosition = nil
	local player = Players.LocalPlayer
	-- the first-person lock keeps the player's own body invisible, so it
	-- is lifted for the ride, as the death view does
	self.savedCameraMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.Classic
	UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	ClientReviveManager:setRunEndDeferred(true)
	ClientReviveManager:setHudHidden(true)
	RunService:BindToRenderStep(
		RENDER_STEP_NAME,
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaSec: number)
			self:stepCamera(deltaSec)
			self:handOffIfNeeded()
		end
	)
end

-- the ride is over before its time: the camera goes straight back
function ClientRescueCameraManager:stopRide()
	if not self.isRiding then
		return
	end
	self.isRiding = false
	self.rideGeneration += 1
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	self.helicopter = nil
	local player = Players.LocalPlayer
	player.CameraMode = self.savedCameraMode or Enum.CameraMode.LockFirstPerson
	self.savedCameraMode = nil
	if not self.isHandingOff then
		ClientReviveManager:releaseCamera()
		ClientReviveManager:setHudHidden(false)
	end
	self.isHandingOff = false
	ClientReviveManager:setRunEndDeferred(false)
end

function ClientRescueCameraManager:onSeated(isSeated: boolean, seat: Instance?)
	if not isSeated then
		if self.isRiding and not self.isHandingOff then
			self:stopRide()
		end
		return
	end
	local helicopter = if seat then findHelicopter(seat) else nil
	if not helicopter then
		return
	end
	local state = self:getRunState()
	if state ~= Enums.RunState.RESCUE and state ~= Enums.RunState.WON then
		return
	end
	self:startRide(helicopter)
end

function ClientRescueCameraManager:watchCharacter(character: Model)
	local previous = self.seatedConnection
	if previous then
		previous:Disconnect()
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	self.seatedConnection = humanoid.Seated:Connect(
		function(isSeated: boolean, seat: Instance?)
			self:onSeated(isSeated, seat)
		end
	)
end

function ClientRescueCameraManager:init()
	local player = Players.LocalPlayer
	local character = player.Character
	if character then
		task.spawn(
			function()
				self:watchCharacter(character)
			end
		)
	end
	player.CharacterAdded:Connect(
		function(newCharacter: Model)
			self:watchCharacter(newCharacter)
		end
	)
	-- a run lost mid-ride (the Refinery falling as it lifts off) ends it
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_STATE,
		function()
			if self:getRunState() == Enums.RunState.LOST then
				self:stopRide()
			end
		end
	)
end

function ClientRescueCameraManager.new(): ClientRescueCameraManager
	local self = setmetatable({}, ClientRescueCameraManager) :: ClientRescueCameraManager
	self.helicopter = nil
	self.isRiding = false
	self.isHandingOff = false
	self.savedCameraMode = nil
	self.cameraPosition = nil
	self.seatedConnection = nil
	self.rideGeneration = 0
	return self
end

return ClientRescueCameraManager.new()
