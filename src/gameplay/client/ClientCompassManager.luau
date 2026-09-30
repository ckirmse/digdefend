--!strict

-- The compass on this client (GDD "Compass"): the locator bar under the
-- day clock, shown once the player owns it (the private CompassLevel). The
-- bar is the view ahead, its middle straight ahead: every frame each
-- marker is placed by how far its target is off the camera's heading
-- (CompassRules). The Refinery is the home icon and pins to the nearer end
-- when it is out of view; a crewmate is a dot in their own colour that
-- shrinks with distance and hides when out of view; either carries an
-- arrow when its target is above or below. Positions come from the
-- replication folders, because streaming hides far characters and the
-- Refinery; a crewmate whose character is loaded here is read directly,
-- which is smoother. Nothing here decides anything.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CompassRules = require("@game/ReplicatedStorage/Shared/CompassRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientCompassManager = {}
ClientCompassManager.__index = ClientCompassManager

type Marker = {
	frame: GuiObject,
	-- the authored size, which the distance scale multiplies
	baseSize: UDim2,
	arrowUp: GuiObject?,
	arrowDown: GuiObject?,
}

type PlayerDot = {
	marker: Marker,
	publishedPosition: Vector3?,
}

export type ClientCompassManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		markersFrame: GuiObject?,
		homeMarker: Marker?,
		dotTemplate: GuiObject?,
		dotByUserId: { [number]: PlayerDot },
		stepConnection: RBXScriptConnection?,
	},
	ClientCompassManager
))

-- CompassLevel at or above this is owning the compass
local OWNED_LEVEL = 2
-- the server publishes the real numbers (GameData/Mining/Compass)
local DEFAULT_FIELD_OF_VIEW_DEGREES = 120
local DEFAULT_DOT_FULL_SIZE_STUDS = 40
local DEFAULT_DOT_SMALLEST_STUDS = 300
local DEFAULT_DOT_SMALLEST_SCALE = 0.5
local DEFAULT_VERTICAL_HINT_STUDS = 8

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function buildMarker(frame: GuiObject): Marker
	local arrowUp = frame:FindFirstChild(Constants.COMPASS_ARROW_UP)
	local arrowDown = frame:FindFirstChild(Constants.COMPASS_ARROW_DOWN)
	return {
		frame = frame,
		baseSize = frame.Size,
		arrowUp = if arrowUp and arrowUp:IsA("GuiObject") then arrowUp else nil,
		arrowDown = if arrowDown and arrowDown:IsA("GuiObject") then arrowDown else nil,
	}
end

function ClientCompassManager:isOwned(): boolean
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.COMPASS_LEVEL), 1) >= OWNED_LEVEL
end

function ClientCompassManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.COMPASS_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientCompassManager: no Compass ScreenGui; run scripts/studio/build_compass_gui.luau")
		return
	end
	local root = gui:FindFirstChild(Constants.COMPASS_ROOT_FRAME)
	local bar = if root then root:FindFirstChild(Constants.COMPASS_BAR) else nil
	local markersFrame = if bar then bar:FindFirstChild(Constants.COMPASS_MARKERS_FRAME) else nil
	local homeIcon = if markersFrame then markersFrame:FindFirstChild(Constants.COMPASS_HOME_ICON) else nil
	local dotTemplate = if markersFrame then markersFrame:FindFirstChild(Constants.COMPASS_PLAYER_DOT_TEMPLATE) else nil
	if not markersFrame or not markersFrame:IsA("GuiObject") or not homeIcon or not homeIcon:IsA("GuiObject") or not dotTemplate or not dotTemplate:IsA("GuiObject") then
		warn("ClientCompassManager: the Compass ScreenGui is missing parts; rebuild it with scripts/studio/build_compass_gui.luau")
		return
	end
	gui.Enabled = false
	dotTemplate.Visible = false
	self.gui = gui
	self.markersFrame = markersFrame
	self.homeMarker = buildMarker(homeIcon)
	self.dotTemplate = dotTemplate
end

function ClientCompassManager:addDot(userId: number, data: ClientDataManager.PublicData)
	local template = self.dotTemplate
	local markersFrame = self.markersFrame
	if not template or not markersFrame or userId == Players.LocalPlayer.UserId or self.dotByUserId[userId] then
		return
	end
	local frame = template:Clone()
	frame.Name = tostring(userId)
	frame.Visible = false
	frame.Parent = markersFrame
	self.dotByUserId[userId] = {
		marker = buildMarker(frame),
		publishedPosition = nil,
	}
	self:updateDot(userId, data)
end

