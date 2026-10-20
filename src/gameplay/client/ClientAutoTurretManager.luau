--!strict

-- The Auto Turret as the client sees it (M66). Two jobs. While the GADGET
-- tool is equipped and the class's gadget is the turret, a ghost of it
-- (ClientGadgetGhost, shared with the Remote Charge since 2026-10-20)
-- hangs a fixed distance ahead of the player on the ground, green where
-- the server would accept it and red where it would not; the use input
-- asks the server to place it there, and a red ghost refuses locally with
-- the fail sound and a line. For every standing turret (a
-- Tags.AUTO_TURRET shadow), the designer's model is cloned onto it from
-- GameAssets/Gadgets, its head eased toward the yaw the server publishes,
-- an HP billboard hung from the placement info template, and, for the
-- owner alone, a Pick Up prompt made here so no other client ever sees
-- one. A shot is NotifyAutoTurretFired: a tracer from the muzzle to the
-- target's body.
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
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientGadgetGhost = require(script.Parent.ClientGadgetGhost)
local ClientWeaponManager = require(script.Parent.ClientWeaponManager)

local ClientAutoTurretManager = {}
ClientAutoTurretManager.__index = ClientAutoTurretManager

type TurretView = {
	shadow: BasePart,
	model: Model,
	head: BasePart?,
	-- the head's rest pose relative to the base, so the yaw turns it in place
	headRest: CFrame?,
	base: CFrame,
	shownYaw: number,
	billboard: BillboardGui?,
	prompt: ProximityPrompt?,
}

