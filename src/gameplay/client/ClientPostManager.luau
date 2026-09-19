--!strict

-- Posts on this client (GDD "Posts", "Using a Post Weapon", "Aiming a Post
-- Weapon"), M25. Three jobs. Prompts: the sign's Claim Post shows only
-- while this player has no post and the post is free, the weapon's Use only
-- to its owner, all set locally (the server still decides every trigger).
-- Rendering: every spawned weapon (Tags.POST_WEAPON) is turned and tilted
-- here from its PostWeaponYaw / Pitch attributes, smoothed, so the server
-- never moves a part after the spawn; the local gunner's weapon follows
-- their own input a frame ahead of the echo. Post Weapon Mode: when the
-- server says this player is manning a post (MannedPostIndex), the camera
-- goes Scriptable at the weapon's CameraLocation looking down the barrel
-- with the kind's field of view, the mouse locks, the character is
-- anchored on the CharacterSpawn and turns with the base, the reticle
-- shows, and a press fires (ClientHoldInput, so mouse, gamepad, and the
-- touch Fire button all work). Left and right are the base turning at its
-- turn speed; up and down are the gun tilting freely within the kind's
-- range. Spacebar, gamepad A (or B), or the touch Exit button that stands
-- where the hidden jump button was all leave, as does any menu opening. Every shot is a request carrying the muzzle ray; the truth
-- comes back as NotifyPostWeaponFired, which also draws everyone else's.
-- A projectile kind (the Rocket Launcher) is drawn from
-- NotifyPostRocketLaunched instead: a client-only clone of the
-- GameAssets/Projectiles model flies at the server's speed with a smoke
-- trail from its TailAttachment and a 3D flight loop, and bursts where
-- NotifyPostRocketExploded says, with a blast, a flash, and the explosion
-- sound; the server's rocket is the truth, this one only shows it.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientHoldInput = require(script.Parent.ClientHoldInput)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientTouchLayoutManager = require(script.Parent.ClientTouchLayoutManager)
local ClientWeaponManager = require(script.Parent.ClientWeaponManager)

local ClientPostManager = {}
ClientPostManager.__index = ClientPostManager

-- a rocket in the air as this client draws it
type RocketView = {
	id: string,
	part: BasePart,
	weaponKind: number,
	unitDirection: Vector3,
	speedStudsPerSec: number,
	tailOffset: Vector3,
}

-- one spawned weapon as this client draws it
type WeaponView = {
	model: Model,
	gun: BasePart,
	muzzle: Attachment?,
	rig: PostRules.Rig,
	-- the Spawn as the server placed it (yaw 0), read once
	baseCFrame: CFrame,
	shownYaw: number,
	shownPitch: number,
	prompt: ProximityPrompt?,
}

export type ClientPostManager = typeof(setmetatable(
	{} :: {
		catalog: PostRules.Catalog?,
		viewsByModel: { [Model]: WeaponView },
		rocketsById: { [string]: RocketView },
		postPromptsByModel: { [Model]: ProximityPrompt },
		isMounted: boolean,
		mountedView: WeaponView?,
		-- this player's own aim while mounted; the server echoes it back
		yawDegrees: number,
		pitchDegrees: number,
		-- how far the input asked the base to turn this frame
		wantedYawDelta: number,
		wantedPitchDelta: number,
		lastSentYaw: number?,
		lastSentPitch: number?,
		lastSendTime: number,
		stats: PostRules.Stats?,
		kindData: PostRules.KindData?,
		holdInput: ClientHoldInput.ClientHoldInput?,
		fireButton: GuiButton?,
		exitButton: GuiButton?,
		exitHint: TextLabel?,
		reticle: ImageLabel?,
		statusBar: Frame?,
		statusFill: Frame?,
		statusLabel: TextLabel?,
		-- this player's own shots since the server's last heat echo, so the
		-- bar climbs with the trigger rather than a beat behind it
		predictedHeat: number,
		predictedHeatTime: number?,
		isPredictedOverheated: boolean,
		-- when this gunner's aim last moved, and how loud the whirring loop
		-- is right now (0 to 1), so it swells and dies away smoothly
		lastTurnTime: number,
		turnLevel: number,
		isTouchOnly: boolean,
		savedCameraType: Enum.CameraType?,
		savedFieldOfView: number?,
		anchoredRoot: BasePart?,
	},
	ClientPostManager
))

local RETICLE_BORROWER = "PostMode"
-- the HUD that means nothing at a gun: balances, backpack, jet pack, the
-- action button (GameplayHud) and the tool bar; hidden while mounted
-- (decided 2026-09-18)
local HIDDEN_HUD_GUI_NAMES = { Constants.GAMEPLAY_HUD_GUI_NAME, Constants.TOOL_BAR_GUI_NAME }
local DEFAULT_FIELD_OF_VIEW = 70
-- how fast a shown weapon chases the last aim heard, per second
local FOLLOW_RATE = 12
local MOUSE_DEGREES_PER_PX = 0.12
local TOUCH_DEGREES_PER_PX = 0.25
-- the right stick tilts the gun this fast at full deflection; the base
-- always turns at its own speed
local STICK_PITCH_DEGREES_PER_SEC = 90
local STICK_DEADZONE = 0.2
local SEND_MIN_INTERVAL_SEC = 0.1
local SEND_MIN_CHANGE_DEGREES = 0.5
-- the character's root sits this far above its feet
local ROOT_LIFT_STUDS = 3
local FIRE_SOUND_FULL_VOLUME_STUDS = 40
local EFFECT_RANGE_STUDS = 500
local REPLAYED_SHOT_OVERSHOOT_STUDS = 1
-- a rocket bursts up to its full range away (500 studs), so the blast is
-- drawn and heard much further than a gunshot: full volume near, tapering
-- to silence past the far side of the camp (decided 2026-09-18)
local BLAST_FULL_VOLUME_STUDS = 200
local BLAST_SILENT_STUDS = 800
local EXIT_HINT_KEYBOARD = "Spacebar to exit"
-- the jump button by the platform's name: A on Xbox, Cross on PlayStation
local EXIT_HINT_GAMEPAD_FORMAT = "%s to exit"
local GAMEPAD_JUMP_NAME_XBOX = "A"
local GAMEPAD_JUMP_NAME_PLAYSTATION = "Cross"
local CLAIMED_FORMAT = "Defense Post #%d is yours"
-- the status bar: heat runs green to red as it climbs; a reload fills red
-- and turns green when done (decided 2026-09-18)
local STATUS_COOL_COLOR = Color3.fromRGB(90, 230, 100)
local STATUS_HOT_COLOR = Color3.fromRGB(240, 80, 70)
-- the turning loop (2D, the gunner's own: it says why the view moves
-- slowly) starts on this much movement in a frame and stops this long
-- after the last movement, so a steady hand is silent and a slow sweep is
-- not stuttered
local TURN_SOUND_MIN_DEGREES = 0.05
local TURN_SOUND_LINGER_SEC = 0.15
-- the whir fades in and out over these, so a stop-start sweep swells and
-- dies away rather than clicking on and off (decided 2026-09-18)
local TURN_SOUND_FADE_IN_SEC = 0.06
local TURN_SOUND_FADE_OUT_SEC = 0.175
local STATUS_OVERHEATED_TEXT = "Overheated"
local STATUS_RELOADING_TEXT = "Reloading"

local NOTIFY_POST_CLAIMED_SHAPE = {
	postIndex = "positiveInteger",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	price = "nonnegativeInteger",
}
local NOTIFY_POST_ROCKET_LAUNCHED_SHAPE = {
	rocketId = "string",
	userId = "positiveInteger",
	postIndex = "positiveInteger",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	origin = "vector3",
	direction = "vector3",
	speed = "positiveNumber",
}
local NOTIFY_POST_ROCKET_EXPLODED_SHAPE = {
	rocketId = "string",
	userId = "positiveInteger",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	position = "vector3",
	hitCount = "nonnegativeInteger",
}
-- the burst: how long the smoke lingers, the flash, and the blast's own light
local BLAST_SMOKE_LIFETIME_SEC = 2.5
local BLAST_SMOKE_COUNT = 40
local BLAST_FLASH_SEC = 0.15
-- a rocket that never hears its burst (a lost message) is dropped after this
local ROCKET_MAX_LIFETIME_SEC = 10
local NOTIFY_POST_WEAPON_FIRED_SHAPE = {
	userId = "positiveInteger",
	postIndex = "positiveInteger",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	origin = "vector3",
	endPosition = "vector3",
	isImpact = "boolean",
	hitId = "string",
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientPostManager:getIsMounted(): boolean
	return self.isMounted
end

function ClientPostManager:getOwnPostIndex(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_INDEX), PostRules.NO_POST)
end

function ClientPostManager:getOwnUpgrades(): PostRules.Upgrades
	local upgrades: PostRules.Upgrades = {}
	for attribute, attributeName in PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE do
		upgrades[attribute] = readNumber(ClientDataManager:getCurrentPlayerAttribute(attributeName), 0)
	end
	return upgrades
end

function ClientPostManager:getPostWeaponSfx(weaponKind: any): SoundNames.PostWeaponSfx?
	local kindName = if typeof(weaponKind) == "number" and Enums.isValidValue(Enums.PostWeaponKind, weaponKind) then Enums.getName(Enums.PostWeaponKind, weaponKind) else nil
	return if kindName then SoundNames.PostWeaponSfxByKindName[kindName] else nil
end

-- the weapon's numbers for this player: the catalogue plus their upgrades
function ClientPostManager:readStats()
	local catalog = self.catalog
	local kind = ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND)
	if not catalog or typeof(kind) ~= "number" then
		self.stats = nil
		self.kindData = nil
		return
	end
	self.stats = PostRules.statsFor(catalog, kind, self:getOwnUpgrades())
	self.kindData = catalog.kinds[kind]
