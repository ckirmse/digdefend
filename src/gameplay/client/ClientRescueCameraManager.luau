--!strict

-- A rider's view of the escape (M75): the moment the local player is
-- seated in the rescue helicopter the camera leaves first person for the
-- pad's authored RideCameraStart shot (designer, 2026-10-27), rises with
-- the lift-off at the helicopter's own pace while turning to the
-- RideCameraEnd shot, then drifts to RideCameraFinal over the rest of the
-- ride so it arrives as the menu does, and RIDE_SEC after lift-off
-- brings in the Results Menu
-- (ClientReviveManager holds the run's end back until then; the menu
-- opens in the dark and the black fades away). A pad without the two
-- parts gets the first build's chase shot. The HUD stays while a rider
-- waits for crewmates and fades once the run is won with the crew aboard.
-- The grounded crew keep their own camera.
-- A ride ends early (the seat lost, the run lost) by handing the camera
-- straight back. Only the flight itself is the server's: the pose the
-- camera follows is what ClientHelicopterManager drew this frame.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientHelicopterManager = require(script.Parent.Parent.Client.ClientHelicopterManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientReviveManager = require(script.Parent.ClientReviveManager)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)

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
		-- the pad's authored shots, when it has them
		shotStart: CFrame?,
		shotEnd: CFrame?,
		shotFinal: CFrame?,
		-- when the camera reached the end shot, the drift's start
		driftStartTime: number?,
		isHudFaded: boolean,
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
-- the Results Menu and its blur come in over this long at the ride's end
-- (designer, 2026-10-27)
local MENU_FADE_IN_SEC = 3
-- the designer's Title card holds the screen for this long at the end of
-- the ride, then the screen rests this long before the menu fades in
-- (designer, 2026-10-27)
local TITLE_HOLD_SEC = 5
-- the card comes this long after the camera reaches its final shot
local TITLE_DELAY_SEC = 0.5
local TITLE_TO_MENU_SEC = 2
local DEFAULT_RIDE_SEC = 10
-- the HUD, the Refinery HP bar, and the countdown fade out together once
-- the crew is aboard and the run won (designer, 2026-10-27)
local HUD_FADE_SEC = 1
-- the ride's song comes in from this far into the track over this long
-- (designer, 2026-10-27)
local EXIT_SONG_START_SEC = 12
local EXIT_SONG_FADE_IN_SEC = 5

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

-- the authored shot: at RideCameraStart while seated on the pad, then up
-- with the helicopter at its own pace, the camera's height gaining what
-- the helicopter's has, while it turns to RideCameraEnd over the climb
-- between the two shots' heights; still there after
function ClientRescueCameraManager:stepAuthoredShot(camera: Camera, pivot: CFrame, shotStart: CFrame, shotEnd: CFrame)
	local helicopter = self.helicopter
	local padCFrame = if helicopter then helicopter:GetAttribute(Attributes.HELICOPTER_PAD_CFRAME) else nil
	local groundY = if typeof(padCFrame) == "CFrame" then padCFrame.Position.Y else pivot.Position.Y
	local climb = math.max(shotEnd.Position.Y - shotStart.Position.Y, 1)
	local gained = math.clamp(pivot.Position.Y - groundY, 0, climb)
	local share = gained / climb
	camera.CameraType = Enum.CameraType.Scriptable
	local shotFinal = self.shotFinal
	if share >= 1 and shotFinal and helicopter then
		-- risen: the drift from the end shot to the final one, timed to
		-- land with the Results Menu (RIDE_SEC after lift-off)
		local now = workspace:GetServerTimeNow()
		local driftStartTime = self.driftStartTime
		if not driftStartTime then
			driftStartTime = now
			self.driftStartTime = now
			-- the sky stands still from here (designer, 2026-10-27)
			ClientRunCycleManager:setSunsetHeld(true)
		end
		local liftOffTime = readNumber(helicopter:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME), driftStartTime)
		local rideSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_RIDE_SEC), DEFAULT_RIDE_SEC)
		local driftSec = math.max(liftOffTime + rideSec - driftStartTime, 0.1)
		local drift = smoothstep((now - driftStartTime) / driftSec)
		camera.CFrame = shotEnd:Lerp(shotFinal, drift)
		return
	end
	local flat = shotStart.Position:Lerp(shotEnd.Position, share)
	local position = Vector3.new(flat.X, shotStart.Position.Y + gained, flat.Z)
	camera.CFrame = CFrame.new(position) * shotStart.Rotation:Lerp(shotEnd.Rotation, share)
end

-- one frame of the shot
function ClientRescueCameraManager:stepCamera(deltaSec: number)
	local helicopter = self.helicopter
	local camera = workspace.CurrentCamera
	if not helicopter or not camera or not self.isRiding then
		return
	end
	local pivot = ClientHelicopterManager:getDrawnPivot(helicopter) or helicopter:GetPivot()
	local shotStart = self.shotStart
	local shotEnd = self.shotEnd
	if shotStart and shotEnd then
		self:stepAuthoredShot(camera, pivot, shotStart, shotEnd)
		return
	end
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

