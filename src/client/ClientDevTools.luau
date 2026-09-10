--!strict

-- Admin-only Iris dev panel. Loaded only when the local player's IsAdmin
-- attribute is true; every command it sends is re-checked on the server.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BakedIconUtil = require("@game/ReplicatedStorage/Shared/BakedIconUtil")
local IconFramingFormat = require("@game/ReplicatedStorage/Shared/IconFramingFormat")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Iris = require(script.Parent.Iris)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.ClientPlayerFeedbackManager)

local ClientDevTools = {}
ClientDevTools.__index = ClientDevTools

export type ClientDevTools = typeof(setmetatable(
	{} :: {
		isConnected: boolean,
		showMenu: any,
		showPlayers: any,
		showIconFraming: any,
		menuSize: any,
		playersSize: any,
		iconFramingSize: any,
		confirmReset: any,
		framingAssetOption: any,
		framingAssetOptions: { string },
		framingYaw: any,
		framingPitch: any,
		framingDistance: any,
		framingHeight: any,
		framingFov: any,
		stagedAssetPath: string?,
		stagedAsset: PVInstance?,
		framingBackdrop: Part?,
		savedCameraFov: number?,
		toggleTapCount: number,
		toggleTapLastTime: number,
	},
	ClientDevTools
))

local TOGGLE_KEY = Enum.KeyCode.RightShift
-- touch has no RightShift: tapping the bottom-right screen quadrant three
-- times in quick succession is the pointer equivalent
local TOGGLE_TAP_COUNT = 3
local TOGGLE_TAP_WINDOW_SEC = 0.6

local TEST_FEEDBACK_MESSAGE = "Test feedback from the dev tools"
local TEST_FEEDBACK_DISPLAY_SEC = 3

-- the framing stage sits high above the map so nothing else is in frame; the
-- chroma backdrop is keyed out of the capture screenshots later
local FRAMING_STAGE_POSITION = Vector3.new(0, 5000, 0)
local FRAMING_BACKDROP_COLOR = Color3.new(0, 1, 0)
local FRAMING_BACKDROP_SIZE = Vector3.new(400, 400, 1)
local FRAMING_BACKDROP_DISTANCE = 60

local function formatBool(value: boolean): string
	return if value then "yes" else "no"
end

-- Roblox defers layout propagation to the render pass, so AutomaticSize on
-- buttons evaluates against a zero-size container when a window is first
-- created; a size nudge triggers a re-layout that fixes the computed sizes
function ClientDevTools:toggleWindow(showState: any, sizeState: any)
	local isShowing = not showState:get()
	if isShowing then
		local size = sizeState:get()
		sizeState:set(Vector2.new(size.X + 1, size.Y))
		task.delay(
			0.02,
			function()
				sizeState:set(size)
			end
		)
	end
	showState:set(isShowing)
end

function ClientDevTools:renderPlayersWindow()
	Iris.Window({ "Players in Server" }, { size = self.playersSize, isOpened = self.showPlayers })
	Iris.Table({ 3, true, true, true })
	Iris.SetHeaderColumnIndex(1)

	Iris.Text({ "Name" })
	Iris.NextColumn()
	Iris.Text({ "UserId" })
	Iris.NextColumn()
	Iris.Text({ "Admin" })
	Iris.NextColumn()

	local localPlayer = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		local name = player.DisplayName
		if player == localPlayer then
			name ..= " (you)"
		end
		Iris.Text({ name })
		Iris.NextColumn()
		Iris.Text({ tostring(player.UserId) })
		Iris.NextColumn()
		Iris.Text({ formatBool(player:GetAttribute(Attributes.IS_ADMIN) == true) })
		Iris.NextColumn()
	end

	Iris.End() -- Table
	Iris.End() -- Window
end

function ClientDevTools:unstageAssetForFraming()
	local stagedAsset = self.stagedAsset
	if stagedAsset then
		stagedAsset:Destroy()
		self.stagedAsset = nil
	end
	local backdrop = self.framingBackdrop
	if backdrop then
		backdrop:Destroy()
		self.framingBackdrop = nil
	end
	self.stagedAssetPath = nil

	local camera = workspace.CurrentCamera
	if camera and self.savedCameraFov then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = self.savedCameraFov
		self.savedCameraFov = nil
	end
