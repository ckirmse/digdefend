--!strict

-- Posts (GDD "Posts", "Post Types"), M25. Every post along the wall is a
-- slot StructureManager fills with the tier's model; this manager owns
-- what happens on it, all as Lua state: who claimed it (the sign's Claim
-- Post prompt), the weapon their class names, cloned from
-- GameAssets/PostWeapons onto the post's Spawn, who is manning the
-- weapon (its Use prompt), the aim the server accepted, and the owner's
-- four upgrade counts. Clients read it back from attributes on the post
-- and weapon models and on AllPlayers, and turn the weapon themselves;
-- the server never moves a part after the spawn. Every shot is a
-- TryFirePostWeapon request carrying the ray the client aimed: the
-- server checks the gunner, the cooldown, and that the ray starts at the
-- muzzle it computes from its own yaw and pitch, then decides the hit
-- exactly as WeaponManager does. Yaw reports are refused when the base
-- could not have turned that far at its turn speed.
--
-- The class posts (2026-10-16) each add one block to the kind's GameData
-- and one branch here, named for the block: a PROJECTILE flies through
-- ProjectileManager (straight, lobbed, piercing, or homing) and lands as
-- a splash, a POOL of fire, or an armed mine (MINES); a HEAT gun
-- overheats; SPIN_UP and CHARGE wait on the trigger, which the client
-- reports held or released (TrySetPostTrigger); PIERCE carries a ray on
-- through several targets; CHAIN jumps a hit to its neighbours; SALVAGE
-- drops Iron where a kill falls; PULL draws monsters to the landing
-- point; LOCK accrues on flyers near the aim and fires a homing missile
-- per lock; IS_UNMANNED has no gunner at all, the server aiming and
-- firing it at the nearest target every Heartbeat.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local FaultLineRules = require("@game/ReplicatedStorage/Shared/FaultLineRules")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local TowerRules = require("@game/ReplicatedStorage/Shared/TowerRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ProjectileRules = require("@game/ReplicatedStorage/Shared/ProjectileRules")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local MapManager = require(script.Parent.MapManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local ProjectileManager = require(script.Parent.ProjectileManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)
local StructureManager = require(script.Parent.StructureManager)
local ToolManager = require(script.Parent.ToolManager)
local WeaponManager = require(script.Parent.WeaponManager)

local PostManager = {}
PostManager.__index = PostManager

-- MonsterManager requires ReviveManager, which requires this module
local monsterManager: any -- prevent circular reference by not initializing here

-- one of the AA Launcher's locks: how long the aim has rested on the
-- target, and whether that is long enough
type Lock = {
	startTime: number,
	isLocked: boolean,
	-- how long this target takes to lock, and whether it flies (a ground
	-- lock's missile does the lock data's ground share, 2026-10-20)
	lockSec: number,
	isAirborne: boolean,
}

type Post = {
	index: number,
	owner: Player?,
	weaponKind: number,
	-- the monster the gunner's reticle is on, as their client last said
	aimedId: string?,
	weaponModel: Model?,
	rig: PostRules.Rig?,
	yawDegrees: number,
	pitchDegrees: number,
	lastAimTime: number?,
	lastFireTime: number?,
	-- overheat (a kind with HEAT): the heat as of the last shot, and the lock
	heat: number,
	isOverheated: boolean,
	-- reload (a kind with RELOAD_SEC): server time it ends, 0 when loaded
	reloadEndTime: number,
	-- server time the trigger closed (SPIN_UP, CHARGE); nil while open
	triggerStartTime: number?,
	-- the AA Launcher's locks by damageable id
	locksById: { [string]: Lock },
	replicatedLocks: string,
	-- an unmanned post's last aim report, so its attributes are written at
	-- the clients' own cadence rather than every Heartbeat
	lastAutoReplicateTime: number,
	gunner: Player?,
	ikControls: { IKControl },
	promptConnections: { RBXScriptConnection },
	-- the post model the claim prompt is wired to, so a fill that keeps the
	-- same model is never bound twice
	boundModel: Model?,
	claimConnection: RBXScriptConnection?,
}

-- a pool of fire on the ground (the TNT Launcher): burns what stands in
-- it every tick until it dies down
type Pool = {
	id: string,
	owner: Player?,
	position: Vector3,
	radiusStuds: number,
	endTime: number,
	nextTickTime: number,
	tickSec: number,
	burnDamagePerSec: number,
	burnSec: number,
}

-- an armed mine on the ground (the Mine Layer)
type Mine = {
	id: string,
	owner: Player,
	postIndex: number,
	weaponKind: number,
	position: Vector3,
	armTime: number,
	triggerRadiusStuds: number,
	damage: number,
	splashRadiusStuds: number,
}

type PlayerState = {
	postIndex: number,
	upgrades: PostRules.Upgrades,
	-- a dev tool's stand-in for the class's post
	loadoutOverride: number?,
	-- the Salvage Gun's Iron dropped so far this night
	salvageIronTonight: number,
}

export type PostManager = typeof(setmetatable(
	{} :: {
		catalog: PostRules.Catalog,
		postsByIndex: { [number]: Post },
		stateByPlayer: { [Player]: PlayerState },
		warnedTemplates: { [string]: boolean },
		pools: { Pool },
		mines: { Mine },
		nextPoolId: number,
		nextMineId: number,
	},
	PostManager
))

local TRY_DISMOUNT_POST_SHAPE = {}
local TRY_SET_POST_AIM_SHAPE = {
	yawDegrees = "number",
	pitchDegrees = "number",
	-- the monster the gunner's reticle sits on as their client draws it
	-- (2026-10-20), for a lock kind; absent when it is on nothing
	aimedId = { type = "string", optional = true },
}
-- how far off the server's own look ray a named aimed monster may sit
-- before it is disbelieved: the reticle's whole frame counts (about
-- twice the lock angle), and the client's aim and its drawn monsters both
-- run a little ahead or behind the server's
local AIMED_ANGLE_SHARE = 6
-- a quarter of a default message, like TrySetAim: the stream must never starve firing
local TRY_SET_POST_AIM_COST = 0.25
-- the machine gun fires every 0.1 s and Fire Rate 4 nearly doubles that,
-- which is more messages than the default bucket refills (10 a second):
-- the seventh playtest (2026-09-29) had a fully upgraded post dropping a
-- third of its shots to the rate limit from night 7 on. The server checks
-- the cooldown and the heat per shot, so a flood of these buys nothing
local TRY_FIRE_POST_WEAPON_COST = 0.25
local TRY_FIRE_POST_WEAPON_SHAPE = {
	origin = "vector3",
	direction = "vector3",
	-- a lob kind's landing spot, where the gunner's reticle reaches
	-- (2026-10-20); it must lie down the direction sent
	aimPosition = { type = "vector3", optional = true },
}
-- how far off the sent direction a lob's aim point may sit
local AIM_POINT_TOLERANCE_DEGREES = 3
local TRY_SET_POST_TRIGGER_SHAPE = {
	isHeld = "boolean",
}
local TRY_UPGRADE_POST_SHAPE = {
	attribute = { type = "enum", name = "PostAttribute" },
}

local NO_HIT_ID = ""
local MIN_DIRECTION_MAGNITUDE = 0.001
local WEAPON_MODEL_FORMAT = "PostWeapon%d"
local POOL_ID_FORMAT = "Pool%d"
local MINE_ID_FORMAT = "Mine%d"
local UNCLAIMED_TEXT = "Unclaimed"
local CLAIM_PROMPT_ATTACHMENT = "ClaimPromptAttachment"
local HEADSHOT_FORMAT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"
-- an unmanned post writes its aim this often, the clients' own cadence
local AUTO_REPLICATE_INTERVAL_SEC = 0.1
-- R15: the chain each hand's IKControl solves from
local IK_ARMS = {
	{ root = "LeftUpperArm", hand = "LeftHand", handle = Constants.POST_WEAPON_HANDLE_LEFT_PART },
	{ root = "RightUpperArm", hand = "RightHand", handle = Constants.POST_WEAPON_HANDLE_RIGHT_PART },
}
-- what a post may hit: everything, on the ground or in the air
local ANY_TARGET_BEHAVIOR = {
	ATTACK = Enums.TowerAttack.SINGLE,
	TARGETS_GROUND = true,
	TARGETS_AIR = true,
	HAS_TURRET = true,
}

