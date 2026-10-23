--!strict

-- The Drill Rig's stock (the Prospector's Tower, GDD "Classes",
-- 2026-10-22). The rig itself is an ordinary placement: PlacementManager
-- builds, sells, upgrades, damages, and removes it like any Tower, and
-- TowerBehaviorManager skips it because its data has no BEHAVIOR. What
-- it adds is here: every standing rig drills ore into a stock, Lua state
-- by placement id, YIELD_PER_MINUTE of the level's row split by the
-- data's RESOURCE_SHARES until the stock reaches STOCK_CAP, where it
-- stops until collected (pure DrillRigRules). The whole units held are
-- published on the rig's own shadow as the DrillRigStock attribute, so
-- every client's billboard reads them from the instance it already
-- dresses. Anyone within COLLECT_DISTANCE_STUDS may collect
-- (TryCollectDrillRig): each resource goes into their backpack through
-- BackpackManager (the one owner of what a player carries, which also
-- flies the icons), and what does not fit stays in the rig. A paused run
-- and a finished one drill nothing; a new run starts every rig empty.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local DrillRigRules = require("@game/ReplicatedStorage/Shared/DrillRigRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local BackpackManager = require(script.Parent.BackpackManager)
local PlacementManager = require(script.Parent.PlacementManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)

local DrillRigManager = {}
DrillRigManager.__index = DrillRigManager

type RigState = {
	stock: DrillRigRules.Stock,
	lastStepTime: number,
	-- the attribute as last written, so an unchanged frame writes nothing
	publishedStock: string,
}

export type DrillRigManager = typeof(setmetatable(
	{} :: {
		stateById: { [string]: RigState },
	},
	DrillRigManager
))

local TRY_COLLECT_DRILL_RIG_SHAPE = {
	id = "string",
}
local FEEDBACK_EMPTY = "The rig has nothing to collect yet."
local FEEDBACK_TOO_FAR = "Stand closer to the rig to collect."
local FEEDBACK_FULL = "Your backpack is full."

function DrillRigManager:getDrillData(): PlacementRules.DrillData?
	local tower = TowersData.BY_KIND[Enums.TowerKind.DRILL_RIG]
	return if tower then tower.DRILL else nil
end

function DrillRigManager:isRig(placement: PlacementManager.Placement): boolean
	return placement.placementKind == Enums.PlacementKind.TOWER and placement.typeKind == Enums.TowerKind.DRILL_RIG
end

function DrillRigManager:getState(placement: PlacementManager.Placement, now: number): RigState
	local state = self.stateById[placement.id]
	if not state then
		state = {
			stock = {},
			lastStepTime = now,
			publishedStock = "",
		}
		self.stateById[placement.id] = state
	end
	return state
end

function DrillRigManager:publish(placement: PlacementManager.Placement, state: RigState)
	local encoded = DrillRigRules.encodeStock(state.stock)
	if encoded == state.publishedStock then
		return
	end
	state.publishedStock = encoded
	placement.shadow:SetAttribute(Attributes.DRILL_RIG_STOCK, encoded)
end

-- every Heartbeat each standing rig drills on from the last step; the
-- clock stands still through a pause and after the run
function DrillRigManager:step()
	if next(self.stateById) == nil and #PlacementManager:getPlacements() == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local isDrilling = RunCycleManager:isRunOn() and not RunPauseManager:isPaused() and not RunCycleRules.isRunOver(RunCycleManager:getRunState())
	local drill = self:getDrillData()
	local catalog = PlacementManager:getCatalog()
	local tower = catalog.towers[Enums.TowerKind.DRILL_RIG]
	local seen = {}
	for _, placement in PlacementManager:getPlacements() do
		if not self:isRig(placement) then
			continue
		end
		seen[placement.id] = true
		local state = self:getState(placement, now)
		local elapsedSec = now - state.lastStepTime
		state.lastStepTime = now
		if not isDrilling or not drill or not tower then
			continue
		end
		local stats = PlacementRules.towerStats(tower, placement.level)
		state.stock = DrillRigRules.accumulate(state.stock, stats.YIELD_PER_MINUTE or 0, drill.RESOURCE_SHARES, elapsedSec, stats.STOCK_CAP or 0)
		self:publish(placement, state)
	end
	-- a sold or destroyed rig takes its stock with it
	for id in self.stateById do
		if not seen[id] then
			self.stateById[id] = nil
		end
	end
end

-- a collector takes every whole unit their backpack has room for
function DrillRigManager:collect(player: Player, id: string)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	local placement = PlacementManager:getPlacement(id)
	if not placement or not self:isRig(placement) then
		return
	end
	local drill = self:getDrillData()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not drill or not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - placement.cframe.Position).Magnitude > drill.COLLECT_DISTANCE_STUDS then
		PlayerFeedbackManager:give(player, FEEDBACK_TOO_FAR)
		return
	end
	local state = self:getState(placement, workspace:GetServerTimeNow())
	local whole = DrillRigRules.wholeUnits(state.stock)
	if next(whole) == nil then
		PlayerFeedbackManager:give(player, FEEDBACK_EMPTY)
		return
	end
	local takenAny = false
	for resource, amount in whole do
		local added = BackpackManager:add(player, resource, amount, placement.cframe.Position)
		if added > 0 then
			takenAny = true
			state.stock = DrillRigRules.take(state.stock, resource, added)
		end
	end
	if not takenAny then
		PlayerFeedbackManager:give(player, FEEDBACK_FULL)
		return
	end
	self:publish(placement, state)
end

function DrillRigManager:getNetHandlers()
	return {
		[NetEventNames.TRY_COLLECT_DRILL_RIG] = {
			shape = TRY_COLLECT_DRILL_RIG_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:collect(player, payload.id)
			end,
		},
	}
end

-- a new run has a new camp and no rigs
function DrillRigManager:onRunStarted()
	self.stateById = {}
end

function DrillRigManager:init()
	GameController:registerPlaceManager(self)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function DrillRigManager.new(): DrillRigManager
	local self = setmetatable({}, DrillRigManager) :: DrillRigManager
	self.stateById = {}
	return self
end

return DrillRigManager.new()