end

function ClientDevTools:stageAssetForFraming(assetPath: string)
	self:unstageAssetForFraming()

	local template = BakedIconUtil.findTemplate(assetPath)
	if not template or not (template:IsA("Model") or template:IsA("BasePart")) then
		warn("ClientDevTools: no stageable template at asset path", assetPath)
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local stagedAsset = template:Clone() :: PVInstance
	-- physics must not settle a rig off its pivot, and effects would pollute
	-- the chroma-key shot
	for _, descendant in stagedAsset:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		elseif
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Highlight")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Sound")
		then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	if stagedAsset:IsA("BasePart") then
		stagedAsset.Anchored = true
	end
	stagedAsset:PivotTo(CFrame.new(FRAMING_STAGE_POSITION))
	stagedAsset.Parent = workspace
	self.stagedAsset = stagedAsset
	self.stagedAssetPath = assetPath

	local backdrop = Instance.new("Part")
	backdrop.Name = "IconFramingBackdrop"
	backdrop.Size = FRAMING_BACKDROP_SIZE
	backdrop.Color = FRAMING_BACKDROP_COLOR
	backdrop.Material = Enum.Material.Neon
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CastShadow = false
	backdrop.Parent = workspace
	self.framingBackdrop = backdrop

	self.savedCameraFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	-- sliders deliberately keep their values across assets so one framing can
	-- serve as the starting point for the next
end

-- inverse of the slider→camera math: recover yaw/pitch/distance/height from a
-- saved pivot-relative framing. Framings saved by this tool always look at the
-- target's vertical axis, so the closest point on that axis along the look ray
-- recovers the focus (and thereby the height offset).
function ClientDevTools:loadFramingIntoSliders(assetPath: string): boolean
	local template = BakedIconUtil.findTemplate(assetPath)
	local encoded = if template then template:GetAttribute(Attributes.ICON_FRAMING) else nil
	if typeof(encoded) ~= "string" then
		warn("ClientDevTools: no saved framing on", assetPath)
		return false
	end
	local framing = IconFramingFormat.decodeAttribute(encoded)
	if not framing then
		warn("ClientDevTools: malformed saved framing on", assetPath)
		return false
	end

	local relative = IconFramingFormat.toRelativeCFrame(framing)
	local position = relative.Position
	local look = relative.LookVector
	local flatLookSquared = look.X * look.X + look.Z * look.Z
	if flatLookSquared < 1e-6 then
		warn("ClientDevTools: saved framing on", assetPath, "looks straight up/down; cannot load into sliders")
		return false
	end
	local rayParameter = -(position.X * look.X + position.Z * look.Z) / flatLookSquared
	local focus = position + look * rayParameter
	local offset = position - focus
	local distance = offset.Magnitude
	if distance < 1e-3 then
		warn("ClientDevTools: degenerate saved framing on", assetPath)
		return false
	end

	self.framingHeight:set(focus.Y)
	self.framingDistance:set(distance)
	self.framingPitch:set(math.deg(-math.asin(math.clamp(offset.Y / distance, -1, 1))))
	self.framingYaw:set(math.deg(math.atan2(offset.X, offset.Z)))
	self.framingFov:set(framing.fov)
	return true
end

-- runs every Iris frame while an asset is staged: the sliders are the sole
-- authority for the camera, and the chroma backdrop stays behind the asset
-- opposite the camera so it always fills the shot
function ClientDevTools:updateFramingCamera()
	local stagedAsset = self.stagedAsset
	local camera = workspace.CurrentCamera
	if not stagedAsset or not camera then
		return
	end
	local focus = stagedAsset:GetPivot().Position + Vector3.new(0, self.framingHeight:get(), 0)
	local rotation = CFrame.fromEulerAnglesYXZ(math.rad(self.framingPitch:get()), math.rad(self.framingYaw:get()), 0)
	local cameraPosition = focus + rotation:VectorToWorldSpace(Vector3.new(0, 0, self.framingDistance:get()))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(cameraPosition, focus)
	camera.FieldOfView = self.framingFov:get()

	local backdrop = self.framingBackdrop
	if backdrop then
		local viewDirection = (focus - cameraPosition).Unit
		backdrop.CFrame = CFrame.lookAt(focus + viewDirection * FRAMING_BACKDROP_DISTANCE, focus)
	end