local FEEDBACK_ALREADY_OWN_POST = "You already have a post"
local FEEDBACK_POST_TAKEN = "That post is taken"
local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"
local FEEDBACK_NOT_ENOUGH_IRON = "Not enough Iron"
local FEEDBACK_MAXED = "Already maxed out"
local FEEDBACK_NO_SUCH_UPGRADE = "This weapon has no such upgrade"

function PostManager:getCatalog(): PostRules.Catalog
	return self.catalog
end

function PostManager:getPost(index: number): Post?
	return self.postsByIndex[index]
end

function PostManager:getPlayerState(player: Player): PlayerState
	local state = self.stateByPlayer[player]
	if not state then
		state = {
			postIndex = PostRules.NO_POST,
			upgrades = {},
			loadoutOverride = nil,
			salvageIronTonight = 0,
		}
		self.stateByPlayer[player] = state
	end
	return state
end

function PostManager:getPostIndex(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.postIndex else PostRules.NO_POST
end

function PostManager:getOwnedPost(player: Player): Post?
	local index = self:getPostIndex(player)
	return if index ~= PostRules.NO_POST then self.postsByIndex[index] else nil
end

function PostManager:getMannedPost(player: Player): Post?
	for _, post in self.postsByIndex do
		if post.gunner == player then
			return post
		end
	end
	return nil
end

function PostManager:getWeaponData(kind: number): PostRules.KindData?
	return PostWeaponsData.BY_KIND[kind]
end

-- the weapon's numbers after its owner's upgrades
function PostManager:getStats(post: Post): PostRules.Stats?
	local owner = post.owner
	local upgrades = if owner then self:getPlayerState(owner).upgrades else {}
	local stats = PostRules.statsFor(self.catalog, post.weaponKind, upgrades)
	if stats and owner then
		-- the owner's class scales the post's damage on top of its Iron
		-- upgrades (M64); the stats table is fresh per call, so this never
		-- compounds
		local damageScale: number = CharacterManager:getModifier(owner, Enums.ClassModifier.POST_DAMAGE)
		stats.damage *= damageScale
	end
	return stats
end

-- dev tools: stands in for the class's post
function PostManager:setLoadoutOverride(player: Player, kind: number?)
	self:getPlayerState(player).loadoutOverride = kind
end

function PostManager:resolveWeaponKind(player: Player): number
	local state = self:getPlayerState(player)
	if state.loadoutOverride and self:getWeaponData(state.loadoutOverride) then
		return state.loadoutOverride
	end
	local kind = CharacterManager:getGearKind(player, Enums.GearSlot.POST, PostWeaponsData.DEFAULT_POST_WEAPON)
	if not self:getWeaponData(kind) then
		warn(`PostManager: no GameData/Posts/PostWeapons entry for post weapon {kind}; using the default`)
		kind = PostWeaponsData.DEFAULT_POST_WEAPON
	end
	return kind
end

function PostManager:replicatePlayer(player: Player)
	local state = self:getPlayerState(player)
	local mannedPost = self:getMannedPost(player)
	local ownedPost = self:getOwnedPost(player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.POST_INDEX, state.postIndex)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.POST_WEAPON_KIND, if ownedPost then ownedPost.weaponKind else 0)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.MANNED_POST_INDEX, if mannedPost then mannedPost.index else PostRules.NO_POST)
	-- repeated on CurrentPlayer so the owning client reads its own state in one place
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.POST_INDEX, state.postIndex)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.POST_WEAPON_KIND, if ownedPost then ownedPost.weaponKind else 0)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.MANNED_POST_INDEX, if mannedPost then mannedPost.index else PostRules.NO_POST)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.POST_LOADOUT_WEAPON_KIND, self:resolveWeaponKind(player))
	for attribute, attributeName in PostRules.UPGRADE_ATTRIBUTE_BY_POST_ATTRIBUTE do
		SplendidReplicationManager:setCurrentPlayerAttribute(player, attributeName, PostRules.upgradeLevel(state.upgrades, attribute))
	end
end

function PostManager:findSlotModel(index: number): Model?
	for _, slot in StructureManager:getPostSlots() do
		if PostRules.postIndexFromName(slot.name) == index then
			return slot.model
		end
	end
	return nil
end

function PostManager:replicatePost(post: Post)
	local slotModel = self:findSlotModel(post.index)
	if slotModel then
		slotModel:SetAttribute(Attributes.POST_OWNER_USER_ID, if post.owner then post.owner.UserId else PostRules.NOBODY)
	end
	local weaponModel = post.weaponModel
	if weaponModel then
		weaponModel:SetAttribute(Attributes.POST_WEAPON_POST_INDEX, post.index)
		weaponModel:SetAttribute(Attributes.POST_WEAPON_MANNED_USER_ID, if post.gunner then post.gunner.UserId else PostRules.NOBODY)
		weaponModel:SetAttribute(Attributes.POST_WEAPON_YAW_DEGREES, post.yawDegrees)
		weaponModel:SetAttribute(Attributes.POST_WEAPON_PITCH_DEGREES, post.pitchDegrees)
	end
end

-- the heat, reload, and trigger travel separately from the aim: they
-- change per shot, the aim a few times a second
function PostManager:replicateFireState(post: Post)
	local weaponModel = post.weaponModel
	if not weaponModel then
		return
	end
	weaponModel:SetAttribute(Attributes.POST_WEAPON_HEAT, post.heat)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_HEAT_TIME, post.lastFireTime or 0)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_IS_OVERHEATED, post.isOverheated)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_RELOAD_END_TIME, post.reloadEndTime)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_TRIGGER_TIME, post.triggerStartTime or 0)
end

-- the AA Launcher's locks as JSON rows the reticle draws from; written
-- only when a row changes
function PostManager:replicateLocks(post: Post, now: number, lockData: PostRules.LockData)
	local weaponModel = post.weaponModel
	if not weaponModel then
		return
	end
	local rows = {}
	for id, lock in post.locksById do
		table.insert(rows, {
			id = id,
			share = if lock.isLocked then 1 else math.clamp((now - lock.startTime) / lock.lockSec, 0, 1),
		})
	end
	local encoded = HttpService:JSONEncode(rows)
	if encoded ~= post.replicatedLocks then
		post.replicatedLocks = encoded
		weaponModel:SetAttribute(Attributes.POST_WEAPON_LOCKS, encoded)
	end
end

-- the sign reads UNCLAIMED, or the owner's headshot, name, and weapon. Written on the server because the models are server
-- instances already (StructureManager numbers them the same way)
function PostManager:renderSign(post: Post)
	local slotModel = self:findSlotModel(post.index)
	local signModel = if slotModel then slotModel:FindFirstChild(Constants.POST_SIGN_MODEL) else nil
	local signPart = if signModel then signModel:FindFirstChild(Constants.POST_SIGN_PART) else nil
	local gui = if signPart then signPart:FindFirstChildWhichIsA("SurfaceGui") else nil
	if not gui then
		return
	end
	local owner = post.owner
	local unclaimed = gui:FindFirstChild(Constants.POST_SIGN_UNCLAIMED_LABEL)
	if unclaimed and unclaimed:IsA("TextLabel") then
		unclaimed.Text = UiStyle.formatTitle(UNCLAIMED_TEXT)
		unclaimed.Visible = owner == nil
	end
	local thumbnail = gui:FindFirstChild(Constants.POST_SIGN_THUMBNAIL)
	if thumbnail and thumbnail:IsA("ImageLabel") then
		thumbnail.Image = if owner then string.format(HEADSHOT_FORMAT, owner.UserId) else ""
		thumbnail.Visible = owner ~= nil
	end
	local displayName = gui:FindFirstChild(Constants.POST_SIGN_DISPLAY_NAME_LABEL)
	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = if owner then owner.DisplayName else ""
		displayName.Visible = owner ~= nil
	end
	local postType = gui:FindFirstChild(Constants.POST_SIGN_POST_TYPE_LABEL)
	if postType and postType:IsA("TextLabel") then
		postType.Text = if owner then (Enums.getPublicName(Enums.PostWeaponKind, post.weaponKind) or "") else ""
		postType.Visible = owner ~= nil
	end
end