end

-- the sign's Claim Post prompt and its "Claim for" line: only for a player
-- without a post, on a post nobody owns
function ClientPostManager:renderPostPrompt(model: Model, prompt: ProximityPrompt)
	local owner = readNumber(model:GetAttribute(Attributes.POST_OWNER_USER_ID), PostRules.NOBODY)
	local canClaim = owner == PostRules.NOBODY and self:getOwnPostIndex() == PostRules.NO_POST
	prompt.Enabled = canClaim
	local priceRow = model:FindFirstChild(Constants.POST_SIGN_CLAIM_PRICE_ROW, true)
	if priceRow and priceRow:IsA("GuiObject") then
		priceRow.Visible = canClaim
	end
end

-- the weapon's Use prompt: only for its owner, while they are on foot
function ClientPostManager:renderWeaponPrompt(view: WeaponView)
	local prompt = view.prompt
	if not prompt then
		return
	end
	local postIndex = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX), 0)
	prompt.Enabled = postIndex == self:getOwnPostIndex() and not self.isMounted
end

function ClientPostManager:renderPrompts()
	for model, prompt in self.postPromptsByModel do
		self:renderPostPrompt(model, prompt)
	end
	for _, view in self.viewsByModel do
		self:renderWeaponPrompt(view)
	end
end

