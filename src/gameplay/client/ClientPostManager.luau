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
-- A projectile kind's shot is drawn by ClientProjectileManager from the
-- launch message (2026-10-16). The class posts add their own showings
-- here: the Railgun's charge as the status bar filling while the trigger
-- is held (the Minigun's bar stays on its heat; its spin-up is heard), the
-- trigger reported to the server as TrySetPostTrigger (the Railgun fires
-- on its release), the
-- AA Launcher's locks as the reticle's readout from the PostWeaponLocks
-- attribute, the Tesla Arc's chain as bolts between the bodies it jumped
-- to, the TNT Launcher's pool of fire, the Mine Layer's armed mines,
-- and the Magnet Gun's pull, each from its own notify.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
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
local ProjectileRules = require("@game/ReplicatedStorage/Shared/ProjectileRules")
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
local ClientHeadshotManager = require(script.Parent.ClientHeadshotManager)
local ClientHoldInput = require(script.Parent.ClientHoldInput)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientProjectileManager = require(script.Parent.ClientProjectileManager)
local ClientScopeGlassManager = require(script.Parent.ClientScopeGlassManager)
local ClientTouchLayoutManager = require(script.Parent.ClientTouchLayoutManager)
local ClientWeaponManager = require(script.Parent.ClientWeaponManager)

local ClientPostManager = {}
ClientPostManager.__index = ClientPostManager

-- an armed mine on the ground as this client draws it
type MineView = {
	part: BasePart,
	light: PointLight?,
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
	-- the spinning barrel, where the template has one: its rest pose
	-- relative to the gun (so it tilts with it), its spin angle, and how
	-- fast it is turning as a share of full speed (0 to 1)
	barrel: BasePart?,
	barrelOffset: CFrame?,
	barrelAngleDegrees: number,
	barrelSpinShare: number,
	-- the parts the designer nested under the gun part (the Railgun's neon
	-- rails), with their rest pose against it: PivotTo turns them with the
	-- base, but the gun's own pitch has to be carried to them by hand
	-- (seen 2026-10-19: they floated level while the gun looked down)
	gunChildOffsets: { [BasePart]: CFrame },
}

export type ClientPostManager = typeof(setmetatable(
	{} :: {
		catalog: PostRules.Catalog?,
		viewsByModel: { [Model]: WeaponView },
		minesById: { [string]: MineView },
		poolParts: { BasePart },
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
		-- a lob kind's landing marker, this gunner's own (2026-10-20)
		targetMarker: BasePart?,
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
		-- the trigger as this client last reported it (a spin-up or charge
		-- kind), and when it closed, for the bar ahead of the server's echo
		isTriggerHeld: boolean,
		triggerStartTime: number?,
		-- true only inside the release of a charge, the one moment a charge
		-- kind may fire (the press used to slip a shot past, 2026-10-19)
		isReleasingCharge: boolean,
		-- the lock ids already announced with the tone, so each sounds once
		announcedLockIds: { [string]: boolean },
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
local NOTIFY_POST_WEAPON_FIRED_SHAPE = {
	userId = "integer",
	postIndex = "positiveInteger",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	origin = "vector3",
	endPosition = "vector3",
	isImpact = "boolean",
	hitId = "string",
	-- a pierce or a chain: every body hit, in order
	hitIds = { type = "array", elementType = "string", optional = true },
	-- the bodies the shot took in the head (the gunner's callout)
	headshotIds = { type = "array", elementType = "string", optional = true },
}
local NOTIFY_POST_POOL_STARTED_SHAPE = {
	poolId = "string",
	position = "vector3",
	radius = "positiveNumber",
	sec = "positiveNumber",
}
local NOTIFY_POST_MINE_PLACED_SHAPE = {
	mineId = "string",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	position = "vector3",
}
local NOTIFY_POST_MINE_REMOVED_SHAPE = {
	mineId = "string",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	position = "vector3",
	isExploded = "boolean",
}
local NOTIFY_POST_PULL_SHAPE = {
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	position = "vector3",
	radius = "positiveNumber",
	sec = "positiveNumber",
}
-- the chain's bolts and a pierce's streak
local BOLT_COLOR = Color3.fromRGB(150, 200, 255)
local BOLT_THICKNESS_STUDS = 0.3
local BOLT_LIFE_SEC = 0.15
-- the status bar's words for the class posts
local STATUS_SPINNING_TEXT = "Spinning up"
-- the barrel at full speed, how long after the last shot it still counts
-- as firing, and how long it takes to wind down once it stops; it winds
-- up over the kind's spin-up so the first shot lands at full speed
local BARREL_SPIN_DEGREES_PER_SEC = 1080
local BARREL_SPIN_LINGER_SEC = 0.2
local BARREL_SPIN_DOWN_SEC = 1.2
local BARREL_SPIN_UP_FALLBACK_SEC = 1
local STATUS_CHARGING_TEXT = "Charging"
local STATUS_LOCKED_FORMAT = "Locked x%d"
-- the fire pool: flames across the radius, and the mine's blink
-- the Napalm pool's Fire: Roblox clamps a Fire's Size to this range
local FIRE_SIZE_MIN = 2
local FIRE_SIZE_MAX = 30
local POOL_FIRE_HEAT = 12
local POOL_FIRE_COLOR = Color3.fromRGB(255, 190, 80)
local POOL_FIRE_SECONDARY_COLOR = Color3.fromRGB(200, 50, 20)
-- the ring of smaller plumes round the centre one, as a share of the radius
local POOL_RING_FIRE_COUNT = 6
local POOL_RING_RADIUS_SHARE = 0.6
local MINE_BLINK_SEC = 0.6
local MINE_PLACEHOLDER_SIZE = Vector3.new(1.2, 0.4, 1.2)
local MINE_COLOR = Color3.fromRGB(70, 75, 70)
local PULL_COLOR = Color3.fromRGB(120, 180, 255)
-- the mines and pools of a run are kept here, under the workspace
local POST_EFFECTS_FOLDER = "PostEffects"

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

-- the sign's Claim Post prompt: only for a player without a post, on a
-- post nobody owns
function ClientPostManager:renderPostPrompt(model: Model, prompt: ProximityPrompt)
	local owner = readNumber(model:GetAttribute(Attributes.POST_OWNER_USER_ID), PostRules.NOBODY)
	local canClaim = owner == PostRules.NOBODY and self:getOwnPostIndex() == PostRules.NO_POST
	prompt.Enabled = canClaim
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
	local promptPart = model:WaitForChild(Constants.POST_WEAPON_PROMPT_PART, 10)
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
	local barrel = model:FindFirstChild(Constants.POST_WEAPON_BARREL_PART)
	local view: WeaponView = {
		model = model,
		gun = gun,
		muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil,
		rig = rig,
		baseCFrame = spawn.CFrame,
		shownYaw = readNumber(model:GetAttribute(Attributes.POST_WEAPON_YAW_DEGREES), 0),
		shownPitch = readNumber(model:GetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES), 0),
		prompt = nil,
		barrel = if barrel and barrel:IsA("BasePart") then barrel else nil,
		-- the template is authored at pitch 0, so the barrel's pose against
		-- the gun now is its rest pose
		barrelOffset = if barrel and barrel:IsA("BasePart") then gun.CFrame:ToObjectSpace(barrel.CFrame) else nil,
		barrelAngleDegrees = 0,
		barrelSpinShare = 0,
		gunChildOffsets = {},
	}
	for _, descendant in gun:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= barrel then
			view.gunChildOffsets[descendant] = gun.CFrame:ToObjectSpace(descendant.CFrame)
		end
	end
	self.viewsByModel[model] = view
	local function bindPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			view.prompt = prompt
			self:renderWeaponPrompt(view)
		end
	end
	local prompt = if promptPart then promptPart:FindFirstChildWhichIsA("ProximityPrompt") else nil
	if prompt then
		bindPrompt(prompt)
	elseif promptPart then
		promptPart.ChildAdded:Connect(bindPrompt)
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
	for part, offset in view.gunChildOffsets do
		part.CFrame = view.gun.CFrame * offset
	end
	local barrel = view.barrel
	local barrelOffset = view.barrelOffset
	if barrel and barrelOffset then
		barrel.CFrame = view.gun.CFrame * barrelOffset * CFrame.Angles(math.rad(view.barrelAngleDegrees), 0, 0)
	end
end

-- whether a post is firing right now, as every client can tell from the
-- server's fire-state echo: the trigger closed (a spin-up or charge kind)
-- or a shot within the linger. The gunner's own view answers from its
-- own trigger and shots, a beat ahead of the echo
function ClientPostManager:isViewFiring(view: WeaponView, now: number): boolean
	if view == self.mountedView and self.isMounted then
		if self.isTriggerHeld then
			return true
		end
		local predictedTime = self.predictedHeatTime
		if typeof(predictedTime) == "number" and now - predictedTime < BARREL_SPIN_LINGER_SEC then
			return true
		end
	end
	if readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_TRIGGER_TIME), 0) > 0 then
		return true
	end
	local lastShotTime = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_HEAT_TIME), 0)
	return lastShotTime > 0 and now - lastShotTime < BARREL_SPIN_LINGER_SEC