function ClientCompassManager:updateDot(userId: number, data: ClientDataManager.PublicData)
	local dot = self.dotByUserId[userId]
	if not dot then
		return
	end
	dot.publishedPosition = data.compassPosition
	local colors = UiStyle.COMPASS_PLAYER_COLORS
	dot.marker.frame.BackgroundColor3 = colors[(data.compassColorIndex - 1) % #colors + 1]
end

function ClientCompassManager:removeDot(userId: number)
	local dot = self.dotByUserId[userId]
	if dot then
		dot.marker.frame:Destroy()
		self.dotByUserId[userId] = nil
	end
end

-- a crewmate's loaded character moves every frame; the published position
-- only a few times a second, so it is the fallback for one streamed out
function ClientCompassManager:getPlayerPosition(userId: number, dot: PlayerDot): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return dot.publishedPosition
end

function ClientCompassManager:placeMarker(marker: Marker, share: number?, scale: number, verticalHint: number)
	local frame = marker.frame
	if not share then
		frame.Visible = false
		return
	end
	frame.Visible = true
	frame.Position = UDim2.fromScale(share, 0.5)
	local baseSize = marker.baseSize
	frame.Size = UDim2.fromScale(baseSize.X.Scale * scale, baseSize.Y.Scale * scale)
	if marker.arrowUp then
		marker.arrowUp.Visible = verticalHint == CompassRules.VERTICAL_HINT_UP
	end
	if marker.arrowDown then
		marker.arrowDown.Visible = verticalHint == CompassRules.VERTICAL_HINT_DOWN
	end
end

function ClientCompassManager:step()
	local camera = workspace.CurrentCamera
	local homeMarker = self.homeMarker
	if not camera or not homeMarker then
		return
	end
	local fieldOfViewDegrees = readNumber(ClientDataManager:getGameMetadata(Attributes.COMPASS_FIELD_OF_VIEW_DEGREES), DEFAULT_FIELD_OF_VIEW_DEGREES)
	local verticalHintStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.COMPASS_VERTICAL_HINT_STUDS), DEFAULT_VERTICAL_HINT_STUDS)
	local fullSizeStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.COMPASS_DOT_FULL_SIZE_STUDS), DEFAULT_DOT_FULL_SIZE_STUDS)
	local smallestStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.COMPASS_DOT_SMALLEST_STUDS), DEFAULT_DOT_SMALLEST_STUDS)
	local smallestScale = readNumber(ClientDataManager:getGameMetadata(Attributes.COMPASS_DOT_SMALLEST_SCALE), DEFAULT_DOT_SMALLEST_SCALE)
	local cameraCFrame = camera.CFrame
	local viewerPosition = cameraCFrame.Position
	local forwardX, forwardZ = CompassRules.flatForward(cameraCFrame.LookVector, cameraCFrame.UpVector)

	local homePosition = ClientDataManager:getGameMetadata(Attributes.COMPASS_HOME_POSITION)
	if typeof(homePosition) == "Vector3" then
		local yaw = CompassRules.relativeYawDegrees(forwardX, forwardZ, viewerPosition, homePosition)
		local share = CompassRules.barShare(yaw, fieldOfViewDegrees, true)
		self:placeMarker(homeMarker, share, 1, CompassRules.verticalHint(homePosition.Y - viewerPosition.Y, verticalHintStuds))
	else
		self:placeMarker(homeMarker, nil, 1, CompassRules.VERTICAL_HINT_NONE)
	end

	for userId, dot in self.dotByUserId do
		local position = self:getPlayerPosition(userId, dot)
		if not position then
			self:placeMarker(dot.marker, nil, 1, CompassRules.VERTICAL_HINT_NONE)
			continue
		end
		local yaw = CompassRules.relativeYawDegrees(forwardX, forwardZ, viewerPosition, position)
		local share = CompassRules.barShare(yaw, fieldOfViewDegrees, false)
		local scale = CompassRules.dotScale((position - viewerPosition).Magnitude, fullSizeStuds, smallestStuds, smallestScale)
		self:placeMarker(dot.marker, share, scale, CompassRules.verticalHint(position.Y - viewerPosition.Y, verticalHintStuds))
	end
end

-- the bar is drawn, and stepped, only while the compass is owned
function ClientCompassManager:refreshOwned()
	local gui = self.gui
	if not gui then
		return
	end
	local isOwned = self:isOwned()
	gui.Enabled = isOwned
	if isOwned and not self.stepConnection then
		self.stepConnection = RunService.RenderStepped:Connect(
			function()
				self:step()
			end
		)
	elseif not isOwned and self.stepConnection then
		self.stepConnection:Disconnect()
		self.stepConnection = nil
	end
end

function ClientCompassManager:init()
	self:findGui()
	if not self.gui then
		return
	end
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			self:addDot(userId, data)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			self:updateDot(userId, data)
		end,
		onRemoved = function(userId: number)
			self:removeDot(userId)
		end,
	})
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.COMPASS_LEVEL,
		function()
			self:refreshOwned()
		end
	)
	self:refreshOwned()
end

function ClientCompassManager.new(): ClientCompassManager
	local self = setmetatable({}, ClientCompassManager) :: ClientCompassManager
	self.gui = nil
	self.markersFrame = nil
	self.homeMarker = nil
	self.dotTemplate = nil
	self.dotByUserId = {}
	self.stepConnection = nil
	return self
end

return ClientCompassManager.new()