function ClientPostManager:bindPost(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local signModel = model:FindFirstChild(Constants.POST_SIGN_MODEL)
	local signPart = if signModel then signModel:FindFirstChild(Constants.POST_SIGN_PART) else nil
	if not signPart then
		return
	end
	local function bindPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			self.postPromptsByModel[model] = prompt
			self:renderPostPrompt(model, prompt)
		end
	end
	-- the server adds the prompt (under an attachment) after the model replicates
	local prompt = signPart:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		bindPrompt(prompt)
	else
		signPart.DescendantAdded:Connect(bindPrompt)
	end
	model:GetAttributeChangedSignal(Attributes.POST_OWNER_USER_ID):Connect(
		function()
			local livePrompt = self.postPromptsByModel[model]
			if livePrompt then
				self:renderPostPrompt(model, livePrompt)
			end
		end
	)
end

function ClientPostManager:bindWeapon(model: Instance)
	if not model:IsA("Model") or self.viewsByModel[model] then
		return
	end
	-- with StreamingEnabled the Model can arrive before its parts
	local spawn = model:WaitForChild(Constants.POST_SPAWN_PART, 10)
	local characterSpawn = model:WaitForChild(Constants.POST_WEAPON_CHARACTER_SPAWN_PART, 10)
	local rig, reason = PostRules.measureRig(model)
	if not rig or not spawn or not spawn:IsA("BasePart") then
		warn(`ClientPostManager: {model:GetFullName()}: {reason or "no Spawn"}; not drawn`)
		return
	end
	local muzzle = model:FindFirstChild(Constants.POST_WEAPON_MUZZLE_ATTACHMENT, true)
	local gun = if muzzle then muzzle.Parent else nil
	if not gun or not gun:IsA("BasePart") then
		return
	end
	local view: WeaponView = {
		model = model,
		gun = gun,
		muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil,
		rig = rig,
		baseCFrame = spawn.CFrame,
		shownYaw = readNumber(model:GetAttribute(Attributes.POST_WEAPON_YAW_DEGREES), 0),
		shownPitch = readNumber(model:GetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES), 0),
		prompt = nil,
	}
	self.viewsByModel[model] = view
	local function bindPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			view.prompt = prompt
			self:renderWeaponPrompt(view)
		end
	end
	local prompt = if characterSpawn then characterSpawn:FindFirstChildWhichIsA("ProximityPrompt") else nil
	if prompt then
		bindPrompt(prompt)
	elseif characterSpawn then
		characterSpawn.ChildAdded:Connect(bindPrompt)
	end
	self:renderWeaponPrompt(view)
	if self.isMounted then
		self:findMountedView()
	end
end

function ClientPostManager:unbindWeapon(model: Instance)
	local view = self.viewsByModel[model :: Model]
	if not view then
		return
	end
	self.viewsByModel[model :: Model] = nil
	if self.mountedView == view then
		self.mountedView = nil
	end
end

-- the weapon this player is manning, by the post number the server gave
function ClientPostManager:findMountedView()
	local mannedIndex = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX), PostRules.NO_POST)
	self.mountedView = nil
	for _, view in self.viewsByModel do
		if readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX), 0) == mannedIndex then
			self.mountedView = view
			-- start from where the server last had it
			self.yawDegrees = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_YAW_DEGREES), 0)
			self.pitchDegrees = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES), 0)
			return
		end
	end
end

function ClientPostManager:applyView(view: WeaponView)
	local base = PostRules.baseFrame(view.baseCFrame, view.shownYaw)
	view.model:PivotTo(base)
	view.gun.CFrame = PostRules.gunFrame(base, view.rig, view.shownPitch)
end

-- the machinery whirs in the gunner's ears while their aim moves: the
-- loop runs the whole time mounted and its level chases 1 while moving
-- and 0 while still, at the fade rates
function ClientPostManager:updateTurnSound(previousYaw: number, previousPitch: number, deltaTime: number)
	local now = workspace:GetServerTimeNow()
	local moved = math.abs(PostRules.wrapDegrees(self.yawDegrees - previousYaw)) + math.abs(self.pitchDegrees - previousPitch)
	if moved > TURN_SOUND_MIN_DEGREES then
		self.lastTurnTime = now
	end
	local isMoving = now - self.lastTurnTime < TURN_SOUND_LINGER_SEC
	local target = if isMoving then 1 else 0
	local step = deltaTime / (if isMoving then TURN_SOUND_FADE_IN_SEC else TURN_SOUND_FADE_OUT_SEC)
	self.turnLevel += math.clamp(target - self.turnLevel, -step, step)
	ClientSoundManager:setSfxLoopLevel(SoundNames.Sfx.POST_TURN, self.turnLevel)
end

-- this player's own turn for the frame: the base at its turn speed, the
-- gun freely within its range
function ClientPostManager:applyInput(deltaTime: number)
	local stats = self.stats
	local kindData = self.kindData
	if not stats or not kindData then
		return
	end
	local stick = Vector3.zero
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				stick = input.Position
			end
		end
	end
	if math.abs(stick.X) > STICK_DEADZONE then
		-- the stick asks for the full turn speed in its direction
		self.wantedYawDelta += stick.X * stats.turnSpeedDegreesPerSec * deltaTime
	end
	if math.abs(stick.Y) > STICK_DEADZONE then
		self.wantedPitchDelta += stick.Y * STICK_PITCH_DEGREES_PER_SEC * deltaTime
	end
	self.yawDegrees = PostRules.turnYaw(self.yawDegrees, self.wantedYawDelta, stats.turnSpeedDegreesPerSec, deltaTime)
	-- the gun tilts no faster than the base turns (decided 2026-09-18), so
	-- up and down feel as heavy as left and right; the server holds the
	-- pitch to the same rate
	local maxPitchStep = PostRules.maxYawStep(stats.turnSpeedDegreesPerSec, deltaTime)
	self.pitchDegrees = PostRules.clampPitch(self.pitchDegrees + math.clamp(self.wantedPitchDelta, -maxPitchStep, maxPitchStep), kindData)
	self.wantedYawDelta = 0
	self.wantedPitchDelta = 0
end

function ClientPostManager:sendAimIfNeeded()
	local now = workspace:GetServerTimeNow()
	if now - self.lastSendTime < SEND_MIN_INTERVAL_SEC then
		return
	end
	local lastYaw = self.lastSentYaw
	local lastPitch = self.lastSentPitch
	if lastYaw and lastPitch and math.abs(PostRules.wrapDegrees(self.yawDegrees - lastYaw)) < SEND_MIN_CHANGE_DEGREES and math.abs(self.pitchDegrees - lastPitch) < SEND_MIN_CHANGE_DEGREES then
		return
	end
	self.lastSentYaw = self.yawDegrees
	self.lastSentPitch = self.pitchDegrees
	self.lastSendTime = now
	ClientNetManager:fireServer(
		NetEventNames.TRY_SET_POST_AIM,
		{
			yawDegrees = self.yawDegrees,
			pitchDegrees = self.pitchDegrees,
		}
	)
