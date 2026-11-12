--!strict

-- One menu (overlay) at a time. A menu registers itself when it opens; this
-- manager blurs the world, puts a click-catching backdrop behind the dialog,
-- turns the player's movement controls off, nudges the camera, and tells
-- every notifier (the HUD) to slide away. Closing reverses all of it.
-- Copied from Lucky Squares. The controls go off rather than the root
-- part being anchored, which left a character who jumped into a store's
-- touch zone hanging in the air (designer, 2026-11-03): the body keeps
-- its physics and lands. UserInputService.ModalEnabled hides the touch
-- thumbstick and jump button (Roblox's own modal-menu switch), and a
-- ContextActionService sink above the default controls swallows keyboard
-- and gamepad movement and jump. The sink passes a release through, so a
-- key held as the menu opens stops the character instead of locking it
-- moving. (Roblox's PlayerModule is engine-side now, so there is no
-- Controls object to call Disable on.)
local ContextActionService = game:GetService("ContextActionService")
local GamepadService = game:GetService("GamepadService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local ClientOverlayManager = {}
ClientOverlayManager.__index = ClientOverlayManager

export type Overlay = {
	getGuiRoot: (self: Overlay) -> GuiObject?,
	notifyForceEnd: (self: Overlay) -> (),
	notifyClickOutside: (self: Overlay) -> (),
	-- a controller's B (Circle) with the menu up; a menu without it gets
	-- notifyClickOutside, so one that a stray click closes also closes on B
	notifyBack: ((self: Overlay) -> ())?,
	doesWantBlur: ((self: Overlay) -> boolean)?,
	doZoomCamera: ((self: Overlay) -> boolean)?,
	doAllowPlayerWorldActions: ((self: Overlay) -> boolean)?,
	-- false keeps the click-catching backdrop off while the controls still
	-- go off, for a menu whose clicks must reach the world (the Supply
	-- Crate's tap on the crate, 2026-11-03); the default is true
	doesWantBackdrop: ((self: Overlay) -> boolean)?,
	-- true asks the HUD notifiers to leave their balances on screen (the
	-- Supply Crate's purchase screen, designer 2026-11-03); the default
	-- is false, every HUD element sliding away
	doesKeepHud: ((self: Overlay) -> boolean)?,
}

-- a notifier is handed the overlay so it can read its asks
export type OverlayNotifier = {
	notifyBeginOverlay: (self: OverlayNotifier, overlay: Overlay) -> (),
	notifyEndOverlay: (self: OverlayNotifier, overlay: Overlay) -> (),
}

export type ClientOverlayManager = typeof(setmetatable(
	{} :: {
		overlay: Overlay?,
		isDeferring: boolean,
		deferredOverlays: { Overlay },
		notifiers: { OverlayNotifier },
		blur: BlurEffect?,
		blurTween: Tween?,
		backdropGui: ScreenGui?,
		isControlsDisabled: boolean,
		isGamepadCursorOn: boolean,
		idleGamepadButtonHandlers: { (keyCode: Enum.KeyCode) -> () },
	},
	ClientOverlayManager
))

local BLUR_SIZE = 12
-- ScreenGui layering contract: HUD ScreenGuis sit at DisplayOrder 0, the
-- backdrop at 1, and every menu ScreenGui at MENU_DISPLAY_ORDER or higher so
-- it renders (and receives input) above the backdrop
ClientOverlayManager.MENU_DISPLAY_ORDER = 5
local ZOOM_TWEEN_SEC = 0.15
local OVERLAY_FOV = 65
local DEFAULT_FOV = 70

-- the sink's action name and the inputs the default controls move and
-- jump from (touch is hidden through ModalEnabled instead)
local BACK_BUTTON = Enum.KeyCode.ButtonB
local MOVEMENT_SINK_ACTION ="OverlayMovementSink"
local MOVEMENT_INPUTS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.Thumbstick1,
}

local function sinkMovement(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	-- a release reaches the default controls so a held key lets go
	if inputState == Enum.UserInputState.End then
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local function tweenCameraFov(fov: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local tweenInfo = TweenInfo.new(ZOOM_TWEEN_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	TweenService:Create(camera, tweenInfo, { FieldOfView = fov }):Play()
end

function ClientOverlayManager:setControlsEnabled(isEnabled: boolean)
	if self.isControlsDisabled == not isEnabled then
		return
	end
	self.isControlsDisabled = not isEnabled
	-- a LocalScript may set ModalEnabled (that is what it is for); the
	-- analyzer's API types call it read-only, hence the cast
	local userInputService: any = UserInputService
	userInputService.ModalEnabled = not isEnabled
	if isEnabled then
		ContextActionService:UnbindAction(MOVEMENT_SINK_ACTION)
	else
		ContextActionService:BindActionAtPriority(
			MOVEMENT_SINK_ACTION,
			sinkMovement,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(MOVEMENT_INPUTS)
		)
	end
end

function ClientOverlayManager:isOverlayActive(): boolean
	return self.overlay ~= nil
end

function ClientOverlayManager:addOverlayNotifier(overlayNotifier: OverlayNotifier)
	table.insert(self.notifiers, overlayNotifier)
end

-- a controller button pressed while no menu is open
function ClientOverlayManager:subscribeIdleGamepadButton(handler: (keyCode: Enum.KeyCode) -> ())
	table.insert(self.idleGamepadButtonHandlers, handler)
end

function ClientOverlayManager:closeOverlayIfExists()
	local overlay = self.overlay
	if overlay then
		overlay:notifyForceEnd()
		self:endOverlayEffects(overlay)
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

-- blurFadeInSec eases the blur up from nothing over that long (the
-- Results Menu arriving at the end of the ride out, 2026-10-27); none
-- sets it at once
function ClientOverlayManager:notifyBeginOverlay(overlay: Overlay, blurFadeInSec: number?)
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
		local blurTween = self.blurTween
		if blurTween then
			blurTween:Cancel()
			self.blurTween = nil
		end
		blur.Enabled = doesWantBlur
		if doesWantBlur and blurFadeInSec and blurFadeInSec > 0 then
			blur.Size = 0
			local tween = TweenService:Create(blur, TweenInfo.new(blurFadeInSec, Enum.EasingStyle.Linear), { Size = BLUR_SIZE })
			self.blurTween = tween
			tween:Play()
		else
			blur.Size = BLUR_SIZE
		end
	end

	local doAllowWorldActionsMethod = overlay.doAllowPlayerWorldActions
	local doAllowWorldActions = if doAllowWorldActionsMethod then doAllowWorldActionsMethod(overlay) else false
	local doesWantBackdropMethod = overlay.doesWantBackdrop
	local doesWantBackdrop = if doesWantBackdropMethod then doesWantBackdropMethod(overlay) else true
	local backdropGui = self.backdropGui
	if backdropGui then
		backdropGui.Enabled = not doAllowWorldActions and doesWantBackdrop
	end
	if not doAllowWorldActions then
		self:setControlsEnabled(false)
	end

	local doZoomCameraMethod = overlay.doZoomCamera
	local doZoomCamera = if doZoomCameraMethod then doZoomCameraMethod(overlay) else true
	if doZoomCamera then
		tweenCameraFov(OVERLAY_FOV)
	end

	for _, overlayNotifier in self.notifiers do
		overlayNotifier:notifyBeginOverlay(overlay)
	end

	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Gamepad1 or lastInput == Enum.UserInputType.Gamepad2 then
		-- every menu gets Roblox's gamepad cursor (left stick moves, A
		-- clicks) on a controller (designer, 2026-11-11; the highlight
		-- stepped from button to button before, and felt worse). nil
		-- starts it at the screen's centre; the API types ask for an
		-- Instance, hence the cast
		self.isGamepadCursorOn = true
		GamepadService:EnableGamepadCursor(nil :: any)
	end
end

function ClientOverlayManager:endOverlayEffects(overlay: Overlay)
	local blur = self.blur
	if blur then
		blur.Enabled = false
	end

	local backdropGui = self.backdropGui
	if backdropGui then
		backdropGui.Enabled = false
	end

	self:setControlsEnabled(true)

	-- a gamepad's selection highlight belongs to the menu: left set, the
	-- sticks keep steering it round the HUD instead of the character
	-- (designer, 2026-11-11). The cursor comes down with every menu,
	-- whether or not this manager believes it put one up (a controller
	-- picked up mid-menu); Build Mode puts its own back the next frame
	self.isGamepadCursorOn = false
	GamepadService:DisableGamepadCursor()
	GuiService.SelectedObject = nil

	tweenCameraFov(DEFAULT_FOV)

	for _, overlayNotifier in self.notifiers do
		overlayNotifier:notifyEndOverlay(overlay)
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
	self:endOverlayEffects(overlay)
end

function ClientOverlayManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	-- B backs out of the open menu (designer, 2026-11-11). Asked before
	-- the processed check: with a button highlighted Roblox may count the
	-- press as its own
	local backOverlay = self.overlay
	if input.KeyCode == BACK_BUTTON and backOverlay then
		local notifyBack = backOverlay.notifyBack
		if notifyBack then
			notifyBack(backOverlay)
		else
			backOverlay:notifyClickOutside()
		end
		return
	end
	if isGameProcessed then
		return
	end
	-- with no menu up a controller's buttons are shortcuts (the lobby
	-- HUD's menus). Handed out from here, after the back press above, so
	-- the B that closes a menu can never also be the B that opens one
	if not backOverlay and not self.isDeferring and string.find(input.UserInputType.Name, "^Gamepad") then
		for _, handler in self.idleGamepadButtonHandlers do
			handler(input.KeyCode)
		end
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

	-- the backdrop is authored in StarterGui (build_overlay_backdrop_gui.luau):
	-- a TextButton rather than a Frame, so it both sinks input (world click
	-- handlers see it as gameProcessed) and reports the click-outside, and
	-- Modal so the first-person mouse is freed while a menu is up
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local backdropGui = playerGui:WaitForChild(Constants.OVERLAY_BACKDROP_GUI_NAME, 10)
	local backdrop = if backdropGui then backdropGui:FindFirstChild(Constants.OVERLAY_BACKDROP_BUTTON) else nil
	if backdropGui and backdropGui:IsA("ScreenGui") and backdrop and backdrop:IsA("GuiButton") then
		backdropGui.Enabled = false
		backdrop.Activated:Connect(
			function()
				self:onBackdropActivated()
			end
		)
		self.backdropGui = backdropGui
	else
		warn("ClientOverlayManager: no OverlayBackdrop ScreenGui; run scripts/studio/build_overlay_backdrop_gui.luau in this place")
	end

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
	self.blurTween = nil
	self.backdropGui = nil
	self.isControlsDisabled = false
	self.isGamepadCursorOn = false
	self.idleGamepadButtonHandlers = {}
	return self
end

return ClientOverlayManager.new()
