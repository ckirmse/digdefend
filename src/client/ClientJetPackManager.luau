--!strict

-- The jet pack on this client (GDD "Jet Pack"). One gesture on every
-- device: jump, press Jump again, and keep holding it. Keyboard and gamepad
-- judge the second press by time (a double tap); touch judges it by the
-- character being in the air when Roblox's jump button is pressed (designer,
-- 2026-11-11; a JET button above the jump button before). Pressing asks the
-- server to start burning,
-- releasing asks it to stop; the server owns the fuel and may cut out first.
-- While the public burning flag is on for the local player, this client
-- lifts its own character straight up (it owns its character's physics) at
-- the climb speed from GameMetadata. The fuel bar sits under the backpack
-- button and is always shown (decided 2026-09-15). Every character wears
-- the pack model on its back with its exhaust effects on while its flag is on.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Wearables = require("@game/ReplicatedStorage/Shared/Wearables")
local ClientDataManager = require(script.Parent.ClientDataManager)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientOverlayManager = require(script.Parent.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.ClientSoundManager)

local ClientJetPackManager = {}
ClientJetPackManager.__index = ClientJetPackManager

type Worn = {
	model: Model,
	-- the exhaust: every effect and light under the pack's attachments
	effects: { Instance },
	level: number,
}

export type ClientJetPackManager = typeof(setmetatable(
	{} :: {
		isBurningByUserId: { [number]: boolean },
		levelByUserId: { [number]: number },
		wornByUserId: { [number]: Worn },
		isRequestingBurn: boolean,
		lastJumpPressTime: number,
		jumpTouch: InputObject?,
		climbSpeed: number,
		fuelSec: number,
		fuelMaxSec: number,
		isLocked: boolean,
		bar: GuiObject?,
		fill: GuiObject?,
		thrustConnection: RBXScriptConnection?,
		hasWarnedTemplate: boolean,
	},
	ClientJetPackManager
))

local DOUBLE_TAP_SEC = 0.35
local JUMP_BUTTON_WAIT_SEC = 10
local DEFAULT_CLIMB_SPEED = 22
local WORN_MODEL_NAME = Constants.WORN_JET_PACK_MODEL
local BASE_LEVEL = 1

local function isJumpInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA
end

local function isExhaustEffect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
end

-- the artist hangs the exhaust (particles, smoke, a light) from attachments
-- on the pack's mesh (2026-11-13; a neon Flame part before); anything
-- under any attachment of the pack is switched with the burn, so a new
-- effect needs no code
local function findExhaustEffects(model: Model): { Instance }
	local effects: { Instance } = {}
	for _, descendant in model:GetDescendants() do
		if isExhaustEffect(descendant) and descendant:FindFirstAncestorWhichIsA("Attachment") then
			table.insert(effects, descendant)
		end
	end
	return effects
end

function ClientJetPackManager:requestStart()
	if self.isRequestingBurn then
		return
	end
	self.isRequestingBurn = true
	ClientNetManager:fireServer(NetEventNames.TRY_JET_PACK_START, {})
end

function ClientJetPackManager:requestStop()
	if not self.isRequestingBurn then
		return
	end
	self.isRequestingBurn = false
	ClientNetManager:fireServer(NetEventNames.TRY_JET_PACK_STOP, {})
end

function ClientJetPackManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not isJumpInput(input) or ClientOverlayManager:isOverlayActive() then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - self.lastJumpPressTime <= DOUBLE_TAP_SEC then
		self:requestStart()
	end
	self.lastJumpPressTime = now
end

function ClientJetPackManager:onInputEnded(input: InputObject)
	if isJumpInput(input) then
		self:requestStop()
	elseif input == self.jumpTouch then
		self.jumpTouch = nil
		self:requestStop()
	end
end

-- Jumping and Freefall only: a seated rider is off the floor too, and a tap
-- there must not light the pack
function ClientJetPackManager:isAirborne(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return false
	end
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
end

-- the press that starts a jump arrives while the character still stands, so
-- only a press made in the air reaches the pack; the finger is remembered
-- because it can lift anywhere on the screen, not only over the button
function ClientJetPackManager:onJumpButtonPressed(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch or input.UserInputState ~= Enum.UserInputState.Begin then
		return
	end
	if self.jumpTouch or ClientOverlayManager:isOverlayActive() or not self:isAirborne() then
		return
	end
	self.jumpTouch = input
	self:requestStart()
end

function ClientJetPackManager:connectJumpButton(button: Instance)
	if button.Name ~= Constants.TOUCH_JUMP_BUTTON_NAME or not button:IsA("GuiObject") then
		return
	end
	button.InputBegan:Connect(
		function(input: InputObject)
			self:onJumpButtonPressed(input)
		end
	)
end

function ClientJetPackManager:watchJumpButton()
	if not UserInputService.TouchEnabled then
		return
	end
	-- the touch gui is built by Roblox's PlayerModule shortly after spawn
	task.spawn(
		function()
			local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
			local touchGui = playerGui:WaitForChild(Constants.TOUCH_GUI_NAME, JUMP_BUTTON_WAIT_SEC)
			local frame = if touchGui then touchGui:WaitForChild(Constants.TOUCH_CONTROL_FRAME_NAME, JUMP_BUTTON_WAIT_SEC) else nil
			if not frame then
				warn("ClientJetPackManager: no TouchGui control frame found; the jet pack has no touch control")
				return
			end
			-- Roblox may build the button late or build it again
			frame.ChildAdded:Connect(
				function(child: Instance)
					self:connectJumpButton(child)
				end
			)
			for _, child in frame:GetChildren() do
				self:connectJumpButton(child)
			end
		end
	)
end

-- own character only: hold the vertical speed at the climb speed while
-- burning; the walk controls keep steering sideways
function ClientJetPackManager:thrust()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, self.climbSpeed, velocity.Z)
end

function ClientJetPackManager:setThrusting(isThrusting: boolean)
	if isThrusting and not self.thrustConnection then
		self.thrustConnection = RunService.Heartbeat:Connect(
			function()
				self:thrust()
			end
		)
	elseif not isThrusting and self.thrustConnection then
		self.thrustConnection:Disconnect()
		self.thrustConnection = nil
	end
	self:renderBar()
end

function ClientJetPackManager:renderBar()
	local bar = self.bar
	local fill = self.fill
	if not bar or not fill then
		return
	end
	local fraction = if self.fuelMaxSec > 0 then math.clamp(self.fuelSec / self.fuelMaxSec, 0, 1) else 0
	fill.Size = UDim2.fromScale(fraction, 1)
	-- green while the pack answers, red while it is locked and refilling to full
	fill.BackgroundColor3 = if self.isLocked then UiStyle.NEGATIVE_COLOR else UiStyle.POSITIVE_COLOR
end

function ClientJetPackManager:readFuel()
	local fuel = ClientDataManager:getCurrentPlayerAttribute(Attributes.JET_PACK_FUEL_SEC)
	local max = ClientDataManager:getCurrentPlayerAttribute(Attributes.JET_PACK_FUEL_MAX_SEC)
	self.fuelSec = if typeof(fuel) == "number" then fuel else 0
	self.fuelMaxSec = if typeof(max) == "number" then max else 0
	local isLocked = ClientDataManager:getCurrentPlayerAttribute(Attributes.IS_JET_PACK_LOCKED) == true
	-- the tank just ran dry
	if isLocked and not self.isLocked then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
	end
	self.isLocked = isLocked
	self:renderBar()
end

-- the pack of this level, else the base pack, so a level with no art yet
-- still shows something
function ClientJetPackManager:getTemplate(level: number): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local wearables = if gameAssets then gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER) else nil
	for _, candidateLevel in { level, BASE_LEVEL } do
		local template = if wearables then wearables:FindFirstChild(Wearables.jetPackTemplateName(candidateLevel)) else nil
		if template and template:IsA("Model") and template:FindFirstChild(Constants.TOOL_HANDLE_PART) then
			return template
		end
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientJetPackManager: no Model with a {Constants.TOOL_HANDLE_PART} at GameAssets.{Constants.WEARABLE_TEMPLATES_FOLDER}.{Wearables.jetPackTemplateName(BASE_LEVEL)}; run scripts/studio/build_wearable_templates.luau`)
	end
	return nil
end

function ClientJetPackManager:removeWorn(userId: number)
	local worn = self.wornByUserId[userId]
	if worn then
		worn.model:Destroy()
		self.wornByUserId[userId] = nil
	end
end

function ClientJetPackManager:wear(userId: number, character: Model)
	local level = self.levelByUserId[userId] or BASE_LEVEL
	local template = self:getTemplate(level)
	if not template then
		return
	end
	self:removeWorn(userId)
	-- a Roblox backpack would sit inside the pack; it comes off on this
	-- client's view (the lobby strips it on the server, 2026-10-12)
	Wearables.removeBackAccessories(character)
	local model = Wearables.wearOnBack(character, template, WORN_MODEL_NAME)
	if not model then
		return
	end
	self.wornByUserId[userId] = {
		model = model,
		effects = findExhaustEffects(model),
		level = level,
	}
	self:renderExhaust(userId)
end

function ClientJetPackManager:renderExhaust(userId: number)
	local worn = self.wornByUserId[userId]
	if not worn then
		return
	end
	local isBurning = self.isBurningByUserId[userId] == true
	for _, effect in worn.effects do
		-- every class isExhaustEffect lets through has Enabled
		(effect :: any).Enabled = isBurning
	end
end

function ClientJetPackManager:refresh(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local worn = self.wornByUserId[userId]
	-- a new character, or an upgrade bought at the store: the old pack comes off
	local level = self.levelByUserId[userId] or BASE_LEVEL
	if worn and (worn.model.Parent ~= character or worn.level ~= level) then
		self:removeWorn(userId)
		worn = nil
	end
	if character and not worn then
		self:wear(userId, character)
	end
	self:renderExhaust(userId)
	if userId == Players.LocalPlayer.UserId then
		self:setThrusting(self.isBurningByUserId[userId] == true)
	end
end

function ClientJetPackManager:watchCharacter(player: Player)
	player.CharacterAdded:Connect(
		function(character: Model)
			character:WaitForChild("Humanoid", 5)
			task.defer(
				function()
					self:refresh(player.UserId)
				end
			)
		end
	)
end

function ClientJetPackManager:findHud()
	-- the pack works in both places since 2026-10-12: the gameplay HUD
	-- carries the fuel bar in a run, the lobby HUD in the lobby
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(Constants.GAMEPLAY_HUD_GUI_NAME) or playerGui:WaitForChild(Constants.HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		return
	end
	local bar = gui:FindFirstChild(Constants.HUD_JET_PACK_BAR, true)
	if bar and bar:IsA("GuiObject") then
		self.bar = bar
		local icon = bar:FindFirstChild(Constants.HUD_JET_PACK_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = if Icons.isPlaceholder(Icons.UI.JET_PACK) then "" else Icons.UI.JET_PACK
		end
		local track = bar:FindFirstChild(Constants.HUD_JET_PACK_TRACK)
		local fill = if track then track:FindFirstChild(Constants.HUD_JET_PACK_FILL) else nil
		self.fill = if fill and fill:IsA("GuiObject") then fill else nil
	else
		warn(`ClientJetPackManager: {gui.Name} is missing JetPackBar; rerun its build script`)
	end
end

function ClientJetPackManager:readTuning()
	local speed = ClientDataManager:getGameMetadata(Attributes.JET_PACK_CLIMB_SPEED)
	self.climbSpeed = if typeof(speed) == "number" then speed else DEFAULT_CLIMB_SPEED
end

function ClientJetPackManager:init()
	self:findHud()
	self:watchJumpButton()
	self:readTuning()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.JET_PACK_CLIMB_SPEED,
		function()
			self:readTuning()
		end
	)
	self:readFuel()
	for _, key in { Attributes.JET_PACK_FUEL_SEC, Attributes.JET_PACK_FUEL_MAX_SEC, Attributes.IS_JET_PACK_LOCKED } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:readFuel()
			end
		)
	end
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	UserInputService.InputEnded:Connect(
		function(input: InputObject)
			self:onInputEnded(input)
		end
	)
	for _, player in Players:GetPlayers() do
		self:watchCharacter(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchCharacter(player)
		end
	)
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			self.isBurningByUserId[userId] = data.isJetPackBurning
			self.levelByUserId[userId] = data.jetPackLevel
			self:refresh(userId)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			self.isBurningByUserId[userId] = data.isJetPackBurning
			self.levelByUserId[userId] = data.jetPackLevel
			self:refresh(userId)
		end,
		onRemoved = function(userId: number)
			self.isBurningByUserId[userId] = nil
			self.levelByUserId[userId] = nil
			self:removeWorn(userId)
		end,
	})
end

function ClientJetPackManager.new(): ClientJetPackManager
	local self = setmetatable({}, ClientJetPackManager) :: ClientJetPackManager
	self.isBurningByUserId = {}
	self.levelByUserId = {}
	self.wornByUserId = {}
	self.isRequestingBurn = false
	self.lastJumpPressTime = 0
	self.jumpTouch = nil
	self.climbSpeed = DEFAULT_CLIMB_SPEED
	self.fuelSec = 0
	self.fuelMaxSec = 0
	self.isLocked = false
	self.bar = nil
	self.fill = nil
	self.thrustConnection = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientJetPackManager.new()
