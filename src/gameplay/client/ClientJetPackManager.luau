--!strict

-- The jet pack on this client (GDD "Jet Pack"). One gesture: on keyboard and
-- gamepad, double-tap Jump and keep holding it; on touch, hold the Jet Pack
-- button above the jump button. Pressing asks the server to start burning,
-- releasing asks it to stop; the server owns the fuel and may cut out first.
-- While the public burning flag is on for the local player, this client
-- lifts its own character straight up (it owns its character's physics) at
-- the climb speed from GameMetadata. The fuel bar sits under the backpack
-- button and is always shown (decided 2026-09-15). Every character wears
-- the pack model on its back with the flame lit while its flag is on.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientJetPackManager = {}
ClientJetPackManager.__index = ClientJetPackManager

type Worn = {
	model: Model,
	flame: BasePart?,
}

export type ClientJetPackManager = typeof(setmetatable(
	{} :: {
		isBurningByUserId: { [number]: boolean },
		wornByUserId: { [number]: Worn },
		isRequestingBurn: boolean,
		lastJumpPressTime: number,
		climbSpeed: number,
		fuelSec: number,
		fuelMaxSec: number,
		isLocked: boolean,
		bar: GuiObject?,
		fill: GuiObject?,
		button: GuiButton?,
		thrustConnection: RBXScriptConnection?,
		hasWarnedTemplate: boolean,
	},
	ClientJetPackManager
))

local DOUBLE_TAP_SEC = 0.35
local DEFAULT_CLIMB_SPEED = 22
local WORN_MODEL_NAME = "WornJetPack"

local function isJumpInput(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA
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
	end
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

function ClientJetPackManager:getTemplate(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local wearables = if gameAssets then gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER) else nil
	local template = if wearables then wearables:FindFirstChild(Constants.JET_PACK_TEMPLATE) else nil
	if template and template:IsA("Model") and template:FindFirstChild(Constants.TOOL_HANDLE_PART) then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientJetPackManager: no Model with a {Constants.TOOL_HANDLE_PART} at GameAssets.{Constants.WEARABLE_TEMPLATES_FOLDER}.{Constants.JET_PACK_TEMPLATE}; run scripts/studio/build_wearable_templates.luau`)
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
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local template = self:getTemplate()
	if not torso or not torso:IsA("BasePart") or not template then
		return
	end
	self:removeWorn(userId)
	local model = template:Clone()
	model.Name = WORN_MODEL_NAME
	local handle = model:FindFirstChild(Constants.TOOL_HANDLE_PART) :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local back = torso:FindFirstChild("BodyBackAttachment")
	local backCFrame = if back and back:IsA("Attachment") then back.CFrame else CFrame.new(0, 0, 0.6)
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = backCFrame * CFrame.new(0, 0, handle.Size.Z / 2)
	weld.Parent = handle
	model.Parent = character
	local flame = model:FindFirstChild(Constants.JET_PACK_FLAME_PART)
	self.wornByUserId[userId] = {
		model = model,
		flame = if flame and flame:IsA("BasePart") then flame else nil,
	}
	self:renderFlame(userId)
end

function ClientJetPackManager:renderFlame(userId: number)
	local worn = self.wornByUserId[userId]
	local flame = if worn then worn.flame else nil
	if flame then
		local isBurning = self.isBurningByUserId[userId] == true
		flame.Transparency = if isBurning then 0 else 1
		-- the flame's light goes with it, or the pack glows all day
		for _, light in flame:GetChildren() do
			if light:IsA("Light") then
				light.Enabled = isBurning
			end
		end
	end
end

function ClientJetPackManager:refresh(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local worn = self.wornByUserId[userId]
	if worn and worn.model.Parent ~= character then
		self:removeWorn(userId)
		worn = nil
	end
	if character and not worn then
		self:wear(userId, character)
	end
	self:renderFlame(userId)
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
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		return
	end
	local bar = gui:FindFirstChild(Constants.HUD_JET_PACK_BAR, true)
	if bar and bar:IsA("GuiObject") then
		self.bar = bar
		local track = bar:FindFirstChild(Constants.HUD_JET_PACK_TRACK)
		local fill = if track then track:FindFirstChild(Constants.HUD_JET_PACK_FILL) else nil
		self.fill = if fill and fill:IsA("GuiObject") then fill else nil
	else
		warn("ClientJetPackManager: GameplayHud is missing JetPackBar; run scripts/studio/build_gameplay_hud_gui.luau")
	end
	local button = gui:FindFirstChild(Constants.HUD_JET_PACK_BUTTON)
	if button and button:IsA("GuiButton") then
		self.button = button
		-- touch only: keyboard and gamepad players double-tap Jump instead
		button.Visible = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		button.MouseButton1Down:Connect(
			function()
				self:requestStart()
			end
		)
		button.MouseButton1Up:Connect(
			function()
				self:requestStop()
			end
		)
		button.MouseLeave:Connect(
			function()
				self:requestStop()
			end
		)
	end
end

function ClientJetPackManager:readTuning()
	local speed = ClientDataManager:getGameMetadata(Attributes.JET_PACK_CLIMB_SPEED)
	self.climbSpeed = if typeof(speed) == "number" then speed else DEFAULT_CLIMB_SPEED
end

function ClientJetPackManager:init()
	self:findHud()
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
			self:refresh(userId)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			self.isBurningByUserId[userId] = data.isJetPackBurning
			self:refresh(userId)
		end,
		onRemoved = function(userId: number)
			self.isBurningByUserId[userId] = nil
			self:removeWorn(userId)
		end,
	})
end

function ClientJetPackManager.new(): ClientJetPackManager
	local self = setmetatable({}, ClientJetPackManager) :: ClientJetPackManager
	self.isBurningByUserId = {}
	self.wornByUserId = {}
	self.isRequestingBurn = false
	self.lastJumpPressTime = 0
	self.climbSpeed = DEFAULT_CLIMB_SPEED
	self.fuelSec = 0
	self.fuelMaxSec = 0
	self.isLocked = false
	self.bar = nil
	self.fill = nil
	self.button = nil
	self.thrustConnection = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientJetPackManager.new()
