--!strict

-- The Flare, Air Defense's gadget (GDD "Classes", 2026-10-20; a flare gun
-- since 2026-10-21, a throw before). The GADGET slot is the gun while the
-- class says so (granted here; the Auto Turret manager, which runs
-- first, takes the slot from any class without a turret, so this only
-- ever gives). With it in hand the use input fires a flare (TryFireFlare,
-- the muzzle's position and the camera's look, the origin allowed the
-- gun's distance from the head as a weapon's is): a ProjectileManager
-- flight the grenade's way, arcing under gravity, that every client
-- draws from the launch notification with the template's own red trail.
-- Where it ends (the ground, a monster, or its range, in which case it
-- drops to the ground under it) the flare lights as one invisible
-- anchored part (the shadow system: Tags.FLARE, the owner and the end
-- time) that every client dresses with the flare's model and fire, and
-- MonsterManager lists it among every target type with the level's draw
-- radius, so every monster within it, air or ground, goes for it and
-- stands over it (a hit on it hurts nothing) until it burns out. The shot
-- starts the cooldown (GadgetReadyTime on CurrentPlayer, shared with the
-- Remote Charge's slot logic). Numbers: GameData/Gadgets/Flare.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local FlareData = require("@game/ServerScriptService/GameData/Gadgets/Flare")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local ProjectileManager = require(script.Parent.ProjectileManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local FlareManager = {}
FlareManager.__index = FlareManager

export type Flare = {
	id: string,
	owner: Player,
	position: Vector3,
	shadow: BasePart,
	endTime: number,
	drawRadiusStuds: number,
}

export type FlareManager = typeof(setmetatable(
	{} :: {
		flaresById: { [string]: Flare },
		-- when a player's next flare is in hand; nil when it is
		readyTimeByPlayer: { [Player]: number },
		nextId: number,
		shadowFolder: Folder?,
	},
	FlareManager
))

local ID_FORMAT = "Flare%d"
local TRY_FIRE_FLARE_SHAPE = {
	origin = "vector3",
	direction = "vector3",
}
local FEEDBACK_COOLING = "Next flare in %d s"
local FEEDBACK_NOT_YET = "Not until the day starts."
local MIN_DIRECTION_MAGNITUDE = 0.001
local GROUND_PROBE_LIFT_STUDS = 0.5

function FlareManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.FLARE_SHADOW_FOLDER
	folder.Parent = workspace
	self.shadowFolder = folder
	return folder
end

function FlareManager:hasFlareGadget(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.FLARE
end

function FlareManager:hasFlare(id: string): boolean
	return self.flaresById[id] ~= nil
end

-- every lit flare, for the monsters' target lists
function FlareManager:getFlares(): { Flare }
	local flares = {}
	for _, flare in self.flaresById do
		table.insert(flares, flare)
	end
	return flares
end

-- seconds until the next flare is in hand; 0 when it is
function FlareManager:getCooldownLeft(player: Player): number
	local readyTime = self.readyTimeByPlayer[player]
	if not readyTime then
		return 0
	end
	return math.max(0, readyTime - workspace:GetServerTimeNow())
end

function FlareManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GADGET_READY_TIME, self.readyTimeByPlayer[player] or 0)
end

function FlareManager:setReadyTime(player: Player, readyTime: number?)
	self.readyTimeByPlayer[player] = readyTime
	self:replicate(player)
end

function FlareManager:removeFlare(flare: Flare)
	if self.flaresById[flare.id] ~= flare then
		return
	end
	self.flaresById[flare.id] = nil
	flare.shadow:Destroy()
end

function FlareManager:getHeadPosition(player: Player): Vector3?
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- where a stopped flare comes to rest: the ground under it, if any
-- within reach (right there after a hit on the floor, further down
-- after a wall, a monster's box, or the end of the range). Characters
-- and the damageable shadows are not ground
function FlareManager:findGround(position: Vector3): Vector3?
	local excluded: { Instance } = { DamageableManager:getShadowFolder(), self:getShadowFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	-- from a touch above the stop, so a flare on the floor finds it
	local result = workspace:Raycast(position + Vector3.new(0, GROUND_PROBE_LIFT_STUDS, 0), Vector3.new(0, -(FlareData.GROUND_DROP_STUDS + GROUND_PROBE_LIFT_STUDS), 0), params)
	return if result then result.Position else nil
end

-- the flare lights where the shot came to rest
function FlareManager:light(player: Player, position: Vector3)
	local id = string.format(ID_FORMAT, self.nextId)
	self.nextId += 1
	local now = workspace:GetServerTimeNow()
	local size: Vector3 = FlareData.BODY_SIZE
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = size
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2, 0))
	shadow:SetAttribute(Attributes.FLARE_OWNER_USER_ID, player.UserId)
	shadow:SetAttribute(Attributes.FLARE_END_TIME, now + FlareData.BURN_SEC)
	CollectionService:AddTag(shadow, Tags.FLARE)
	shadow.Parent = self:getShadowFolder()
	self.flaresById[id] = {
		id = id,
		owner = player,
		position = position,
		shadow = shadow,
		endTime = now + FlareData.BURN_SEC,
		drawRadiusStuds = FlareData.DRAW_RADIUS_STUDS,
	}
	print(`[FlareManager] {player.Name} lit {id} for {FlareData.BURN_SEC} s, drawing {FlareData.DRAW_RADIUS_STUDS} studs`)
end

-- the shot ended (the world, a monster, or the end of its range): the
-- flare lights on the ground under where it stopped
function FlareManager:onShotEnded(player: Player, position: Vector3)
	if not player.Parent or not RunCycleManager:isRunOn() then
		return
	end
	local ground = self:findGround(position)
	if not ground then
		warn(`FlareManager: {player.Name}'s flare ended over no ground; it is lost`)
		return
	end
	self:light(player, ground)
end

function FlareManager:fire(player: Player, origin: Vector3, direction: Vector3)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:hasFlareGadget(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.GADGET then
		return
	end
	if direction.Magnitude < MIN_DIRECTION_MAGNITUDE then
		return
	end
	local cooldownLeft = self:getCooldownLeft(player)
	if cooldownLeft > 0 then
		PlayerFeedbackManager:give(player, string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)))
		return
	end
	-- not in the arrival: there is nothing to draw yet
	if not RunCycleManager:isRunOn() then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_YET)
		return
	end
	-- the muzzle is allowed a weapon's distance from the head
	local headPosition = self:getHeadPosition(player)
	if not headPosition or not WeaponRules.isOriginPlausible(headPosition, origin, HandheldData.ORIGIN_TOLERANCE_STUDS) then
		return
	end
	local now = workspace:GetServerTimeNow()
	local fireData = FlareData.FIRE
	-- the shot is the spend: the hand is empty and the next flare comes
	self:setReadyTime(player, now + FlareData.COOLDOWN_SEC)
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)
	ProjectileManager:launch({
		owner = player,
		templateName = fireData.TEMPLATE,
		origin = origin,
		unitDirection = direction.Unit,
		speedStudsPerSec = fireData.SPEED_STUDS_PER_SEC,
		gravityStudsPerSec2 = fireData.GRAVITY_STUDS_PER_SEC2,
		rangeStuds = fireData.RANGE_STUDS,
		onEnd = function(position: Vector3, _hitId: string?)
			self:onShotEnded(player, position)
		end,
	})
