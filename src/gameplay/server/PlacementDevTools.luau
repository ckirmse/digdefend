--!strict

-- Gameplay dev tools for placements (M26). The lobby store and loadout
-- menu that fill the Defense slots are later milestones, so an admin
-- builds the Tower loadout their build bar shows here, grants Traps
-- without a store trip, damages a placement to test HP and destruction,
-- and clears the grid.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local PlacementManager = require(script.Parent.PlacementManager)

local PlacementDevTools = {}
PlacementDevTools.__index = PlacementDevTools

export type PlacementDevTools = typeof(setmetatable(
	{} :: {
		loadoutByPlayer: { [Player]: { number } },
	},
	PlacementDevTools
))

PlacementDevTools.ADD_LOADOUT_TOWER_COMMAND = "addLoadoutTower"
PlacementDevTools.CLEAR_LOADOUT_TOWERS_COMMAND = "clearLoadoutTowers"
PlacementDevTools.GRANT_TRAP_COMMAND = "grantTrap"
PlacementDevTools.DAMAGE_PLACEMENT_COMMAND = "damagePlacement"
PlacementDevTools.CLEAR_PLACEMENTS_COMMAND = "clearPlacements"

local ADD_LOADOUT_TOWER_ARGS_SHAPE = {
	kind = { type = "enum", name = "TowerKind" },
}
local CLEAR_ARGS_SHAPE = {}
local GRANT_TRAP_ARGS_SHAPE = {
	kind = { type = "enum", name = "TrapKind" },
	amount = "positiveInteger",
}
local DAMAGE_PLACEMENT_ARGS_SHAPE = {
	id = "string",
	amount = "positiveInteger",
}

-- as many slots as the loadout has
local MAX_LOADOUT_TOWERS = 3

function PlacementDevTools:init()
	DevTools:registerPlaceCommand(
		PlacementDevTools.ADD_LOADOUT_TOWER_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, ADD_LOADOUT_TOWER_ARGS_SHAPE)
			if not isValid then
				warn("PlacementDevTools: addLoadoutTower with invalid args:", err)
				return
			end
			local loadout = self.loadoutByPlayer[player] or {}
			if not table.find(loadout, args.kind) then
				table.insert(loadout, args.kind)
			end
			-- the oldest drops off past three, like swapping a slot
			while #loadout > MAX_LOADOUT_TOWERS do
				table.remove(loadout, 1)
			end
			self.loadoutByPlayer[player] = loadout
			PlacementManager:setLoadoutOverride(player, loadout)
			PlayerFeedbackManager:give(player, `Loadout now has {#loadout} Tower(s)`)
		end
	)
	DevTools:registerPlaceCommand(
		PlacementDevTools.CLEAR_LOADOUT_TOWERS_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, CLEAR_ARGS_SHAPE)
			if not isValid then
				warn("PlacementDevTools: clearLoadoutTowers with invalid args:", err)
				return
			end
			self.loadoutByPlayer[player] = nil
			PlacementManager:setLoadoutOverride(player, nil)
			PlayerFeedbackManager:give(player, "Tower loadout back to the saved one")
		end
	)
	DevTools:registerPlaceCommand(
		PlacementDevTools.GRANT_TRAP_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, GRANT_TRAP_ARGS_SHAPE)
			if not isValid then
				warn("PlacementDevTools: grantTrap with invalid args:", err)
				return
			end
			PlacementManager:addTrap(player, args.kind, args.amount)
			PlayerFeedbackManager:give(player, `Granted {args.amount} {Enums.getPublicName(Enums.TrapKind, args.kind)}`)
		end
	)
	DevTools:registerPlaceCommand(
		PlacementDevTools.DAMAGE_PLACEMENT_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, DAMAGE_PLACEMENT_ARGS_SHAPE)
			if not isValid then
				warn("PlacementDevTools: damagePlacement with invalid args:", err)
				return
			end
			if not PlacementManager:getPlacement(args.id) then
				PlayerFeedbackManager:give(player, `No placement named {args.id}`)
				return
			end
			PlacementManager:damagePlacement(args.id, args.amount)
		end
	)
	DevTools:registerPlaceCommand(
		PlacementDevTools.CLEAR_PLACEMENTS_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, CLEAR_ARGS_SHAPE)
			if not isValid then
				warn("PlacementDevTools: clearPlacements with invalid args:", err)
				return
			end
			PlacementManager:clearPlacements()
			PlayerFeedbackManager:give(player, "Every placement removed")
		end
	)
end

function PlacementDevTools.new(): PlacementDevTools
	local self = setmetatable({}, PlacementDevTools) :: PlacementDevTools
	self.loadoutByPlayer = {}
	return self
end

return PlacementDevTools.new()