end

-- the gunner stands on the CharacterSpawn and turns with the base; the
-- root is anchored so the humanoid never walks off
function ClientPostManager:placeCharacter(view: WeaponView)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if self.anchoredRoot ~= root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		self.anchoredRoot = root
	end
	local base = PostRules.baseFrame(view.baseCFrame, view.shownYaw)
	root.CFrame = PostRules.characterFrame(base, view.rig) * CFrame.new(0, ROOT_LIFT_STUDS, 0)
end

function ClientPostManager:placeCamera(view: WeaponView)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local base = PostRules.baseFrame(view.baseCFrame, view.shownYaw)
	camera.CFrame = PostRules.cameraFrame(PostRules.gunFrame(base, view.rig, view.shownPitch), view.rig)
end

function ClientPostManager:onRenderStep(deltaTime: number)
	local mountedView = self.mountedView
	if self.isMounted and mountedView then
		local previousYaw, previousPitch = self.yawDegrees, self.pitchDegrees
		self:applyInput(deltaTime)
		mountedView.shownYaw = self.yawDegrees
		mountedView.shownPitch = self.pitchDegrees
		self:updateTurnSound(previousYaw, previousPitch, deltaTime)
		self:sendAimIfNeeded()
	end
	for _, view in self.viewsByModel do
		if view ~= mountedView or not self.isMounted then
			local targetYaw = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_YAW_DEGREES), 0)
			local targetPitch = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES), 0)
			local follow = math.min(1, FOLLOW_RATE * deltaTime)
			view.shownYaw = PostRules.wrapDegrees(view.shownYaw + PostRules.wrapDegrees(targetYaw - view.shownYaw) * follow)
			view.shownPitch += (targetPitch - view.shownPitch) * follow
		end
		self:applyView(view)
	end
	self:stepRockets(deltaTime)
	if self.isMounted and mountedView then
		self:renderStatusBar()
		self:placeCharacter(mountedView)
		self:placeCamera(mountedView)
		-- Roblox's camera scripts hand the mouse back every frame while the
		-- camera is Scriptable, so the lock is reasserted here
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

function ClientPostManager:findLocalEnd(origin: Vector3, unitDirection: Vector3, rangeStuds: number): (Vector3, Vector3?, Instance?)
	return ClientWeaponManager:findLocalEnd(origin, unitDirection, rangeStuds)
end

