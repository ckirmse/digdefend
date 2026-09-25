--!strict

-- Posts (GDD "Posts"), M25. Every post along the wall is a slot
-- StructureManager fills with the tier's model; this manager owns what
-- happens on it, all as Lua state: who claimed it (the sign's Claim Post
-- prompt, 10 Gold), the weapon their loadout named, cloned from
-- GameAssets/PostWeapons onto the post's Spawn, the upgrade bench beside
-- the stairs, who is manning the weapon (its Use prompt), the aim the
-- server accepted, and the owner's four upgrade counts. Clients read it
-- back from attributes on the post and weapon models and on AllPlayers,
-- and turn the weapon themselves; the server never moves a part after the
-- spawn. Every shot is a TryFirePostWeapon request carrying the ray the
-- client aimed: the server checks the gunner, the cooldown, and that the
-- ray starts at the muzzle it computes from its own yaw and pitch, then
-- decides the hit exactly as WeaponManager does. A projectile kind (the
-- Rocket Launcher) flies instead: the rocket is a few numbers stepped
-- every Heartbeat, cast segment by segment against the world and the
-- damageables, and where it lands everything within the splash radius is
-- hurt; clients fly the model from the launch message and burst it on the
-- explode message. Yaw reports are refused when the base could not have
-- turned that far at its turn speed.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local LevelData = require("@game/ServerScriptService/GameData/Camp/Level")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MapManager = require(script.Parent.MapManager)
local RefineryManager = require(script.Parent.RefineryManager)
local StructureManager = require(script.Parent.StructureManager)
local ToolManager = require(script.Parent.ToolManager)
local WeaponManager = require(script.Parent.WeaponManager)

local PostManager = {}
PostManager.__index = PostManager

type Post = {
	index: number,
	owner: Player?,
	weaponKind: number,
	weaponModel: Model?,
	workbench: Model?,
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
	gunner: Player?,
	ikControls: { IKControl },
	promptConnections: { RBXScriptConnection },
	-- the post model the claim prompt is wired to, so a fill that keeps the
	-- same model is never bound twice
	boundModel: Model?,
	claimConnection: RBXScriptConnection?,
}

-- a rocket in flight, server truth only
type Rocket = {
	id: string,
	gunner: Player,
	postIndex: number,
	weaponKind: number,
	position: Vector3,
	unitDirection: Vector3,
	speedStudsPerSec: number,
	travelledStuds: number,
	rangeStuds: number,
	damage: number,
	splashRadiusStuds: number,
}

type PlayerState = {
	postIndex: number,
	upgrades: PostRules.Upgrades,
	-- a dev tool's stand-in for the lobby loadout until the store exists
	loadoutOverride: number?,
}

export type PostManager = typeof(setmetatable(
	{} :: {
		catalog: PostRules.Catalog,
		postsByIndex: { [number]: Post },
		stateByPlayer: { [Player]: PlayerState },
		warnedTemplates: { [string]: boolean },
		rockets: { Rocket },
		nextRocketId: number,
	},
	PostManager
))

local TRY_DISMOUNT_POST_SHAPE = {}
local TRY_SET_POST_AIM_SHAPE = {
	yawDegrees = "number",
	pitchDegrees = "number",
}
-- a quarter of a default message, like TrySetAim: the stream must never starve firing
local TRY_SET_POST_AIM_COST = 0.25
local TRY_FIRE_POST_WEAPON_SHAPE = {
	origin = "vector3",
	direction = "vector3",
}
local TRY_UPGRADE_POST_SHAPE = {
	attribute = { type = "enum", name = "PostAttribute" },
}

local NO_HIT_ID = ""
local ROCKET_ID_FORMAT = "Rocket%d"
local MIN_DIRECTION_MAGNITUDE = 0.001
local WEAPON_MODEL_FORMAT = "PostWeapon%d"
local WORKBENCH_MODEL_FORMAT = "PostWorkbench%d"
local UNCLAIMED_TEXT = "Unclaimed"
local CLAIM_PROMPT_ATTACHMENT = "ClaimPromptAttachment"
local HEADSHOT_FORMAT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"
-- R15: the chain each hand's IKControl solves from
local IK_ARMS = {
	{ root = "LeftUpperArm", hand = "LeftHand", handle = Constants.POST_WEAPON_HANDLE_LEFT_PART },
	{ root = "RightUpperArm", hand = "RightHand", handle = Constants.POST_WEAPON_HANDLE_RIGHT_PART },
}

local FEEDBACK_ALREADY_OWN_POST = "You already have a post"
local FEEDBACK_POST_TAKEN = "That post is taken"
local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"
local FEEDBACK_MAXED = "Already maxed out"

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
	return PostRules.statsFor(self.catalog, post.weaponKind, upgrades)
end