end

-- the barrel winds up while the post fires and down when it stops, and
-- turns at its share of full speed
function ClientPostManager:stepBarrel(view: WeaponView, deltaTime: number, now: number)
	if not view.barrel then
		return
	end
	local isFiring = self:isViewFiring(view, now)
	local stats = if view == self.mountedView then self.stats else nil
	local spinUpSec: number = BARREL_SPIN_UP_FALLBACK_SEC
	if stats and typeof(stats.spinUpSec) == "number" then
		spinUpSec = stats.spinUpSec
	end
	local step = deltaTime / (if isFiring then math.max(spinUpSec, 0.01) else BARREL_SPIN_DOWN_SEC)
	view.barrelSpinShare = math.clamp(view.barrelSpinShare + (if isFiring then step else -step), 0, 1)
	view.barrelAngleDegrees = (view.barrelAngleDegrees + view.barrelSpinShare * BARREL_SPIN_DEGREES_PER_SEC * deltaTime) % 360
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
		self:updateTargetMarker()
	end
	local now = workspace:GetServerTimeNow()
	for _, view in self.viewsByModel do
		if view ~= mountedView or not self.isMounted then
			local targetYaw = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_YAW_DEGREES), 0)
			local targetPitch = readNumber(view.model:GetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES), 0)
			local follow = math.min(1, FOLLOW_RATE * deltaTime)
			view.shownYaw = PostRules.wrapDegrees(view.shownYaw + PostRules.wrapDegrees(targetYaw - view.shownYaw) * follow)
			view.shownPitch += (targetPitch - view.shownPitch) * follow
		end
		self:stepBarrel(view, deltaTime, now)
		self:applyView(view)
	end
	self:stepTrigger()
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
	local travelSec = ClientWeaponManager:drawTracer(from, to, UiStyle.POST_TRACER_COLORS[weaponKind], UiStyle.POST_TRACER_SPEEDS[weaponKind])
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

