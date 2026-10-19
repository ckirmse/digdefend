--!strict

-- The Binoculars, the Sniper's gadget (GDD "Classes", 2026-10-19), fused
-- with the Railgun post the same day: a gadget in the tool slot cost the
-- Sniper their firing time. While a Sniper mans their post, the aim
-- button asks TryTagMonster with the post camera's look ray; the server
-- checks the ray starts at the post's muzzle, casts it the gadget's range
-- through the same world a post shot flies through, and, if the first
-- body it meets is a monster, tags it: DamageableManager scales every hit
-- on that body by the gadget's multiplier until the tag ends, and the tag
-- travels as one public attribute on the tagger's AllPlayers entry
-- (BinocularsRules JSON: the body's id and the end time) so every client
-- can dress the body, the Camp Map, and the compass from it. One tag per
-- Sniper, a new one replacing the old; a short cooldown between tags,
-- published as the next allowed time so the client can refuse early. A
-- tag ends when its time runs out, when the body dies, when the Sniper
-- dies or leaves, or when the class changes under them. The GADGET tool
-- slot stays empty for the Sniper. Tuning: GameData/Gadgets/Binoculars.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BinocularsRules = require("@game/ReplicatedStorage/Shared/BinocularsRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local BinocularsData = require("@game/ServerScriptService/GameData/Gadgets/Binoculars")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MonsterManager = require(script.Parent.MonsterManager)
local PostManager = require(script.Parent.PostManager)
local ReviveManager = require(script.Parent.ReviveManager)
local WeaponManager = require(script.Parent.WeaponManager)

local BinocularsManager = {}
BinocularsManager.__index = BinocularsManager

type PlayerState = {
	tag: BinocularsRules.Tag?,
	lastTagTime: number?,
}

export type BinocularsManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: PlayerState },
	},
	BinocularsManager
))

local TRY_TAG_MONSTER_SHAPE = {
	origin = "vector3",
	direction = "vector3",
}

local MIN_DIRECTION_MAGNITUDE = 1e-3
local FEEDBACK_NOTHING_TO_TAG = "Nothing to tag there."

function BinocularsManager:getPlayerState(player: Player): PlayerState
	local state = self.stateByPlayer[player]
	if not state then
		state = {
			tag = nil,
			lastTagTime = nil,
		}
		self.stateByPlayer[player] = state
	end
	return state
end

function BinocularsManager:hasBinoculars(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.BINOCULARS
end

function BinocularsManager:getTag(player: Player): BinocularsRules.Tag?
	local state = self.stateByPlayer[player]
	return if state then state.tag else nil
end

-- whether this body is under anyone's tag (the run report, the client's own checks)
function BinocularsManager:isTagged(damageableId: string): boolean
	for _, state in self.stateByPlayer do
		local tag = state.tag
		if tag and tag.damageableId == damageableId then
			return true
		end
	end
	return false
end

function BinocularsManager:replicateTag(player: Player)
	if not player.Parent then
		return
	end
	local state = self:getPlayerState(player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.BINOCULARS_TAG, BinocularsRules.encodeTag(state.tag))
end

function BinocularsManager:replicateCooldown(player: Player)
	if not player.Parent then
		return
	end
	local state = self:getPlayerState(player)
	local lastTagTime = state.lastTagTime
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BINOCULARS_COOLDOWN_END_TIME, if lastTagTime then lastTagTime + BinocularsData.COOLDOWN_SEC else 0)
end

-- the body stops taking extra damage and every client takes the callout down
function BinocularsManager:clearTag(player: Player)
	local state = self.stateByPlayer[player]
	local tag = if state then state.tag else nil
	if not state or not tag then
		return
	end
	state.tag = nil
	-- another Sniper's tag on the same body keeps its multiple
	if not self:isTagged(tag.damageableId) then
		DamageableManager:setDamageTakenMultiplier(tag.damageableId, nil)
	end
	self:replicateTag(player)
end

function BinocularsManager:applyTag(player: Player, damageableId: string, now: number)
	self:clearTag(player)
	local state = self:getPlayerState(player)
	state.tag = {
		damageableId = damageableId,
		endTime = now + BinocularsData.TAG_SEC,
	}
	state.lastTagTime = now
	DamageableManager:setDamageTakenMultiplier(damageableId, BinocularsData.DAMAGE_MULTIPLIER)
	self:replicateTag(player)
	self:replicateCooldown(player)
end

function BinocularsManager:tryTag(player: Player, origin: Vector3, direction: Vector3)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	local post = PostManager:getMannedPost(player)
	if not self:hasBinoculars(player) or not post then
		return
	end
	if direction.Magnitude < MIN_DIRECTION_MAGNITUDE then
		return
	end
	local now = workspace:GetServerTimeNow()
	local state = self:getPlayerState(player)
	if not BinocularsRules.isCooldownOver(state.lastTagTime, now, BinocularsData.COOLDOWN_SEC) then
		return
	end
	local muzzle = PostManager:getAim(post)
	if not muzzle or not WeaponRules.isOriginPlausible(muzzle, origin, BinocularsData.ORIGIN_TOLERANCE_STUDS) then
		return
	end
	local unitDirection = direction.Unit
	-- the look stops where a bullet would: at the world, through the
	-- fortifications a post fires through, never at a crewmate
	local worldDistance = WeaponManager:getWorldDistance(origin, unitDirection, BinocularsData.RANGE_STUDS, true)
	local hitId = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, DamageableManager:getHitBoxes())
	if not hitId or not MonsterManager:isMonsterDamageable(hitId) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOTHING_TO_TAG)
		return
	end
	self:applyTag(player, hitId, now)
end

-- every Heartbeat: a tag whose time is up or whose body is gone comes off
function BinocularsManager:step()
	local now = workspace:GetServerTimeNow()
	for player, state in self.stateByPlayer do
		local tag = state.tag
		if not tag then
			continue
		end
		if not BinocularsRules.isTagLive(tag.endTime, now) or DamageableManager:getTarget(tag.damageableId) == nil then
			self:clearTag(player)
		end
	end
end

function BinocularsManager:getNetHandlers()
	return {
		[NetEventNames.TRY_TAG_MONSTER] = {
			shape = TRY_TAG_MONSTER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:tryTag(player, payload.origin, payload.direction)
			end,
		},
	}
end

-- a new run: every tag's body is gone with the last one
function BinocularsManager:onRunStarted()
	for player in self.stateByPlayer do
		self:clearTag(player)
	end
end

function BinocularsManager:onPlayerReady(player: Player)
	self:getPlayerState(player)
	self:replicateTag(player)
	self:replicateCooldown(player)
end

function BinocularsManager:onPlayerRemoved(player: Player)
	self:clearTag(player)
	self.stateByPlayer[player] = nil
end

function BinocularsManager:init()
	-- the post HUD's hint shows the cooldown's share by the same number
	SplendidReplicationManager:setGameMetadata(Attributes.BINOCULARS_COOLDOWN_SEC, BinocularsData.COOLDOWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if not self:hasBinoculars(player) then
				self:clearTag(player)
			end
		end
	)
	ReviveManager:subscribeDied(
		function(player: Player)
			self:clearTag(player)
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function BinocularsManager.new(): BinocularsManager
	local self = setmetatable({}, BinocularsManager) :: BinocularsManager
	self.stateByPlayer = {}
	return self
end

return BinocularsManager.new()