-- dev tools: stands in for the lobby loadout's Post slot
function PostManager:setLoadoutOverride(player: Player, kind: number?)
	self:getPlayerState(player).loadoutOverride = kind
end

function PostManager:resolveWeaponKind(player: Player): number
	local state = self:getPlayerState(player)
	if state.loadoutOverride and self:getWeaponData(state.loadoutOverride) then
		return state.loadoutOverride
	end
	local playerData = GameController:getPlayerData(player)
	local unlockName = if playerData then playerData:getLoadoutSlot(Enums.LoadoutSlot.POST) else nil
	local kind = PostRules.resolveLoadoutPost(unlockName, PostWeaponsData.DEFAULT_POST_WEAPON)
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

-- the heat and reload travel separately from the aim: they change per
-- shot, the aim a few times a second
function PostManager:replicateFireState(post: Post)
	local weaponModel = post.weaponModel
	if not weaponModel then
		return
	end
	weaponModel:SetAttribute(Attributes.POST_WEAPON_HEAT, post.heat)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_HEAT_TIME, post.lastFireTime or 0)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_IS_OVERHEATED, post.isOverheated)
	weaponModel:SetAttribute(Attributes.POST_WEAPON_RELOAD_END_TIME, post.reloadEndTime)
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
	prompt.Enabled = true
end

function PostManager:spawnWeapon(post: Post)
	local slotModel = self:findSlotModel(post.index)
	local spawn = if slotModel then slotModel:FindFirstChild(Constants.POST_SPAWN_PART) else nil
	local folder = self:getSpawnedFolder()
	local template = self:findTemplate(Constants.POST_WEAPON_TEMPLATES_FOLDER, PostRules.templateNameFor(post.weaponKind))
	if not spawn or not spawn:IsA("BasePart") or not folder or not template then
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
	CollectionService:AddTag(model, Tags.POST_WEAPON)
	model.Parent = folder
	post.weaponModel = model
	self:replicateFireState(post)

	local characterSpawn = model:FindFirstChild(Constants.POST_WEAPON_CHARACTER_SPAWN_PART)
	if characterSpawn then
		local prompt = characterSpawn:FindFirstChildWhichIsA("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = characterSpawn
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
end

-- the bench stands at the post's WorkbenchSpawn marker; its Upgrade prompt
-- is only ever acted on by the owner's own client (it opens the menu)
function PostManager:spawnWorkbench(post: Post)
	local slotModel = self:findSlotModel(post.index)
	local marker = if slotModel then slotModel:FindFirstChild(Constants.POST_WORKBENCH_SPAWN_PART) else nil
	local folder = self:getSpawnedFolder()
	local template = self:findTemplate(Constants.STRUCTURE_TEMPLATES_FOLDER, Constants.POST_WORKBENCH_TEMPLATE)
	if not marker or not marker:IsA("BasePart") or not folder or not template then
		warn(`PostManager: post {post.index} has no {Constants.POST_WORKBENCH_SPAWN_PART} part or the bench template is missing; no bench spawned`)
		return
	end
	local model = template:Clone()
	model.Name = string.format(WORKBENCH_MODEL_FORMAT, post.index)
	model:PivotTo(marker.CFrame)
	model:SetAttribute(Attributes.POST_MODEL_INDEX, post.index)
	CollectionService:AddTag(model, Tags.POST_WORKBENCH)
	local promptPart = model:FindFirstChild(Constants.WORKBENCH_PROMPT_PART)
	if promptPart then
		local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = promptPart
		end
		self:configurePrompt(prompt :: ProximityPrompt, PostWeaponsData.UPGRADE_PROMPT_ACTION_TEXT, 0, PostWeaponsData.PROMPT_MAX_DISTANCE_STUDS)
	end
	model.Parent = folder
	post.workbench = model
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
	self:destroyIkControls(post)
	self:replicatePost(post)
	self:replicatePlayer(player)
end

function PostManager:mount(player: Player, post: Post)
	if not GameController:isPlayerReady(player) or post.owner ~= player or post.gunner ~= nil or not post.rig then
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
	-- hands off the held tool: the gun on the post is what they use now
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)
	character:PivotTo(PostRules.characterFrame(PostRules.baseFrame(weaponModel.PrimaryPart.CFrame, post.yawDegrees), rig))
	self:createIkControls(post, player)
	self:replicatePost(post)
	self:replicatePlayer(player)
end

function PostManager:setAim(player: Player, yawDegrees: number, pitchDegrees: number)
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
	self:replicatePost(post)
end