-- where a shot leaves and where it is aimed: the muzzle as this client
-- draws it, and the point the reticle's own ray reaches. The camera sits
-- above the barrel, so a shot parallel to its look landed below the
-- reticle by that offset (seen 2026-10-19): the shot leaves the muzzle
-- toward the reticle's point instead (the server checks only that the
-- origin is at the muzzle)
function ClientPostManager:findAimPoint(view: WeaponView, stats: PostRules.Stats): (Vector3, Vector3, Vector3)
	local base = PostRules.baseFrame(view.baseCFrame, view.shownYaw)
	local gunFrame = PostRules.gunFrame(base, view.rig, view.shownPitch)
	local origin = PostRules.muzzlePosition(gunFrame, view.rig)
	local unitDirection = PostRules.barrelDirection(gunFrame, view.rig)
	local aimPoint = origin + unitDirection * stats.rangeStuds
	local camera = workspace.CurrentCamera
	if camera then
		local cameraPosition = camera.CFrame.Position
		aimPoint = self:findLocalEnd(cameraPosition, camera.CFrame.LookVector, stats.rangeStuds + (origin - cameraPosition).Magnitude)
		local toAimPoint = aimPoint - origin
		-- the server takes an aim point only inside the gun's reach
		if toAimPoint.Magnitude > stats.rangeStuds then
			aimPoint = origin + toAimPoint.Unit * stats.rangeStuds
			toAimPoint = aimPoint - origin
		end
		if toAimPoint.Magnitude > 0 then
			unitDirection = toAimPoint.Unit
		end
	end
	return origin, unitDirection, aimPoint