function PostManager:findTemplate(folderName: string, templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(folderName) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") then
		return template
	end
	local key = `{folderName}.{templateName}`
	if not self.warnedTemplates[key] then
		self.warnedTemplates[key] = true
		warn(`PostManager: no Model named {templateName} under GameAssets.{folderName}`)
	end
	return nil
end

function PostManager:getSpawnedFolder(): Instance?
	local camp = MapManager:getCamp()
	if not camp then
		return nil
	end
	local folder = camp:FindFirstChild(Constants.CAMP_POST_WEAPONS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.CAMP_POST_WEAPONS_FOLDER
		folder.Parent = camp
	end
	return folder
end

-- the whole model is anchored: clients move its parts locally every frame,
-- and an unanchored gun would otherwise fall off its base
local function anchorModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

function PostManager:configurePrompt(prompt: ProximityPrompt, actionText: string, holdSec: number, maxDistance: number)
	prompt.ActionText = actionText
	prompt.ObjectText = ""
	prompt.HoldDuration = holdSec
	prompt.MaxActivationDistance = maxDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = false
	prompt.Enabled = true
end

function PostManager:spawnWeapon(post: Post)
	local slotModel = self:findSlotModel(post.index)
	local spawn = if slotModel then slotModel:FindFirstChild(Constants.POST_SPAWN_PART) else nil
	local folder = self:getSpawnedFolder()
	local template = self:findTemplate(Constants.POST_WEAPON_TEMPLATES_FOLDER, PostRules.templateNameFor(post.weaponKind))
	local data = self:getWeaponData(post.weaponKind)
	if not spawn or not spawn:IsA("BasePart") or not folder or not template or not data then
		warn(`PostManager: post {post.index} has no {Constants.POST_SPAWN_PART} part or the weapon template is missing; no weapon spawned`)
		return
	end
	local model = template:Clone()
	model.Name = string.format(WEAPON_MODEL_FORMAT, post.index)
	anchorModel(model)
	model:PivotTo(spawn.CFrame)
	-- the weapon brings its own base, the same cylinder: two would z-fight
	spawn.Transparency = 1
	local rig, reason = PostRules.measureRig(model)
	if not rig then
		warn(`PostManager: {template:GetFullName()}: {reason}; the weapon cannot be aimed`)
	end
	post.rig = rig
	post.yawDegrees = 0
	post.pitchDegrees = 0
	post.heat = 0
	post.isOverheated = false
	post.reloadEndTime = 0
	post.lastFireTime = nil
	post.triggerStartTime = nil
	post.locksById = {}
	post.replicatedLocks = ""
	CollectionService:AddTag(model, Tags.POST_WEAPON)
	model:SetAttribute(Attributes.POST_WEAPON_IS_UNMANNED, data.IS_UNMANNED == true)
	model:SetAttribute(Attributes.POST_WEAPON_WEAPON_KIND, post.weaponKind)
	model.Parent = folder
	post.weaponModel = model
	self:replicateFireState(post)

	local promptPart = model:FindFirstChild(Constants.POST_WEAPON_PROMPT_PART)
	local prompt = if promptPart then promptPart:FindFirstChildWhichIsA("ProximityPrompt") else nil
	if data.IS_UNMANNED then
		-- nobody mans it: the designer's Use prompt goes, so no client ever shows one
		if prompt then
			prompt:Destroy()
		end
		return
	end
	if not promptPart then
		warn(`PostManager: {model:GetFullName()} has no {Constants.POST_WEAPON_PROMPT_PART} part; the weapon cannot be mounted`)
		return
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
		prompt.Parent = promptPart
	end
	local livePrompt = prompt :: ProximityPrompt
	self:configurePrompt(livePrompt, PostWeaponsData.USE_PROMPT_ACTION_TEXT, 0, PostWeaponsData.PROMPT_MAX_DISTANCE_STUDS)
	table.insert(
		post.promptConnections,
		livePrompt.Triggered:Connect(
			function(player: Player)
				self:mount(player, post)
			end
		)
	)
end

-- the Post Upgrade Table in the defense building (2026-10-01): its prompt
-- is created and tagged here, and acted on only by the triggering player's
-- own client, which opens the menu or says a post must be claimed first
function PostManager:bindUpgradeTable()
	local promptPart = MapManager:findDefenseTablePart(Constants.POST_UPGRADE_TABLE_MODEL, Constants.DEFENSE_TABLE_PROMPT_PART)
	if not promptPart then
		warn(`PostManager: the loaded camp has no {Constants.POST_UPGRADE_TABLE_MODEL}.{Constants.DEFENSE_TABLE_PROMPT_PART} in its {Constants.CAMP_DEFENSE_STORE_MODEL}; posts cannot be upgraded`)
		return
	end
	local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = promptPart
	end
	local livePrompt = prompt :: ProximityPrompt
	self:configurePrompt(livePrompt, PostWeaponsData.TABLE_PROMPT_ACTION_TEXT, 0, PostWeaponsData.TABLE_PROMPT_MAX_DISTANCE_STUDS)
	livePrompt.ObjectText = PostWeaponsData.TABLE_PROMPT_OBJECT_TEXT
	CollectionService:AddTag(livePrompt, Tags.POST_UPGRADE_PROMPT)
end

function PostManager:destroyIkControls(post: Post)
	for _, control in post.ikControls do
		control:Destroy()
	end
	post.ikControls = {}
end

-- each hand reaches for its handle; the IKControls are server instances so
-- every client solves the pose for the gunner it sees
function PostManager:createIkControls(post: Post, player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local weaponModel = post.weaponModel
	if not character or not humanoid or not weaponModel then
		return
	end
	for _, arm in IK_ARMS do
		local root = character:FindFirstChild(arm.root)
		local hand = character:FindFirstChild(arm.hand)
		local handle = weaponModel:FindFirstChild(arm.handle)
		if not root or not hand or not handle then
			continue
		end
		local control = Instance.new("IKControl")
		control.Type = Enum.IKControlType.Position
		control.ChainRoot = root
		control.EndEffector = hand
		control.Target = handle
		control.Parent = humanoid
		table.insert(post.ikControls, control)
	end
end

function PostManager:dismount(player: Player)
	local post = self:getMannedPost(player)
	if not post then
		return
	end
	post.gunner = nil
	post.lastAimTime = nil
	post.triggerStartTime = nil
	post.locksById = {}
	self:destroyIkControls(post)
	ToolManager:setToolsLocked(player, false)
	self:replicatePost(post)
	self:replicateFireState(post)
	self:replicatePlayer(player)
end

function PostManager:mount(player: Player, post: Post)
	local data = self:getWeaponData(post.weaponKind)
	if not GameController:isPlayerReady(player) or post.owner ~= player or post.gunner ~= nil or not post.rig or not data or data.IS_UNMANNED then
		return
	end
	if self:getMannedPost(player) then
		return
	end
	local character = player.Character
	local rig = post.rig
	local weaponModel = post.weaponModel
	if not character or not rig or not weaponModel or not weaponModel.PrimaryPart then
		return
	end
	post.gunner = player
	post.lastAimTime = nil
	-- hands off the held tool, and kept off until they step down: the gun
	-- on the post is what they use now (a hotkey at the post once put the
	-- rifle back in hand beside the post gun, 2026-09-29)
	ToolManager:setToolsLocked(player, true)
	character:PivotTo(PostRules.characterFrame(PostRules.baseFrame(weaponModel.PrimaryPart.CFrame, post.yawDegrees), rig))
	self:createIkControls(post, player)
	self:replicatePost(post)
	self:replicatePlayer(player)
end

-- the gunner's own look for the post's current aim: the camera's place
-- and direction, which the reticle sits on (the camera is above the
-- barrel, so the barrel's own line misses what the reticle is on at
-- short range); the Missile Launcher locks along it (2026-10-20)
function PostManager:getLookRay(post: Post): (Vector3?, Vector3?)
	local rig = post.rig
	local weaponModel = post.weaponModel
	if not rig or not weaponModel or not weaponModel.PrimaryPart then
		return nil, nil
	end
	local gunFrame = PostRules.gunFrame(PostRules.baseFrame(weaponModel.PrimaryPart.CFrame, post.yawDegrees), rig, post.pitchDegrees)
	local cameraFrame = PostRules.cameraFrame(gunFrame, rig)
	return cameraFrame.Position, cameraFrame.LookVector
end

-- the muzzle and the barrel's direction for the post's current aim
function PostManager:getAim(post: Post): (Vector3?, Vector3?)
	local rig = post.rig
	local weaponModel = post.weaponModel
	if not rig or not weaponModel or not weaponModel.PrimaryPart then
		return nil, nil
	end
	local gunFrame = PostRules.gunFrame(PostRules.baseFrame(weaponModel.PrimaryPart.CFrame, post.yawDegrees), rig, post.pitchDegrees)
	return PostRules.muzzlePosition(gunFrame, rig), PostRules.barrelDirection(gunFrame, rig)
end

-- whether the gunner's reticle is on this target: their client said so
-- with its last aim (the one source, so the white outline it draws and
-- the lock agree; the server's own ray and the client's drawn monsters
-- disagreed on which of two in a line was under the reticle,
-- 2026-10-20), and the server's own look ray is not far off it
function PostManager:isReticleOn(post: Post, target: DamageableManager.Target, lockData: PostRules.LockData, stats: PostRules.Stats, eye: Vector3, direction: Vector3): boolean
	if post.aimedId ~= target.id then
		return false
	end
	if (target.position - eye).Magnitude > stats.rangeStuds then
		return false
	end
	return PostRules.angleToDegrees(eye, direction, target.position) <= lockData.ANGLE_DEGREES * AIMED_ANGLE_SHARE
end

-- the Missile Launcher's locks (reshaped 2026-10-20, twice): one target
-- locks at a time, the one under the reticle, and it must stay inside the
-- reticle for its seconds (a flyer's SEC, a ground monster's GROUND_SEC)
-- or the lock in progress is dropped and the next starts from nothing. A
-- held lock stays until the volley fires, however the aim wanders, and
-- goes only with the target's death; once the count is held nothing more starts
function PostManager:updateLocks(post: Post, lockData: PostRules.LockData, stats: PostRules.Stats, now: number)
	-- angles from the gunner's own look, the ray the reticle sits on
	local eye, direction = self:getLookRay(post)
	if not eye or not direction then
		return
	end
	local targetById: { [string]: DamageableManager.Target } = {}
	for _, target in DamageableManager:getTargets() do
		targetById[target.id] = target
	end
	-- the held locks, and the one still building
	local lockCount = 0
	local buildingId: string? = nil
	for id, lock in post.locksById do
		local target = targetById[id]
		if not target then
			post.locksById[id] = nil
			continue
		end
		if lock.isLocked then
			lockCount += 1
			continue
		end
		-- a lock in progress needs the reticle to stay on the target
		if not self:isReticleOn(post, target, lockData, stats, eye, direction) then
			post.locksById[id] = nil
			continue
		end
		buildingId = id
		if now - lock.startTime >= lock.lockSec then
			if lockCount < (stats.lockCount or lockData.COUNT) then
				lock.isLocked = true
				lockCount += 1
			else
				post.locksById[id] = nil
			end
			buildingId = nil
		end
	end
	-- with the count held nothing more starts; otherwise the monster under
	-- the reticle starts building
	if buildingId == nil and lockCount < (stats.lockCount or lockData.COUNT) then
		local aimedId = post.aimedId
		local candidate = if aimedId and not post.locksById[aimedId] then targetById[aimedId] else nil
		if candidate and not self:isReticleOn(post, candidate, lockData, stats, eye, direction) then
			candidate = nil
		end
		if candidate then
			post.locksById[candidate.id] = {
				startTime = now,
				isLocked = false,
				lockSec = if candidate.isAirborne then lockData.SEC else (lockData.GROUND_SEC or lockData.SEC),
				isAirborne = candidate.isAirborne,
			}
		end
	end
	self:replicateLocks(post, now, lockData)
end

function PostManager:setAim(player: Player, yawDegrees: number, pitchDegrees: number, aimedId: string?)
	local post = self:getMannedPost(player)
	local data = if post then self:getWeaponData(post.weaponKind) else nil
	local stats = if post then self:getStats(post) else nil
	if not post or not data or not stats then
		return
	end
	local now = workspace:GetServerTimeNow()
	local lastAimTime = post.lastAimTime
	-- the gun tilts no faster than the base turns (decided 2026-09-18), so
	-- both axes are held to the turn speed
	if lastAimTime and not PostRules.isYawStepAllowed(post.yawDegrees, yawDegrees, stats.turnSpeedDegreesPerSec, now - lastAimTime, PostWeaponsData.YAW_TOLERANCE_DEGREES) then
		return
	end
	if lastAimTime and not PostRules.isYawStepAllowed(post.pitchDegrees, pitchDegrees, stats.turnSpeedDegreesPerSec, now - lastAimTime, PostWeaponsData.YAW_TOLERANCE_DEGREES) then
		return
	end
	post.lastAimTime = now
	post.yawDegrees = PostRules.wrapDegrees(yawDegrees)
	post.pitchDegrees = PostRules.clampPitch(pitchDegrees, data)
	post.aimedId = aimedId
	self:replicatePost(post)
end

-- the trigger closed or opened (the class posts, 2026-10-16): a spin-up
-- or a charge counts from the close; the client sends it with the hold
function PostManager:setTrigger(player: Player, isHeld: boolean)
	local post = self:getMannedPost(player)
	local data = if post then self:getWeaponData(post.weaponKind) else nil
	if not post or not data or (not data.SPIN_UP and not data.CHARGE) then
		return
	end
	if isHeld then
		if post.triggerStartTime == nil then
			post.triggerStartTime = workspace:GetServerTimeNow()
		end
	else
		post.triggerStartTime = nil
	end
	self:replicateFireState(post)
end

-- the Salvage Gun: a kill drops Iron where the target stood, up to the
-- night's cap for that owner
function PostManager:salvage(owner: Player, salvage: PostRules.SalvageData, position: Vector3)
	local state = self:getPlayerState(owner)
	local amount = math.min(salvage.IRON_PER_KILL, salvage.CAP_PER_NIGHT - state.salvageIronTonight)
	if amount <= 0 then
		return
	end
	state.salvageIronTonight += amount
	OrePickupManager:dropBars(position, Enums.RefinedResource.IRON_BAR, amount)
end

-- one damageable hit by a post: the damage, and the Salvage Gun's drop
-- when the hit kills
function PostManager:damageTarget(post: Post, hitId: string, amount: number, attacker: Player?)
	local data = self:getWeaponData(post.weaponKind)
	local salvage = if data then data.SALVAGE else nil
	local target = if salvage then DamageableManager:getTarget(hitId) else nil
	local hpLeft = DamageableManager:damage(hitId, amount, attacker)
	if salvage and target and hpLeft == 0 and post.owner then
		self:salvage(post.owner, salvage, target.position)
	end
end

-- a burst at a point: everything within the radius takes the damage
function PostManager:splash(post: Post, position: Vector3, radiusStuds: number, damage: number, attacker: Player?): number
	local hitIds = PostRules.findSplashHits(position, radiusStuds, DamageableManager:getHitBoxes())
	for _, hitId in hitIds do
		self:damageTarget(post, hitId, damage, attacker)
	end
	return #hitIds
end

-- the TNT Launcher's pool: it burns whoever stands in it every tick
function PostManager:startPool(_post: Post, poolData: PostRules.PoolData, stats: PostRules.Stats, position: Vector3, attacker: Player?)
	-- the pool as the gunner's rows shaped it (2026-10-20)
	self:addPool(attacker, position, stats.poolRadiusStuds or poolData.RADIUS_STUDS, stats.poolSec or poolData.SEC, poolData.TICK_SEC, stats.burnDamagePerSec or poolData.BURN_DAMAGE_PER_SEC, stats.burnSec or poolData.BURN_SEC)
end

-- a pool of fire from anything (the TNT Launcher's shell, the Remote
-- Charge's burst, 2026-10-20): stepped here, drawn by every client from
-- the notify
function PostManager:addPool(owner: Player?, position: Vector3, radiusStuds: number, sec: number, tickSec: number, burnDamagePerSec: number, burnSec: number)
	self.nextPoolId += 1
	local now = workspace:GetServerTimeNow()
	local id = string.format(POOL_ID_FORMAT, self.nextPoolId)
	table.insert(self.pools, {
		id = id,
		owner = owner,
		position = position,
		radiusStuds = radiusStuds,
		endTime = now + sec,
		nextTickTime = now,
		tickSec = tickSec,
		burnDamagePerSec = burnDamagePerSec,
		burnSec = burnSec,
	})
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_POOL_STARTED, {
		poolId = id,
		position = position,
		radius = radiusStuds,
		sec = sec,
	})
end

function PostManager:stepPools(now: number)
	if #self.pools == 0 then
		return
	end
	local hitBoxes = DamageableManager:getHitBoxes()
	local survivors = {}
	for _, pool in self.pools do
		if now >= pool.endTime then
			continue
		end
		if now >= pool.nextTickTime then
			pool.nextTickTime = now + pool.tickSec
			for _, hitId in PostRules.findSplashHits(pool.position, pool.radiusStuds, hitBoxes) do
				DamageableManager:applyBurn(hitId, pool.burnDamagePerSec, pool.burnSec)
			end
		end
		table.insert(survivors, pool)
	end
	self.pools = survivors
end

-- the Mine Layer's mine arms where it lands; past the owner's cap the
-- oldest fizzles
function PostManager:placeMine(post: Post, owner: Player, minesData: PostRules.MinesData, projectile: PostRules.ProjectileData, stats: PostRules.Stats, position: Vector3)
	self.nextMineId += 1
	local id = string.format(MINE_ID_FORMAT, self.nextMineId)
	table.insert(self.mines, {
		id = id,
		owner = owner,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		position = position,
		armTime = workspace:GetServerTimeNow() + minesData.ARM_SEC,
		triggerRadiusStuds = minesData.TRIGGER_RADIUS_STUDS,
		damage = stats.damage,
		splashRadiusStuds = projectile.SPLASH_RADIUS_STUDS,
	})
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_MINE_PLACED, {
		mineId = id,
		weaponKind = post.weaponKind,
		position = position,
	})
	local ownedCount = 0
	for index = #self.mines, 1, -1 do
		local mine = self.mines[index]
		if mine.owner ~= owner then
			continue
		end
		ownedCount += 1
		if ownedCount > minesData.MAX_ARMED then
			self:removeMine(index, false)
		end
	end
end

function PostManager:removeMine(index: number, isExploded: boolean)
	local mine = table.remove(self.mines, index)
	if not mine then
		return
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_MINE_REMOVED, {
		mineId = mine.id,
		weaponKind = mine.weaponKind,
		position = mine.position,
		isExploded = isExploded,
	})
end

function PostManager:stepMines(now: number)
	if #self.mines == 0 then
		return
	end
	local targets = DamageableManager:getTargets()
	local index = 1
	while index <= #self.mines do
		local mine = self.mines[index]
		if now < mine.armTime then
			index += 1
			continue
		end
		local isTriggered = false
		for _, target in targets do
			if not target.isAirborne and PostRules.distanceToBox(mine.position, target.cframe, target.size) <= mine.triggerRadiusStuds then
				isTriggered = true
				break
			end
		end
		if not isTriggered then
			index += 1
			continue
		end
		local post = self.postsByIndex[mine.postIndex]
		if post then
			self:splash(post, mine.position, mine.splashRadiusStuds, mine.damage, mine.owner)
		end
		self:removeMine(index, true)
	end
end

-- every mine fizzles at dawn (and with the run)
function PostManager:clearMines()
	while #self.mines > 0 do
		self:removeMine(#self.mines, false)
	end
end

-- a projectile kind's shot: straight, lobbed, piercing, or homing on a
-- lock; what it does where it lands is the kind's block
function PostManager:launchProjectile(post: Post, attacker: Player?, origin: Vector3, unitDirection: Vector3, stats: PostRules.Stats, data: PostRules.KindData, projectile: PostRules.ProjectileData, homingTargetId: string?, damage: number, aimPosition: Vector3?)
	local owner = post.owner
	local homing = projectile.HOMING
	local speedStudsPerSec = projectile.SPEED_STUDS_PER_SEC
	local rangeStuds = stats.rangeStuds
	local lobAngle = projectile.LOB_ANGLE_DEGREES
	if lobAngle then
		-- a lob flies the gun's arc to the aim point (the barrel's own line
		-- when none was sent), and its range is the arc's length, not the
		-- gunner's reach: the reach was applied to the aim point already
		local target = aimPosition or (origin + unitDirection * rangeStuds)
		local lob = ProjectileRules.lobToward(origin, target, lobAngle, projectile.GRAVITY_STUDS_PER_SEC2 or 0, speedStudsPerSec)
		unitDirection = lob.unitDirection
		speedStudsPerSec = lob.speedStudsPerSec
		rangeStuds = speedStudsPerSec * lob.flightSec * 2 + rangeStuds
	elseif aimPosition and (projectile.GRAVITY_STUDS_PER_SEC2 or 0) > 0 then
		-- a falling shot is raised to land on the reticle's point (the
		-- drill, 2026-10-22); out of reach it flies the straight line
		local aim = ProjectileRules.aimToward(origin, aimPosition, projectile.GRAVITY_STUDS_PER_SEC2 or 0, speedStudsPerSec)
		if aim.isReached then
			unitDirection = aim.unitDirection
			rangeStuds = math.max(rangeStuds, speedStudsPerSec * aim.flightSec * 1.5)
		end
	end
	local excludedInstances: { Instance } = {}
	if post.weaponModel then
		table.insert(excludedInstances, post.weaponModel)
	end
	ProjectileManager:launch({
		owner = attacker,
		templateName = projectile.TEMPLATE,
		blastTemplateName = projectile.BLAST_TEMPLATE,
		postWeaponKind = post.weaponKind,
		origin = origin,
		unitDirection = unitDirection,
		speedStudsPerSec = speedStudsPerSec,
		gravityStudsPerSec2 = projectile.GRAVITY_STUDS_PER_SEC2 or 0,
		rangeStuds = rangeStuds,
		excludedInstances = excludedInstances,
		isPiercing = projectile.IS_PIERCING,
		isReturning = projectile.IS_RETURNING,
		homingTargetId = homingTargetId,
		homingTurnDegreesPerSec = if homing then homing.TURN_DEGREES_PER_SEC else nil,
		onHit = if projectile.IS_PIERCING
			then function(hitId: string, _position: Vector3)
				self:damageTarget(post, hitId, damage, attacker)
			end
			else nil,
		onEnd = function(position: Vector3, hitId: string?, isSpent: boolean)
			if data.MINES and owner then
				self:placeMine(post, owner, data.MINES, projectile, stats, position)
				return
			end
			local faultLine = data.FAULT_LINE
			if faultLine then
				-- a drill that ran out of range in the air bursts and that is
				-- all: no crack under a bit that struck nothing (designer,
				-- 2026-10-22)
				if not isSpent then
					self:runFaultLine(post, attacker, position, unitDirection, stats, faultLine)
				end
				return
			end
			local splashRadius = stats.splashRadiusStuds or projectile.SPLASH_RADIUS_STUDS
			if splashRadius > 0 then
				self:splash(post, position, splashRadius, damage, attacker)
			elseif hitId and not projectile.IS_PIERCING then
				-- a plain shot (the Nail Gun's nail) hurts the one body it lands on
				self:damageTarget(post, hitId, damage, attacker)
			end
			if data.POOL then
				self:startPool(post, data.POOL, stats, position, attacker)
			end
		end,
	})
end

-- the Fault Line Drill's crack: where its drill stopped (a body, the
-- world, or the end of its flight), the crack starts on the ground under
-- that spot and runs on in the shot's flat direction for the block's
-- length. The hits and the crack's points are FaultLineRules' over the
-- path grid's ground heights; the points go to every client, which draws
-- the same spikes from them. The body the drill struck itself is on the
-- crack's first point, so it is hit the same way as the rest
function PostManager:runFaultLine(post: Post, attacker: Player?, landing: Vector3, unitDirection: Vector3, stats: PostRules.Stats, faultLine: PostRules.FaultLineData)
	local flatDirection = FaultLineRules.flatDirection(unitDirection)
	if not flatDirection then
		return
	end
	local groundHeightAt: FaultLineRules.GroundHeightAt = function(x: number, z: number): number?
		return MonsterPathManager:getGroundHeight(x, z)
	end
	local origin = Vector3.new(landing.X, groundHeightAt(landing.X, landing.Z) or landing.Y, landing.Z)
	local lengthStuds = faultLine.LENGTH_STUDS
	local holdSec = stats.knockdownSec or faultLine.KNOCKDOWN_SEC
	local hitIds = FaultLineRules.hitsAlong(origin, flatDirection, lengthStuds, faultLine.WIDTH_STUDS, DamageableManager:getTargets(), groundHeightAt, faultLine.GROUND_TOLERANCE_STUDS)
	for _, hitId in hitIds do
		self:damageTarget(post, hitId, stats.damage, attacker)
		DamageableManager:applyKnockdown(hitId, holdSec)
	end
	local userId = if attacker then attacker.UserId else PostRules.NOBODY
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_FAULT_LINE, {
		userId = userId,
		weaponKind = post.weaponKind,
		points = FaultLineRules.samplePoints(origin, flatDirection, lengthStuds, faultLine.SPIKE_SPACING_STUDS, groundHeightAt),
		widthStuds = faultLine.WIDTH_STUDS,
		spikeSec = holdSec,
		raceStudsPerSec = faultLine.RACE_STUDS_PER_SEC,
	})
	-- the hit flashes and the gunner's hit confirm ride the usual message
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_WEAPON_FIRED, {
		userId = userId,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		origin = origin,
		endPosition = origin + flatDirection * lengthStuds,
		isImpact = false,
		hitId = hitIds[1] or NO_HIT_ID,
		hitIds = hitIds,
	})
