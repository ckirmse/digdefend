--!strict

-- The Flare as the client sees it (2026-10-20). While the GADGET tool is
-- equipped and the class's gadget is the flare, the use input (click,
-- tap, or the right trigger) asks the server to throw it (TryThrowFlare),
-- refused here with the fail sound and a line while the next is still
-- coming (GadgetReadyTime). A thrown stick (a Tags.FLARE_STICK part) is
-- dressed with the flare's model and, for the thrower, launched again at
-- the stamped velocity for its first frames, as the dynamite is. A lit
-- flare (a Tags.FLARE shadow) gets the model stood on its ground point
-- with Roblox's Fire and a light over it until the server takes it down.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientGadgetGhost = require(script.Parent.ClientGadgetGhost)

local ClientFlareManager = {}
ClientFlareManager.__index = ClientFlareManager

export type ClientFlareManager = typeof(setmetatable(
	{} :: {
		template: Model?,
		modelByShadow: { [BasePart]: Model },
		bodiesFolder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientFlareManager
))

local BODIES_FOLDER = "FlareBodies"
-- how long the thrower's client keeps pressing the launch velocity onto
-- its own stick after it appears (the ownership lands a few frames late)
local LAUNCH_HOLD_SEC = 0.3
-- the thrown stick is drawn this many times the physics body's length
local THROWN_SCALE = 1.5
-- the lit flare's fire and light
local FIRE_SIZE = 4
local FIRE_HEAT = 10
local FIRE_COLOR = Color3.fromRGB(255, 60, 60)
local FIRE_SECONDARY_COLOR = Color3.fromRGB(255, 180, 120)
local LIGHT_COLOR = Color3.fromRGB(255, 80, 80)
local LIGHT_RANGE = 30
local LIGHT_BRIGHTNESS = 3
local FEEDBACK_COOLING = "Next flare in %d s"
local FEEDBACK_DISPLAY_SEC = 2

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientFlareManager:getBodiesFolder(): Folder
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

function ClientFlareManager:findTemplate(): Model?
	if self.template then
		return self.template
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local gadgets = if gameAssets then gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER) else nil
	local template = if gadgets then gadgets:FindFirstChild(Constants.FLARE_TEMPLATE) else nil
	if template and template:IsA("Model") then
		self.template = template
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientFlareManager: no GameAssets.{Constants.GADGET_TEMPLATES_FOLDER}.{Constants.FLARE_TEMPLATE}; run scripts/studio/build_flare_template.luau`)
	end
	return nil
end

-- the thrown stick wears the model, welded on so it tumbles with it
function ClientFlareManager:dressStick(stick: BasePart)
	local template = self:findTemplate()
	if not template then
		return
	end
	local model = template:Clone()
	model.Name = "Look"
	local _, bounds = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * stick.Size.X * THROWN_SCALE / math.max(bounds.X, bounds.Y, bounds.Z))
	-- the stick is a cylinder along its X; the model stands along its Y
	model:PivotTo(stick.CFrame * CFrame.Angles(0, 0, -math.pi / 2))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = stick
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	model.Parent = stick
end

-- the thrower's own stick leaves at the stamped velocity, pressed on for
-- the first frames since this client simulates it and the server's own
-- set can be lost in the handover
function ClientFlareManager:launchOwnStick(stick: BasePart)
	local launchVelocity = stick:GetAttribute(Attributes.FLARE_LAUNCH_VELOCITY)
	if typeof(launchVelocity) ~= "Vector3" then
		return
	end
	local endTime = workspace:GetServerTimeNow() + LAUNCH_HOLD_SEC
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(
		function()
			if not stick.Parent or workspace:GetServerTimeNow() >= endTime then
				if connection then
					connection:Disconnect()
				end
				return
			end
			stick.AssemblyLinearVelocity = launchVelocity
		end
	)
end

function ClientFlareManager:onStickAdded(stick: Instance)
	if not stick:IsA("BasePart") then
		return
	end
	self:dressStick(stick)
	if stick:GetAttribute(Attributes.FLARE_THROWER_USER_ID) == Players.LocalPlayer.UserId then
		self:launchOwnStick(stick)
	end
end

-- a lit flare: the model stood on the shadow's ground point, burning
function ClientFlareManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.modelByShadow[shadow] then
		return
	end
	local template = self:findTemplate()
	if not template then
		return
	end
	local model = ClientGadgetGhost.buildModel(template, shadow.Name)
	local base = shadow.CFrame * CFrame.new(0, -shadow.Size.Y / 2, 0)
	ClientGadgetGhost.poseModel(model, base, 0)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if primary then
		local fire = Instance.new("Fire")
		fire.Size = FIRE_SIZE
		fire.Heat = FIRE_HEAT
		fire.Color = FIRE_COLOR
		fire.SecondaryColor = FIRE_SECONDARY_COLOR
		fire.Parent = primary
		local light = Instance.new("PointLight")
		light.Color = LIGHT_COLOR
		light.Range = LIGHT_RANGE
		light.Brightness = LIGHT_BRIGHTNESS
		light.Parent = primary
	end
	model.Parent = self:getBodiesFolder()
	self.modelByShadow[shadow] = model
end

function ClientFlareManager:untrack(shadow: Instance)
	local model = self.modelByShadow[shadow :: BasePart]
	if not model then
		return
	end
	self.modelByShadow[shadow :: BasePart] = nil
	model:Destroy()
end

function ClientFlareManager:isActive(): boolean
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	return equipped == Enums.ToolKind.GADGET and gadgetKind == Enums.GadgetKind.FLARE
end

function ClientFlareManager:getCooldownLeft(): number
	local readyTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_READY_TIME)
	return if typeof(readyTime) == "number" then math.max(0, readyTime - workspace:GetServerTimeNow()) else 0
end

function ClientFlareManager:use()
	local cooldownLeft = self:getCooldownLeft()
	if cooldownLeft > 0 then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)), FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_THROW_FLARE, {})
end

function ClientFlareManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() or not isUseInput(input) or not self:isActive() then
		return
	end
	self:use()
end

function ClientFlareManager:init()
	for _, stick in CollectionService:GetTagged(Tags.FLARE_STICK) do
		self:onStickAdded(stick)
	end
	CollectionService:GetInstanceAddedSignal(Tags.FLARE_STICK):Connect(
		function(stick: Instance)
			self:onStickAdded(stick)
		end
	)
	for _, shadow in CollectionService:GetTagged(Tags.FLARE) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.FLARE):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.FLARE):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
end

function ClientFlareManager.new(): ClientFlareManager
	local self = setmetatable({}, ClientFlareManager) :: ClientFlareManager
	self.template = nil
	self.modelByShadow = {}
	self.bodiesFolder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientFlareManager.new()
