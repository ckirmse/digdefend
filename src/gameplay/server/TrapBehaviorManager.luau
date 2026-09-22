--!strict

-- What a standing Trap does (GDD "Trap Types"), M27. Every Heartbeat,
-- each Trap PlacementManager holds looks at the ground targets in
-- DamageableManager (air units never touch a Trap) and acts by its kind's
-- Enums.TrapBehavior with pure TrapRules: a barrier (Wall, Decoy) is what
-- the registry's blocker query answers with, so a walker stops against
-- it and, being held up, hits it every frame at its attack rate; spikes
-- pop under the first crosser, hurt everything on top, and run their Up
-- and Recharging clock; goo slows every crosser; a mine blows once at the
-- first touch and hurts everything in its range; a snare hurts and stuns
-- the one crosser once. A Trap that is spent is removed through
-- PlacementManager. The Spike Trap's state is published on its shadow for
-- the clients to draw, and a trigger is a NotifyTrapTriggered broadcast.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local TrapRules = require("@game/ReplicatedStorage/Shared/TrapRules")
local NetManager = require(script.Parent.Parent.Server.NetManager)
local DamageableManager = require(script.Parent.DamageableManager)
local PlacementManager = require(script.Parent.PlacementManager)

local TrapBehaviorManager = {}
TrapBehaviorManager.__index = TrapBehaviorManager

type TrapState = {
	triggeredTime: number?,
	publishedState: number,
}

export type TrapBehaviorManager = typeof(setmetatable(
	{} :: {
		stateById: { [string]: TrapState },
	},
	TrapBehaviorManager
))

function TrapBehaviorManager:getState(id: string): TrapState
	local state = self.stateById[id]
	if not state then
		state = {
			triggeredTime = nil,
			publishedState = Enums.TrapState.DOWN,
		}
		self.stateById[id] = state
	end
	return state
end

function TrapBehaviorManager:trapDataFor(placement: PlacementManager.Placement): PlacementRules.TrapData?
	if placement.placementKind ~= Enums.PlacementKind.TRAP then
		return nil
	end
	return PlacementManager:getCatalog().traps[placement.typeKind]
end

-- the shadow's size is the footprint on the grid, which is the Trap's box
function TrapBehaviorManager:getBarriers(): { TrapRules.Box }
	local barriers = {}
	for _, placement in PlacementManager:getPlacements() do
		local trap = self:trapDataFor(placement)
		if trap and trap.BEHAVIOR == Enums.TrapBehavior.BARRIER then
			table.insert(barriers, {
				id = placement.id,
				cframe = placement.cframe,
				size = placement.shadow.Size,
			})
		end
	end
	return barriers
end

function TrapBehaviorManager:touching(placement: PlacementManager.Placement, targets: { DamageableManager.Target }): { DamageableManager.Target }
	local touching = {}
	for _, target in targets do
		if TrapRules.isTouching(target.position, target.size, placement.cframe, placement.shadow.Size) then
			table.insert(touching, target)
		end
	end
	return touching
end

function TrapBehaviorManager:notifyTriggered(placement: PlacementManager.Placement)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_TRAP_TRIGGERED, {
		id = placement.id,
		trapKind = placement.typeKind,
	})
end

function TrapBehaviorManager:publishState(placement: PlacementManager.Placement, state: TrapState, trapState: number)
	if state.publishedState == trapState then
		return
	end
	state.publishedState = trapState
	placement.shadow:SetAttribute(Attributes.PLACEMENT_TRAP_STATE, trapState)
end

function TrapBehaviorManager:stepSpikes(placement: PlacementManager.Placement, trap: PlacementRules.TrapData, state: TrapState, targets: { DamageableManager.Target }, now: number)
	local upSec = trap.UP_SEC or 0
	local rechargeSec = trap.RECHARGE_SEC or 0
	local trapState = TrapRules.spikeState(state.triggeredTime, upSec, rechargeSec, now)
	if trapState == Enums.TrapState.DOWN then
		local touching = self:touching(placement, targets)
		if #touching > 0 then
			state.triggeredTime = now
			trapState = Enums.TrapState.UP
			for _, target in touching do
				DamageableManager:damage(target.id, trap.DAMAGE or 0, placement.owner)
			end
			self:notifyTriggered(placement)
		end
	end
	self:publishState(placement, state, trapState)
