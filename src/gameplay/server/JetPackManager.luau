--!strict

-- The jet pack (GDD "Jet Pack"): the server owns the fuel tank. A client
-- asks to start and stop burning; the tank drains here every frame while
-- burning, cuts out at empty, and refills whenever it is not burning. A
-- tank run dry locks the pack until it is full again (decided 2026-09-15).
-- The burn is a looping 3D emitter on the character's root, so every player
-- hears a jet pack from where it is.
-- The burning flag is public so every client shows the flame, and the
-- owning client applies the upward thrust itself (it already owns its
-- character's physics), reading the climb speed from GameMetadata. The fuel
-- is a private attribute written a few times a second while it changes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local JetPackRules = require("@game/ReplicatedStorage/Shared/JetPackRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local JetPackData = require("@game/ServerScriptService/GameData/Mining/JetPack")
local GameController = require(script.Parent.Parent.Server.GameController)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local JetPackManager = {}
JetPackManager.__index = JetPackManager

type PackState = {
	level: number,
	tank: JetPackRules.Tank,
	-- the looping burn on the character while it burns
	burnSound: AudioPlayer?,
	lastReplicatedFuelSec: number,
	lastReplicateTime: number,
}

export type JetPackManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: PackState },
	},
	JetPackManager
))

local TRY_JET_PACK_START_SHAPE = {}
local TRY_JET_PACK_STOP_SHAPE = {}

local STARTING_LEVEL = 1

function JetPackManager:getLevel(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.level else STARTING_LEVEL
end

function JetPackManager:getMaxFuelSec(player: Player): number
	return JetPackRules.maxFuelForLevel(JetPackData.BASE_FUEL_SEC, JetPackData.FUEL_PER_LEVEL_SEC, self:getLevel(player))
end

function JetPackManager:isBurning(player: Player): boolean
	local state = self.stateByPlayer[player]
	return state ~= nil and state.tank.isBurning
end

function JetPackManager:replicate(player: Player, now: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.JET_PACK_LEVEL, state.level)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.JET_PACK_FUEL_MAX_SEC, self:getMaxFuelSec(player))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.JET_PACK_FUEL_SEC, state.tank.fuelSec)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_JET_PACK_LOCKED, state.tank.isLocked)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.IS_JET_PACK_BURNING, state.tank.isBurning)
	state.lastReplicatedFuelSec = state.tank.fuelSec
	state.lastReplicateTime = now
end

function JetPackManager:setLevel(player: Player, level: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	state.level = level
	self:replicate(player, workspace:GetServerTimeNow())
end

function JetPackManager:setBurning(player: Player, isBurning: boolean)
	local state = self.stateByPlayer[player]
	if not state or state.tank.isBurning == isBurning then
		return
	end
	state.tank.isBurning = isBurning
	self:syncBurnSound(player)
	self:replicate(player, workspace:GetServerTimeNow())
end

function JetPackManager:syncBurnSound(player: Player)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	local existing = state.burnSound
	if existing then
		existing:Destroy()
		state.burnSound = nil
	end
	if not state.tank.isBurning then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		state.burnSound = SpatialSoundManager:attach(root, SoundNames.Sfx.JET_PACK_BURN, true)
	end
end

function JetPackManager:handleStart(player: Player)
	local state = self.stateByPlayer[player]
	if not state or not JetPackRules.canStart(state.tank) then
		return
	end
	self:setBurning(player, true)
end

function JetPackManager:handleStop(player: Player)
	self:setBurning(player, false)
end

function JetPackManager:step(deltaSec: number)
	local now = workspace:GetServerTimeNow()
	for player, state in self.stateByPlayer do
		local tank = state.tank
		local fuel, isCutOut, isLocked = JetPackRules.step(tank, deltaSec, self:getMaxFuelSec(player), JetPackData.REFILL_RATE)
		tank.fuelSec = fuel
		local wasLocked = tank.isLocked
		tank.isLocked = isLocked
		if isCutOut then
			self:setBurning(player, false)
			continue
		end
		if wasLocked ~= isLocked then
			self:replicate(player, now)
			continue
		end
		if fuel ~= state.lastReplicatedFuelSec and now - state.lastReplicateTime >= JetPackData.FUEL_REPLICATE_INTERVAL_SEC then
			self:replicate(player, now)
		end
	end
end

function JetPackManager:getNetHandlers()
	return {
		[NetEventNames.TRY_JET_PACK_START] = {
			shape = TRY_JET_PACK_START_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleStart(player)
			end,
		},
		[NetEventNames.TRY_JET_PACK_STOP] = {
			shape = TRY_JET_PACK_STOP_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleStop(player)
			end,
		},
	}
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function JetPackManager:onPlayerReady(player: Player)
	if not self.stateByPlayer[player] then
		self.stateByPlayer[player] = {
			level = STARTING_LEVEL,
			tank = {
				fuelSec = JetPackRules.maxFuelForLevel(JetPackData.BASE_FUEL_SEC, JetPackData.FUEL_PER_LEVEL_SEC, STARTING_LEVEL),
				isBurning = false,
				isLocked = false,
			},
			lastReplicatedFuelSec = -1,
			lastReplicateTime = 0,
			burnSound = nil,
		}
		-- a respawn lands with the pack off
		player.CharacterAdded:Connect(
			function()
				self:setBurning(player, false)
			end
		)
	end
	self:replicate(player, workspace:GetServerTimeNow())
end

function JetPackManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.JET_PACK_CLIMB_SPEED, JetPackData.CLIMB_SPEED_STUDS_PER_SEC)
	GameController:registerPlaceManager(self)
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

function JetPackManager.new(): JetPackManager
	local self = setmetatable({}, JetPackManager) :: JetPackManager
	self.stateByPlayer = {}
	return self
end

return JetPackManager.new()