function ClientPostManager:playFireEffects(weaponKind: number, from: Vector3, to: Vector3, impactNormal: Vector3?, impactSurface: Instance?)
	local travelSec = ClientWeaponManager:drawTracer(from, to)
	local weaponSfx = self:getPostWeaponSfx(weaponKind)
	if weaponSfx then
		ClientSoundManager:playSfxAt(from, weaponSfx.FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
	if impactNormal then
		task.delay(
			travelSec,
			function()
				ClientImpactManager:play(to, impactNormal, impactSurface)
			end
		)
	end
end

-- one shot: a request, never a result. The ray leaves the muzzle down the
-- barrel as this client draws it; the server checks it against its own
function ClientPostManager:fire(isFreshPress: boolean): boolean
	local view = self.mountedView
	local stats = self.stats
	local kindData = self.kindData
	if not view or not stats or not kindData then
		return false
	end
	-- an empty or overheated gun does not fire; the hold keeps trying
	if self:getIsReloading() then
		return false
	end
	local heatData = kindData.HEAT
	if heatData then
		local currentHeat, isOverheated = self:getCurrentHeat()
		local isFired, newHeat, isNowOverheated = PostRules.heatAfterShot(currentHeat, isOverheated, heatData, stats.fireIntervalSec)
		if not isFired then
			-- a fresh pull on a locked gun is told once; a held one stays quiet
			if isFreshPress then
				ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
			end
			return false
		end
		self.predictedHeat = newHeat
		self.predictedHeatTime = workspace:GetServerTimeNow()
		self.isPredictedOverheated = isNowOverheated
		-- the shot that tips it over is the one that says so
		if isNowOverheated and not isOverheated then
			ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		end
	end
	local base = PostRules.baseFrame(view.baseCFrame, view.shownYaw)
	local gunFrame = PostRules.gunFrame(base, view.rig, view.shownPitch)
	local origin = PostRules.muzzlePosition(gunFrame, view.rig)
	local unitDirection = PostRules.barrelDirection(gunFrame, view.rig)
	ClientNetManager:fireServer(
		NetEventNames.TRY_FIRE_POST_WEAPON,
		{
			origin = origin,
			direction = unitDirection,
		}
	)
	ClientWeaponManager:playMuzzleEffects(view.muzzle)
	local weaponKind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0)
	local kindData = self.kindData
	if kindData and kindData.PROJECTILE then
		-- the rocket itself is drawn when the server announces it; the
		-- launch sound is the gunner's own
		local weaponSfx = self:getPostWeaponSfx(weaponKind)
		if weaponSfx then
			ClientSoundManager:playSfxAt(origin, weaponSfx.FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
		end
		return true
	end
	local endPosition, impactNormal, impactSurface = self:findLocalEnd(origin, unitDirection, stats.rangeStuds)
	self:playFireEffects(weaponKind, origin, endPosition, impactNormal, impactSurface)
	return true
end

function ClientPostManager:findProjectileTemplate(templateName: string): BasePart?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("BasePart") then
		return template
	end
	warn(`ClientPostManager: no part named {templateName} under GameAssets.{Constants.PROJECTILE_TEMPLATES_FOLDER}; rockets fly unseen`)
	return nil
end

-- the flight loop rides the rocket: an AudioEmitter on the part, fed by a
-- copy of the authored player (the same wiring ClientSoundManager uses for
-- a one-shot, kept alive for the flight)
function ClientPostManager:attachFlightSound(part: BasePart, weaponKind: number)
	local weaponSfx = self:getPostWeaponSfx(weaponKind)
	local name = if weaponSfx then weaponSfx.FLIGHT else nil
	if not name then
		return
	end
	ClientSoundManager:attachLoop(part, name, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
end

-- the smoke trail streams from the TailAttachment while the rocket flies.
-- The designer authors it on the template (any ParticleEmitter or light
-- under the attachment is used as is); this placeholder is only built when
-- the attachment carries nothing
function ClientPostManager:attachTrail(tail: Attachment)
	local hasAuthoredTrail = false
	for _, child in tail:GetChildren() do
		if child:IsA("ParticleEmitter") then
			child.Enabled = true
			hasAuthoredTrail = true
		end
	end
	if hasAuthoredTrail then
		return
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Trail"
	smoke.Color = ColorSequence.new(Color3.fromRGB(220, 215, 205), Color3.fromRGB(110, 105, 100))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Rate = 60
	smoke.LightEmission = 0.1
	smoke.Parent = tail
	local flame = Instance.new("PointLight")
	flame.Name = "Flame"
	flame.Brightness = 3
	flame.Range = 12
	flame.Color = Color3.fromRGB(255, 170, 90)
	flame.Parent = tail
end

function ClientPostManager:onRocketLaunched(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_ROCKET_LAUNCHED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostRocketLaunched")
		return
	end
	local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
	-- the gunner heard their own launch when they fired; everyone else hears it now
	if payload.userId ~= Players.LocalPlayer.UserId and weaponSfx then
		local view: WeaponView? = nil
		for _, candidate in self.viewsByModel do
			if readNumber(candidate.model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX), 0) == payload.postIndex then
				view = candidate
			end
		end
		ClientWeaponManager:playMuzzleEffects(if view then view.muzzle else nil)
		ClientSoundManager:playSfxAt(payload.origin, weaponSfx.FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
	local catalog = self.catalog
	local kindData = if catalog then catalog.kinds[payload.weaponKind] else nil
	local projectile = if kindData then kindData.PROJECTILE else nil
	local template = if projectile then self:findProjectileTemplate(projectile.TEMPLATE) else nil
	if not template then
		return
	end
	local part = template:Clone()
	part.Name = payload.rocketId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local tail = part:FindFirstChild(Constants.PROJECTILE_TAIL_ATTACHMENT)
	local tailOffset = if tail and tail:IsA("Attachment") then tail.Position else Vector3.zero
	local direction: Vector3 = payload.direction
	local unitDirection = if direction.Magnitude > 0.001 then direction.Unit else Vector3.zAxis
	part.CFrame = PostRules.projectileFrame(payload.origin, unitDirection, tailOffset)
	if tail and tail:IsA("Attachment") then
		self:attachTrail(tail)
	end
	part.Parent = workspace
	self:attachFlightSound(part, payload.weaponKind)
	self.rocketsById[payload.rocketId] = {
		id = payload.rocketId,
		part = part,
		weaponKind = payload.weaponKind,
		unitDirection = unitDirection,
		speedStudsPerSec = payload.speed,
		tailOffset = tailOffset,
	}
	Debris:AddItem(part, ROCKET_MAX_LIFETIME_SEC)
end

-- the authored blast: the template's part at the point, every emitter
-- fired once for its BurstCount, every light on for the flash. Nil when
-- there is no template, and the placeholder below is used instead
function ClientPostManager:playAuthoredBlast(position: Vector3, templateName: string): boolean
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if not template or not template:IsA("BasePart") then
		return false
	end
	local part = template:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	local longestLifeSec = BLAST_FLASH_SEC
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			descendant:Emit(readNumber(descendant:GetAttribute(Attributes.BURST_COUNT), BLAST_SMOKE_COUNT))
			longestLifeSec = math.max(longestLifeSec, descendant.Lifetime.Max)
		elseif descendant:IsA("Light") then
			descendant.Enabled = true
			Debris:AddItem(descendant, BLAST_FLASH_SEC)
		end
	end
	Debris:AddItem(part, longestLifeSec + 0.2)
	return true
end

-- the blast at the burst point: the authored effect when there is one,
-- else a ball of smoke and a flash; then the sound
function ClientPostManager:playBlast(position: Vector3, weaponKind: number)
	local weaponSfx = self:getPostWeaponSfx(weaponKind)
	local explodeName = if weaponSfx then weaponSfx.EXPLODE else nil
	if explodeName then
		ClientSoundManager:playSfxAt(position, explodeName, BLAST_FULL_VOLUME_STUDS, BLAST_SILENT_STUDS)
	end
	local catalog = self.catalog
	local kindData = if catalog then catalog.kinds[weaponKind] else nil
	local projectile = if kindData then kindData.PROJECTILE else nil
	local blastTemplate = if projectile then projectile.BLAST_TEMPLATE else nil
	if blastTemplate and self:playAuthoredBlast(position, blastTemplate) then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "RocketBlast"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(200, 60, 20))
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 8),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.Speed = NumberRange.new(10, 25)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.LightEmission = 1
	fire.Rate = 0
	fire.Parent = anchor
	fire:Emit(BLAST_SMOKE_COUNT)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(40, 38, 36))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 10),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.2, BLAST_SMOKE_LIFETIME_SEC)
	smoke.Speed = NumberRange.new(6, 16)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(BLAST_SMOKE_COUNT)
	local flash = Instance.new("PointLight")
	flash.Brightness = 10
	flash.Range = 40
	flash.Color = Color3.fromRGB(255, 190, 110)
	flash.Parent = anchor
	Debris:AddItem(flash, BLAST_FLASH_SEC)
	Debris:AddItem(anchor, BLAST_SMOKE_LIFETIME_SEC + 0.2)
end

