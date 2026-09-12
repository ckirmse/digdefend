--!strict

-- Each player's backpack for the run (GDD "Backpack", "Collecting Ore"): raw
-- ore counts, level, and capacity in ore units. Run state held in Lua and
-- replicated as private CurrentPlayer attributes, one per resource, so the
-- Explorer shows exactly what a player carries. Ore arrives from broken
-- rocks (MiningManager) and ground pickups (OrePickupManager); the refinery
-- (M20) takes it all.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local BackpackData = require("@game/ServerScriptService/GameData/Mining/Backpack")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local BackpackManager = {}
BackpackManager.__index = BackpackManager

type BackpackState = {
	level: number,
	contents: BackpackRules.Contents,
}

export type BackpackManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: BackpackState },
	},
	BackpackManager
))

local STARTING_LEVEL = 1

function BackpackManager:getCapacity(player: Player): number
	local state = self.stateByPlayer[player]
	local level = if state then state.level else STARTING_LEVEL
	return BackpackRules.capacityForLevel(BackpackData.CAPACITY_BY_LEVEL, level)
end

function BackpackManager:getContents(player: Player): BackpackRules.Contents?
	local state = self.stateByPlayer[player]
	return if state then state.contents else nil
end

function BackpackManager:hasRoom(player: Player): boolean
	local state = self.stateByPlayer[player]
	return state ~= nil and not BackpackRules.isFull(state.contents, self:getCapacity(player))
end

function BackpackManager:replicate(player: Player)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BACKPACK_LEVEL, state.level)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BACKPACK_CAPACITY, self:getCapacity(player))
	for _, resource in Enums.getAllValues(Enums.RawResource) do
		local attribute = BackpackRules.attributeForResource(resource) :: string
		SplendidReplicationManager:setCurrentPlayerAttribute(player, attribute, state.contents[resource] or 0)
	end
end

-- adds what fits, tells the player so the pop plays, returns (added, overflow)
function BackpackManager:add(player: Player, resource: number, amount: number): (number, number)
	local state = self.stateByPlayer[player]
	if not state then
		return 0, amount
	end
	local added, overflow = BackpackRules.add(state.contents, self:getCapacity(player), resource, amount)
	if added > 0 then
		self:replicate(player)
		NetManager:notifyClient(player, NetEventNames.NOTIFY_ORE_COLLECTED, {
			resource = resource,
			amount = added,
		})
	end
	return added, overflow
end

function BackpackManager:takeAll(player: Player): BackpackRules.Contents
	local state = self.stateByPlayer[player]
	if not state then
		return {}
	end
	local taken = BackpackRules.takeAll(state.contents)
	self:replicate(player)
	return taken
end

-- dev tools
function BackpackManager:fill(player: Player)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	local room = self:getCapacity(player) - BackpackRules.getTotal(state.contents)
	BackpackRules.add(state.contents, self:getCapacity(player), Enums.RawResource.IRON_ORE, room)
	self:replicate(player)
end

function BackpackManager:empty(player: Player)
	self:takeAll(player)
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function BackpackManager:onPlayerReady(player: Player)
	if not self.stateByPlayer[player] then
		self.stateByPlayer[player] = {
			level = STARTING_LEVEL,
			contents = {},
		}
	end
	self:replicate(player)
end

function BackpackManager:init()
	GameController:registerPlaceManager(self)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
		end
	)
end

function BackpackManager.new(): BackpackManager
	local self = setmetatable({}, BackpackManager) :: BackpackManager
	self.stateByPlayer = {}
	return self
end

return BackpackManager.new()