end

-- the shot itself, once the gunner (or the unmanned post) is allowed it:
-- the kind's block decides what leaves the muzzle
function PostManager:fireShot(post: Post, attacker: Player?, origin: Vector3, unitDirection: Vector3, stats: PostRules.Stats, data: PostRules.KindData, aimPosition: Vector3?, _chargeProgress: number?)
	local projectile = data.PROJECTILE
	if projectile then
		local lockData = data.LOCK
		if lockData then
			local lockedIds = {}
			for id, lock in post.locksById do
				if lock.isLocked then
					table.insert(lockedIds, id)
				end
			end
			if #lockedIds > 0 then
				for _, id in lockedIds do
					local lock = post.locksById[id]
					local damageShare = if lock and not lock.isAirborne then (lockData.GROUND_DAMAGE_SHARE or 1) else 1
					self:launchProjectile(post, attacker, origin, unitDirection, stats, data, projectile, id, stats.damage * damageShare)
				end
			else
				self:launchProjectile(post, attacker, origin, unitDirection, stats, data, projectile, nil, stats.damage * lockData.DUMB_FIRE_DAMAGE_SHARE)
			end
			post.locksById = {}
			post.replicatedLocks = ""
			if post.weaponModel then
				post.weaponModel:SetAttribute(Attributes.POST_WEAPON_LOCKS, "")
			end
			return
		end
		self:launchProjectile(post, attacker, origin, unitDirection, stats, data, projectile, nil, stats.damage, aimPosition)
		return
	end
	local worldDistance = WeaponManager:getWorldDistance(origin, unitDirection, stats.rangeStuds, true)
	local hitBoxes = DamageableManager:getHitBoxes()
	local userId = if attacker then attacker.UserId else PostRules.NOBODY
	local pull = data.PULL
	if pull then
		-- no damage: the shot's landing point is where the magnet pulls to
		local _hitId, hitDistance = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, hitBoxes)
		local point = origin + unitDirection * (hitDistance or worldDistance)
		local radius = stats.pullRadiusStuds or pull.RADIUS_STUDS
		monsterManager:applyPull(point, radius, pull.SEC, pull.SPEED_STUDS_PER_SEC)
		NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_PULL, {
			weaponKind = post.weaponKind,
			position = point,
			radius = radius,
			sec = pull.SEC,
		})
		NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_WEAPON_FIRED, {
			userId = userId,
			postIndex = post.index,
			weaponKind = post.weaponKind,
			origin = origin,
			endPosition = point,
			isImpact = true,
			hitId = NO_HIT_ID,
		})
		return
	end
	local headshotMultiplier = stats.headshotMultiplier
	local pierceCount = stats.pierceCount
	if pierceCount then
		local hitIds, hitDistances = WeaponRules.findPierceHits(origin, unitDirection, worldDistance, hitBoxes, pierceCount)
		local headshotIds = {}
		for index, hitId in hitIds do
			local damage = stats.damage
			if headshotMultiplier > 1 and self:isHeadshot(hitId, origin + unitDirection * hitDistances[index]) then
				damage *= headshotMultiplier
				table.insert(headshotIds, hitId)
			end
			self:damageTarget(post, hitId, damage, attacker)
		end
		NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_WEAPON_FIRED, {
			userId = userId,
			postIndex = post.index,
			weaponKind = post.weaponKind,
			origin = origin,
			endPosition = origin + unitDirection * worldDistance,
			isImpact = worldDistance < stats.rangeStuds,
			hitId = hitIds[1] or NO_HIT_ID,
			hitIds = hitIds,
			headshotIds = headshotIds,
		})
		return
	end
	local hitId, hitDistance = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, hitBoxes)
	local endDistance = hitDistance or worldDistance
	local chainIds: { string }? = nil
	local headshotIds: { string } = {}
	if hitId and hitDistance then
		local chain = data.CHAIN
		local first = if chain then DamageableManager:getTarget(hitId) else nil
		if chain and first then
			-- the arc jumps from the hit to its neighbours before any of
			-- them takes damage, so a kill never breaks the chain
			chainIds = {}
			for _, target in TowerRules.chainTargets(first, DamageableManager:getTargets(), chain.COUNT, stats.chainJumpStuds or chain.JUMP_STUDS, ANY_TARGET_BEHAVIOR) do
				table.insert(chainIds :: { string }, target.id)
			end
			for _, id in chainIds :: { string } do
				self:damageTarget(post, id, stats.damage, attacker)
			end
		else
			local damage = stats.damage
			if headshotMultiplier > 1 and self:isHeadshot(hitId, origin + unitDirection * hitDistance) then
				damage *= headshotMultiplier
				table.insert(headshotIds, hitId)
			end
			self:damageTarget(post, hitId, damage, attacker)
		end
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_WEAPON_FIRED, {
		userId = userId,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		origin = origin,
		endPosition = origin + unitDirection * endDistance,
		isImpact = hitId ~= nil or worldDistance < stats.rangeStuds,
		hitId = hitId or NO_HIT_ID,
		hitIds = chainIds,
		headshotIds = headshotIds,
	})