end

function TrapBehaviorManager:stepGoo(placement: PlacementManager.Placement, trap: PlacementRules.TrapData, targets: { DamageableManager.Target })
	for _, target in self:touching(placement, targets) do
		DamageableManager:applySlow(target.id, trap.SLOW_SHARE or 0, trap.SLOW_SEC or 0)
	end
end

function TrapBehaviorManager:stepMine(placement: PlacementManager.Placement, trap: PlacementRules.TrapData, targets: { DamageableManager.Target })
	if #self:touching(placement, targets) == 0 then
		return
	end
	for _, id in TrapRules.targetsWithin(placement.cframe.Position, trap.RANGE_STUDS or 0, targets) do
		DamageableManager:damage(id, trap.DAMAGE or 0, placement.owner)
	end
	self:notifyTriggered(placement)
	PlacementManager:removePlacement(placement.id)
end

function TrapBehaviorManager:stepSnare(placement: PlacementManager.Placement, trap: PlacementRules.TrapData, targets: { DamageableManager.Target })
	local touching = self:touching(placement, targets)
	local victim = touching[1]
	if not victim then
		return
	end
	DamageableManager:applySlow(victim.id, trap.SLOW_SHARE or 0, trap.SLOW_SEC or 0)
	DamageableManager:damage(victim.id, trap.DAMAGE or 0, placement.owner)
	self:notifyTriggered(placement)
	PlacementManager:removePlacement(placement.id)
end

function TrapBehaviorManager:step(deltaSec: number)
	local now = workspace:GetServerTimeNow()
	-- walkers a barrier holds up wear it down
	for _, blocked in DamageableManager:getBlockedTargets() do
		if blocked.attackDamagePerSec > 0 then
			PlacementManager:damagePlacement(blocked.placementId, blocked.attackDamagePerSec * deltaSec)
		end
	end
	local groundTargets: { DamageableManager.Target }? = nil
	local seen = {}
	for _, placement in PlacementManager:getPlacements() do
		local trap = self:trapDataFor(placement)
		if not trap or trap.BEHAVIOR == nil or trap.BEHAVIOR == Enums.TrapBehavior.BARRIER then
			continue
		end
		seen[placement.id] = true
		if not groundTargets then
			groundTargets = {}
			for _, target in DamageableManager:getTargets() do
				if not target.isAirborne then
					table.insert(groundTargets, target)
				end
			end
		end
		local targets = groundTargets :: { DamageableManager.Target }
		if trap.BEHAVIOR == Enums.TrapBehavior.SPIKES then
			self:stepSpikes(placement, trap, self:getState(placement.id), targets, now)
		elseif trap.BEHAVIOR == Enums.TrapBehavior.GOO then
			self:stepGoo(placement, trap, targets)
		elseif trap.BEHAVIOR == Enums.TrapBehavior.MINE then
			self:stepMine(placement, trap, targets)
		elseif trap.BEHAVIOR == Enums.TrapBehavior.SNARE then
			self:stepSnare(placement, trap, targets)
		end
	end
	for id in self.stateById do
		if not seen[id] then
			self.stateById[id] = nil
		end
	end
end

function TrapBehaviorManager:init()
	DamageableManager:setBlockerQuery(
		function(position: Vector3, size: Vector3): string?
			return TrapRules.findBlocker(position, size, self:getBarriers())
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function TrapBehaviorManager.new(): TrapBehaviorManager
	local self = setmetatable({}, TrapBehaviorManager) :: TrapBehaviorManager
	self.stateById = {}
	return self
end

return TrapBehaviorManager.new()
