--!strict

-- Gameplay dev tools for camp structures (M23). Nothing deals damage until
-- weapons and enemies exist, and the day clock is M28, so these are how HP,
-- rubble, repairs, the shared tier, and the gate's day and night behaviour
-- are tested: damage or destroy a structure, grant Iron, set the tier, and
-- flip day and night.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local RefineryManager = require(script.Parent.RefineryManager)
local StructureManager = require(script.Parent.StructureManager)

local StructureDevTools = {}
StructureDevTools.__index = StructureDevTools

export type StructureDevTools = typeof(setmetatable({} :: {}, StructureDevTools))

StructureDevTools.DAMAGE_STRUCTURE_COMMAND = "damageStructure"
StructureDevTools.ADD_IRON_COMMAND = "addIron"
StructureDevTools.SET_FORTIFICATION_TIER_COMMAND = "setFortificationTier"
StructureDevTools.SET_NIGHT_COMMAND = "setNight"

local DAMAGE_STRUCTURE_ARGS_SHAPE = {
	-- a structure id ("Wall3", "Gate", "Refinery")
	id = "string",
	amount = "positiveInteger",
}
local ADD_IRON_ARGS_SHAPE = {
	amount = "integer",
}
local SET_FORTIFICATION_TIER_ARGS_SHAPE = {
	tier = "positiveInteger",
}
local SET_NIGHT_ARGS_SHAPE = {
	isNight = "boolean",
}

function StructureDevTools:damageStructure(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, DAMAGE_STRUCTURE_ARGS_SHAPE)
	if not isValid then
		warn("StructureDevTools: damageStructure with invalid args:", err)
		return
	end
	if not StructureManager:getStructure(args.id) then
		PlayerFeedbackManager:give(player, `No structure named {args.id}`)
		return
	end
	StructureManager:damageStructure(args.id, args.amount)
end

function StructureDevTools:init()
	DevTools:registerPlaceCommand(
		StructureDevTools.DAMAGE_STRUCTURE_COMMAND,
		function(player: Player, args: { [string]: any })
			self:damageStructure(player, args)
		end
	)
	DevTools:registerPlaceCommand(
		StructureDevTools.ADD_IRON_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, ADD_IRON_ARGS_SHAPE)
			if not isValid then
				warn("StructureDevTools: addIron with invalid args:", err)
				return
			end
			RefineryManager:addIronBars(player, args.amount)
		end
	)
	DevTools:registerPlaceCommand(
		StructureDevTools.SET_FORTIFICATION_TIER_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_FORTIFICATION_TIER_ARGS_SHAPE)
			if not isValid then
				warn("StructureDevTools: setFortificationTier with invalid args:", err)
				return
			end
			StructureManager:setFortificationTier(args.tier)
		end
	)
	DevTools:registerPlaceCommand(
		StructureDevTools.SET_NIGHT_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_NIGHT_ARGS_SHAPE)
			if not isValid then
				warn("StructureDevTools: setNight with invalid args:", err)
				return
			end
			StructureManager:setNight(args.isNight)
		end
	)
end

function StructureDevTools.new(): StructureDevTools
	local self = setmetatable({}, StructureDevTools) :: StructureDevTools
	return self
end

return StructureDevTools.new()