end

-- whether a shot's hit point lies in the target's head (WeaponRules.HEAD_SHARE)
function PostManager:isHeadshot(hitId: string, hitPoint: Vector3): boolean
	local target = DamageableManager:getTarget(hitId)
	if not target then
		return false
	end
	return WeaponRules.isHeadshot(hitPoint, target.cframe, target.size, WeaponRules.HEAD_SHARE)
end

-- whether the post may fire now, and the heat and reload a shot sets;
-- shared by the gunner's request and the unmanned step
-- whether the shot may happen now, and how far a charge had come (0 to 1;
-- 1 for every kind without one): a released charge fires at any point,
-- and fire() scales the shot by it (2026-10-19)
function PostManager:tryBeginShot(post: Post, data: PostRules.KindData, stats: PostRules.Stats, now: number): (boolean, number)
	if not WeaponRules.canFire(post.lastFireTime, now, stats.fireCooldownSec) then
		return false, 0
	end
	-- a reloading gun is empty; an overheated one waits for cool
	if data.RELOAD_SEC and WeaponRules.isReloading(post.reloadEndTime, now) then
		return false, 0
	end
	if data.SPIN_UP and not PostRules.isWoundUp(post.triggerStartTime, now, stats.spinUpSec or data.SPIN_UP.SEC, PostWeaponsData.WINDUP_TOLERANCE_SEC) then
		return false, 0
	end
	local chargeProgress = 1
	if data.CHARGE then
		-- no trigger closed means no charge at all: the press is the only way in
		if post.triggerStartTime == nil then
			return false, 0
		end
		chargeProgress = PostRules.windupProgress(post.triggerStartTime, now + PostWeaponsData.WINDUP_TOLERANCE_SEC, stats.chargeSec or data.CHARGE.SEC)
		-- the release is the shot: the next one charges from nothing
		post.triggerStartTime = nil
	end
	if data.HEAT then
		local currentHeat = PostRules.cooledHeat(post.heat, post.lastFireTime, now, stats.fireIntervalSec, stats.coolSec or data.HEAT.COOL_SEC)
		local elapsedSec = if post.lastFireTime then now - post.lastFireTime else nil
		local isFired, newHeat, isOverheated = PostRules.heatAfterShot(currentHeat, post.isOverheated, data.HEAT, stats.fireIntervalSec, elapsedSec)
		if not isFired then
			return false, 0
		end
		post.heat = newHeat
		post.isOverheated = isOverheated
	end
	if stats.reloadSec then
		post.reloadEndTime = now + stats.reloadSec
	end
	post.lastFireTime = now
	self:replicateFireState(post)
	return true, chargeProgress
