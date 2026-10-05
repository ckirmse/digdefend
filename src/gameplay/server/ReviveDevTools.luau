--!strict

-- Gameplay dev tools for death and revives (M32): die now, come back
-- without paying (through the same door as the paid revives), revive the
-- wiped crew, make the once-per-run Team Revive available again, and hand
-- out a saved credit, so every path can be played without Robux.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local ReviveManager = require(script.Parent.ReviveManager)

local ReviveDevTools = {}
ReviveDevTools.__index = ReviveDevTools

export type ReviveDevTools = typeof(setmetatable({} :: {}, ReviveDevTools))

ReviveDevTools.KILL_ME_COMMAND = "killMe"
ReviveDevTools.REVIVE_COMMAND = "reviveFree"
ReviveDevTools.RESET_TEAM_REVIVE_COMMAND = "resetTeamRevive"
ReviveDevTools.ADD_REVIVE_CREDIT_COMMAND = "addReviveCredit"

local NO_ARGS_SHAPE = {}

local REVIVE_KIND_ARGS_SHAPE = {
	reviveKind = "positiveInteger",
}

function ReviveDevTools:init()
	DevTools:registerPlaceCommand(
		ReviveDevTools.KILL_ME_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("ReviveDevTools: killMe with invalid args:", errorMessage)
				return
			end
			ReviveManager:killForDevTool(player)
		end
	)
	DevTools:registerPlaceCommand(
		ReviveDevTools.REVIVE_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, REVIVE_KIND_ARGS_SHAPE)
			if not isValid or not Enums.isValidValue(Enums.ReviveKind, args.reviveKind) then
				warn("ReviveDevTools: reviveFree with invalid args:", errorMessage)
				return
			end
			ReviveManager:reviveForDevTool(player, args.reviveKind)
		end
	)
	DevTools:registerPlaceCommand(
		ReviveDevTools.RESET_TEAM_REVIVE_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("ReviveDevTools: resetTeamRevive with invalid args:", errorMessage)
				return
			end
			ReviveManager:resetTeamReviveForDevTool()
		end
	)
	DevTools:registerPlaceCommand(
		ReviveDevTools.ADD_REVIVE_CREDIT_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, errorMessage = Validate.isTableShape(args, REVIVE_KIND_ARGS_SHAPE)
			local playerData = GameController:getPlayerData(player)
			if not isValid or not playerData or not Enums.isValidValue(Enums.ReviveKind, args.reviveKind) then
				warn("ReviveDevTools: addReviveCredit with invalid args:", errorMessage)
				return
			end
			playerData:addReviveCredit(args.reviveKind)
			ReviveManager:replicateCredits(player)
		end
	)
end

function ReviveDevTools.new(): ReviveDevTools
	local self = setmetatable({}, ReviveDevTools) :: ReviveDevTools
	return self
end

return ReviveDevTools.new()