function ClientPostManager:onRocketExploded(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_ROCKET_EXPLODED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostRocketExploded")
		return
	end
	local rocket = self.rocketsById[payload.rocketId]
	if rocket then
		self.rocketsById[payload.rocketId] = nil
		rocket.part:Destroy()
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - payload.position).Magnitude <= BLAST_SILENT_STUDS then
		self:playBlast(payload.position, payload.weaponKind)
	end
	if payload.userId == Players.LocalPlayer.UserId and payload.hitCount > 0 then
		local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
		if weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.HIT)
		end
	end
end

function ClientPostManager:stepRockets(deltaTime: number)
	for id, rocket in self.rocketsById do
		if not rocket.part.Parent then
			self.rocketsById[id] = nil
			continue
		end
		local position = rocket.part.Position + rocket.unitDirection * rocket.speedStudsPerSec * deltaTime
		rocket.part.CFrame = PostRules.projectileFrame(position, rocket.unitDirection, rocket.tailOffset)
	end
end

function ClientPostManager:onPostWeaponFired(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_POST_WEAPON_FIRED_SHAPE)
	if not isValid then
		warn("ClientPostManager: malformed NotifyPostWeaponFired")
		return
	end
	if payload.hitId ~= "" then
		ClientDamageableManager:flashHit(payload.hitId)
	end
	if payload.userId == Players.LocalPlayer.UserId then
		local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
		if payload.hitId ~= "" and weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.HIT)
		end
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - payload.origin).Magnitude > EFFECT_RANGE_STUDS then
		return
	end
	local view: WeaponView? = nil
	for _, candidate in self.viewsByModel do
		if readNumber(candidate.model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX), 0) == payload.postIndex then
			view = candidate
		end
	end
	ClientWeaponManager:playMuzzleEffects(if view then view.muzzle else nil)
	local shotVector = payload.endPosition - payload.origin
	local endPosition: Vector3 = payload.endPosition
	local impactNormal: Vector3? = nil
	local impactSurface: Instance? = nil
	if payload.isImpact and shotVector.Magnitude > 0.01 then
		local localPosition, localNormal, localSurface = self:findLocalEnd(payload.origin, shotVector.Unit, shotVector.Magnitude + REPLAYED_SHOT_OVERSHOOT_STUDS)
		if localNormal then
			endPosition = localPosition
		end
		impactNormal = localNormal or -shotVector.Unit
		impactSurface = localSurface
	end
	self:playFireEffects(payload.weaponKind, payload.origin, endPosition, impactNormal, impactSurface)
end

function ClientPostManager:onPostClaimed(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_CLAIMED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostClaimed")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
	ClientPlayerFeedbackManager:giveLocal(string.format(CLAIMED_FORMAT, payload.postIndex))
end

function ClientPostManager:requestDismount()
	if self.isMounted then
		ClientNetManager:fireServer(NetEventNames.TRY_DISMOUNT_POST, {})
	end
end

-- the mounted weapon's model attributes: the server's last word on heat and reload
function ClientPostManager:readFireState(): (number, number?, boolean, number)
	local view = self.mountedView
	if not view then
		return 0, nil, false, 0
	end
	local model = view.model
	local heatTime = model:GetAttribute(Attributes.POST_WEAPON_HEAT_TIME)
	return readNumber(model:GetAttribute(Attributes.POST_WEAPON_HEAT), 0),
		if typeof(heatTime) == "number" and heatTime > 0 then heatTime else nil,
		model:GetAttribute(Attributes.POST_WEAPON_IS_OVERHEATED) == true,
		readNumber(model:GetAttribute(Attributes.POST_WEAPON_RELOAD_END_TIME), 0)
end

-- the heat right now: the newer of the server's echo and this client's
-- own prediction, cooled for the rest since
function ClientPostManager:getCurrentHeat(): (number, boolean)
	local kindData = self.kindData
	local stats = self.stats
	local heatData = if kindData then kindData.HEAT else nil
	if not heatData or not stats then
		return 0, false
	end
	local serverHeat, serverTime, isServerOverheated = self:readFireState()
	local heat, heatTime, isOverheated = serverHeat, serverTime, isServerOverheated
	local predictedTime = self.predictedHeatTime
	if predictedTime and (serverTime == nil or predictedTime > serverTime) then
		heat, heatTime, isOverheated = self.predictedHeat, predictedTime, self.isPredictedOverheated
	end
	local now = workspace:GetServerTimeNow()
	local cooled = PostRules.cooledHeat(heat, heatTime, now, stats.fireIntervalSec, heatData)
	return cooled, isOverheated and cooled > 0
end

function ClientPostManager:getIsReloading(): boolean
	local kindData = self.kindData
	if not kindData or not kindData.RELOAD_SEC then
		return false
	end
	local _heat, _heatTime, _isOverheated, reloadEndTime = self:readFireState()
	return WeaponRules.isReloading(reloadEndTime, workspace:GetServerTimeNow())
end

-- heat: fill = heat, green cooling to red. Reload: fill = progress, red
-- while filling, green once loaded. Neither: no bar
function ClientPostManager:renderStatusBar()
	local bar = self.statusBar
	local fill = self.statusFill
	local kindData = self.kindData
	if not bar or not fill then
		return
	end
	if not self.isMounted or not kindData or (not kindData.HEAT and not kindData.RELOAD_SEC) then
		bar.Visible = false
		if self.statusLabel then
			self.statusLabel.Visible = false
		end
		return
	end
	bar.Visible = true
	local label = self.statusLabel
	if kindData.HEAT then
		local heat, isOverheated = self:getCurrentHeat()
		fill.Size = UDim2.fromScale(heat, 1)
		fill.BackgroundColor3 = STATUS_COOL_COLOR:Lerp(STATUS_HOT_COLOR, heat)
		if label then
			label.Text = UiStyle.formatTitle(STATUS_OVERHEATED_TEXT)
			label.Visible = isOverheated
		end
		return
	end
	local _heat, _heatTime, _isOverheated, reloadEndTime = self:readFireState()
	local stats = self.stats
	local progress = PostRules.reloadProgress(reloadEndTime, workspace:GetServerTimeNow(), if stats and stats.reloadSec then stats.reloadSec else 0)
	fill.Size = UDim2.fromScale(progress, 1)
	fill.BackgroundColor3 = if progress >= 1 then STATUS_COOL_COLOR else STATUS_HOT_COLOR
	if label then
		label.Text = UiStyle.formatTitle(STATUS_RELOADING_TEXT)
		label.Visible = progress < 1
	end
end

-- the weapon's own reticle when Icons has one for the kind; the mining dot otherwise
function ClientPostManager:renderReticle()
	local kind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0)
	local imageId = Icons.POST_WEAPON_RETICLE[kind]
	local reticle = self.reticle
	local hasImage = self.isMounted and reticle ~= nil and imageId ~= nil and not Icons.isPlaceholder(imageId)
	if reticle then
		reticle.Image = if hasImage then imageId :: string else ""
		reticle.Visible = hasImage
	end
	ClientMiningManager:setReticleBorrowed(RETICLE_BORROWER, self.isMounted and not hasImage)