end

function PostManager:fire(player: Player, origin: Vector3, direction: Vector3, aimPosition: Vector3?)
	local post = self:getMannedPost(player)
	local stats = if post then self:getStats(post) else nil
	local data = if post then self:getWeaponData(post.weaponKind) else nil
	if not post or not stats or not data then
		return
	end
	if direction.Magnitude < MIN_DIRECTION_MAGNITUDE then
		return
	end
	local muzzle = self:getAim(post)
	if not muzzle or not WeaponRules.isOriginPlausible(muzzle, origin, PostWeaponsData.ORIGIN_TOLERANCE_STUDS) then
		return
	end
	-- the aim point is only ever where the direction sent already leads,
	-- and no farther than the gun reaches
	if aimPosition then
		local toAim = aimPosition - origin
		if toAim.Magnitude > stats.rangeStuds + PostWeaponsData.ORIGIN_TOLERANCE_STUDS or PostRules.angleToDegrees(origin, direction.Unit, aimPosition) > AIM_POINT_TOLERANCE_DEGREES then
			return
		end
	end
	local now = workspace:GetServerTimeNow()
	local isFired, chargeProgress = self:tryBeginShot(post, data, stats, now)
	if not isFired then
		return
	end
	if chargeProgress < 1 then
		-- a part-charged shot: damage by the square of the charge, fewer
		-- bodies pierced; the stats table is fresh per call, so this never compounds
		local partStats: PostRules.Stats = table.clone(stats :: any)
		partStats.damage = partStats.damage * PostRules.chargeDamageShare(chargeProgress)
		local pierceCount = partStats.pierceCount
		if pierceCount then
			partStats.pierceCount = PostRules.chargePierceCount(chargeProgress, pierceCount)
		end
		stats = partStats
	end
	self:fireShot(post, player, origin, direction.Unit, stats, data, aimPosition, chargeProgress)