end

function ClientDevTools:renderIconFramingWindow()
	local window = Iris.Window({ "Icon Framing" }, { size = self.iconFramingSize, isOpened = self.showIconFraming })

	if #self.framingAssetOptions == 0 then
		Iris.Text({ "No assets under ReplicatedStorage.GameAssets yet." })
	else
		Iris.ComboArray({ "Asset" }, { index = self.framingAssetOption }, self.framingAssetOptions)
		if Iris.Button({ "Stage asset" }).clicked() then
			local assetPath = self.framingAssetOption:get()
			if assetPath and assetPath ~= "" then
				self:stageAssetForFraming(assetPath)
			end
		end
		if Iris.Button({ "Load framing" }).clicked() then
			local assetPath = self.framingAssetOption:get()
			if assetPath and assetPath ~= "" then
				self:loadFramingIntoSliders(assetPath)
			end
		end
	end

	if self.stagedAsset then
		Iris.Text({ `Staged: {self.stagedAssetPath}` })
		Iris.SliderNum({ "Yaw", 1, 0, 360 }, { number = self.framingYaw })
		Iris.SliderNum({ "Pitch", 1, -80, 80 }, { number = self.framingPitch })
		Iris.SliderNum({ "Distance", 0.1, 1, 100 }, { number = self.framingDistance })
		Iris.SliderNum({ "Height", 0.1, -20, 20 }, { number = self.framingHeight })
		Iris.SliderNum({ "FOV", 1, 5, 100 }, { number = self.framingFov })
		if Iris.Button({ "Save framing (prints to Output)" }).clicked() then
			local camera = workspace.CurrentCamera
			local stagedAssetPath = self.stagedAssetPath
			local stagedAsset = self.stagedAsset
			if camera and stagedAssetPath and stagedAsset then
				local framing = IconFramingFormat.fromCameraAndTarget(camera.CFrame, stagedAsset:GetPivot(), camera.FieldOfView)
				print(IconFramingFormat.encodeLine(stagedAssetPath, framing))
			end
		end
		Iris.Text({ "Copy the printed ICON_FRAMING lines from the Output" })
		Iris.Text({ "window, then follow docs/icon-capture.md." })
		if Iris.Button({ "Done (release camera)" }).clicked() then
			self:unstageAssetForFraming()
		end
	end

	Iris.End() -- Window

	-- closing the window (or collapsing it) must hand the camera back
	if window.closed() or not self.showIconFraming:get() then
		if self.stagedAsset then
			self:unstageAssetForFraming()
		end
	else
		self:updateFramingCamera()
	end
end

function ClientDevTools:renderMenuWindow()
	Iris.Window({ "Dev Tools" }, { size = self.menuSize, isOpened = self.showMenu })

	if Iris.Button({ "Players in Server" }).clicked() then
		self:toggleWindow(self.showPlayers, self.playersSize)
	end
	if Iris.Button({ "Icon Framing" }).clicked() then
		self.framingAssetOptions = BakedIconUtil.getAllBakeableAssetPaths()
		self.framingAssetOption:set(self.framingAssetOptions[1])
		self:toggleWindow(self.showIconFraming, self.iconFramingSize)
	end

	Iris.Separator()
	if Iris.Button({ "Send test feedback (server)" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = "sendTestFeedback",
				args = {
					message = TEST_FEEDBACK_MESSAGE,
					displaySec = TEST_FEEDBACK_DISPLAY_SEC,
				},
			}
		)
	end
	if Iris.Button({ "Send test feedback (local)" }).clicked() then
		ClientPlayerFeedbackManager:giveLocal(TEST_FEEDBACK_MESSAGE, TEST_FEEDBACK_DISPLAY_SEC)
	end

	Iris.Separator()
	Iris.Checkbox({ "Confirm full reset" }, { isChecked = self.confirmReset })
	if Iris.Button({ "Reset player state" }).clicked() and self.confirmReset:get() then
		self.confirmReset:set(false)
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = "resetPlayerState",
			}
		)
	end

	Iris.End() -- Window