end

function ClientPostManager:renderHud()
	self:renderReticle()
	local isGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	if self.fireButton then
		self.fireButton.Visible = self.isMounted and self.isTouchOnly
	end
	if self.exitButton then
		self.exitButton.Visible = self.isMounted and self.isTouchOnly
	end
	if self.exitHint then
		-- touch has the Exit button instead of a hint
		self.exitHint.Visible = self.isMounted and not self.isTouchOnly
		local hint = EXIT_HINT_KEYBOARD
		if isGamepad then
			-- Roblox names the button for the connected controller
			local isPlayStation = string.find(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA), "Cross") ~= nil
			hint = string.format(EXIT_HINT_GAMEPAD_FORMAT, if isPlayStation then GAMEPAD_JUMP_NAME_PLAYSTATION else GAMEPAD_JUMP_NAME_XBOX)
		end
		self.exitHint.Text = UiStyle.formatTitle(hint)
	end
end

function ClientPostManager:setHudHidden(isHidden: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	for _, name in HIDDEN_HUD_GUI_NAMES do
		local gui = if playerGui then playerGui:FindFirstChild(name) else nil
		if gui and gui:IsA("ScreenGui") then
			gui.Enabled = not isHidden
		end
	end
end

-- the Exit button takes the jump button's exact spot, the one place the
-- GUI standard allows offsets read from Roblox's own GUI
function ClientPostManager:placeExitButton()
	local exitButton = self.exitButton
	local jump = ClientTouchLayoutManager:getJumpButton()
	if not exitButton or not jump then
		return
	end
	exitButton.AnchorPoint = Vector2.new(0, 0)
	exitButton.Position = UDim2.fromOffset(jump.AbsolutePosition.X, jump.AbsolutePosition.Y)
	exitButton.Size = UDim2.fromOffset(jump.AbsoluteSize.X, jump.AbsoluteSize.Y)
end

function ClientPostManager:enterMode()
	self:setHudHidden(true)
	if self.isTouchOnly then
		ClientTouchLayoutManager:setJumpButtonHidden(true)
		self:placeExitButton()
	end
	local camera = workspace.CurrentCamera
	if camera then
		self.savedCameraType = camera.CameraType
		self.savedFieldOfView = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		local kindData = self.kindData
		camera.FieldOfView = if kindData then kindData.FIELD_OF_VIEW else DEFAULT_FIELD_OF_VIEW
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	self.lastSentYaw = nil
	self.lastSentPitch = nil
	self.wantedYawDelta = 0
	self.wantedPitchDelta = 0
end

function ClientPostManager:exitMode()
	self:setHudHidden(false)
	ClientTouchLayoutManager:setJumpButtonHidden(false)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = self.savedCameraType or Enum.CameraType.Custom
		camera.FieldOfView = self.savedFieldOfView or DEFAULT_FIELD_OF_VIEW
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local root = self.anchoredRoot
	if root then
		root.Anchored = false
		self.anchoredRoot = nil
	end
	if self.holdInput then
		self.holdInput:cancel()
	end
	ClientSoundManager:stopSfxLoop(SoundNames.Sfx.POST_TURN)
	self.turnLevel = 0
end

function ClientPostManager:setMounted(isMounted: boolean)
	if self.isMounted == isMounted then
		return
	end
	self.isMounted = isMounted
	if isMounted then
		self:readStats()
		self:findMountedView()
		self.predictedHeatTime = nil
		self.predictedHeat = 0
		self.isPredictedOverheated = false
		self:enterMode()
	else
		self:exitMode()
		self.mountedView = nil
	end
	self:renderHud()
	self:renderStatusBar()
	self:renderPrompts()
end

-- a menu opening (the backpack, a store) ends the mode: two things
-- fighting over the camera and the anchored root would be a mess
function ClientPostManager:notifyBeginOverlay()
	self:requestDismount()
end

function ClientPostManager:notifyEndOverlay()
end

function ClientPostManager:onInputChanged(input: InputObject, isGameProcessed: boolean)
	if not self.isMounted or isGameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		self.wantedYawDelta += input.Delta.X * MOUSE_DEGREES_PER_PX
		self.wantedPitchDelta -= input.Delta.Y * MOUSE_DEGREES_PER_PX
	elseif input.UserInputType == Enum.UserInputType.Touch then
		self.wantedYawDelta += input.Delta.X * TOUCH_DEGREES_PER_PX
		self.wantedPitchDelta -= input.Delta.Y * TOUCH_DEGREES_PER_PX
	end
end

function ClientPostManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if not self.isMounted or isGameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.ButtonB then
		self:requestDismount()
	end
end

function ClientPostManager:findHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.POST_HUD_GUI_NAME, 10)
	if not gui then
		warn("ClientPostManager: no PostHud ScreenGui; run scripts/studio/build_post_hud_gui.luau")
		return
	end
	local fireButton = gui:FindFirstChild(Constants.POST_HUD_FIRE_BUTTON)
	if fireButton and fireButton:IsA("GuiButton") then
		self.fireButton = fireButton
		fireButton.MouseButton1Down:Connect(
			function()
				if self.holdInput then
					self.holdInput:beginHold()
				end
			end
		)
		local function release()
			if self.holdInput then
				self.holdInput:endHold()
			end
		end
		fireButton.MouseButton1Up:Connect(release)
		fireButton.MouseLeave:Connect(release)
	end
	local exitButton = gui:FindFirstChild(Constants.POST_HUD_EXIT_BUTTON)
	if exitButton and exitButton:IsA("GuiButton") then
		self.exitButton = exitButton
		exitButton.Activated:Connect(
			function()
				self:requestDismount()
			end
		)
	end
	local reticle = gui:FindFirstChild(Constants.POST_HUD_RETICLE)
	self.reticle = if reticle and reticle:IsA("ImageLabel") then reticle else nil
	local statusBar = gui:FindFirstChild(Constants.POST_HUD_STATUS_BAR)
	self.statusBar = if statusBar and statusBar:IsA("Frame") then statusBar else nil
	local statusFill = if statusBar then statusBar:FindFirstChild(Constants.POST_HUD_STATUS_FILL) else nil
	self.statusFill = if statusFill and statusFill:IsA("Frame") then statusFill else nil
	local statusLabel = gui:FindFirstChild(Constants.POST_HUD_STATUS_LABEL)
	self.statusLabel = if statusLabel and statusLabel:IsA("TextLabel") then statusLabel else nil
	if self.statusBar then
		self.statusBar.Visible = false
	end
	if self.statusLabel then
		self.statusLabel.Visible = false
	end
	local exitHint = gui:FindFirstChild(Constants.POST_HUD_EXIT_HINT_LABEL)
	self.exitHint = if exitHint and exitHint:IsA("TextLabel") then exitHint else nil
	if self.exitHint then
		self.exitHint.Text = UiStyle.formatTitle(EXIT_HINT_KEYBOARD)
	end