function PostManager:fire(player: Player, origin: Vector3, direction: Vector3)
	local post = self:getMannedPost(player)
	local stats = if post then self:getStats(post) else nil
	local rig = if post then post.rig else nil
	local weaponModel = if post then post.weaponModel else nil
	if not post or not stats or not rig or not weaponModel or not weaponModel.PrimaryPart then
		return
	end
	if direction.Magnitude < MIN_DIRECTION_MAGNITUDE then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not WeaponRules.canFire(post.lastFireTime, now, stats.fireCooldownSec) then
		return
	end
	local data = self:getWeaponData(post.weaponKind)
	if not data then
		return
	end
	-- a reloading gun is empty; an overheated one waits for cool
	if data.RELOAD_SEC and WeaponRules.isReloading(post.reloadEndTime, now) then
		return
	end
	if data.HEAT then
		local currentHeat = PostRules.cooledHeat(post.heat, post.lastFireTime, now, stats.fireIntervalSec, data.HEAT)
		local isFired, newHeat, isOverheated = PostRules.heatAfterShot(currentHeat, post.isOverheated, data.HEAT, stats.fireIntervalSec)
		if not isFired then
			return
		end
		post.heat = newHeat
		post.isOverheated = isOverheated
	end
	if stats.reloadSec then
		post.reloadEndTime = now + stats.reloadSec
	end
	local gunFrame = PostRules.gunFrame(PostRules.baseFrame(weaponModel.PrimaryPart.CFrame, post.yawDegrees), rig, post.pitchDegrees)
	local muzzle = PostRules.muzzlePosition(gunFrame, rig)
	if not WeaponRules.isOriginPlausible(muzzle, origin, PostWeaponsData.ORIGIN_TOLERANCE_STUDS) then
		return
	end
	local unitDirection = direction.Unit
	post.lastFireTime = now
	self:replicateFireState(post)
	if data.PROJECTILE then
		self:launchRocket(post, player, origin, unitDirection, stats, data.PROJECTILE)
		return
	end
	local worldDistance = WeaponManager:getWorldDistance(origin, unitDirection, stats.rangeStuds)
	local hitId, hitDistance = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, DamageableManager:getHitBoxes())
	local endDistance = hitDistance or worldDistance
	if hitId then
		DamageableManager:damage(hitId, stats.damage, player)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_WEAPON_FIRED, {
		userId = player.UserId,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		origin = origin,
		endPosition = origin + unitDirection * endDistance,
		isImpact = hitId ~= nil or worldDistance < stats.rangeStuds,
		hitId = hitId or NO_HIT_ID,
	})
end

function PostManager:launchRocket(post: Post, player: Player, origin: Vector3, unitDirection: Vector3, stats: PostRules.Stats, projectile: PostRules.ProjectileData)
	self.nextRocketId += 1
	local rocket: Rocket = {
		id = string.format(ROCKET_ID_FORMAT, self.nextRocketId),
		gunner = player,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		position = origin,
		unitDirection = unitDirection,
		speedStudsPerSec = projectile.SPEED_STUDS_PER_SEC,
		travelledStuds = 0,
		rangeStuds = stats.rangeStuds,
		damage = stats.damage,
		splashRadiusStuds = projectile.SPLASH_RADIUS_STUDS,
	}
	table.insert(self.rockets, rocket)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_ROCKET_LAUNCHED, {
		rocketId = rocket.id,
		userId = player.UserId,
		postIndex = post.index,
		weaponKind = post.weaponKind,
		origin = origin,
		direction = unitDirection,
		speed = rocket.speedStudsPerSec,
	})
end

-- the burst: everything within the radius of the point takes the damage
function PostManager:explodeRocket(rocket: Rocket, position: Vector3)
	local hitIds = PostRules.findSplashHits(position, rocket.splashRadiusStuds, DamageableManager:getHitBoxes())
	for _, hitId in hitIds do
		DamageableManager:damage(hitId, rocket.damage, rocket.gunner)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_POST_ROCKET_EXPLODED, {
		rocketId = rocket.id,
		userId = rocket.gunner.UserId,
		weaponKind = rocket.weaponKind,
		position = position,
		hitCount = #hitIds,
	})
end

-- one Heartbeat of flight for every rocket: the segment it would cover is
-- cast against the world and the damageables, and the first thing struck
-- (or the end of its range) is where it bursts
function PostManager:stepRockets(deltaSec: number)
	if #self.rockets == 0 then
		return
	end
	local hitBoxes = DamageableManager:getHitBoxes()
	local survivors = {}
	for _, rocket in self.rockets do
		local step = math.min(rocket.speedStudsPerSec * deltaSec, rocket.rangeStuds - rocket.travelledStuds)
		local worldDistance = WeaponManager:getWorldDistance(rocket.position, rocket.unitDirection, step)
		local _hitId, hitDistance = WeaponRules.findClosestHit(rocket.position, rocket.unitDirection, worldDistance, hitBoxes)
		local endDistance = hitDistance or worldDistance
		local isBurst = hitDistance ~= nil or worldDistance < step or rocket.travelledStuds + step >= rocket.rangeStuds
		rocket.position += rocket.unitDirection * endDistance
		rocket.travelledStuds += endDistance
		if isBurst then
			self:explodeRocket(rocket, rocket.position)
		else
			table.insert(survivors, rocket)
		end
	end
	self.rockets = survivors