export type ClientAutoTurretManager = typeof(setmetatable(
	{} :: {
		template: Model?,
		viewsByShadow: { [BasePart]: TurretView },
		ghost: ClientGadgetGhost.ClientGadgetGhost?,
		-- the GADGET tool is equipped and the class's gadget is this turret
		isActive: boolean,
		bodiesFolder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientAutoTurretManager
))

local NOTIFY_AUTO_TURRET_FIRED_SHAPE = {
	id = "string",
	hitId = "string",
}

local BODIES_FOLDER = "AutoTurretBodies"
-- the Machine Gun's crack at the turret, full at this range and gone past the other
local FIRE_SOUND_FULL_VOLUME_STUDS = 20
local FIRE_SOUND_SILENT_STUDS = 120
-- how quickly the shown head catches up with the published yaw
local FOLLOW_RATE = 10
-- the designer's model points its barrel down its own +X; the base's
-- forward is -Z (where the player looks, and where a yaw of 0 aims), so
-- the model is turned this much to stand facing away from the player
local MODEL_YAW_OFFSET_DEGREES = 90
local BILLBOARD_LIFT_STUDS = 1.5
local PROMPT_HOLD_SEC = 0.5
local PROMPT_MAX_DISTANCE_STUDS = 10
local FEEDBACK_CANNOT_BUILD = "Can't build here"
local FEEDBACK_DISPLAY_SEC = 2

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientAutoTurretManager:getBodiesFolder(): Folder
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

function ClientAutoTurretManager:findTemplate(): Model?
	if self.template then
		return self.template
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local gadgets = if gameAssets then gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER) else nil
	local template = if gadgets then gadgets:FindFirstChild(Constants.AUTO_TURRET_TEMPLATE) else nil
	if template and template:IsA("Model") then
		self.template = template
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientAutoTurretManager: no GameAssets.{Constants.GADGET_TEMPLATES_FOLDER}.{Constants.AUTO_TURRET_TEMPLATE}; run scripts/studio/build_auto_turret_template.luau`)
	end
	return nil
end

function ClientAutoTurretManager:findBillboardTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.PLACEMENT_INFO_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	return nil
end

function ClientAutoTurretManager:refreshBillboard(view: TurretView)
	local billboard = view.billboard
	if not billboard then
		return
	end
	local shadow = view.shadow
	local root = billboard:FindFirstChild(Constants.PLACEMENT_INFO_ROOT_FRAME)
	local nameLabel = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_NAME_LABEL) else nil
	local bar = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.PLACEMENT_INFO_FILL) else nil
	local ownerLabel = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_OWNER_LABEL) else nil
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.GadgetKind, Enums.GadgetKind.AUTO_TURRET) or "Auto Turret")
	end
	if ownerLabel and ownerLabel:IsA("TextLabel") then
		local ownerUserId = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_OWNER_USER_ID), 0)
		local publicData = ClientDataManager:getPlayerPublicData(ownerUserId)
		ownerLabel.Text = if publicData then publicData.displayName else ""
	end
	if fill and fill:IsA("Frame") then
		local hp = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_HP), 0)
		local maxHp = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_MAX_HP), 1)
		local share = math.clamp(hp / math.max(maxHp, 1), 0, 1)
		fill.Size = UDim2.fromScale(share, 1)
		fill.BackgroundColor3 = UiStyle.HP_EMPTY_COLOR:Lerp(UiStyle.HP_FULL_COLOR, share)
	end
end

-- the head turns about the base's up axis to the yaw the server published
function ClientAutoTurretManager:applyYaw(view: TurretView)
	local head = view.head
	local headRest = view.headRest
	if head and headRest then
		head.CFrame = view.base * CFrame.Angles(0, math.rad(view.shownYaw), 0) * headRest
	end
end

function ClientAutoTurretManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.viewsByShadow[shadow] then
		return
	end
	local template = self:findTemplate()
	if not template then
		return
	end
	local model = ClientGadgetGhost.buildModel(template, shadow.Name)
	-- the shadow's centre is half its height up; the model stands on the ground under it
	local base = shadow.CFrame * CFrame.new(0, -shadow.Size.Y / 2, 0)
	ClientGadgetGhost.poseModel(model, base, MODEL_YAW_OFFSET_DEGREES)
	local head = model:FindFirstChild(Constants.AUTO_TURRET_HEAD_PART)
	local headPart = if head and head:IsA("BasePart") then head else nil
	local view: TurretView = {
		shadow = shadow,
		model = model,
		head = headPart,
		headRest = if headPart then base:ToObjectSpace(headPart.CFrame) else nil,
		base = base,
		shownYaw = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_YAW_DEGREES), 0),
		billboard = nil,
		prompt = nil,
	}
	model.Parent = self:getBodiesFolder()
	self.viewsByShadow[shadow] = view
	self:applyYaw(view)

	local stand = model:FindFirstChild(Constants.AUTO_TURRET_BASE_PART)
	local standPart = if stand and stand:IsA("BasePart") then stand else model.PrimaryPart
	local billboardTemplate = self:findBillboardTemplate()
	if billboardTemplate and standPart then
		local billboard = billboardTemplate:Clone()
		local _, boxSize = model:GetBoundingBox()
		billboard.Adornee = standPart
		billboard.StudsOffsetWorldSpace = Vector3.new(0, boxSize.Y + BILLBOARD_LIFT_STUDS, 0)
		billboard.Parent = standPart
		view.billboard = billboard
		self:refreshBillboard(view)
	end
	shadow:GetAttributeChangedSignal(Attributes.AUTO_TURRET_HP):Connect(
		function()
			self:refreshBillboard(view)
		end
	)

	-- only the owner picks it up, so only the owner gets a prompt at all;
	-- their own placing rings like a tower going up (2026-10-20)
	local ownerUserId = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_OWNER_USER_ID), 0)
	if ownerUserId == Players.LocalPlayer.UserId then
		ClientSoundManager:playSfx(SoundNames.Sfx.PLACEMENT_BUILD)
	end
	if ownerUserId == Players.LocalPlayer.UserId and standPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = Constants.AUTO_TURRET_PICK_UP_ACTION_TEXT
		prompt.ObjectText = Enums.getPublicName(Enums.GadgetKind, Enums.GadgetKind.AUTO_TURRET) or ""
		prompt.HoldDuration = PROMPT_HOLD_SEC
		prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE_STUDS
		prompt.RequiresLineOfSight = false
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person
		prompt.ClickablePrompt = false
		prompt.Parent = standPart
		prompt.Triggered:Connect(
			function()
				ClientNetManager:fireServer(NetEventNames.TRY_PICK_UP_AUTO_TURRET, {})
			end
		)
		view.prompt = prompt
	end
end

function ClientAutoTurretManager:untrack(shadow: Instance)
	local view = self.viewsByShadow[shadow :: BasePart]
	if not view then
		return
	end
	self.viewsByShadow[shadow :: BasePart] = nil
	view.model:Destroy()
end

function ClientAutoTurretManager:findViewById(id: string): TurretView?
	for shadow, view in self.viewsByShadow do
		if shadow.Name == id then
			return view
		end
	end
	return nil
end

-- the ghost exists only while the turret is the tool in hand
function ClientAutoTurretManager:setGhostVisible(isVisible: boolean)
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

-- the use input (click, trigger, or the touch action button): place where
-- the ghost stands, or say why not
function ClientAutoTurretManager:use()
	local ghost = self.ghost
	if not self.isActive or not ghost or ClientOverlayManager:isOverlayActive() then
		return
	end
	local position = ghost.position
	if not ghost.isValid or not position then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_CANNOT_BUILD, FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(
		NetEventNames.TRY_PLACE_AUTO_TURRET,
		{
			position = position,
			yawDegrees = ghost.yawDegrees,
		}
	)
end

function ClientAutoTurretManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not isUseInput(input) then
		return
	end
	self:use()
end

function ClientAutoTurretManager:onRenderStep(deltaTime: number)
	local follow = math.min(1, FOLLOW_RATE * deltaTime)
	for shadow, view in self.viewsByShadow do
		local targetYaw = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_YAW_DEGREES), 0)
		local delta = (targetYaw - view.shownYaw + 180) % 360 - 180
		view.shownYaw += delta * follow
		self:applyYaw(view)
	end
	local ghost = self.ghost
	if self.isActive and ghost then
		ghost:update()
	end
end

function ClientAutoTurretManager:onFired(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_AUTO_TURRET_FIRED_SHAPE) then
		warn("ClientAutoTurretManager: malformed NotifyAutoTurretFired")
		return
	end
	local view = self:findViewById(payload.id)
	if not view then
		return
	end
	local muzzle = view.model:FindFirstChild(Constants.AUTO_TURRET_MUZZLE_ATTACHMENT, true)
	local from = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else view.model:GetPivot().Position
	local to = ClientDamageableManager:getBodyPosition(payload.hitId)
	if not to then
		return
	end
	ClientWeaponManager:drawTracer(from, to)
	ClientDamageableManager:flashHit(payload.hitId)
	-- the Machine Gun post's crack, from the turret (decided 2026-10-19)
	ClientSoundManager:playSfxAt(from, SoundNames.Sfx.MACHINE_GUN_FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, FIRE_SOUND_SILENT_STUDS)
end

-- active while the GADGET tool is in hand and the class's gadget is the turret
function ClientAutoTurretManager:refreshActive()
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	self.isActive = equipped == Enums.ToolKind.GADGET and gadgetKind == Enums.GadgetKind.AUTO_TURRET
	self:setGhostVisible(self.isActive)
end

function ClientAutoTurretManager:init()
	for _, shadow in CollectionService:GetTagged(Tags.AUTO_TURRET) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.AUTO_TURRET):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.AUTO_TURRET):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_AUTO_TURRET_FIRED,
		function(payload: any)
			self:onFired(payload)
		end
	)
	self:refreshActive()
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.EQUIPPED_TOOL,
		function(_value: any)
			self:refreshActive()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.GADGET_KIND,
		function(_value: any)
			self:refreshActive()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	RunService.RenderStepped:Connect(
		function(deltaTime: number)
			self:onRenderStep(deltaTime)
		end
	)
end

function ClientAutoTurretManager.new(): ClientAutoTurretManager
	local self = setmetatable({}, ClientAutoTurretManager) :: ClientAutoTurretManager
	self.template = nil
	self.viewsByShadow = {}
	self.ghost = nil
	self.isActive = false
	self.bodiesFolder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientAutoTurretManager.new()