end

-- an unmanned post (the Auto Machine Gun): every Heartbeat it turns
-- toward the nearest target in range at its turn speed and fires once
-- its barrel is on it, with the owner credited
function PostManager:stepUnmanned(post: Post, data: PostRules.KindData, now: number, deltaSec: number)
	local owner = post.owner
	local stats = self:getStats(post)
	local weaponModel = post.weaponModel
	local muzzle, direction = self:getAim(post)
	if not owner or not stats or not weaponModel or not weaponModel.PrimaryPart or not muzzle or not direction then
		return
	end
	local target = TowerRules.pickTarget(muzzle, stats.rangeStuds, Enums.TargetPriority.CLOSEST, DamageableManager:getTargets(), ANY_TARGET_BEHAVIOR)
	if not target then
		return
	end
	-- the yaw from the base (the gun turns about it), the pitch from the
	-- muzzle, where the shot leaves; the muzzle moves with the pitch, so
	-- each Heartbeat's step from the last muzzle settles on the target
	local wantedYaw = PostRules.aimAnglesToward(weaponModel.PrimaryPart.CFrame, target.position)
	local wantedPitch = PostRules.pitchDegreesToward(muzzle, target.position)
	post.yawDegrees = PostRules.stepYawToward(post.yawDegrees, wantedYaw, stats.turnSpeedDegreesPerSec, deltaSec)
	local maxPitchStep = PostRules.maxYawStep(stats.turnSpeedDegreesPerSec, deltaSec)
	post.pitchDegrees = PostRules.clampPitch(post.pitchDegrees + math.clamp(wantedPitch - post.pitchDegrees, -maxPitchStep, maxPitchStep), data)
	if now - post.lastAutoReplicateTime >= AUTO_REPLICATE_INTERVAL_SEC then
		post.lastAutoReplicateTime = now
		self:replicatePost(post)
	end
	local aimedMuzzle, aimedDirection = self:getAim(post)
	if not aimedMuzzle or not aimedDirection then
		return
	end
	if PostRules.angleToDegrees(aimedMuzzle, aimedDirection, target.position) > PostWeaponsData.UNMANNED_AIM_TOLERANCE_DEGREES then
		return
	end
	if not self:tryBeginShot(post, data, stats, now) then
		return
	end
	-- an unmanned lob lands on the target itself
	self:fireShot(post, owner, aimedMuzzle, aimedDirection, stats, data, target.position)
end

function PostManager:step(deltaSec: number)
	if RunPauseManager:isPaused() or RunCycleRules.isRunOver(RunCycleManager:getRunState()) then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, post in self.postsByIndex do
		local data = if post.owner then self:getWeaponData(post.weaponKind) else nil
		if data and data.IS_UNMANNED then
			self:stepUnmanned(post, data, now, deltaSec)
		end
		-- a manned lock kind builds its lock every Heartbeat, aim moving or
		-- still (until 2026-10-20 only an aim message ticked it, so a held
		-- aim never locked and the bar never filled)
		if data and data.LOCK and post.gunner then
			local stats = self:getStats(post)
			if stats then
				self:updateLocks(post, data.LOCK, stats, now)
			end
		end
	end
	self:stepPools(now)
	self:stepMines(now)
end