end

function ClientPostManager:readCatalog()
	self.catalog = PostRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.POST_CATALOG))
	self:readStats()
end

function ClientPostManager:init()
	self.isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self:findHud()
	self:readCatalog()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.POST_CATALOG,
		function()
			self:readCatalog()
		end
	)
	for _, attributeName in PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attributeName,
			function()
				self:readStats()
			end
		)
	end
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.POST_WEAPON_KIND,
		function()
			self:readStats()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.POST_INDEX,
		function()
			self:renderPrompts()
		end
	)
	local function applyManned(value: any)
		self:setMounted(readNumber(value, PostRules.NO_POST) ~= PostRules.NO_POST)
	end
	applyManned(ClientDataManager:getCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX, applyManned)

	for _, model in CollectionService:GetTagged(Tags.POST) do
		self:bindPost(model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.POST):Connect(
		function(model: Instance)
			self:bindPost(model)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.POST):Connect(
		function(model: Instance)
			self.postPromptsByModel[model :: Model] = nil
		end
	)
	for _, model in CollectionService:GetTagged(Tags.POST_WEAPON) do
		task.spawn(
			function()
				self:bindWeapon(model)
			end
		)
	end
	CollectionService:GetInstanceAddedSignal(Tags.POST_WEAPON):Connect(
		function(model: Instance)
			self:bindWeapon(model)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.POST_WEAPON):Connect(
		function(model: Instance)
			self:unbindWeapon(model)
		end
	)

	local holdInput = ClientHoldInput.new({
		isEnabled = function(): boolean
			return self.isMounted
		end,
		getIntervalSec = function(): number
			local stats = self.stats
			return if stats then stats.fireIntervalSec else 1
		end,
		swing = function(isFreshPress: boolean): boolean
			return self:fire(isFreshPress)
		end,
	})
	holdInput:connect()
	self.holdInput = holdInput

	UserInputService.InputChanged:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputChanged(input, isGameProcessed)
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	-- the jump button leaves the gun (decided 2026-09-18): the touch jump
	-- button, gamepad A, and Space all raise this, so no Exit button is needed
	UserInputService.JumpRequest:Connect(
		function()
			self:requestDismount()
		end
	)
	RunService.RenderStepped:Connect(
		function(deltaTime: number)
			self:onRenderStep(deltaTime)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_WEAPON_FIRED,
		function(payload: any)
			self:onPostWeaponFired(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_ROCKET_LAUNCHED,
		function(payload: any)
			self:onRocketLaunched(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_ROCKET_EXPLODED,
		function(payload: any)
			self:onRocketExploded(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_CLAIMED,
		function(payload: any)
			self:onPostClaimed(payload)
		end
	)
	ClientOverlayManager:addOverlayNotifier(self)
	self:renderHud()
end

function ClientPostManager.new(): ClientPostManager
	local self = setmetatable({}, ClientPostManager) :: ClientPostManager
	self.catalog = nil
	self.viewsByModel = {}
	self.rocketsById = {}
	self.postPromptsByModel = {}
	self.isMounted = false
	self.mountedView = nil
	self.yawDegrees = 0
	self.pitchDegrees = 0
	self.wantedYawDelta = 0
	self.wantedPitchDelta = 0
	self.lastSentYaw = nil
	self.lastSentPitch = nil
	self.lastSendTime = 0
	self.stats = nil
	self.kindData = nil
	self.holdInput = nil
	self.fireButton = nil
	self.exitButton = nil
	self.exitHint = nil
	self.reticle = nil
	self.statusBar = nil
	self.statusFill = nil
	self.statusLabel = nil
	self.predictedHeat = 0
	self.predictedHeatTime = nil
	self.isPredictedOverheated = false
	self.lastTurnTime = 0
	self.turnLevel = 0
	self.isTouchOnly = false
	self.savedCameraType = nil
	self.savedFieldOfView = nil
	self.anchoredRoot = nil
	return self
end

return ClientPostManager.new()