end

-- a lob kind's landing marker: the GameAssets/Effects part named by the
-- kind, laid flat where the shell will fall (the same solve the server
-- runs), sized to the pool it leaves, the gunner's own and local
function ClientPostManager:updateTargetMarker()
	local view = self.mountedView
	local stats = self.stats
	local kindData = self.kindData
	local projectile = if kindData then kindData.PROJECTILE else nil
	local lobAngle = if projectile then projectile.LOB_ANGLE_DEGREES else nil
	if not self.isMounted or not view or not stats or not projectile or not lobAngle or not projectile.TARGET_TEMPLATE then
		self:removeTargetMarker()
		return
	end
	local marker = self.targetMarker
	if not marker then
		local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
		local effects = if gameAssets then gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER) else nil
		local template = if effects then effects:FindFirstChild(projectile.TARGET_TEMPLATE) else nil
		if not template or not template:IsA("BasePart") then
			return
		end
		marker = template:Clone()
		marker.Parent = workspace
		self.targetMarker = marker
	end
	local origin, _unitDirection, aimPoint = self:findAimPoint(view, stats)
	local lob = ProjectileRules.lobToward(origin, aimPoint, lobAngle, projectile.GRAVITY_STUDS_PER_SEC2 or 0, projectile.SPEED_STUDS_PER_SEC)
	local radius = stats.poolRadiusStuds or projectile.SPLASH_RADIUS_STUDS
	-- a Cylinder part lies along its X, so it is stood on end to lie flat
	marker.Size = Vector3.new(marker.Size.X, radius * 2, radius * 2)
	marker.CFrame = CFrame.new(lob.landing + Vector3.new(0, marker.Size.X / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

function ClientPostManager:removeTargetMarker()
	local marker = self.targetMarker
	if marker then
		marker:Destroy()
		self.targetMarker = nil
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
	-- a charge kind fires on the trigger's release (stepTrigger) and never
	-- from the press or the hold's interval; a spin-up kind only once spun up
	if kindData.CHARGE and not self.isReleasingCharge then
		return false
	end
	if kindData.SPIN_UP and not PostRules.isWoundUp(self.triggerStartTime, workspace:GetServerTimeNow(), stats.spinUpSec or kindData.SPIN_UP.SEC, 0) then
		return false
	end
	local heatData = kindData.HEAT
	if heatData then
		local currentHeat, isOverheated, heatTime = self:getCurrentHeat()
		local elapsedSec = if typeof(heatTime) == "number" then workspace:GetServerTimeNow() - heatTime else nil
		local isFired, newHeat, isNowOverheated = PostRules.heatAfterShot(currentHeat, isOverheated, heatData, stats.fireIntervalSec, elapsedSec)
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
	local origin, unitDirection, aimPoint = self:findAimPoint(view, stats)
	local projectile = kindData.PROJECTILE
	ClientNetManager:fireServer(
		NetEventNames.TRY_FIRE_POST_WEAPON,
		{
			origin = origin,
			direction = unitDirection,
			-- a lob lands on the reticle's point, as the marker showed
			aimPosition = if projectile and projectile.LOB_ANGLE_DEGREES then aimPoint else nil,
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

function ClientPostManager:onPostWeaponFired(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_POST_WEAPON_FIRED_SHAPE)
	if not isValid then
		warn("ClientPostManager: malformed NotifyPostWeaponFired")
		return
	end
	local hitIds: { string } = payload.hitIds or {}
	if #hitIds == 0 and payload.hitId ~= "" then
		hitIds = { payload.hitId }
	end
	for _, hitId in hitIds do
		ClientDamageableManager:flashHit(hitId)
	end
	local catalog = self.catalog
	local kindData = if catalog then catalog.kinds[payload.weaponKind] else nil
	if kindData and kindData.CHAIN then
		-- the arc: a bolt from the muzzle to the first body, then on
		-- between each pair it jumped
		local from: Vector3 = payload.origin
		for _, hitId in hitIds do
			local to = ClientDamageableManager:getBodyPosition(hitId)
			if to then
				self:drawStreak(from, to, BOLT_COLOR, BOLT_THICKNESS_STUDS, BOLT_LIFE_SEC)
				from = to
			end
		end
	end
	local isOwnShot = payload.userId == Players.LocalPlayer.UserId
	local mountedView = self.mountedView
	local isOwnMannedShot = isOwnShot and self.isMounted and mountedView ~= nil and readNumber(mountedView.model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX), 0) == payload.postIndex
	if isOwnShot then
		local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
		if #hitIds > 0 and weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.HIT)
		end
		for _, headshotId in (payload.headshotIds or {}) :: { string } do
			ClientHeadshotManager:showBonus(headshotId)
		end
	end
	if isOwnMannedShot then
		-- this client drew its own shot when it fired; the news is the hit
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
	if kindData and kindData.CHAIN then
		local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
		if weaponSfx then
			ClientSoundManager:playSfxAt(payload.origin, weaponSfx.FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
		end
		return
	end
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
-- own prediction, cooled for the rest since; the third value is when that
-- last shot was, for the next shot's held time
function ClientPostManager:getCurrentHeat(): (number, boolean, number?)
	local kindData = self.kindData
	local stats = self.stats
	local heatData = if kindData then kindData.HEAT else nil
	if not heatData or not stats then
		return 0, false, nil
	end
	local serverHeat, serverTime, isServerOverheated = self:readFireState()
	local heat, heatTime, isOverheated = serverHeat, serverTime, isServerOverheated
	local predictedTime = self.predictedHeatTime
	if predictedTime and (serverTime == nil or predictedTime > serverTime) then
		heat, heatTime, isOverheated = self.predictedHeat, predictedTime, self.isPredictedOverheated
	end
	local now = workspace:GetServerTimeNow()
	local cooled = PostRules.cooledHeat(heat, heatTime, now, stats.fireIntervalSec, stats.coolSec or heatData.COOL_SEC)
	return cooled, isOverheated and cooled > 0, heatTime
end

function ClientPostManager:getIsReloading(): boolean
	local kindData = self.kindData
	if not kindData or not kindData.RELOAD_SEC then
		return false
	end
	local _heat, _heatTime, _isOverheated, reloadEndTime = self:readFireState()
	return WeaponRules.isReloading(reloadEndTime, workspace:GetServerTimeNow())
end

-- the AA Launcher's locks as the server last wrote them: how many are
-- locked and the furthest-along share, with the tone once per new lock
function ClientPostManager:readLocks(): (number, number)
	local view = self.mountedView
	local encoded = if view then view.model:GetAttribute(Attributes.POST_WEAPON_LOCKS) else nil
	if typeof(encoded) ~= "string" or encoded == "" then
		self.announcedLockIds = {}
		return 0, 0
	end
	local isSuccess, rows = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(rows) ~= "table" then
		return 0, 0
	end
	local lockedCount = 0
	local bestShare = 0
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		if typeof(row) ~= "table" or typeof(row.share) ~= "number" then
			continue
		end
		bestShare = math.max(bestShare, row.share)
		if row.share >= 1 then
			lockedCount += 1
			if typeof(row.id) == "string" then
				seen[row.id] = true
				if not self.announcedLockIds[row.id] then
					self.announcedLockIds[row.id] = true
					local weaponSfx = self:getPostWeaponSfx(readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0))
					if weaponSfx and weaponSfx.WINDUP then
						ClientSoundManager:playSfx(weaponSfx.WINDUP)
					end
				end
			end
		end
	end
	for id in self.announcedLockIds do
		if not seen[id] then
			self.announcedLockIds[id] = nil
		end
	end
	return lockedCount, bestShare
end

-- the trigger of a spin-up or charge kind follows the hold: the server is
-- told when it closes and opens, the wind-up sound plays at the close,
-- and a charge kind fires on the release once charged
function ClientPostManager:stepTrigger()
	local kindData = self.kindData
	local holdInput = self.holdInput
	if not self.isMounted or not kindData or not holdInput or (not kindData.SPIN_UP and not kindData.CHARGE) then
		if self.isTriggerHeld then
			self.isTriggerHeld = false
			self.triggerStartTime = nil
		end
		return
	end
	local isHeld = holdInput:getIsHolding()
	if isHeld == self.isTriggerHeld then
		return
	end
	self.isTriggerHeld = isHeld
	local now = workspace:GetServerTimeNow()
	if isHeld then
		ClientNetManager:fireServer(NetEventNames.TRY_SET_POST_TRIGGER, { isHeld = true })
		self.triggerStartTime = now
		local weaponSfx = self:getPostWeaponSfx(readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0))
		if weaponSfx and weaponSfx.WINDUP then
			ClientSoundManager:playSfx(weaponSfx.WINDUP)
		end
		return
	end
	-- the shot goes before the release: a client's messages arrive in order,
	-- and the server forgets the charge the moment the trigger opens, so a
	-- release sent first left every Railgun shot refused (fixed 2026-10-19)
	-- any release fires: the server scales the damage by how far the
	-- charge had come, so a snap shot is a weak shot, not a refused one;
	-- the charge sound stops with the hold whether or not it had finished
	if kindData.CHARGE then
		local weaponSfx = self:getPostWeaponSfx(readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0))
		if weaponSfx and weaponSfx.WINDUP then
			ClientSoundManager:stopSfx(weaponSfx.WINDUP)
		end
		self.isReleasingCharge = true
		self:fire(true)
		self.isReleasingCharge = false
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SET_POST_TRIGGER, { isHeld = false })
	self.triggerStartTime = nil
