--!strict

-- The Remote Charge, the Pyro's gadget (GDD "Classes", 2026-10-20). The
-- GADGET slot is the mine while the class says so (granted here; the Auto
-- Turret manager, which runs first, takes the slot from any class without
-- a turret, so this only ever gives). With it in hand the use input plants
-- it where the client's ghost stood (TryPlaceRemoteCharge, judged by the
-- Auto Turret's placement rules through AutoTurretManager:findPlacement:
-- ground the monsters can walk, not a roof, not too steep) as one
-- invisible server part (the shadow system: Tags.REMOTE_CHARGE, the
-- owner's id) that every client dresses with the mine's model and
-- breathes. The hand then holds the detonator (ToolManager's gadget
-- variant, the same slot) and the next use blows the charge
-- (TryDetonateRemoteCharge) from anywhere, no line of sight: the level's
-- damage to every monster within the burst, the owner credited, and a
-- pool of fire through PostManager (the one stepper of pools). A
-- detonation starts the cooldown (RemoteChargeReadyTime on
-- CurrentPlayer): the slot stays, greyed and counting down, and the mine
-- is in hand again when it ends. One charge at a time; it never breaks
-- rock. Numbers: GameData/Gadgets/RemoteCharge.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local GadgetRules = require("@game/ReplicatedStorage/Shared/GadgetRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local RemoteChargeData = require("@game/ServerScriptService/GameData/Gadgets/RemoteCharge")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local AutoTurretManager = require(script.Parent.AutoTurretManager)
local DamageableManager = require(script.Parent.DamageableManager)
local GadgetUpgradeManager = require(script.Parent.GadgetUpgradeManager)
local PostManager = require(script.Parent.PostManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local RemoteChargeManager = {}
RemoteChargeManager.__index = RemoteChargeManager

export type Charge = {
	id: string,
	owner: Player,
	position: Vector3,
	shadow: BasePart,
}

export type LevelStats = {
	DAMAGE: number,
	BURST_RADIUS_STUDS: number,
	POOL_SEC: number,
}

export type RemoteChargeManager = typeof(setmetatable(
	{} :: {
		chargeByPlayer: { [Player]: Charge },
		-- when a player's next mine is in hand after a detonation; nil when it is
		readyTimeByPlayer: { [Player]: number },
		nextId: number,
		shadowFolder: Folder?,
	},
	RemoteChargeManager
))

local ID_FORMAT = "RemoteCharge%d"
local TRY_PLACE_REMOTE_CHARGE_SHAPE = {
	position = "vector3",
	yawDegrees = "number",
}
local TRY_DETONATE_REMOTE_CHARGE_SHAPE = {}
local FEEDBACK_COOLING = "Next charge in %d s"
local FEEDBACK_NOT_YET = "Not until the day starts."
local FEEDBACK_NOTHING_PLANTED = "No charge planted"

function RemoteChargeManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.REMOTE_CHARGE_SHADOW_FOLDER
	folder.Parent = workspace
	self.shadowFolder = folder
	return folder
end

function RemoteChargeManager:hasRemoteCharge(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.REMOTE_CHARGE
end

-- seconds until the next mine is in hand; 0 when it is
function RemoteChargeManager:getCooldownLeft(player: Player): number
	local readyTime = self.readyTimeByPlayer[player]
	if not readyTime then
		return 0
	end
	return math.max(0, readyTime - workspace:GetServerTimeNow())
end

function RemoteChargeManager:getPlayerCharge(player: Player): Charge?
	return self.chargeByPlayer[player]
end

function RemoteChargeManager:statsFor(player: Player): LevelStats
	return GadgetRules.statsFor(RemoteChargeData.STATS_BY_LEVEL, GadgetUpgradeManager:getLevel(player))
end

function RemoteChargeManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.REMOTE_CHARGE_READY_TIME, self.readyTimeByPlayer[player] or 0)
end

function RemoteChargeManager:setReadyTime(player: Player, readyTime: number?)
	self.readyTimeByPlayer[player] = readyTime
	self:replicate(player)
end

-- the charge goes and the hand holds the mine again
function RemoteChargeManager:removeCharge(player: Player)
	local charge = self.chargeByPlayer[player]
	if not charge then
		return
	end
	self.chargeByPlayer[player] = nil
	charge.shadow:Destroy()
	ToolManager:setGadgetVariant(player, nil)
end

-- the common gate for both uses: alive, the Pyro, the slot in hand
function RemoteChargeManager:canUse(player: Player): boolean
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return false
	end
	return self:hasRemoteCharge(player) and ToolManager:getEquippedTool(player) == Enums.ToolKind.GADGET
end

function RemoteChargeManager:place(player: Player, position: Vector3, yawDegrees: number)
	if not self:canUse(player) or self.chargeByPlayer[player] then
		return
	end
	local cooldownLeft = self:getCooldownLeft(player)
	if cooldownLeft > 0 then
		PlayerFeedbackManager:give(player, string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)))
		return
	end
	local groundPosition = AutoTurretManager:findPlacement(player, position)
	if not groundPosition then
		return
	end
	local id = string.format(ID_FORMAT, self.nextId)
	self.nextId += 1
	local size: Vector3 = RemoteChargeData.BODY_SIZE
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = size
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = CFrame.new(groundPosition) * CFrame.Angles(0, math.rad(yawDegrees), 0) * CFrame.new(0, size.Y / 2, 0)
	shadow:SetAttribute(Attributes.REMOTE_CHARGE_OWNER_USER_ID, player.UserId)
	CollectionService:AddTag(shadow, Tags.REMOTE_CHARGE)
	shadow.Parent = self:getShadowFolder()
	self.chargeByPlayer[player] = {
		id = id,
		owner = player,
		position = groundPosition,
		shadow = shadow,
	}
	-- the hand holds the detonator now, in the same slot
	ToolManager:setGadgetVariant(player, Constants.REMOTE_CHARGE_DETONATOR_VARIANT)
	print(`[RemoteChargeManager] {player.Name} planted {id}`)
end

-- the charge goes up: the burst on the monsters within it and the pool it
-- leaves, then the cooldown runs
function RemoteChargeManager:detonate(player: Player)
	if not self:canUse(player) then
		return
	end
	local charge = self.chargeByPlayer[player]
	if not charge then
		PlayerFeedbackManager:give(player, FEEDBACK_NOTHING_PLANTED)
		return
	end
	-- not in the arrival: there is nothing to blow up yet
	if not RunCycleManager:isRunOn() then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_YET)
		return
	end
	local stats = self:statsFor(player)
	local hitIds = PostRules.findSplashHits(charge.position, stats.BURST_RADIUS_STUDS, DamageableManager:getHitBoxes())
	for _, hitId in hitIds do
		DamageableManager:damage(hitId, stats.DAMAGE, player)
	end
	PostManager:addPool(player, charge.position, stats.BURST_RADIUS_STUDS * RemoteChargeData.POOL_RADIUS_SHARE, stats.POOL_SEC, RemoteChargeData.POOL_TICK_SEC, RemoteChargeData.POOL_BURN_DAMAGE_PER_SEC, RemoteChargeData.POOL_BURN_SEC)
	local position = charge.position
	self:removeCharge(player)
	self:setReadyTime(player, workspace:GetServerTimeNow() + RemoteChargeData.COOLDOWN_SEC)
	-- the detonator leaves the hand with the blast; the slot stays in the
	-- bar, greyed until the next mine is ready, and the player picks it up again
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_REMOTE_CHARGE_DETONATED, {
		positions = { position },
		radius = stats.BURST_RADIUS_STUDS,
	})
	print(`[RemoteChargeManager] {player.Name} detonated {charge.id}, {#hitIds} hit`)