end

function PostManager:upgrade(player: Player, attribute: number)
	local post = self:getOwnedPost(player)
	if not post then
		return
	end
	local state = self:getPlayerState(player)
	local offer = PostRules.getUpgradeOffer(self.catalog, state.upgrades, attribute, RefineryManager:getCampLevel())
	if offer.status == Enums.StoreOffer.MAXED then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	if offer.status == Enums.StoreOffer.LOCKED then
		PlayerFeedbackManager:give(player, string.format(PostRules.LOCKED_FORMAT, offer.requiredCampLevel or 0))
		return
	end
	local price = offer.price or 0
	if not PostRules.canAfford(RefineryManager:getGoldBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_GOLD)
		return
	end
	if not RefineryManager:spendGoldBars(player, price) then
		return
	end
	state.upgrades[attribute] = offer.level or 1
	self:replicatePlayer(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_POST_UPGRADED, {
		attribute = attribute,
		level = state.upgrades[attribute],
		price = price,
	})
	print(`[PostManager] {player.Name} upgraded {Enums.getPublicName(Enums.PostAttribute, attribute)} to {state.upgrades[attribute]} for {price} Gold`)
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
	if not RefineryManager:spendGoldBars(player, price) then
		return
	end
	post.owner = player
	post.weaponKind = self:resolveWeaponKind(player)
	self:getPlayerState(player).postIndex = post.index
	self:spawnWeapon(post)
	self:spawnWorkbench(post)
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

-- a claim ends only with the player (disconnect, or a dev-tool reset):
-- the weapon and bench go, the sign reads Unclaimed again
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
	post.owner = nil
	post.gunner = nil
	post.rig = nil
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
	if post.workbench then
		post.workbench:Destroy()
		post.workbench = nil
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
				workbench = nil,
				rig = nil,
				yawDegrees = 0,
				pitchDegrees = 0,
				lastAimTime = nil,
				lastFireTime = nil,
				heat = 0,
				isOverheated = false,
				reloadEndTime = 0,
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
		local marker = if slot.model then slot.model:FindFirstChild(Constants.POST_WORKBENCH_SPAWN_PART) else nil
		if post.workbench and marker and marker:IsA("BasePart") then
			post.workbench:PivotTo(marker.CFrame)
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
				self:setAim(player, payload.yawDegrees, payload.pitchDegrees)
			end,
		},
		[NetEventNames.TRY_FIRE_POST_WEAPON] = {
			shape = TRY_FIRE_POST_WEAPON_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:fire(player, payload.origin, payload.direction)
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
	self.rockets = {}
	for player, state in self.stateByPlayer do
		state.postIndex = PostRules.NO_POST
		state.upgrades = {}
		if player.Parent then
			self:replicatePlayer(player)
		end
	end
	self:bindPostModels()
end

function PostManager:onPlayerReady(player: Player)
	self:getPlayerState(player)
	self:replicatePlayer(player)
end

-- teardown entry: a disconnect or a dev-tool reset releases the claim
function PostManager:onPlayerRemoved(player: Player)
	self:release(player)
end

function PostManager:init()
	local kinds: { [number]: PostRules.KindData } = {}
	for kind, data in PostWeaponsData.BY_KIND do
		kinds[kind] = data
	end
	self.catalog = {
		claimPriceGold = PostWeaponsData.CLAIM_PRICE_GOLD,
		upgradePriceByLevel = PostWeaponsData.UPGRADE_PRICE_BY_LEVEL,
		requiredCampLevelByLevel = LevelData.POST_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
		bonusPerLevelByAttribute = PostWeaponsData.BONUS_PER_LEVEL_BY_ATTRIBUTE,
		kinds = kinds,
	}
	SplendidReplicationManager:setGameMetadata(Attributes.POST_CATALOG, PostRules.encodeCatalog(self.catalog))
	GameController:registerPlaceManager(self)
	StructureManager:subscribePostModelsFilled(
		function()
			self:bindPostModels()
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:stepRockets(deltaSec)
		end
	)
end

function PostManager.new(): PostManager
	local self = setmetatable({}, PostManager) :: PostManager
	self.catalog = {
		claimPriceGold = 0,
		upgradePriceByLevel = {},
		requiredCampLevelByLevel = {},
		bonusPerLevelByAttribute = {},
		kinds = {},
	}
	self.postsByIndex = {}
	self.stateByPlayer = {}
	self.warnedTemplates = {}
	self.rockets = {}
	self.nextRocketId = 0
	return self
end

return PostManager.new()
