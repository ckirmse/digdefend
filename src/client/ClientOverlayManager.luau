--!strict

-- One menu (overlay) at a time. A menu registers itself when it opens; this
-- manager blurs the world, puts a click-catching backdrop behind the dialog,
-- freezes the character, nudges the camera, and tells every notifier (the
-- HUD) to slide away. Closing reverses all of it. Copied from Lucky Squares.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientOverlayManager = {}
ClientOverlayManager.__index = ClientOverlayManager

export type Overlay = {
	getGuiRoot: (self: Overlay) -> GuiObject?,
	notifyForceEnd: (self: Overlay) -> (),
	notifyClickOutside: (self: Overlay) -> (),
	doesWantBlur: ((self: Overlay) -> boolean)?,
	doZoomCamera: ((self: Overlay) -> boolean)?,
	doAllowPlayerWorldActions: ((self: Overlay) -> boolean)?,
}

export type OverlayNotifier = {
	notifyBeginOverlay: (self: OverlayNotifier) -> (),
	notifyEndOverlay: (self: OverlayNotifier) -> (),
}

export type ClientOverlayManager = typeof(setmetatable(
	{} :: {
		overlay: Overlay?,
		isDeferring: boolean,
		deferredOverlays: { Overlay },
		notifiers: { OverlayNotifier },
		blur: BlurEffect?,
		backdropGui: ScreenGui?,
		anchoredRootPart: BasePart?,
	},
	ClientOverlayManager
))

local BLUR_SIZE = 12
-- ScreenGui layering contract: HUD ScreenGuis sit at DisplayOrder 0, the
-- backdrop at 1, and every menu ScreenGui at MENU_DISPLAY_ORDER or higher so
-- it renders (and receives input) above the backdrop
local BACKDROP_DISPLAY_ORDER = 1
ClientOverlayManager.MENU_DISPLAY_ORDER = 5
local ZOOM_TWEEN_SEC = 0.15
local OVERLAY_FOV = 65
local DEFAULT_FOV = 70

