--!strict

-- The Flare as the client sees it (2026-10-20; a flare gun since
-- 2026-10-21). While the GADGET tool is equipped and the class's gadget
-- is the flare, the use input (click, tap, or the right trigger) asks the
-- server to fire one (TryFireFlare: the held gun's Muzzle attachment as
-- the origin, the camera's look as the direction), refused here with the
-- fail sound and a line while the next is still coming (GadgetReadyTime);
-- a sent shot pulses the gun's muzzle flash and smoke and plays the shot
-- for the gunner. The flare in flight is a projectile drawn by
-- ClientProjectileManager from the launch notification, trail and light
-- authored on its template. A lit flare (a Tags.FLARE shadow) gets the
-- model stood on its ground point with Roblox's Fire and a light over it
-- until the server takes it down.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientGadgetGhost = require(script.Parent.ClientGadgetGhost)
local ClientViewModelManager = require(script.Parent.ClientViewModelManager)

local ClientFlareManager = {}
ClientFlareManager.__index = ClientFlareManager

export type ClientFlareManager = typeof(setmetatable(
	{} :: {
		template: Model?,
		modelByShadow: { [BasePart]: Model },
		bodiesFolder: Folder?,
		hasWarnedTemplate: boolean,
		pulseTokenByInstance: { [Instance]: number },
	},
	ClientFlareManager
))

local BODIES_FOLDER = "FlareBodies"
-- the first-person view model is shared with the weapons (ClientWeaponManager)
local VIEW_MODEL_OWNER = "FlareGun"
-- the lit flare's fire and light
local FIRE_SIZE = 4
local FIRE_HEAT = 10
local FIRE_COLOR = Color3.fromRGB(255, 60, 60)
local FIRE_SECONDARY_COLOR = Color3.fromRGB(255, 180, 120)
local LIGHT_COLOR = Color3.fromRGB(255, 80, 80)
local LIGHT_RANGE = 30
local LIGHT_BRIGHTNESS = 3
-- the gun's muzzle flash and smoke, pulsed on a shot (the weapon's timings)
local MUZZLE_FLASH_SEC = 0.08
local MUZZLE_SMOKE_SEC = 0.12
local FIRE_SOUND_FULL_VOLUME_STUDS = 40
local FIRE_SOUND_RANGE_STUDS = 200
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

-- the gun in first person: the same view model the weapons use, a copy of
-- GADGET_FLARE locked to the camera so it aims with the reticle (the Tool
-- in the hand only plays the stock hold pose), shown while the gun is
-- the equipped tool and hidden as soon as it is not
function ClientFlareManager:renderViewModel()
	if self:isActive() then
		ClientViewModelManager:show(MiningRules.gadgetTemplateName(Enums.GadgetKind.FLARE), VIEW_MODEL_OWNER)
	else
		ClientViewModelManager:hide(VIEW_MODEL_OWNER)
	end
end

-- the gun's Muzzle attachment: the view model's when it is shown, else the
-- held Tool's (the template builder's, placed by the designer's
-- MuzzleAttachment)
function ClientFlareManager:findHeldMuzzle(): Attachment?
	local shown = ClientViewModelManager:getMuzzle()
	if shown then
		return shown
	end
	local character = Players.LocalPlayer.Character
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	local muzzle = if tool then tool:FindFirstChild(Constants.WEAPON_MUZZLE_ATTACHMENT, true) else nil
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

-- switches a light or an emitter on for a moment
function ClientFlareManager:pulse(instance: PointLight | ParticleEmitter, seconds: number)
	local token = (self.pulseTokenByInstance[instance] or 0) + 1
	self.pulseTokenByInstance[instance] = token
	instance.Enabled = true
	task.delay(
		seconds,
		function()
			if self.pulseTokenByInstance[instance] ~= token then
				return
			end
			self.pulseTokenByInstance[instance] = nil
			instance.Enabled = false
		end
	)
end

function ClientFlareManager:playMuzzleEffects(muzzle: Attachment)
	local flash = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_FLASH_LIGHT)
	if flash and flash:IsA("PointLight") then
		self:pulse(flash, MUZZLE_FLASH_SEC)
	end
	local smoke = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_SMOKE_EMITTER)
	if smoke and smoke:IsA("ParticleEmitter") then
		self:pulse(smoke, MUZZLE_SMOKE_SEC)
	end
end

function ClientFlareManager:use()
	local cooldownLeft = self:getCooldownLeft()
	if cooldownLeft > 0 then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)), FEEDBACK_DISPLAY_SEC)
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- the flare leaves the gun's muzzle toward where the camera looks;
	-- the server allows the gun's distance from the head
	local muzzle = self:findHeldMuzzle()
	local origin = if muzzle then muzzle.WorldPosition else camera.CFrame.Position
	ClientNetManager:fireServer(
		NetEventNames.TRY_FIRE_FLARE,
		{
			origin = origin,
			direction = camera.CFrame.LookVector,
		}
	)
	if muzzle then
		self:playMuzzleEffects(muzzle)
	end
	ClientViewModelManager:kick()
	ClientSoundManager:playSfxAt(origin, SoundNames.Sfx.FLARE_FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, FIRE_SOUND_RANGE_STUDS)
end

function ClientFlareManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() or not isUseInput(input) or not self:isActive() then
		return
	end
	self:use()
end

function ClientFlareManager:init()
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
	-- the gun follows the equipped tool and the class's gadget; this
	-- manager starts after the weapon manager, so on a swap to the gun the
	-- weapon's hide has already run, and on a swap away the owner check
	-- keeps the flare's hide off the weapon's fresh show
	local function applyHeld()
		self:renderViewModel()
	end
	applyHeld()
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyHeld)
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.GADGET_KIND, applyHeld)
end

function ClientFlareManager.new(): ClientFlareManager
	local self = setmetatable({}, ClientFlareManager) :: ClientFlareManager
	self.template = nil
	self.modelByShadow = {}
	self.bodiesFolder = nil
	self.hasWarnedTemplate = false
	self.pulseTokenByInstance = {}
	return self
end

return ClientFlareManager.new()