end

-- the slot is the gun's while the class says so (see the header)
function FlareManager:applyGadget(player: Player)
	if self:hasFlareGadget(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
end

function FlareManager:getNetHandlers()
	return {
		[NetEventNames.TRY_FIRE_FLARE] = {
			shape = TRY_FIRE_FLARE_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:fire(player, payload.origin, payload.direction)
			end,
		},
	}
end

-- every Heartbeat a burnt-out flare goes
function FlareManager:step()
	if next(self.flaresById) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, flare in self:getFlares() do
		if now >= flare.endTime then
			self:removeFlare(flare)
		end
	end
end

-- a new run: every flare is out and every cooldown over
function FlareManager:onRunStarted()
	for _, flare in self:getFlares() do
		self:removeFlare(flare)
	end
	for player in self.readyTimeByPlayer do
		if player.Parent then
			self:setReadyTime(player, nil)
		end
	end
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

function FlareManager:onPlayerReady(player: Player)
	self:replicate(player)
	self:applyGadget(player)
end

function FlareManager:onPlayerRemoved(player: Player)
	self.readyTimeByPlayer[player] = nil
end

function FlareManager:init()
	-- the slot drains its sheet over the same wait the server keeps
	SplendidReplicationManager:setGameMetadata(Attributes.FLARE_COOLDOWN_SEC, FlareData.COOLDOWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function FlareManager.new(): FlareManager
	local self = setmetatable({}, FlareManager) :: FlareManager
	self.flaresById = {}
	self.readyTimeByPlayer = {}
	self.nextId = 1
	self.shadowFolder = nil
	return self
end

return FlareManager.new()