local function tweenCameraFov(fov: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local tweenInfo = TweenInfo.new(ZOOM_TWEEN_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	TweenService:Create(camera, tweenInfo, { FieldOfView = fov }):Play()
end

function ClientOverlayManager:isOverlayActive(): boolean
	return self.overlay ~= nil
end

function ClientOverlayManager:addOverlayNotifier(overlayNotifier: OverlayNotifier)
	table.insert(self.notifiers, overlayNotifier)
end

function ClientOverlayManager:closeOverlayIfExists()
	local overlay = self.overlay
	if overlay then
		overlay:notifyForceEnd()
		self:endOverlayEffects()
		self.overlay = nil
	end
end

-- while the loading screen is up, menus that open during startup are held
-- back and replayed (in order, so the last one wins as usual) once it hides
function ClientOverlayManager:setDeferOverlays(isDeferring: boolean)
	self.isDeferring = isDeferring
	if isDeferring then
		return
	end
	local deferred = self.deferredOverlays
	self.deferredOverlays = {}
	for _, overlay in deferred do
		self:notifyBeginOverlay(overlay)
	end
end

function ClientOverlayManager:notifyBeginOverlay(overlay: Overlay)
	if self.isDeferring then
		table.insert(self.deferredOverlays, overlay)
		return
	end
	self:closeOverlayIfExists()
	self.overlay = overlay
	-- the backdrop absorbs clicks everywhere but the dialog; the root Frame
	-- must be Active so clicks on the dialog body stop there instead of
	-- reaching the backdrop and closing the overlay
	local guiRoot = overlay:getGuiRoot()
	if guiRoot then
		guiRoot.Active = true
	end

	local doesWantBlurMethod = overlay.doesWantBlur
	local doesWantBlur = if doesWantBlurMethod then doesWantBlurMethod(overlay) else true
	local blur = self.blur
	if blur then
		blur.Enabled = doesWantBlur
	end

	local doAllowWorldActionsMethod = overlay.doAllowPlayerWorldActions
	local doAllowWorldActions = if doAllowWorldActionsMethod then doAllowWorldActionsMethod(overlay) else false
	local backdropGui = self.backdropGui
	if backdropGui then
		backdropGui.Enabled = not doAllowWorldActions
	end
	if not doAllowWorldActions then
		local character = Players.LocalPlayer.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = true
			self.anchoredRootPart = rootPart
		end
	end

	local doZoomCameraMethod = overlay.doZoomCamera
	local doZoomCamera = if doZoomCameraMethod then doZoomCameraMethod(overlay) else true
	if doZoomCamera then
		tweenCameraFov(OVERLAY_FOV)
	end

	for _, overlayNotifier in self.notifiers do
		overlayNotifier:notifyBeginOverlay()
	end

	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Gamepad1 or lastInput == Enum.UserInputType.Gamepad2 then
		if guiRoot then
			GuiService:Select(guiRoot)
		end
	end
end

function ClientOverlayManager:endOverlayEffects()
	local blur = self.blur
	if blur then
		blur.Enabled = false
	end

	local backdropGui = self.backdropGui
	if backdropGui then
		backdropGui.Enabled = false
	end

	local anchoredRootPart = self.anchoredRootPart
	if anchoredRootPart then
		anchoredRootPart.Anchored = false
		self.anchoredRootPart = nil
	end

	tweenCameraFov(DEFAULT_FOV)

	for _, overlayNotifier in self.notifiers do
		overlayNotifier:notifyEndOverlay()
	end
end

function ClientOverlayManager:notifyEndOverlay(overlay: Overlay)
	local deferredIndex = table.find(self.deferredOverlays, overlay)
	if deferredIndex then
		table.remove(self.deferredOverlays, deferredIndex)
		return
	end
	if self.overlay ~= overlay then
		warn("ClientOverlayManager: notifyEndOverlay for an overlay that is not active")
		return
	end
	self.overlay = nil
	self:endOverlayEffects()
end

function ClientOverlayManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local overlay = self.overlay
	if not overlay then
		return
	end
	local guiRoot = overlay:getGuiRoot()
	-- a nil root means the overlay handles its own outside-click detection
	if not guiRoot then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local guiObjects = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
	local isClickOnOverlay = false
	for _, guiObject in guiObjects do
		if guiObject:IsDescendantOf(guiRoot) then
			isClickOnOverlay = true
			break
		end
	end
	if not isClickOnOverlay then
		overlay:notifyClickOutside()
	end
end

function ClientOverlayManager:onBackdropActivated()
	local overlay = self.overlay
	if overlay then
		overlay:notifyClickOutside()
	end
end

function ClientOverlayManager:init()
	local blur = Instance.new("BlurEffect")
	blur.Size = BLUR_SIZE
	blur.Enabled = false
	blur.Parent = Lighting
	self.blur = blur

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local backdropGui = Instance.new("ScreenGui")
	backdropGui.Name = "OverlayBackdrop"
	backdropGui.ResetOnSpawn = false
	backdropGui.IgnoreGuiInset = true
	backdropGui.DisplayOrder = BACKDROP_DISPLAY_ORDER
	backdropGui.Enabled = false
	-- a TextButton rather than a Frame: it both sinks input (so world click
	-- handlers see it as gameProcessed) and reports the click-outside
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Selectable = false
	backdrop.Active = true
	backdrop.Parent = backdropGui
	backdrop.Activated:Connect(
		function()
			self:onBackdropActivated()
		end
	)
	backdropGui.Parent = playerGui
	self.backdropGui = backdropGui

	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
end

function ClientOverlayManager.new(): ClientOverlayManager
	local self = setmetatable({}, ClientOverlayManager) :: ClientOverlayManager
	self.overlay = nil
	self.isDeferring = false
	self.deferredOverlays = {}
	self.notifiers = {}
	self.blur = nil
	self.backdropGui = nil
	self.anchoredRootPart = nil
	return self
end

return ClientOverlayManager.new()
