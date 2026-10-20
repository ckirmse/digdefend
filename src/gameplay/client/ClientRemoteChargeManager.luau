--!strict

-- The Remote Charge as the client sees it (2026-10-20, reshaped the same
-- day to place like the Auto Turret). While the GADGET tool is equipped
-- and the class's gadget is the charge, the mine is in hand and its ghost
-- (ClientGadgetGhost, the turret's rules) hangs ahead of the player;
-- the use input asks the server to plant it there
-- (TryPlaceRemoteCharge), a red ghost refusing locally. Once this
-- player's charge is planted the server swaps the hand to the detonator
-- (the GadgetVariant attribute) and the ghost goes; the use input then
-- blows it (TryDetonateRemoteCharge). A mine still cooling down
-- (RemoteChargeReadyTime) is refused here with the fail sound and a line.
-- For every planted charge (a Tags.REMOTE_CHARGE shadow) the mine's
-- model is cloned onto it from GameAssets/Gadgets and its Light part
-- breathes: colour red to black and its light's brightness to nothing
-- over two seconds, then back, looped (designer, 2026-10-20). A
-- detonation (NotifyRemoteChargeDetonated) bursts the Rocket Launcher's
-- blast and sound at every position; the pool of fire it leaves arrives
-- as the posts' own pool notify and is drawn by ClientPostManager.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientGadgetGhost = require(script.Parent.ClientGadgetGhost)
local ClientProjectileManager = require(script.Parent.ClientProjectileManager)

local ClientRemoteChargeManager = {}
ClientRemoteChargeManager.__index = ClientRemoteChargeManager

type ChargeView = {
	shadow: BasePart,
	model: Model,
	tweens: { Tween },
}

export type ClientRemoteChargeManager = typeof(setmetatable(
	{} :: {
		template: Model?,
		viewsByShadow: { [BasePart]: ChargeView },
		ghost: ClientGadgetGhost.ClientGadgetGhost?,
		-- the GADGET tool is equipped and the class's gadget is the charge
		isActive: boolean,
		-- the hand holds the detonator: this player's charge is planted
		isDetonatorHeld: boolean,
		bodiesFolder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientRemoteChargeManager
))

local NOTIFY_REMOTE_CHARGE_DETONATED_SHAPE = {
	positions = { type = "array", elementType = "vector3" },
	radius = "positiveNumber",
}

local BODIES_FOLDER = "RemoteChargeBodies"
local BLAST_TEMPLATE = "RocketBlast"
local BLAST_FULL_VOLUME_STUDS = 200
local BLAST_SILENT_STUDS = 800
-- the mine's model lies flat with its face up and has no front of its
-- own, so it takes the base's forward as it is
local MODEL_YAW_OFFSET_DEGREES = 0
-- the planted mine's breath (designer, 2026-10-20): the Light part from
-- red to black and its light's brightness to nothing over this long,
-- then back, for as long as it stands
local BLINK_SEC = 2
local LIGHT_ON_COLOR = Color3.fromRGB(255, 0, 0)
local LIGHT_OFF_COLOR = Color3.fromRGB(0, 0, 0)
local LIGHT_ON_BRIGHTNESS = 1
local FEEDBACK_COOLING = "Next charge in %d s"
local FEEDBACK_CANNOT_BUILD = "Can't build here"
local FEEDBACK_DISPLAY_SEC = 2

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientRemoteChargeManager:getBodiesFolder(): Folder
	local folder = self.bodiesFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = BODIES_FOLDER
	folder.Parent = workspace
	self.bodiesFolder = folder
	return folder
end

function ClientRemoteChargeManager:findTemplate(): Model?
	if self.template then
		return self.template
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local gadgets = if gameAssets then gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER) else nil
	local template = if gadgets then gadgets:FindFirstChild(Constants.REMOTE_CHARGE_TEMPLATE) else nil
	if template and template:IsA("Model") then
		self.template = template
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientRemoteChargeManager: no GameAssets.{Constants.GADGET_TEMPLATES_FOLDER}.{Constants.REMOTE_CHARGE_TEMPLATE}; run scripts/studio/build_remote_charge_template.luau`)
	end
	return nil
end

-- the Light part and its light breathe together, looped and reversed
function ClientRemoteChargeManager:startBreath(model: Model): { Tween }
	local tweens = {}
	local light = model:FindFirstChild(Constants.REMOTE_CHARGE_LIGHT_PART, true)
	if not light or not light:IsA("BasePart") then
		return tweens
	end
	local info = TweenInfo.new(BLINK_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
	light.Color = LIGHT_ON_COLOR
	table.insert(tweens, TweenService:Create(light, info, { Color = LIGHT_OFF_COLOR }))
	for _, child in light:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = true
			child.Brightness = LIGHT_ON_BRIGHTNESS
			table.insert(tweens, TweenService:Create(child, info, { Brightness = 0 }))
		end
	end
	for _, tween in tweens do
		tween:Play()
	end
	return tweens
end

-- the mine's model stood on the shadow's ground point, turned its way
function ClientRemoteChargeManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.viewsByShadow[shadow] then
		return
	end
	local template = self:findTemplate()
	if not template then
		return
	end
	local model = ClientGadgetGhost.buildModel(template, shadow.Name)
	local base = shadow.CFrame * CFrame.new(0, -shadow.Size.Y / 2, 0)
	ClientGadgetGhost.poseModel(model, base, MODEL_YAW_OFFSET_DEGREES)
	model.Parent = self:getBodiesFolder()
	self.viewsByShadow[shadow] = {
		shadow = shadow,
		model = model,
		tweens = self:startBreath(model),
	}
	-- the owner's own planting rings like a tower going up (decided
	-- 2026-10-20); the shadow's arrival is the server's confirmation
	if readNumber(shadow:GetAttribute(Attributes.REMOTE_CHARGE_OWNER_USER_ID), 0) == Players.LocalPlayer.UserId then
		ClientSoundManager:playSfx(SoundNames.Sfx.PLACEMENT_BUILD)
	end
end

function ClientRemoteChargeManager:untrack(shadow: Instance)
	local view = self.viewsByShadow[shadow :: BasePart]
	if not view then
		return
	end
	self.viewsByShadow[shadow :: BasePart] = nil
	for _, tween in view.tweens do
		tween:Cancel()
	end
	view.model:Destroy()
end

-- the ghost exists only while the mine itself is the tool in hand
function ClientRemoteChargeManager:setGhostVisible(isVisible: boolean)
	local ghost = self.ghost
	if not isVisible then
		if ghost then
			ghost:destroy()
			self.ghost = nil
		end
		return
	end
	if ghost then
		return
	end
	local template = self:findTemplate()
	if not template then
		return
	end
	ghost = ClientGadgetGhost.new(template, self:getBodiesFolder(), MODEL_YAW_OFFSET_DEGREES)
	ghost:setVisible(true)
	self.ghost = ghost
end

-- the use input: the detonator blows the planted charge; the mine is
-- planted where the ghost stands, or the ghost says why not
function ClientRemoteChargeManager:use()
	if not self.isActive or ClientOverlayManager:isOverlayActive() then
		return
	end
	if self.isDetonatorHeld then
		-- the beep is the button going down, the user's own
		ClientSoundManager:playSfx(SoundNames.Sfx.REMOTE_CHARGE_DETONATE)
		ClientNetManager:fireServer(NetEventNames.TRY_DETONATE_REMOTE_CHARGE, {})
		return
	end
	local cooldownLeft = self:getCooldownLeft()
	if cooldownLeft > 0 then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)), FEEDBACK_DISPLAY_SEC)
		return
	end
	local ghost = self.ghost
	local position = if ghost then ghost.position else nil
	if not ghost or not ghost.isValid or not position then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_CANNOT_BUILD, FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(
		NetEventNames.TRY_PLACE_REMOTE_CHARGE,
		{
			position = position,
			yawDegrees = ghost.yawDegrees,
		}
	)
end

function ClientRemoteChargeManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not isUseInput(input) then
		return
	end
	self:use()
end

function ClientRemoteChargeManager:onRenderStep()
	local ghost = self.ghost
	if ghost then
		ghost:update()
	elseif self.isActive and not self.isDetonatorHeld and self:getCooldownLeft() <= 0 then
		-- the cooldown ran out with the slot already in hand: the ghost comes back
		self:setGhostVisible(true)
	end
end

function ClientRemoteChargeManager:onDetonated(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_REMOTE_CHARGE_DETONATED_SHAPE) then
		warn("ClientRemoteChargeManager: malformed NotifyRemoteChargeDetonated")
		return
	end
	for _, position in payload.positions do
		ClientProjectileManager:playBlast(position, BLAST_TEMPLATE)
		ClientSoundManager:playSfxAt(position, SoundNames.Sfx.ROCKET_LAUNCHER_EXPLODE, BLAST_FULL_VOLUME_STUDS, BLAST_SILENT_STUDS)
	end
end

-- seconds until the next mine is in hand; 0 when it is
function ClientRemoteChargeManager:getCooldownLeft(): number
	local readyTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.REMOTE_CHARGE_READY_TIME)
	return if typeof(readyTime) == "number" then math.max(0, readyTime - workspace:GetServerTimeNow()) else 0
end

-- active while the GADGET tool is in hand and the class's gadget is the
-- charge; the ghost only while the hand holds a ready mine, not the
-- detonator and not one still cooling
function ClientRemoteChargeManager:refreshActive()
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	self.isActive = equipped == Enums.ToolKind.GADGET and gadgetKind == Enums.GadgetKind.REMOTE_CHARGE
	self.isDetonatorHeld = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_VARIANT) == Constants.REMOTE_CHARGE_DETONATOR_VARIANT
	self:setGhostVisible(self.isActive and not self.isDetonatorHeld and self:getCooldownLeft() <= 0)
end

function ClientRemoteChargeManager:init()
	for _, shadow in CollectionService:GetTagged(Tags.REMOTE_CHARGE) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.REMOTE_CHARGE):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.REMOTE_CHARGE):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_REMOTE_CHARGE_DETONATED,
		function(payload: any)
			self:onDetonated(payload)
		end
	)
	self:refreshActive()
	for _, attribute in { Attributes.EQUIPPED_TOOL, Attributes.GADGET_KIND, Attributes.GADGET_VARIANT, Attributes.REMOTE_CHARGE_READY_TIME } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function(_value: any)
				self:refreshActive()
			end
		)
	end
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	RunService.RenderStepped:Connect(
		function(_deltaTime: number)
			self:onRenderStep()
		end
	)
end

function ClientRemoteChargeManager.new(): ClientRemoteChargeManager
	local self = setmetatable({}, ClientRemoteChargeManager) :: ClientRemoteChargeManager
	self.template = nil
	self.viewsByShadow = {}
	self.ghost = nil
	self.isActive = false
	self.isDetonatorHeld = false
	self.bodiesFolder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientRemoteChargeManager.new()