end

function ClientPostManager:getEffectsFolder(): Folder
	local folder = workspace:FindFirstChild(POST_EFFECTS_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = POST_EFFECTS_FOLDER
	created.Parent = workspace
	return created
end

function ClientPostManager:drawStreak(from: Vector3, to: Vector3, color: Color3, thickness: number, lifeSec: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local streak = Instance.new("Part")
	streak.Name = "Streak"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = color
	streak.Size = Vector3.new(thickness, thickness, length)
	streak.CFrame = CFrame.lookAt((from + to) / 2, to)
	streak.Parent = self:getEffectsFolder()
	Debris:AddItem(streak, lifeSec)
end

-- the TNT Launcher's pool: flames over the radius for as long as it burns
function ClientPostManager:onPoolStarted(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_POOL_STARTED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostPoolStarted")
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = payload.poolId
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(payload.radius * 2, 0.2, payload.radius * 2)
	anchor.CFrame = CFrame.new(payload.position)
	anchor.Parent = self:getEffectsFolder()
	-- Roblox's own Fire (decided 2026-10-20 over a particle volume): one
	-- plume at the centre and a ring of smaller ones, each on its own
	-- invisible part since a Fire sits at its part's centre
	local fires: { Fire } = {}
	local function addFire(offset: Vector3, size: number)
		local holder = Instance.new("Part")
		holder.Name = "Flame"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(payload.position + offset)
		holder.Parent = anchor
		local fire = Instance.new("Fire")
		fire.Name = "Flames"
		fire.Size = size
		fire.Heat = POOL_FIRE_HEAT
		fire.Color = POOL_FIRE_COLOR
		fire.SecondaryColor = POOL_FIRE_SECONDARY_COLOR
		fire.Parent = holder
		table.insert(fires, fire)
	end
	addFire(Vector3.zero, math.clamp(payload.radius * 2, FIRE_SIZE_MIN, FIRE_SIZE_MAX))
	local ringRadius = payload.radius * POOL_RING_RADIUS_SHARE
	for index = 1, POOL_RING_FIRE_COUNT do
		local angle = (index / POOL_RING_FIRE_COUNT) * math.pi * 2
		addFire(Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius), math.clamp(payload.radius, FIRE_SIZE_MIN, FIRE_SIZE_MAX))
	end
	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = payload.radius * 2
	light.Color = Color3.fromRGB(255, 160, 70)
	light.Parent = anchor
	table.insert(self.poolParts, anchor)
	Debris:AddItem(anchor, payload.sec)
	task.delay(
		payload.sec - 0.5,
		function()
			if anchor.Parent then
				for _, fire in fires do
					fire.Enabled = false
				end
			end
		end
	)
end

-- the Mine Layer's mine: the projectile part at rest with a blinking
-- light, until the server says it blew or fizzled
function ClientPostManager:onMinePlaced(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_MINE_PLACED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostMinePlaced")
		return
	end
	local catalog = self.catalog
	local kindData = if catalog then catalog.kinds[payload.weaponKind] else nil
	local projectile = if kindData then kindData.PROJECTILE else nil
	local template = if projectile then ClientProjectileManager:findTemplate(projectile.TEMPLATE) else nil
	local part: BasePart
	if template then
		part = template:Clone()
	else
		part = Instance.new("Part")
		part.Size = MINE_PLACEHOLDER_SIZE
		part.Color = MINE_COLOR
		part.Material = Enum.Material.Metal
		part.Shape = Enum.PartType.Cylinder
	end
	part.Name = payload.mineId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = if template then CFrame.new(payload.position) else CFrame.new(payload.position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = self:getEffectsFolder()
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 4
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Parent = part
	self.minesById[payload.mineId] = { part = part, light = light }
	task.spawn(
		function()
			while part.Parent do
				light.Enabled = not light.Enabled
				task.wait(MINE_BLINK_SEC)
			end
		end
	)
end

function ClientPostManager:onMineRemoved(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_MINE_REMOVED_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostMineRemoved")
		return
	end
	local mine = self.minesById[payload.mineId]
	if mine then
		self.minesById[payload.mineId] = nil
		mine.part:Destroy()
	end
	if not payload.isExploded then
		return
	end
	local catalog = self.catalog
	local kindData = if catalog then catalog.kinds[payload.weaponKind] else nil
	local projectile = if kindData then kindData.PROJECTILE else nil
	local weaponSfx = self:getPostWeaponSfx(payload.weaponKind)
	if weaponSfx and weaponSfx.EXPLODE then
		ClientSoundManager:playSfxAt(payload.position, weaponSfx.EXPLODE, BLAST_FULL_VOLUME_STUDS, BLAST_SILENT_STUDS)
	end
	ClientProjectileManager:playBlast(payload.position, if projectile and projectile.BLAST_TEMPLATE then projectile.BLAST_TEMPLATE else "")
end

-- the Magnet Gun's pull: a ring of light drawn in at the point for as
-- long as the pull lasts
function ClientPostManager:onPull(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_PULL_SHAPE) then
		warn("ClientPostManager: malformed NotifyPostPull")
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Pull"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(payload.position)
	anchor.Parent = self:getEffectsFolder()
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(PULL_COLOR)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.6, 0.1)
	sparks.Lifetime = NumberRange.new(0.6, 0.9)
	-- the particles fly outward and are dragged back: negative drag pulls
	-- them home, which reads as suction
	sparks.Speed = NumberRange.new(payload.radius * 1.2, payload.radius * 1.5)
	sparks.Drag = 4
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 80
	sparks.Parent = anchor
	local light = Instance.new("PointLight")
	light.Brightness = 3
	light.Range = payload.radius
	light.Color = PULL_COLOR
	light.Parent = anchor
	Debris:AddItem(anchor, payload.sec)
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
	if not self.isMounted or not kindData or (not kindData.HEAT and not kindData.RELOAD_SEC and not kindData.SPIN_UP and not kindData.CHARGE and not kindData.LOCK) then
		bar.Visible = false
		if self.statusLabel then
			self.statusLabel.Visible = false
		end
		return
	end
	bar.Visible = true
	local label = self.statusLabel
	local now = workspace:GetServerTimeNow()
	local stats = self.stats
	-- a spin-up that also overheats (the Minigun) keeps the bar on its heat,
	-- which is the number the gunner manages; the half-second spin-up is
	-- heard, not drawn (decided 2026-10-19). A charge is always drawn
	local windupSec = if kindData.CHARGE then (if stats and stats.chargeSec then stats.chargeSec else kindData.CHARGE.SEC) elseif kindData.SPIN_UP and not kindData.HEAT then (if stats and stats.spinUpSec then stats.spinUpSec else kindData.SPIN_UP.SEC) else nil
	if windupSec and self.isTriggerHeld then
		-- the trigger is held: the bar is the spin-up or charge filling
		local progress = PostRules.windupProgress(self.triggerStartTime, now, windupSec)
		fill.Size = UDim2.fromScale(progress, 1)
		fill.BackgroundColor3 = STATUS_HOT_COLOR:Lerp(STATUS_COOL_COLOR, progress)
		if label then
			label.Text = UiStyle.formatTitle(if kindData.SPIN_UP then STATUS_SPINNING_TEXT else STATUS_CHARGING_TEXT)
			label.Visible = progress < 1
		end
		return
	end
	if kindData.LOCK then
		-- the AA Launcher: the bar is the best lock's progress, the label
		-- how many are locked
		local lockedCount, bestShare = self:readLocks()
		fill.Size = UDim2.fromScale(bestShare, 1)
		fill.BackgroundColor3 = STATUS_HOT_COLOR:Lerp(STATUS_COOL_COLOR, bestShare)
		if label then
			label.Text = UiStyle.formatTitle(string.format(STATUS_LOCKED_FORMAT, lockedCount))
			label.Visible = lockedCount > 0
		end
		return
	end
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
	-- a scoped post is aimed through the glass's own reticle: no picture
	-- here and no centre dot borrowed (2026-10-19)
	local isScoped = Icons.POST_WEAPON_SCOPE[kind] ~= nil
	local hasImage = self.isMounted and not isScoped and reticle ~= nil and imageId ~= nil and not Icons.isPlaceholder(imageId)
	if reticle then
		reticle.Image = if hasImage then imageId :: string else ""
		reticle.Visible = hasImage
	end
	ClientMiningManager:setReticleBorrowed(RETICLE_BORROWER, self.isMounted and not hasImage and not isScoped)
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
	-- a scoped post (the Railgun) is manned behind the rifle's glass
	local weaponKind = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.POST_WEAPON_KIND), 0)
	local scopeImage = Icons.POST_WEAPON_SCOPE[weaponKind]
	if scopeImage then
		ClientScopeGlassManager:show(scopeImage)
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	self.lastSentYaw = nil
	self.lastSentPitch = nil
	self.wantedYawDelta = 0
	self.wantedPitchDelta = 0
end

function ClientPostManager:exitMode()
	self:removeTargetMarker()
	self:setHudHidden(false)
	ClientTouchLayoutManager:setJumpButtonHidden(false)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = self.savedCameraType or Enum.CameraType.Custom
		camera.FieldOfView = self.savedFieldOfView or DEFAULT_FIELD_OF_VIEW
	end
	ClientScopeGlassManager:hide()
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
	if self.isTriggerHeld then
		self.isTriggerHeld = false
		ClientNetManager:fireServer(NetEventNames.TRY_SET_POST_TRIGGER, { isHeld = false })
	end
	self.triggerStartTime = nil
	self.announcedLockIds = {}
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
		NetEventNames.NOTIFY_POST_POOL_STARTED,
		function(payload: any)
			self:onPoolStarted(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_MINE_PLACED,
		function(payload: any)
			self:onMinePlaced(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_MINE_REMOVED,
		function(payload: any)
			self:onMineRemoved(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_PULL,
		function(payload: any)
			self:onPull(payload)
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
	self.minesById = {}
	self.poolParts = {}
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
	self.targetMarker = nil
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
	self.isTriggerHeld = false
	self.isReleasingCharge = false
	self.triggerStartTime = nil
	self.announcedLockIds = {}
	self.isTouchOnly = false
	self.savedCameraType = nil
	self.savedFieldOfView = nil
	self.anchoredRoot = nil
	return self
end

return ClientPostManager.new()
