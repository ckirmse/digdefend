--!strict

-- Each player's tools for the run (GDD "Tools"): the slot list in stable
-- order, which one is equipped, and the pick axe level. Run state, not
-- persistent, held in Lua and replicated as attributes: the equipped tool is
-- public so every client shows the held model; slots and level are private.
-- Everyone starts with a pick axe; the weapon (M24) and store tools (M21)
-- are added here later.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local ToolManager = {}
ToolManager.__index = ToolManager

type ToolState = {
	slots: { number },
	equipped: number,
	pickAxeLevel: number,
}

export type ToolManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: ToolState },
	},
	ToolManager
))

local TRY_EQUIP_TOOL_SHAPE = {
	-- an Enums.ToolKind, or MiningRules.NO_TOOL to unequip
	tool = "nonnegativeInteger",
}

local STARTING_PICK_AXE_LEVEL = 1

function ToolManager:getState(player: Player): ToolState?
	return self.stateByPlayer[player]
end

function ToolManager:getEquippedTool(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.equipped else MiningRules.NO_TOOL
end

function ToolManager:getPickAxeLevel(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.pickAxeLevel else STARTING_PICK_AXE_LEVEL
end

function ToolManager:hasTool(player: Player, tool: number): boolean
	local state = self.stateByPlayer[player]
	return state ~= nil and table.find(state.slots, tool) ~= nil
end

function ToolManager:replicate(player: Player)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	SplendidReplicationManager:setPublicAttribute(player, Attributes.EQUIPPED_TOOL, state.equipped)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.EQUIPPED_TOOL, state.equipped)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.TOOL_SLOTS, MiningRules.encodeToolSlots(state.slots))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.PICK_AXE_LEVEL, state.pickAxeLevel)
end

function ToolManager:grantTool(player: Player, tool: number)
	local state = self.stateByPlayer[player]
	if not state or table.find(state.slots, tool) then
		return
	end
	table.insert(state.slots, tool)
	self:replicate(player)
end

function ToolManager:setEquippedTool(player: Player, tool: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	if tool ~= MiningRules.NO_TOOL and not table.find(state.slots, tool) then
		warn(`ToolManager: {player.Name} tried to equip tool {tool} they do not have`)
		return
	end
	if state.equipped == tool then
		return
	end
	state.equipped = tool
	self:replicate(player)
end

function ToolManager:getNetHandlers()
	return {
		[NetEventNames.TRY_EQUIP_TOOL] = {
			shape = TRY_EQUIP_TOOL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				local tool = payload.tool
				if tool ~= MiningRules.NO_TOOL and not Enums.isValidValue(Enums.ToolKind, tool) then
					warn(`ToolManager: {player.Name} sent unknown tool {tool}`)
					return
				end
				self:setEquippedTool(player, tool)
			end,
		},
	}
end

-- ready-sequence entry: a fresh arrival gets the starting pick axe; a
-- dev-tool reset does not replay this, so run state survives it
function ToolManager:onPlayerReady(player: Player)
	if self.stateByPlayer[player] then
		self:replicate(player)
		return
	end
	self.stateByPlayer[player] = {
		slots = {},
		equipped = MiningRules.NO_TOOL,
		pickAxeLevel = STARTING_PICK_AXE_LEVEL,
	}
	self:grantTool(player, Enums.ToolKind.PICK_AXE)
end

function ToolManager:init()
	GameController:registerPlaceManager(self)
	-- not a teardown entry: a dev-tool reset must not strip the run's tools
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
		end
	)
end

function ToolManager.new(): ToolManager
	local self = setmetatable({}, ToolManager) :: ToolManager
	self.stateByPlayer = {}
	return self
end

return ToolManager.new()