end

-- Iris walks every emitted widget each cycle even when its window is closed,
-- so closed windows must emit nothing or the dev tools cost several ms per
-- frame while idle
function ClientDevTools:render()
	if self.showMenu:get() then
		self:renderMenuWindow()
	end
	if self.showPlayers:get() then
		self:renderPlayersWindow()
	end
	if self.showIconFraming:get() then
		self:renderIconFramingWindow()
	end
end

function ClientDevTools:onToggleTap(position: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewportSize = camera.ViewportSize
	if position.X < viewportSize.X / 2 or position.Y < viewportSize.Y / 2 then
		self.toggleTapCount = 0
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - self.toggleTapLastTime > TOGGLE_TAP_WINDOW_SEC then
		self.toggleTapCount = 0
	end
	self.toggleTapLastTime = now
	self.toggleTapCount += 1
	if self.toggleTapCount >= TOGGLE_TAP_COUNT then
		self.toggleTapCount = 0
		self:toggleWindow(self.showMenu, self.menuSize)
	end
end

function ClientDevTools:init()
	if self.isConnected then
		return
	end
	self.isConnected = true

	Iris.Init()
	self.showMenu = Iris.State(false)
	self.showPlayers = Iris.State(false)
	self.showIconFraming = Iris.State(false)
	self.menuSize = Iris.State(Vector2.new(320, 320))
	self.playersSize = Iris.State(Vector2.new(400, 250))
	self.iconFramingSize = Iris.State(Vector2.new(350, 400))
	self.confirmReset = Iris.State(false)
	self.framingAssetOptions = BakedIconUtil.getAllBakeableAssetPaths()
	self.framingAssetOption = Iris.State(self.framingAssetOptions[1])
	self.framingYaw = Iris.State(180)
	self.framingPitch = Iris.State(0)
	self.framingDistance = Iris.State(5)
	self.framingHeight = Iris.State(0)
	self.framingFov = Iris.State(30)

	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			if isGameProcessed then
				return
			end
			if input.KeyCode == TOGGLE_KEY then
				self:toggleWindow(self.showMenu, self.menuSize)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:onToggleTap(input.Position)
			end
		end
	)

	Iris:Connect(
		function()
			self:render()
		end
	)
	print("ClientDevTools: ready (RightShift or triple-tap bottom-right)")
end

-- the server stamps IsAdmin after an async group lookup, so the attribute may
-- arrive after the client script starts
function ClientDevTools:initWhenAdmin()
	local localPlayer = Players.LocalPlayer
	local function checkIfNeeded()
		if localPlayer:GetAttribute(Attributes.IS_ADMIN) == true then
			self:init()
		end
	end
	localPlayer:GetAttributeChangedSignal(Attributes.IS_ADMIN):Connect(checkIfNeeded)
	checkIfNeeded()
end

function ClientDevTools.new(): ClientDevTools
	local self = setmetatable({}, ClientDevTools) :: ClientDevTools
	self.isConnected = false
	self.showMenu = nil
	self.showPlayers = nil
	self.showIconFraming = nil
	self.menuSize = nil
	self.playersSize = nil
	self.iconFramingSize = nil
	self.confirmReset = nil
	self.framingAssetOption = nil
	self.framingAssetOptions = {}
	self.framingYaw = nil
	self.framingPitch = nil
	self.framingDistance = nil
	self.framingHeight = nil
	self.framingFov = nil
	self.stagedAssetPath = nil
	self.stagedAsset = nil
	self.framingBackdrop = nil
	self.savedCameraFov = nil
	self.toggleTapCount = 0
	self.toggleTapLastTime = 0
	return self
end

return ClientDevTools.new()