end

-- the slot is the charge's while the class says so (see the header); a
-- class change takes a planted charge with it
function RemoteChargeManager:applyGadget(player: Player)
	if self:hasRemoteCharge(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	else
		self:removeCharge(player)
	end
end

function RemoteChargeManager:getNetHandlers()
	return {
		[NetEventNames.TRY_PLACE_REMOTE_CHARGE] = {
			shape = TRY_PLACE_REMOTE_CHARGE_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:place(player, payload.position, payload.yawDegrees)
			end,
		},
		[NetEventNames.TRY_DETONATE_REMOTE_CHARGE] = {
			shape = TRY_DETONATE_REMOTE_CHARGE_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:detonate(player)
			end,
		},
	}
end

-- a new run: every charge is gone and every cooldown over
function RemoteChargeManager:onRunStarted()
	for player in self.chargeByPlayer do
		self:removeCharge(player)
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

function RemoteChargeManager:onPlayerReady(player: Player)
	self:replicate(player)
	self:applyGadget(player)
end

-- a leaver's charge goes with them
function RemoteChargeManager:onPlayerRemoved(player: Player)
	local charge = self.chargeByPlayer[player]
	if charge then
		self.chargeByPlayer[player] = nil
		charge.shadow:Destroy()
	end
	self.readyTimeByPlayer[player] = nil
end

function RemoteChargeManager:init()
	-- the slot drains its sheet over the same length the server waits
	SplendidReplicationManager:setGameMetadata(Attributes.REMOTE_CHARGE_COOLDOWN_SEC, RemoteChargeData.COOLDOWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
end

function RemoteChargeManager.new(): RemoteChargeManager
	local self = setmetatable({}, RemoteChargeManager) :: RemoteChargeManager
	self.chargeByPlayer = {}
	self.readyTimeByPlayer = {}
	self.nextId = 1
	self.shadowFolder = nil
	return self
end

return RemoteChargeManager.new()
