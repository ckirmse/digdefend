--!strict

-- The Stim Shot, the Ranger's gadget (GDD "Classes", 2026-10-19). The
-- GADGET slot is the injector while the class says so (granted here; the
-- Auto Turret manager, which runs first, takes the slot from any class
-- without a turret, so this only ever gives). With it in hand the use
-- input asks TryUseStimShot; the server checks the player is alive, holds
-- the Stim Shot, has it equipped, and has not used it since dawn, then
-- raises their health to a share of the maximum and opens an
-- invulnerability window through ReviveManager (the one owner of health
-- and of who takes damage), raises their speed for the same while through
-- BootsManager (the one owner of walk speed), marks the shot used until the next dawn
-- (StimShotIsUsed on CurrentPlayer) and takes the slot and the injector away
-- until dawn gives them back (decided 2026-10-19), and tells the
-- player (NotifyStimShotUsed) so their screen flashes white. Tuning:
-- GameData/Gadgets/StimShot.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local StimShotData = require("@game/ServerScriptService/GameData/Gadgets/StimShot")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BootsManager = require(script.Parent.BootsManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local StimShotManager = {}
StimShotManager.__index = StimShotManager

export type StimShotManager = typeof(setmetatable(
	{} :: {
		-- the day a player used their shot; nil when it is unused. A dawn
		-- gives back only a shot used on an earlier day, so one used in the
		-- arrival before day 1 is not handed straight back by day 1
		usedOnDayByPlayer: { [Player]: number },
		-- when a running effect ends; nil when none is
		effectEndTimeByPlayer: { [Player]: number },
	},
	StimShotManager
))

local TRY_USE_STIM_SHOT_SHAPE = {}
local FEEDBACK_USED = "Stim Shot used. Back at dawn."
local FEEDBACK_NOT_YET = "Not until the day starts."

function StimShotManager:hasStimShot(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.STIM_SHOT
end

function StimShotManager:isUsed(player: Player): boolean
	return self.usedOnDayByPlayer[player] ~= nil
end

function StimShotManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.STIM_SHOT_IS_USED, self:isUsed(player))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.STIM_SHOT_EFFECT_END_TIME, self.effectEndTimeByPlayer[player] or 0)
end

function StimShotManager:setUsedOnDay(player: Player, day: number?)
	self.usedOnDayByPlayer[player] = day
	self:replicate(player)
end

function StimShotManager:use(player: Player)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:hasStimShot(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.GADGET then
		return
	end
	if self:isUsed(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_USED)
		return
	end
	-- not in the arrival: there is nothing to survive yet, and the first
	-- dawn would otherwise hand a shot used there straight back
	if not RunCycleManager:isRunOn() then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_YET)
		return
	end
	local now = workspace:GetServerTimeNow()
	-- the user alone: health up to the share, no damage taken, and the
	-- speed, all for the effect's length
	ReviveManager:healUpTo(player, StimShotData.HEAL_TO_SHARE)
	ReviveManager:setInvulnerableFor(player, StimShotData.EFFECT_SEC)
	BootsManager:setSpeedBoost(player, StimShotData.SPEED_MULTIPLIER, now + StimShotData.EFFECT_SEC)
	self.effectEndTimeByPlayer[player] = now + StimShotData.EFFECT_SEC
	self:setUsedOnDay(player, RunCycleManager:getDay())
	-- the injector is spent: out of the hand, while the slot stays in the
	-- bar to count the effect down and then grey out (decided 2026-10-19)
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_STIM_SHOT_USED, {
		speedSec = StimShotData.EFFECT_SEC,
	})
end

-- the slot is the Stim Shot's while the class says so (see the header)
function StimShotManager:applyGadget(player: Player)
	if self:hasStimShot(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
end

function StimShotManager:getNetHandlers()
	return {
		[NetEventNames.TRY_USE_STIM_SHOT] = {
			shape = TRY_USE_STIM_SHOT_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:use(player)
			end,
		},
	}
end

-- dawn: a shot used on an earlier day is back, in the bar again
function StimShotManager:onDayStarted(day: number)
	for player, usedOnDay in self.usedOnDayByPlayer do
		if player.Parent and usedOnDay < day then
			self.effectEndTimeByPlayer[player] = nil
			self:setUsedOnDay(player, nil)
		end
	end
end

function StimShotManager:onRunStarted()
	for player in self.usedOnDayByPlayer do
		if player.Parent then
			self.effectEndTimeByPlayer[player] = nil
			self:setUsedOnDay(player, nil)
		end
	end
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

function StimShotManager:onPlayerReady(player: Player)
	self:replicate(player)
	self:applyGadget(player)
end

function StimShotManager:onPlayerRemoved(player: Player)
	self.usedOnDayByPlayer[player] = nil
	self.effectEndTimeByPlayer[player] = nil
end

function StimShotManager:init()
	GameController:registerPlaceManager(self)
	RunCycleManager:subscribeDayStarted(
		function(day: number, _scalingCount: number)
			self:onDayStarted(day)
		end
	)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
end

function StimShotManager.new(): StimShotManager
	local self = setmetatable({}, StimShotManager) :: StimShotManager
	self.usedOnDayByPlayer = {}
	self.effectEndTimeByPlayer = {}
	return self
end

return StimShotManager.new()
