--!strict

-- Spectate Mode on this client (GDD "Spectate Mode"), M32: a dead player
-- watches a living one. The camera is Roblox's own follow camera with its
-- subject set to the watched player's Humanoid, so the spectator drags to
-- orbit and scrolls to zoom; the gameplay place's first-person lock is
-- lifted for as long as it lasts and put back after. The Spectate bar
-- (StarterGui.Spectate, scripts/studio/build_spectate_gui.luau) names the
-- player and has arrows to change, with Results and Return to Lobby over
-- it and, to its right while a revive is on offer, a Revive button under
-- a countdown. The server is
-- told who is being watched (TrySpectate) so it streams the world and the
-- monsters round that player, and the mine renderer is pointed at them
-- too. Who can be watched comes from the public IsDead attribute.
-- ClientReviveManager starts and stops it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientSpectateManager = {}
ClientSpectateManager.__index = ClientSpectateManager

export type ClientSpectateManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		nameLabel: TextLabel?,
		isSpectating: boolean,
		targetUserId: number?,
		-- the Humanoid the camera is on, so it is set once per character
		subject: Humanoid?,
		savedCameraMode: Enum.CameraMode?,
		savedMinZoom: number?,
		savedMaxZoom: number?,
		stepAccumulatorSec: number,
		bar: GuiObject?,
		reviveBox: GuiObject?,
		reviveButton: TextButton?,
		reviveTimerLabel: TextLabel?,
		resultsRequestedHandler: (() -> ())?,
		noTargetsHandler: (() -> ())?,
		reviveRequestedHandler: (() -> ())?,
		lobbyRequestedHandler: (() -> ())?,
	},
	ClientSpectateManager
))

local STEP_INTERVAL_SEC = 0.25
-- how close and how far the orbiting camera may sit from the watched player
local MIN_ZOOM_STUDS = 8
local MAX_ZOOM_STUDS = 30
local NO_TARGET = 0

function ClientSpectateManager:getIsSpectating(): boolean
	return self.isSpectating
end

-- everyone else in the run who is alive, in a stable order
function ClientSpectateManager:getTargetUserIds(): { number }
	local targets = {}
	for _, userId in ClientDataManager:getAllPlayerIds() do
		local data = ClientDataManager:getPlayerPublicData(userId)
		if data and userId ~= Players.LocalPlayer.UserId and not data.isDead then
			table.insert(targets, userId)
		end
	end
	return targets
end

function ClientSpectateManager:hasTargets(): boolean
	return #self:getTargetUserIds() > 0
end

function ClientSpectateManager:getTargetRoot(): BasePart?
	local userId = self.targetUserId
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- where the watched player stands: their character once it has streamed
-- in, and until then the position the compass already publishes
function ClientSpectateManager:getViewPosition(): Vector3?
	if not self.isSpectating or not self.targetUserId then
		return nil
	end
	local root = self:getTargetRoot()
	if root then
		return root.Position
	end
	local data = ClientDataManager:getPlayerPublicData(self.targetUserId)
	return if data then data.compassPosition else nil
end

function ClientSpectateManager:setTarget(userId: number)
	self.targetUserId = userId
	self.subject = nil
	local data = ClientDataManager:getPlayerPublicData(userId)
	if self.nameLabel then
		self.nameLabel.Text = if data then data.displayName else ""
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SPECTATE, { userId = userId })
end

-- the watched player's character streams in a moment after the server
-- moves the focus, so the camera is put on it when it appears
function ClientSpectateManager:attachCameraIfNeeded()
	local camera = workspace.CurrentCamera
	local root = self:getTargetRoot()
	local character = if root then root.Parent else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not camera or not humanoid or self.subject == humanoid then
		return
	end
	self.subject = humanoid
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end

