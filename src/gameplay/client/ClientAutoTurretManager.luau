--!strict

-- The Auto Turret as the client sees it (M66). Two jobs. While the GADGET
-- tool is equipped and the class's gadget is the turret, a ghost of it
-- hangs a fixed distance ahead of the player on the ground, green where
-- the server would accept it and red where it would not (the same
-- AutoTurretRules the server decides by, read against the camp's
-- walkable areas); the use input asks the server to place it there, and a
-- red ghost refuses locally with the fail sound and a line. For every
-- standing turret (a Tags.AUTO_TURRET shadow), the designer's model is
-- cloned onto it from GameAssets/Gadgets, its head eased toward the yaw
-- the server publishes, an HP billboard hung from the placement info
-- template, and, for the owner alone, a Pick Up prompt made here so no
-- other client ever sees one. A shot is NotifyAutoTurretFired: a tracer
-- from the muzzle to the target's body.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local AutoTurretRules = require("@game/ReplicatedStorage/Shared/AutoTurretRules")
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
		ghost: Model?,
		ghostParts: { BasePart },
		-- the GADGET tool is equipped and the class's gadget is this turret
		isActive: boolean,
		isGhostValid: boolean,
		ghostPosition: Vector3?,
		ghostYawDegrees: number,
		placeDistanceStuds: number,
		minGroundNormalY: number,
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
local GHOST_NAME = "AutoTurretGhost"
local GHOST_TRANSPARENCY = 0.5
-- the ghost's ground ray: from above the spot to well below, so a slope
-- or a step still finds a floor
local GHOST_RAY_ABOVE_STUDS = 10
local GHOST_RAY_BELOW_STUDS = 30
-- the roof test the client can make without the server's path grid: a
-- surface with another floor this far beneath it is a roof, not the ground
-- (a ray from just under a surface never meets that surface again)
local ROOF_PROBE_START_BELOW_STUDS = 0.5
local ROOF_PROBE_LENGTH_STUDS = 60
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

local function hasTag(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag)
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

-- a clone the client owns outright: anchored, touching and hitting nothing
function ClientAutoTurretManager:buildModel(): Model?
	local template = self:findTemplate()
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return model
end

-- stands the model on the base pose: its bounding box's bottom on the
-- ground point, turned the base's way
function ClientAutoTurretManager:poseModel(model: Model, base: CFrame)
	local turned = base * CFrame.Angles(0, math.rad(MODEL_YAW_OFFSET_DEGREES), 0)
	model:PivotTo(turned)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local lift = base.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	model:PivotTo(turned * CFrame.new(0, lift, 0))
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
	local model = self:buildModel()
	if not model then
		return
	end
	-- the shadow's centre is half its height up; the model stands on the ground under it
	local base = shadow.CFrame * CFrame.new(0, -shadow.Size.Y / 2, 0)
	model.Name = shadow.Name
	self:poseModel(model, base)
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

	-- only the owner picks it up, so only the owner gets a prompt at all
	local ownerUserId = readNumber(shadow:GetAttribute(Attributes.AUTO_TURRET_OWNER_USER_ID), 0)
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
	if not isVisible then
		if self.ghost then
			self.ghost:Destroy()
			self.ghost = nil
			self.ghostParts = {}
		end
		self.ghostPosition = nil
		return
	end
	if self.ghost then
		return
	end
	local model = self:buildModel()
	if not model then
		return
	end
	model.Name = GHOST_NAME
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = GHOST_TRANSPARENCY
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.CastShadow = false
			table.insert(parts, descendant)
		end
	end
	model.Parent = self:getBodiesFolder()
	self.ghost = model
	self.ghostParts = parts
end

-- inside one of the camp's monster areas (WaveAreas, CampArea), flat
function ClientAutoTurretManager:isInsideMonsterArea(position: Vector3): boolean
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if not camp then
		return false
	end
	for _, folderName in { Constants.CAMP_WAVE_AREAS_FOLDER, Constants.CAMP_CAMP_AREA_FOLDER } do
		local folder = camp:FindFirstChild(folderName)
		if not folder then
			continue
		end
		for _, area in folder:GetChildren() do
			if not area:IsA("BasePart") then
				continue
			end
			local localPosition = area.CFrame:PointToObjectSpace(Vector3.new(position.X, area.Position.Y, position.Z))
			if math.abs(localPosition.X) <= area.Size.X / 2 and math.abs(localPosition.Z) <= area.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

function ClientAutoTurretManager:updateGhost()
	local ghost = self.ghost
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not ghost or not root or not root:IsA("BasePart") then
		self.isGhostValid = false
		self.ghostPosition = nil
		return
	end
	local origin = AutoTurretRules.ghostOrigin(root.CFrame, self.placeDistanceStuds)
	local excluded: { Instance } = { ghost, self:getBodiesFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = excluded
	parameters.RespectCanCollide = true
	local hit = workspace:Raycast(origin + Vector3.new(0, GHOST_RAY_ABOVE_STUDS, 0), Vector3.new(0, -(GHOST_RAY_ABOVE_STUDS + GHOST_RAY_BELOW_STUDS), 0), parameters)
	local isGround = hit ~= nil and AutoTurretRules.findBlockingTag(hit.Instance, hasTag) == nil
	local groundPosition = if hit then hit.Position else origin
	local normalY = if hit then hit.Normal.Y else 0
	local isAtGroundLevel = true
	if hit then
		local beneath = workspace:Raycast(hit.Position - Vector3.new(0, ROOF_PROBE_START_BELOW_STUDS, 0), Vector3.new(0, -ROOF_PROBE_LENGTH_STUDS, 0), parameters)
		isAtGroundLevel = beneath == nil
	end
	local problem = AutoTurretRules.placementProblem(isGround, normalY, self.minGroundNormalY, self:isInsideMonsterArea(groundPosition), isAtGroundLevel)
	self.isGhostValid = problem == nil
	self.ghostPosition = groundPosition
	self.ghostYawDegrees = AutoTurretRules.yawDegreesOf(root.CFrame)
	self:poseModel(ghost, CFrame.new(groundPosition) * CFrame.Angles(0, math.rad(self.ghostYawDegrees), 0))
	local color = if self.isGhostValid then UiStyle.POSITIVE_COLOR else UiStyle.NEGATIVE_COLOR
	for _, part in self.ghostParts do
		part.Color = color
	end
end

-- the use input (click, trigger, or the touch action button): place where
-- the ghost stands, or say why not
function ClientAutoTurretManager:use()
	if not self.isActive or not self.ghost or ClientOverlayManager:isOverlayActive() then
		return
	end
	local position = self.ghostPosition
	if not self.isGhostValid or not position then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_CANNOT_BUILD, FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(
		NetEventNames.TRY_PLACE_AUTO_TURRET,
		{
			position = position,
			yawDegrees = self.ghostYawDegrees,
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
	if self.isActive then
		self:updateGhost()
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
	self.placeDistanceStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.AUTO_TURRET_PLACE_DISTANCE_STUDS), self.placeDistanceStuds)
	self.minGroundNormalY = readNumber(ClientDataManager:getGameMetadata(Attributes.AUTO_TURRET_MIN_GROUND_NORMAL_Y), self.minGroundNormalY)
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
	self.ghostParts = {}
	self.isActive = false
	self.isGhostValid = false
	self.ghostPosition = nil
	self.ghostYawDegrees = 0
	self.placeDistanceStuds = 15
	self.minGroundNormalY = 0.8
	self.bodiesFolder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientAutoTurretManager.new()