-- upgrades belong to the player, not the post (2026-10-06), and cost Iron
-- (M63: Gold buys mining, Iron buys defense): they can be bought before a
-- claim, against the class weapon the claim would spawn, and a claimed
-- post fires with them from its first shot
function PostManager:upgrade(player: Player, attribute: number)
	if not GameController:isPlayerReady(player) then
		return
	end
	local post = self:getOwnedPost(player)
	local weaponKind = if post then post.weaponKind else self:resolveWeaponKind(player)
	local state = self:getPlayerState(player)
	if not PostRules.kindHasAttribute(self.catalog, weaponKind, attribute) then
		PlayerFeedbackManager:give(player, FEEDBACK_NO_SUCH_UPGRADE)
		return
	end
	local offer = PostRules.getUpgradeOffer(self.catalog, state.upgrades, attribute)
	if offer.status == Enums.StoreOffer.MAXED then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	local price = offer.price or 0
	if not PostRules.canAfford(RefineryManager:getIronBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	if not RefineryManager:spendIronBars(player, price, `post {Enums.getPublicName(Enums.PostAttribute, attribute)} {offer.level or 1}`) then
		return
	end
	state.upgrades[attribute] = offer.level or 1
	self:replicatePlayer(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_POST_UPGRADED, {
		attribute = attribute,
		level = state.upgrades[attribute],
		price = price,
	})
	print(`[PostManager] {player.Name} upgraded {Enums.getPublicName(Enums.PostAttribute, attribute)} to {state.upgrades[attribute]} for {price} Iron`)
end

function PostManager:claim(player: Player, post: Post)
	if not GameController:isPlayerReady(player) then
		return
	end
	if self:getOwnedPost(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_ALREADY_OWN_POST)
		return
	end
	if post.owner then
		PlayerFeedbackManager:give(player, FEEDBACK_POST_TAKEN)
		return
	end
	local price = self.catalog.claimPriceGold
	if not PostRules.canAfford(RefineryManager:getGoldBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_GOLD)
		return
	end
	if not RefineryManager:spendGoldBars(player, price, `post {post.index} claim`) then
		return
	end
	post.owner = player
	post.weaponKind = self:resolveWeaponKind(player)
	self:getPlayerState(player).postIndex = post.index
	self:spawnWeapon(post)
	self:renderSign(post)
	self:replicatePost(post)
	self:replicatePlayer(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_POST_CLAIMED, {
		postIndex = post.index,
		weaponKind = post.weaponKind,
		price = price,
	})
	print(`[PostManager] {player.Name} claimed post {post.index} with a {Enums.getPublicName(Enums.PostWeaponKind, post.weaponKind)} for {price} Gold`)
end

-- a class change mid-run (the dev tool): the loadout attribute follows,
-- and a claimed post is rebuilt as the new class's weapon in place. The
-- gunner is dismounted first, since the rig and prompt belong to the model
function PostManager:applyClass(player: Player)
	local post = self:getOwnedPost(player)
	if not post then
		if player.Parent then
			self:replicatePlayer(player)
		end
		return
	end
	local weaponKind = self:resolveWeaponKind(player)
	if weaponKind == post.weaponKind then
		self:replicatePlayer(player)
		return
	end
	if post.gunner then
		self:dismount(post.gunner)
	end
	for _, connection in post.promptConnections do
		connection:Disconnect()
	end
	post.promptConnections = {}
	if post.weaponModel then
		post.weaponModel:Destroy()
		post.weaponModel = nil
	end
	post.rig = nil
	post.weaponKind = weaponKind
	self:spawnWeapon(post)
	self:renderSign(post)
	self:replicatePost(post)
	self:replicatePlayer(player)
	print(`[PostManager] {player.Name}'s post {post.index} is now a {Enums.getPublicName(Enums.PostWeaponKind, post.weaponKind)}`)
end

-- a claim ends only with the player (disconnect, or a dev-tool reset):
-- the weapon goes, the sign reads Unclaimed again, and its mines fizzle
function PostManager:release(player: Player)
	self:dismount(player)
	local post = self:getOwnedPost(player)
	local state = self.stateByPlayer[player]
	if state then
		state.postIndex = PostRules.NO_POST
		state.upgrades = {}
	end
	if not post then
		return
	end
	for index = #self.mines, 1, -1 do
		if self.mines[index].owner == player then
			self:removeMine(index, false)
		end
	end
	post.owner = nil
	post.gunner = nil
	post.rig = nil
	post.locksById = {}
	for _, connection in post.promptConnections do
		connection:Disconnect()
	end
	post.promptConnections = {}
	if post.weaponModel then
		post.weaponModel:Destroy()
		post.weaponModel = nil
	end
	local slotModel = self:findSlotModel(post.index)
	local spawn = if slotModel then slotModel:FindFirstChild(Constants.POST_SPAWN_PART) else nil
	if spawn and spawn:IsA("BasePart") then
		spawn.Transparency = 0
	end
	self:renderSign(post)
	self:replicatePost(post)
	if player.Parent then
		self:replicatePlayer(player)
	end
end

function PostManager:bindClaimPrompt(post: Post)
	local slotModel = self:findSlotModel(post.index)
	local signModel = if slotModel then slotModel:FindFirstChild(Constants.POST_SIGN_MODEL) else nil
	local signPart = if signModel then signModel:FindFirstChild(Constants.POST_SIGN_PART) else nil
	if not signPart or not signPart:IsA("BasePart") then
		warn(`PostManager: post {post.index} has no {Constants.POST_SIGN_MODEL}.{Constants.POST_SIGN_PART} part; it cannot be claimed`)
		return
	end
	-- the prompt hangs from an attachment below the sign's centre, so its
	-- bubble sits under the text rather than over it
	local attachment = signPart:FindFirstChild(CLAIM_PROMPT_ATTACHMENT)
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = CLAIM_PROMPT_ATTACHMENT
		attachment.Parent = signPart
	end
	local liveAttachment = attachment :: Attachment
	liveAttachment.Position = signPart.CFrame:PointToObjectSpace(signPart.Position - Vector3.new(0, PostWeaponsData.CLAIM_PROMPT_DROP_STUDS, 0))
	local prompt = liveAttachment:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
		prompt.Parent = liveAttachment
	end
	local livePrompt = prompt :: ProximityPrompt
	self:configurePrompt(livePrompt, PostWeaponsData.CLAIM_PROMPT_ACTION_TEXT, PostWeaponsData.CLAIM_PROMPT_HOLD_SEC, PostWeaponsData.CLAIM_PROMPT_MAX_DISTANCE_STUDS)
	if post.claimConnection then
		post.claimConnection:Disconnect()
	end
	post.claimConnection = livePrompt.Triggered:Connect(
		function(player: Player)
			self:claim(player, post)
		end
	)
	post.boundModel = slotModel
end

-- StructureManager just swapped the post models (run start or a new
-- fortification tier): the signs are blank and the prompts gone, and a
-- claimed weapon must land on the new model's Spawn
function PostManager:bindPostModels()
	for _, slot in StructureManager:getPostSlots() do
		local index = PostRules.postIndexFromName(slot.name)
		if not index then
			warn(`PostManager: post marker {slot.name} is not named Post<n>; skipped`)
			continue
		end
		local post = self.postsByIndex[index]
		if not post then
			post = {
				index = index,
				owner = nil,
				weaponKind = PostWeaponsData.DEFAULT_POST_WEAPON,
				weaponModel = nil,
				rig = nil,
				yawDegrees = 0,
				pitchDegrees = 0,
				lastAimTime = nil,
				lastFireTime = nil,
				heat = 0,
				isOverheated = false,
				reloadEndTime = 0,
				triggerStartTime = nil,
				locksById = {},
				replicatedLocks = "",
				aimedId = nil,
				lastAutoReplicateTime = 0,
				gunner = nil,
				ikControls = {},
				promptConnections = {},
				boundModel = nil,
				claimConnection = nil,
			}
			self.postsByIndex[index] = post
		end
		if post.boundModel ~= slot.model then
			self:bindClaimPrompt(post)
		end
		self:renderSign(post)
		local spawn = if slot.model then slot.model:FindFirstChild(Constants.POST_SPAWN_PART) else nil
		if post.weaponModel and spawn and spawn:IsA("BasePart") then
			post.weaponModel:PivotTo(spawn.CFrame)
			spawn.Transparency = 1
		end
		self:replicatePost(post)
	end
end

function PostManager:getNetHandlers()
	return {
		[NetEventNames.TRY_DISMOUNT_POST] = {
			shape = TRY_DISMOUNT_POST_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:dismount(player)
			end,
		},
		[NetEventNames.TRY_SET_POST_AIM] = {
			shape = TRY_SET_POST_AIM_SHAPE,
			cost = TRY_SET_POST_AIM_COST,
			handler = function(player: Player, payload: { [string]: any })
				self:setAim(player, payload.yawDegrees, payload.pitchDegrees, payload.aimedId)
			end,
		},
		[NetEventNames.TRY_FIRE_POST_WEAPON] = {
			shape = TRY_FIRE_POST_WEAPON_SHAPE,
			cost = TRY_FIRE_POST_WEAPON_COST,
			handler = function(player: Player, payload: { [string]: any })
				self:fire(player, payload.origin, payload.direction, payload.aimPosition)
			end,
		},
		[NetEventNames.TRY_SET_POST_TRIGGER] = {
			shape = TRY_SET_POST_TRIGGER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:setTrigger(player, payload.isHeld)
			end,
		},
		[NetEventNames.TRY_UPGRADE_POST] = {
			shape = TRY_UPGRADE_POST_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:upgrade(player, payload.attribute)
			end,
		},
	}
end

-- a new run has a new camp: every claim and every spawned model is gone
-- with it. StructureManager has already filled the fresh post models by
-- now (it subscribed to the run first), so they are bound here; the fill
-- subscription covers the later tier changes
function PostManager:onRunStarted()
	for _, post in self.postsByIndex do
		self:destroyIkControls(post)
		for _, connection in post.promptConnections do
			connection:Disconnect()
		end
		if post.claimConnection then
			post.claimConnection:Disconnect()
		end
	end
	self.postsByIndex = {}
	self.pools = {}
	self:clearMines()
	ProjectileManager:clear()
	for player, state in self.stateByPlayer do
		state.postIndex = PostRules.NO_POST
		state.upgrades = {}
		state.salvageIronTonight = 0
		if player.Parent then
			self:replicatePlayer(player)
		end
	end
	self:bindPostModels()
	self:bindUpgradeTable()
end

-- dawn: the mines fizzle and the Salvage Gun's cap starts over
function PostManager:onDayStarted()
	self:clearMines()
	self.pools = {}
	for _, state in self.stateByPlayer do
		state.salvageIronTonight = 0
	end
end

function PostManager:onPlayerReady(player: Player)
	self:getPlayerState(player)
	self:replicatePlayer(player)
end

-- teardown entry: a disconnect or a dev-tool reset releases the claim
function PostManager:onPlayerRemoved(player: Player)
	self:release(player)
end

function PostManager:init(monsterManagerIn: any)
	monsterManager = monsterManagerIn
	local kinds: { [number]: PostRules.KindData } = {}
	for kind, data in PostWeaponsData.BY_KIND do
		kinds[kind] = data
	end
	self.catalog = {
		claimPriceGold = PostWeaponsData.CLAIM_PRICE_GOLD,
		upgradePriceByLevel = PostWeaponsData.UPGRADE_PRICE_BY_LEVEL,
		bonusPerLevelByAttribute = PostWeaponsData.BONUS_PER_LEVEL_BY_ATTRIBUTE,
		headshotMultiplier = PostWeaponsData.HEADSHOT_MULTIPLIER,
		kinds = kinds,
	}
	SplendidReplicationManager:setGameMetadata(Attributes.POST_CATALOG, PostRules.encodeCatalog(self.catalog))
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			self:applyClass(player)
		end
	)
	StructureManager:subscribePostModelsFilled(
		function()
			self:bindPostModels()
		end
	)
	RunCycleManager:subscribeDayStarted(
		function(_day: number, _scalingCount: number)
			self:onDayStarted()
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function PostManager.new(): PostManager
	local self = setmetatable({}, PostManager) :: PostManager
	self.catalog = {
		claimPriceGold = 0,
		upgradePriceByLevel = {},
		bonusPerLevelByAttribute = {},
		headshotMultiplier = 1,
		kinds = {},
	}
	self.postsByIndex = {}
	self.stateByPlayer = {}
	self.warnedTemplates = {}
	self.pools = {}
	self.mines = {}
	self.nextPoolId = 0
	self.nextMineId = 0
	return self
end

return PostManager.new()