function ClientSpectateManager:cycle(direction: number)
	local targets = self:getTargetUserIds()
	if #targets == 0 then
		return
	end
	local index = table.find(targets, self.targetUserId or NO_TARGET) or 1
	self:setTarget(targets[(index - 1 + direction) % #targets + 1])
end

function ClientSpectateManager:start(): boolean
	if self.isSpectating then
		return true
	end
	local targets = self:getTargetUserIds()
	if #targets == 0 then
		return false
	end
	local player = Players.LocalPlayer
	self.isSpectating = true
	self.savedCameraMode = player.CameraMode
	self.savedMinZoom = player.CameraMinZoomDistance
	self.savedMaxZoom = player.CameraMaxZoomDistance
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = MAX_ZOOM_STUDS
	player.CameraMinZoomDistance = MIN_ZOOM_STUDS
	if self.gui then
		self.gui.Enabled = true
	end
	self:setTarget(targets[1])
	self:attachCameraIfNeeded()
	return true
end

function ClientSpectateManager:stop()
	if not self.isSpectating then
		return
	end
	self.isSpectating = false
	self.targetUserId = nil
	self.subject = nil
	if self.gui then
		self.gui.Enabled = false
	end
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	-- the camera holds where it is: the dead player's own character is in
	-- the DeathRoom, which they must never see, and whoever takes the
	-- camera next (the grave view, or their own eyes after a revive) sets
	-- it when ready
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- the minimum first: it was the smaller of the two, and may never be
	-- above the maximum
	player.CameraMinZoomDistance = self.savedMinZoom or MIN_ZOOM_STUDS
	player.CameraMaxZoomDistance = self.savedMaxZoom or MAX_ZOOM_STUDS
	player.CameraMode = self.savedCameraMode or Enum.CameraMode.LockFirstPerson
	ClientNetManager:fireServer(NetEventNames.TRY_SPECTATE, { userId = NO_TARGET })
end

function ClientSpectateManager:step(deltaSec: number)
	if not self.isSpectating then
		return
	end
	self.stepAccumulatorSec += deltaSec
	if self.stepAccumulatorSec < STEP_INTERVAL_SEC then
		return
	end
	self.stepAccumulatorSec = 0
	local targets = self:getTargetUserIds()
	if #targets == 0 then
		self:stop()
		local handler = self.noTargetsHandler
		if handler then
			handler()
		end
		return
	end
	-- the watched player died or left: on to the next
	if not table.find(targets, self.targetUserId or NO_TARGET) then
		self:setTarget(targets[1])
	end
	self:attachCameraIfNeeded()
end

function ClientSpectateManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.SPECTATE_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientSpectateManager: no Spectate ScreenGui; run scripts/studio/build_spectate_gui.luau")
		return
	end
	gui.Enabled = false
	self.gui = gui
	local bar = gui:FindFirstChild(Constants.SPECTATE_BAR)
	local nameLabel = if bar then bar:FindFirstChild(Constants.SPECTATE_NAME_LABEL, true) else nil
	self.nameLabel = if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil
	local buttons: { [string]: () -> () } = {
		[Constants.SPECTATE_PREVIOUS_BUTTON] = function()
			self:cycle(-1)
		end,
		[Constants.SPECTATE_NEXT_BUTTON] = function()
			self:cycle(1)
		end,
		[Constants.SPECTATE_RESULTS_BUTTON] = function()
			local handler = self.resultsRequestedHandler
			if handler then
				handler()
			end
		end,
		[Constants.SPECTATE_LOBBY_BUTTON] = function()
			local handler = self.lobbyRequestedHandler
			if handler then
				handler()
			end
		end,
	}
	self.bar = if bar and bar:IsA("GuiObject") then bar else nil
	local reviveBox = gui:FindFirstChild(Constants.SPECTATE_REVIVE_BOX)
	local reviveButton = if reviveBox then reviveBox:FindFirstChild(Constants.SPECTATE_REVIVE_BUTTON) else nil
	local reviveTimer = if reviveBox then reviveBox:FindFirstChild(Constants.SPECTATE_REVIVE_TIMER_LABEL) else nil
	if reviveBox and reviveBox:IsA("GuiObject") and reviveButton and reviveButton:IsA("TextButton") then
		reviveBox.Visible = false
		self.reviveBox = reviveBox
		self.reviveButton = reviveButton
		self.reviveTimerLabel = if reviveTimer and reviveTimer:IsA("TextLabel") then reviveTimer else nil
		reviveButton.Activated:Connect(
			function()
				local handler = self.reviveRequestedHandler
				if handler then
					handler()
				end
			end
		)
	else
		warn("ClientSpectateManager: the Spectate gui has no ReviveBox.ReviveButton")
	end
	for buttonName, onActivated in buttons do
		local button = if bar then bar:FindFirstChild(buttonName) else nil
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(onActivated)
		else
			warn(`ClientSpectateManager: the Spectate bar has no {buttonName}`)
		end
	end
end

-- the Revive box to the right of the bar: the button's words (the revive
-- on offer and its price) and the countdown above it, or nil to hide the
-- box once nothing is on offer. ClientReviveManager, which knows the
-- offer, keeps this up to date. The box is centred between the bar's
-- right edge (the right arrow) and the right edge of the screen, wherever
-- those are on this screen
function ClientSpectateManager:setRevive(text: string?, timerText: string)
	local box = self.reviveBox
	local button = self.reviveButton
	if not box or not button then
		return
	end
	box.Visible = text ~= nil
	if not text then
		return
	end
	button.Text = text
	if self.reviveTimerLabel then
		self.reviveTimerLabel.Text = timerText
	end
	local gui = self.gui
	local bar = self.bar
	if gui and bar and gui.AbsoluteSize.X > 0 then
		local barRight = bar.AbsolutePosition.X + bar.AbsoluteSize.X - gui.AbsolutePosition.X
		local middle = (barRight + gui.AbsoluteSize.X) / 2
		box.Position = UDim2.new(middle / gui.AbsoluteSize.X, 0, box.Position.Y.Scale, box.Position.Y.Offset)
	end
end

-- resultsRequested, reviveRequested, lobbyRequested: the bar's three
-- buttons; noTargets: nobody is left alive to watch, so spectating has stopped
function ClientSpectateManager:init(resultsRequestedHandler: () -> (), noTargetsHandler: () -> (), reviveRequestedHandler: () -> (), lobbyRequestedHandler: () -> ())
	self.resultsRequestedHandler = resultsRequestedHandler
	self.noTargetsHandler = noTargetsHandler
	self.reviveRequestedHandler = reviveRequestedHandler
	self.lobbyRequestedHandler = lobbyRequestedHandler
	self:findGui()
	ClientMineManager:setViewPositionProvider(
		function(): Vector3?
			return self:getViewPosition()
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientSpectateManager.new(): ClientSpectateManager
	local self = setmetatable({}, ClientSpectateManager) :: ClientSpectateManager
	self.gui = nil
	self.nameLabel = nil
	self.isSpectating = false
	self.targetUserId = nil
	self.subject = nil
	self.savedCameraMode = nil
	self.savedMinZoom = nil
	self.savedMaxZoom = nil
	self.stepAccumulatorSec = 0
	self.bar = nil
	self.reviveBox = nil
	self.reviveButton = nil
	self.reviveTimerLabel = nil
	self.resultsRequestedHandler = nil
	self.noTargetsHandler = nil
	self.reviveRequestedHandler = nil
	self.lobbyRequestedHandler = nil
	return self
end

return ClientSpectateManager.new()