-- the Title card is on the screen for the hold, over the ride's last
-- picture; the card is the designer's authored gui, only enabled here
function ClientRescueCameraManager:showTitleCard()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local titleGui = if playerGui then playerGui:FindFirstChild(Constants.RESCUE_TITLE_GUI_NAME) else nil
	if not titleGui or not titleGui:IsA("ScreenGui") then
		warn(`ClientRescueCameraManager: no {Constants.RESCUE_TITLE_GUI_NAME} ScreenGui in StarterGui; the title card is skipped`)
		task.wait(TITLE_HOLD_SEC)
		return
	end
	titleGui.Enabled = true
	task.wait(TITLE_HOLD_SEC)
	titleGui.Enabled = false
end

-- the lift-off has been watched long enough: the designer's Title card
-- holds over the ride's last picture, the screen rests, then the Results
-- Menu fades in (designer, 2026-10-27: no cut to black), the ride's own
-- camera staying under it all
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
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	local generation = self.rideGeneration
	task.spawn(
		function()
			task.wait(TITLE_DELAY_SEC)
			if generation ~= self.rideGeneration then
				return
			end
			self:showTitleCard()
			if generation ~= self.rideGeneration then
				return
			end
			task.wait(TITLE_TO_MENU_SEC)
			if generation ~= self.rideGeneration then
				return
			end
			-- the song plays on under the menu (designer, 2026-10-27)
			ClientReviveManager:setRunEndDeferred(false, MENU_FADE_IN_SEC)
		end
	)
end

-- the win can reach a rider before their seat is seen (the last one in
-- boards and the run ends in the same server step): a rider whose ride
-- has not begun by then starts it on the helicopter in the world
function ClientRescueCameraManager:startRideIfAboard()
	if self.isRiding or self:getRunState() ~= Enums.RunState.WON then
		return
	end
	if ClientDataManager:getCurrentPlayerAttribute(Attributes.RESCUE_IS_ABOARD) ~= true then
		return
	end
	for _, instance in CollectionService:GetTagged(Tags.HELICOPTER) do
		if instance:IsA("Model") and instance:GetAttribute(Attributes.HELICOPTER_PAD_CFRAME) ~= nil then
			self:startRide(instance)
			return
		end
	end
end

-- the pad's authored shots, read when the ride starts
function ClientRescueCameraManager:findShots(helicopter: Model)
	self.shotStart = nil
	self.shotEnd = nil
	self.shotFinal = nil
	self.driftStartTime = nil
	local pad = helicopter.Parent
	if not pad then
		return
	end
	local startPart = pad:FindFirstChild(Constants.PAD_RIDE_CAMERA_START_PART)
	local endPart = pad:FindFirstChild(Constants.PAD_RIDE_CAMERA_END_PART)
	local finalPart = pad:FindFirstChild(Constants.PAD_RIDE_CAMERA_FINAL_PART)
	if startPart and startPart:IsA("BasePart") and endPart and endPart:IsA("BasePart") then
		self.shotStart = startPart.CFrame
		self.shotEnd = endPart.CFrame
		-- a pad without the final shot holds the end shot
		self.shotFinal = if finalPart and finalPart:IsA("BasePart") then finalPart.CFrame else nil
	end
end

-- the run won with this player aboard (the last crew member in): the
-- HUD goes (every HUD gui, the Refinery HP bar and the countdown among
-- them) and the ride's song comes in
function ClientRescueCameraManager:fadeHudIfNeeded()
	if self.isHudFaded or not self.isRiding or self:getRunState() ~= Enums.RunState.WON then
		return
	end
	self.isHudFaded = true
	ClientReviveManager:setHudHidden(true, HUD_FADE_SEC)
	ClientSoundManager:fadeInMusic(SoundNames.Music.RESCUE_EXIT_SONG, nil, EXIT_SONG_FADE_IN_SEC, true, EXIT_SONG_START_SEC)
end

function ClientRescueCameraManager:startRide(helicopter: Model)
	if self.isRiding then
		return
	end
	self.isRiding = true
	self.isHandingOff = false
	self.isHudFaded = false
	self.rideGeneration += 1
	self.helicopter = helicopter
	self.cameraPosition = nil
	self:findShots(helicopter)
	local player = Players.LocalPlayer
	-- the first-person lock keeps the player's own body invisible, so it
	-- is lifted for the ride, as the death view does
	self.savedCameraMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.Classic
	UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	ClientReviveManager:setRunEndDeferred(true)
	self:fadeHudIfNeeded()
	RunService:BindToRenderStep(
		RENDER_STEP_NAME,
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaSec: number)
			self:stepCamera(deltaSec)
			self:fadeHudIfNeeded()
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
		if self.isHudFaded then
			ClientReviveManager:setHudHidden(false)
		end
	end
	self.isHudFaded = false
	self.isHandingOff = false
	ClientRunCycleManager:setSunsetHeld(false)
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
	-- a run lost mid-ride (the Refinery falling as it lifts off) ends it;
	-- a win with this player aboard starts the ride if the seat has not
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_STATE,
		function()
			if self:getRunState() == Enums.RunState.LOST then
				self:stopRide()
			else
				self:startRideIfAboard()
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
	self.shotStart = nil
	self.shotEnd = nil
	self.shotFinal = nil
	self.driftStartTime = nil
	self.isHudFaded = false
	return self
end

return ClientRescueCameraManager.new()
